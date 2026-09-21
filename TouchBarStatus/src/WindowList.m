#import "WindowList.h"
#import <ApplicationServices/ApplicationServices.h>

@interface AppWindow ()
@property (assign) AXUIElementRef element;
@property (assign) pid_t pid;
@property (copy, readwrite) NSString *title;
@end

@implementation AppWindow

- (instancetype)initWithElement:(AXUIElementRef)element pid:(pid_t)pid title:(NSString *)title {
    self = [super init];
    if (!self) return nil;
    _element = (AXUIElementRef)CFRetain(element);
    _pid = pid;
    _title = [title copy];
    return self;
}

- (void)dealloc {
    if (_element) CFRelease(_element);
}

- (BOOL)focus {
    if (!self.element) return NO;
    // Order matters: mark the window main/focused, raise it, then activate the
    // app. Activating first can leave a different window frontmost.
    AXUIElementSetAttributeValue(self.element, kAXMainAttribute, kCFBooleanTrue);
    AXUIElementSetAttributeValue(self.element, kAXFocusedAttribute, kCFBooleanTrue);
    AXError err = AXUIElementPerformAction(self.element, kAXRaiseAction);

    NSRunningApplication *app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:self.pid];
    [app activateWithOptions:0];
    return err == kAXErrorSuccess;
}

@end

@implementation WindowList

+ (BOOL)accessibilityAvailable {
    NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
}

+ (NSArray<AppWindow *> *)windowsForPID:(pid_t)pid {
    if (![self accessibilityAvailable]) return @[];

    AXUIElementRef appEl = AXUIElementCreateApplication(pid);
    if (!appEl) return @[];

    CFTypeRef windowsRef = NULL;
    AXError err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute, &windowsRef);
    NSArray *windows = (err == kAXErrorSuccess && windowsRef) ? CFBridgingRelease(windowsRef) : @[];

    // Some apps report an empty AXWindows array even while showing a window -
    // Alacritty does exactly this. Fall back to the focused/main window so
    // such apps are still represented (one process, one window).
    if (windows.count == 0) {
        CFTypeRef single = NULL;
        if (AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute, &single) != kAXErrorSuccess || !single) {
            single = NULL;
            AXUIElementCopyAttributeValue(appEl, kAXMainWindowAttribute, &single);
        }
        if (single) windows = @[CFBridgingRelease(single)];
    }

    NSMutableArray<AppWindow *> *result = [NSMutableArray array];
    NSUInteger index = 0;
    for (id w in windows) {
        AXUIElementRef win = (__bridge AXUIElementRef)w;

        CFTypeRef titleRef = NULL;
        AXUIElementCopyAttributeValue(win, kAXTitleAttribute, &titleRef);
        NSString *title = titleRef ? CFBridgingRelease(titleRef) : nil;

        // Skip windows that cannot be raised (sheets, popovers and the like
        // report no title and no subrole we care about).
        index++;
        if (title.length == 0) title = [NSString stringWithFormat:@"Window %lu", (unsigned long)index];

        [result addObject:[[AppWindow alloc] initWithElement:win pid:pid title:title]];
    }
    CFRelease(appEl);
    return result;
}

+ (NSUInteger)approximateWindowCountForPID:(pid_t)pid {
    CFArrayRef listRef = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    NSArray *list = CFBridgingRelease(listRef);
    NSUInteger count = 0;
    for (NSDictionary *w in list) {
        if ([w[(id)kCGWindowLayer] intValue] != 0) continue;       // normal windows only
        if ([w[(id)kCGWindowOwnerPID] intValue] != pid) continue;
        count++;
    }
    return count;
}

@end
