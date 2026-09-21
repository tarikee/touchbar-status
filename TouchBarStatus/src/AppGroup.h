//
//  One entry in the picker's first level.
//
//  An app can be several processes (Alacritty spawns one per window) or one
//  process with several windows (Brave). Both are grouped under a single
//  entry so the picker shows one button per application either way.
//

#import <Cocoa/Cocoa.h>
#import "WindowList.h"

@interface AppGroup : NSObject
@property (readonly, copy) NSString *name;
@property (readonly, strong) NSImage *icon;
@property (readonly, strong) NSArray<NSRunningApplication *> *processes;

/// Every window of every process in this group, across all of them.
- (NSArray<AppWindow *> *)windows;
/// Rough count without Accessibility, used to label the app button.
- (NSUInteger)approximateWindowCount;
/// Focus the group's most recently used process.
- (void)activate;

/// Groups the given applications, preserving their order (most recent first).
+ (NSArray<AppGroup *> *)groupsFromApplications:(NSArray<NSRunningApplication *> *)apps;
@end
