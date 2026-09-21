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
//  Configurable without any GUI (deliberate — this runs on a machine where
//  System Settings is unreachable):
//
//    defaults write com.tarik.touchbarstatus FlashDuration -float 2.5
//    defaults write com.tarik.touchbarstatus FlashEnabled -bool NO
//    defaults write com.tarik.touchbarstatus TrayIconSize -float 26
//
//  Changes apply live; no restart needed.
//

#import <Cocoa/Cocoa.h>
#import "Picker.h"
#import "WindowList.h"
#import "AppGroup.h"

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
static NSString *const kControlStripBundleID = @"com.apple.controlstrip";

#pragma mark - Defaults keys

static NSString *const kFlashEnabled     = @"FlashEnabled";
static NSString *const kFlashDuration    = @"FlashDuration";
static NSString *const kTrayIconSize     = @"TrayIconSize";
static NSString *const kFlashIconSize    = @"FlashIconSize";
static NSString *const kFlashFontSize    = @"FlashFontSize";
static NSString *const kReassertInterval = @"ReassertInterval";
static NSString *const kPickerTimeout    = @"PickerTimeout";
/// Written on launch so the shell helper can tell whether the running
/// instance inherited Accessibility, and relaunch it from the terminal if not.
static NSString *const kLastLaunchAXKey  = @"LastLaunchAXTrusted";

static void RegisterDefaultConfig(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kFlashEnabled:     @YES,
        kFlashDuration:    @1.5,
        kTrayIconSize:     @24.0,
        kFlashIconSize:    @26.0,
        kFlashFontSize:    @18.0,
        kReassertInterval: @15.0,
        kPickerTimeout:    @10.0,
    }];
}

/// Read fresh each time so `defaults write` from a shell takes effect live.
static double ConfigDouble(NSString *key, double minimum, double maximum) {
    double v = [[NSUserDefaults standardUserDefaults] doubleForKey:key];
    if (v < minimum) v = minimum;
    if (v > maximum) v = maximum;
    return v;
}

static BOOL ConfigBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

#pragma mark - Tray view (permanent Control Strip icon)

@interface TrayView : NSView
@property (strong) NSButton *button;
@property (strong) NSImageView *iconView;
@property (strong) NSLayoutConstraint *iconWidth;
@property (strong) NSLayoutConstraint *iconHeight;
@end

@implementation TrayView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.imageScaling = NSImageScaleProportionallyDown;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.hidden = YES;   // the button carries the image; kept for sizing
    [self addSubview:_iconView];

    _button = [NSButton buttonWithTitle:@"" target:nil action:nil];
    _button.bordered = NO;
    _button.imagePosition = NSImageOnly;
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_button];
    [NSLayoutConstraint activateConstraints:@[
        [_button.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    _iconWidth  = [_iconView.widthAnchor constraintEqualToConstant:24];
    _iconHeight = [_iconView.heightAnchor constraintEqualToConstant:24];
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        _iconWidth, _iconHeight,
    ]];
    return self;
}

- (void)setIcon:(NSImage *)icon name:(NSString *)name {
    CGFloat size = ConfigDouble(kTrayIconSize, 8, 30);
    self.iconWidth.constant = size;
    self.iconHeight.constant = size;
    NSImage *sized = [icon copy];
    sized.size = NSMakeSize(size, size);
    self.iconView.image = sized;
    self.button.image = sized;
    self.toolTip = name;
}

@end

#pragma mark - Flash view (full-width icon + name)

@interface FlashView : NSView
@property (strong) NSImageView *iconView;
@property (strong) NSTextField *label;
@property (strong) NSLayoutConstraint *iconWidth;
@property (strong) NSLayoutConstraint *iconHeight;
@end

@implementation FlashView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.imageScaling = NSImageScaleProportionallyDown;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;

    _label = [NSTextField labelWithString:@""];
    _label.textColor = [NSColor labelColor];
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconView];
    [self addSubview:_label];

    _iconWidth  = [_iconView.widthAnchor constraintEqualToConstant:26];
    _iconHeight = [_iconView.heightAnchor constraintEqualToConstant:26];
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        _iconWidth, _iconHeight,
        [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    return self;
}

