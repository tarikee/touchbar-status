//
//  TouchBarStatus — shows which app currently has keyboard focus, on the
//  macOS Touch Bar.
//
//  Built for a MacBook Pro whose main display is dead. The Touch Bar is a
//  separate panel that still works, so it can answer "where am I?" while
//  cmd-tabbing blind.
//
//  Two surfaces:
//    1. A permanent icon in the Control Strip (right side, always visible,
//       coexists with whatever Touch Bar the focused app draws).
//    2. On every app switch, a full-width flash showing the icon plus the
//       FULL app name in large text, which auto-dismisses. The Control Strip
//       only grants a fixed ~64pt slot, far too narrow for a readable name,
//       so the name gets the whole bar for a moment instead.
//
//  Requires NO permissions: NSWorkspace's frontmostApplication and its
//  activation notifications are unprivileged.
//

#import <Cocoa/Cocoa.h>

#pragma mark - Private DFRFoundation API

extern void DFRElementSetControlStripPresenceForIdentifier(NSString *identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

@interface NSTouchBarItem (DFRPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (DFRPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
           systemTrayItemIdentifier:(NSString *)identifier;
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar
                            placement:(long long)placement
             systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)dismissSystemModalFunctionBar:(NSTouchBar *)touchBar;
@end

static NSString *const kTrayIdentifier  = @"com.tarik.touchbarstatus.tray";
static NSString *const kFlashIdentifier = @"com.tarik.touchbarstatus.flash";

/// How long the full-width name stays up before handing the bar back.
static const NSTimeInterval kFlashDuration = 1.5;
static const CGFloat kTrayIconSize  = 24.0;
static const CGFloat kFlashIconSize = 26.0;

#pragma mark - Tray view (permanent Control Strip icon)

@interface TrayView : NSView
@property (strong) NSImageView *iconView;
@end

@implementation TrayView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.imageScaling = NSImageScaleProportionallyDown;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_iconView];
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:kTrayIconSize],
        [_iconView.heightAnchor constraintEqualToConstant:kTrayIconSize],
    ]];
    return self;
}

- (void)setIcon:(NSImage *)icon name:(NSString *)name {
    NSImage *sized = [icon copy];
    sized.size = NSMakeSize(kTrayIconSize, kTrayIconSize);
    self.iconView.image = sized;
    self.toolTip = name;
}

@end

#pragma mark - Flash view (full-width icon + name)

@interface FlashView : NSView
@property (strong) NSImageView *iconView;
@property (strong) NSTextField *label;
@end

@implementation FlashView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.imageScaling = NSImageScaleProportionallyDown;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;

    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    _label.textColor = [NSColor labelColor];
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconView];
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:kFlashIconSize],
        [_iconView.heightAnchor constraintEqualToConstant:kFlashIconSize],

        [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    return self;
}

- (void)setIcon:(NSImage *)icon name:(NSString *)name {
    NSImage *sized = [icon copy];
    sized.size = NSMakeSize(kFlashIconSize, kFlashIconSize);
    self.iconView.image = sized;
    self.label.stringValue = name;
}

@end

#pragma mark - App delegate

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSCustomTouchBarItem *trayItem;
@property (strong) TrayView *trayView;
@property (strong) NSTouchBar *flashBar;
@property (strong) FlashView *flashView;
@property (strong) NSTimer *dismissTimer;
@property (assign) BOOL flashVisible;
@property (copy)   NSString *currentName;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    DFRSystemModalShowsCloseBoxWhenFrontMost(NO);
    [self buildTrayItem];
    [self buildFlashBar];

    [[NSWorkspace sharedWorkspace].notificationCenter
        addObserver:self
           selector:@selector(activeAppChanged:)
               name:NSWorkspaceDidActivateApplicationNotification
             object:nil];

    // Seed with whatever has focus right now, without flashing on launch.
    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front) [self applyApp:front flash:NO];

    NSLog(@"TouchBarStatus: ready");
}

- (void)buildTrayItem {
    self.trayView = [[TrayView alloc] initWithFrame:NSMakeRect(0, 0, 64, 30)];
    self.trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:kTrayIdentifier];
    self.trayItem.view = self.trayView;
    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, YES);
}

- (void)buildFlashBar {
    self.flashView = [[FlashView alloc] initWithFrame:NSMakeRect(0, 0, 600, 30)];
    NSCustomTouchBarItem *flashItem =
        [[NSCustomTouchBarItem alloc] initWithIdentifier:kFlashIdentifier];
    flashItem.view = self.flashView;

    self.flashBar = [[NSTouchBar alloc] init];
    self.flashBar.defaultItemIdentifiers = @[kFlashIdentifier];
    self.flashBar.templateItems = [NSSet setWithObject:flashItem];
}

#pragma mark Focus tracking

- (void)activeAppChanged:(NSNotification *)note {
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey]
                                ?: [NSWorkspace sharedWorkspace].frontmostApplication;
    if (app) [self applyApp:app flash:YES];
}

- (void)applyApp:(NSRunningApplication *)app flash:(BOOL)shouldFlash {
    NSString *name = app.localizedName ?: @"Unknown";
    NSImage *icon = app.icon;
    self.currentName = name;

    [self.trayView setIcon:icon name:name];
    [self.flashView setIcon:icon name:name];

    // The Control Strip drops registrations when ControlStrip.app restarts,
    // so re-assert presence on every switch. Cheap and idempotent.
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, YES);

    if (shouldFlash) [self showFlash];
    NSLog(@"TouchBarStatus: focus -> %@", name);
}

#pragma mark Flash presentation

- (void)showFlash {
    if (!self.flashVisible) {
        if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
            [NSTouchBar presentSystemModalTouchBar:self.flashBar
                                         placement:1
                          systemTrayItemIdentifier:kTrayIdentifier];
        } else {
            [NSTouchBar presentSystemModalFunctionBar:self.flashBar
                                            placement:1
                             systemTrayItemIdentifier:kTrayIdentifier];
        }
        self.flashVisible = YES;
        NSLog(@"TouchBarStatus: flash presented");
    }
    // Restart the countdown so rapid cmd-tabbing keeps showing the latest app.
    [self.dismissTimer invalidate];
    self.dismissTimer = [NSTimer scheduledTimerWithTimeInterval:kFlashDuration
                                                        repeats:NO
                                                          block:^(NSTimer *t) {
        [self hideFlash];
    }];
}

- (void)hideFlash {
    if (!self.flashVisible) return;
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:self.flashBar];
    } else {
        [NSTouchBar dismissSystemModalFunctionBar:self.flashBar];
    }
    self.flashVisible = NO;
    NSLog(@"TouchBarStatus: flash dismissed");
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self.dismissTimer invalidate];
    [self hideFlash];
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, NO);
    [NSTouchBarItem removeSystemTrayItem:self.trayItem];
    [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
