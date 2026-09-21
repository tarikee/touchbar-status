#import "AppGroup.h"

@interface AppGroup ()
@property (copy, readwrite) NSString *name;
@property (strong, readwrite) NSImage *icon;
@property (strong, readwrite) NSMutableArray<NSRunningApplication *> *mutableProcesses;
@end

@implementation AppGroup

- (NSArray<NSRunningApplication *> *)processes { return self.mutableProcesses; }

+ (NSArray<AppGroup *> *)groupsFromApplications:(NSArray<NSRunningApplication *> *)apps {
    NSMutableArray<AppGroup *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, AppGroup *> *byKey = [NSMutableDictionary dictionary];

    for (NSRunningApplication *a in apps) {
        NSString *key = a.bundleIdentifier ?: (a.localizedName ?: @"?");
        AppGroup *g = byKey[key];
        if (!g) {
            g = [AppGroup new];
            g.name = a.localizedName ?: @"?";
            g.icon = a.icon;
            g.mutableProcesses = [NSMutableArray array];
            byKey[key] = g;
            [order addObject:g];
        }
        [g.mutableProcesses addObject:a];
    }
    return order;
}

- (NSArray<AppWindow *> *)windows {
    NSMutableArray<AppWindow *> *all = [NSMutableArray array];
    for (NSRunningApplication *a in self.processes) {
        [all addObjectsFromArray:[WindowList windowsForPID:a.processIdentifier]];
    }
    return all;
}

- (NSUInteger)approximateWindowCount {
    // One process per window (Alacritty) still reads as multiple entries.
    if (self.processes.count > 1) return self.processes.count;
    NSUInteger n = 0;
    for (NSRunningApplication *a in self.processes) {
        n += [WindowList approximateWindowCountForPID:a.processIdentifier];
    }
    return n;
}

- (void)activate {
    [self.processes.firstObject activateWithOptions:0];
}

@end