- (void)setIcon:(NSImage *)icon name:(NSString *)name {
    CGFloat size = ConfigDouble(kFlashIconSize, 8, 30);
    self.iconWidth.constant = size;
    self.iconHeight.constant = size;
    NSImage *sized = [icon copy];
    sized.size = NSMakeSize(size, size);
    self.iconView.image = sized;

    self.label.font = [NSFont systemFontOfSize:ConfigDouble(kFlashFontSize, 8, 26)
                                        weight:NSFontWeightSemibold];
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
@property (strong) NSTimer *reassertTimer;
@property (assign) BOOL flashVisible;
@property (assign) pid_t controlStripPID;
@property (strong) Picker *picker;
/// pids in most-recently-used order, so the picker reads like cmd-tab.
@property (strong) NSMutableArray<NSNumber *> *mruPIDs;
- (void)trayTapped:(id)sender;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    RegisterDefaultConfig();
    DFRSystemModalShowsCloseBoxWhenFrontMost(NO);

    self.mruPIDs = [NSMutableArray array];

    BOOL ax = [WindowList accessibilityAvailable];
    [[NSUserDefaults standardUserDefaults] setBool:ax forKey:kLastLaunchAXKey];
    NSLog(@"TouchBarStatus: accessibility %@ - window picking %@",
          ax ? @"granted" : @"NOT granted",
          ax ? @"enabled" : @"disabled (app list only)");

    self.picker = [[Picker alloc] init];
    self.picker.trayIdentifier = kTrayIdentifier;

    [self buildTrayItem];
    [self buildFlashBar];

    NSNotificationCenter *ws = [NSWorkspace sharedWorkspace].notificationCenter;
    [ws addObserver:self selector:@selector(activeAppChanged:)
               name:NSWorkspaceDidActivateApplicationNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(configChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];

    self.controlStripPID = [self currentControlStripPID];
    [self restartReassertTimer];

    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front) [self applyApp:front flash:NO];

    // Reinstate the tray item after the picker closes, same teardown problem
    // the flash has.
    __weak AppDelegate *weakSelf = self;
    self.picker.onDismiss = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf reinstallTrayItem]; });
    };

    NSLog(@"TouchBarStatus: ready");
}

#pragma mark Setup

- (void)buildTrayItem {
    self.trayView = [[TrayView alloc] initWithFrame:NSMakeRect(0, 0, 64, 30)];
    self.trayView.button.target = self;
    self.trayView.button.action = @selector(trayTapped:);
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

#pragma mark Control Strip presence

/// Cheap and idempotent: just re-assert the registration.
- (void)assertPresence {
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, YES);
}

/// Heavier: re-supply the view too, for when ControlStrip.app has restarted
/// and forgotten us entirely.
- (void)reinstallTrayItem {
    [NSTouchBarItem removeSystemTrayItem:self.trayItem];
    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, YES);
    NSLog(@"TouchBarStatus: tray item reinstalled");
}

/// ControlStrip.app is a background agent, so NSWorkspace never posts a launch
/// notification for it. Poll its pid instead: a change means it restarted and
/// has forgotten our registration.
- (pid_t)currentControlStripPID {
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:kControlStripBundleID];
    return apps.firstObject ? apps.firstObject.processIdentifier : 0;
}

- (void)checkControlStripRestart {
    pid_t pid = [self currentControlStripPID];
    if (pid == 0) return;                       // between restarts; try again next tick
    if (self.controlStripPID == 0) { self.controlStripPID = pid; return; }
    if (pid != self.controlStripPID) {
        NSLog(@"TouchBarStatus: ControlStrip restarted (%d -> %d)", self.controlStripPID, pid);
        self.controlStripPID = pid;
        [self reinstallTrayItem];
    }
}

- (void)restartReassertTimer {
    [self.reassertTimer invalidate];
    self.reassertTimer = nil;
    double interval = ConfigDouble(kReassertInterval, 0, 3600);
    if (interval <= 0) return;   // 0 disables the safety net
    self.reassertTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                         repeats:YES
                                                           block:^(NSTimer *t) {
        [self checkControlStripRestart];
        [self assertPresence];
    }];
}

#pragma mark Config

- (void)configChanged:(NSNotification *)note {
    [self restartReassertTimer];
    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front) [self applyApp:front flash:NO];   // re-render at any new sizes
}

#pragma mark Focus tracking

- (void)activeAppChanged:(NSNotification *)note {
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey]
                                ?: [NSWorkspace sharedWorkspace].frontmostApplication;
    if (app) [self applyApp:app flash:YES];
}

- (void)noteMRU:(NSRunningApplication *)app {
    NSNumber *pid = @(app.processIdentifier);
    [self.mruPIDs removeObject:pid];
    [self.mruPIDs insertObject:pid atIndex:0];
}

