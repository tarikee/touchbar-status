//
//  The two-level Touch Bar picker: applications, then that application's
//  windows.
//

#import <Cocoa/Cocoa.h>
#import "AppGroup.h"

@interface Picker : NSObject
/// Identifier of the Control Strip tray item the picker is anchored to.
@property (copy) NSString *trayIdentifier;
/// Called after the picker closes, for any reason.
@property (copy) void (^onDismiss)(void);
@property (readonly) BOOL visible;

/// Shows the application list. `groups` should already be in the order to
/// display, most recently used first.
- (void)presentWithGroups:(NSArray<AppGroup *> *)groups;
- (void)dismiss;
@end
