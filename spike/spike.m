#import <Cocoa/Cocoa.h>

extern void DFRElementSetControlStripPresenceForIdentifier(NSString *identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

@interface NSTouchBarItem (DFRPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

static NSString *const kIdent = @"com.tarik.touchbarstatus.spike";

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSCustomTouchBarItem *item;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSLog(@"SPIKE: launching");
    DFRSystemModalShowsCloseBoxWhenFrontMost(NO);

    self.item = [[NSCustomTouchBarItem alloc] initWithIdentifier:kIdent];
    NSButton *b = [NSButton buttonWithTitle:@"SPIKE-OK"
                                     target:self
                                     action:@selector(tapped:)];
    b.bezelColor = [NSColor systemGreenColor];
    self.item.view = b;

    [NSTouchBarItem addSystemTrayItem:self.item];
    DFRElementSetControlStripPresenceForIdentifier(kIdent, YES);
    NSLog(@"SPIKE: item registered in control strip");
}
- (void)tapped:(id)sender { NSLog(@"SPIKE: tapped!"); }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *d = [AppDelegate new];
        app.delegate = d;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