/// Regular (Dock-visible) apps, most recently used first, excluding ourselves.
- (NSArray<NSRunningApplication *> *)orderedApps {
    NSMutableArray<NSRunningApplication *> *ordered = [NSMutableArray array];
    NSMutableArray<NSRunningApplication *> *rest = [NSMutableArray array];

    NSMutableDictionary<NSNumber *, NSRunningApplication *> *byPID = [NSMutableDictionary dictionary];
    for (NSRunningApplication *a in [NSWorkspace sharedWorkspace].runningApplications) {
        if (a.activationPolicy != NSApplicationActivationPolicyRegular) continue;
        if (a.processIdentifier == NSProcessInfo.processInfo.processIdentifier) continue;
        byPID[@(a.processIdentifier)] = a;
    }
    for (NSNumber *pid in self.mruPIDs) {
        NSRunningApplication *a = byPID[pid];
        if (a) { [ordered addObject:a]; [byPID removeObjectForKey:pid]; }
    }
    for (NSRunningApplication *a in byPID.allValues) [rest addObject:a];
    [rest sortUsingComparator:^NSComparisonResult(NSRunningApplication *x, NSRunningApplication *y) {
        return [(x.localizedName ?: @"") caseInsensitiveCompare:(y.localizedName ?: @"")];
    }];
    [ordered addObjectsFromArray:rest];
    return ordered;
}

- (void)trayTapped:(id)sender {
    if (self.picker.visible) { [self.picker dismiss]; return; }
    [self hideFlash];
    [self.picker presentWithGroups:[AppGroup groupsFromApplications:[self orderedApps]]];
}

- (void)applyApp:(NSRunningApplication *)app flash:(BOOL)shouldFlash {
    NSString *name = app.localizedName ?: @"Unknown";
    NSImage *icon = app.icon;

    [self noteMRU:app];
    [self.trayView setIcon:icon name:name];
    [self.flashView setIcon:icon name:name];
    [self assertPresence];

    // Never let the flash steal the bar back while the picker is open.
    if (shouldFlash && ConfigBool(kFlashEnabled) && !self.picker.visible) [self showFlash];
    NSLog(@"TouchBarStatus: focus -> %@", name);
}

#pragma mark Flash presentation

- (void)showFlash {
    if (!self.flashVisible) {
        if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
            [NSTouchBar presentSystemModalTouchBar:self.flashBar placement:1
                          systemTrayItemIdentifier:kTrayIdentifier];
        } else {
            [NSTouchBar presentSystemModalFunctionBar:self.flashBar placement:1
                             systemTrayItemIdentifier:kTrayIdentifier];
        }
        self.flashVisible = YES;
        NSLog(@"TouchBarStatus: flash presented");
    }
    // Restart the countdown so rapid cmd-tabbing keeps showing the latest app.
    [self.dismissTimer invalidate];
    self.dismissTimer = [NSTimer scheduledTimerWithTimeInterval:ConfigDouble(kFlashDuration, 0.2, 10.0)
                                                        repeats:NO
                                                          block:^(NSTimer *t) { [self hideFlash]; }];
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

    // Dismissing the system-modal bar tears our item out of the Control Strip
    // (observed: the icon is present before the first flash and gone after).
    // Nothing reports this - DFRElementGetControlStripPresenceForIdentifier
    // returns 0 even right after a successful set - so reinstall it
    // unconditionally once the teardown has settled.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self reinstallTrayItem]; });
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self.dismissTimer invalidate];
    [self.reassertTimer invalidate];
    [self hideFlash];
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, NO);
    [NSTouchBarItem removeSystemTrayItem:self.trayItem];
    [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

/// `--dump` prints what the picker would show and exits. Lets the picker's
/// data layer be verified from a shell, without tapping the Touch Bar.
static int DumpApps(void) {
    BOOL ax = [WindowList accessibilityAvailable];
    printf("accessibility: %s\n", ax ? "GRANTED" : "NOT GRANTED (app list only)");
    NSMutableArray<NSRunningApplication *> *regular = [NSMutableArray array];
    for (NSRunningApplication *a in [NSWorkspace sharedWorkspace].runningApplications) {
        if (a.activationPolicy == NSApplicationActivationPolicyRegular) [regular addObject:a];
    }
    for (AppGroup *g in [AppGroup groupsFromApplications:regular]) {
        NSArray<AppWindow *> *ws = [g windows];
        printf("%-24s  procs=%lu  windows=%lu\n", g.name.UTF8String,
               (unsigned long)g.processes.count, (unsigned long)ws.count);
        for (AppWindow *w in ws) printf("      - %s\n", w.title.UTF8String);
    }
    return 0;
}

static AppDelegate *gDelegate = nil;

/// SIGUSR1 opens the picker, so it can be triggered without a physical tap.
static void HandleUSR1(int sig) {
    dispatch_async(dispatch_get_main_queue(), ^{ [gDelegate trayTapped:nil]; });
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--dump") == 0) return DumpApps();
        }
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        gDelegate = delegate;
        app.delegate = delegate;
        signal(SIGUSR1, HandleUSR1);
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
