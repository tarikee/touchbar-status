//
//  Window enumeration and focusing, via the Accessibility API.
//
//  All of this degrades to "unavailable" when the process is not Accessibility
//  trusted, which is the normal case when launched by launchd. Callers must
//  check +accessibilityAvailable and fall back to activating the whole app.
//

#import <Cocoa/Cocoa.h>

/// One window of one application.
@interface AppWindow : NSObject
@property (readonly, copy) NSString *title;
/// Brings this specific window to the front and focuses its app.
- (BOOL)focus;
@end

@interface WindowList : NSObject
/// Whether this process can read window titles and raise windows.
+ (BOOL)accessibilityAvailable;
/// Windows of the given process, in the app's own order. Empty when
/// Accessibility is unavailable.
+ (NSArray<AppWindow *> *)windowsForPID:(pid_t)pid;
/// Window count without Accessibility, via CGWindowList. Titles are not
/// available this way, but the count is, which is enough to decide whether
/// drilling in is worthwhile.
+ (NSUInteger)approximateWindowCountForPID:(pid_t)pid;
@end
