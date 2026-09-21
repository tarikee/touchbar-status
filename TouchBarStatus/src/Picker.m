#import "Picker.h"
#import "WindowList.h"
#import "AppGroup.h"

static NSString *const kPickerItemIdentifier = @"com.tarik.touchbarstatus.picker";

/// Touch Bar rows are 30pt tall; these are tuned so roughly eight entries are
/// visible at once on a ~1000pt strip, with the rest reachable by swiping.
static const CGFloat kRowHeight    = 30.0;
static const CGFloat kAppButtonW   = 116.0;
static const CGFloat kWinButtonW   = 190.0;
static const CGFloat kIconSize     = 20.0;

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

@interface Picker ()
@property (strong) NSTouchBar *touchBar;
@property (strong) NSCustomTouchBarItem *item;
@property (strong) NSScrollView *scrollView;
@property (strong) NSStackView *stack;
@property (strong) NSTimer *timeoutTimer;
@property (strong) NSArray<AppGroup *> *groups;
@property (strong) NSArray<AppWindow *> *windows;
@property (assign, readwrite) BOOL visible;
@end

@implementation Picker

#pragma mark - Presentation

- (void)presentWithGroups:(NSArray<AppGroup *> *)groups {
    self.groups = groups;
    [self buildBarIfNeeded];
    [self showAppLevel];

    if (!self.visible) {
        if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
            [NSTouchBar presentSystemModalTouchBar:self.touchBar placement:1
                          systemTrayItemIdentifier:self.trayIdentifier];
        } else {
            [NSTouchBar presentSystemModalFunctionBar:self.touchBar placement:1
                             systemTrayItemIdentifier:self.trayIdentifier];
        }
        self.visible = YES;
        NSLog(@"TouchBarStatus: picker opened (%lu apps, accessibility=%@)",
              (unsigned long)groups.count,
              [WindowList accessibilityAvailable] ? @"yes" : @"no");
    }
    [self restartTimeout];
}

- (void)dismiss {
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
    if (!self.visible) return;
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:self.touchBar];
    } else {
        [NSTouchBar dismissSystemModalFunctionBar:self.touchBar];
    }
    self.visible = NO;
    self.windows = nil;
    NSLog(@"TouchBarStatus: picker closed");
    if (self.onDismiss) self.onDismiss();
}

- (void)restartTimeout {
    [self.timeoutTimer invalidate];
    double seconds = [[NSUserDefaults standardUserDefaults] doubleForKey:@"PickerTimeout"];
    if (seconds < 2) seconds = 2;
    if (seconds > 60) seconds = 60;
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:seconds repeats:NO
                                                          block:^(NSTimer *t) { [self dismiss]; }];
}

#pragma mark - Bar construction

- (void)buildBarIfNeeded {
    if (self.touchBar) return;

    self.stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.stack.spacing = 6;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 1000, kRowHeight)];
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.hasVerticalScroller = NO;
    self.scrollView.drawsBackground = NO;
    self.scrollView.documentView = self.stack;

    [NSLayoutConstraint activateConstraints:@[
        [self.stack.heightAnchor constraintEqualToConstant:kRowHeight],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.contentView.topAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentView.leadingAnchor],
    ]];

    self.item = [[NSCustomTouchBarItem alloc] initWithIdentifier:kPickerItemIdentifier];
    self.item.view = self.scrollView;

    self.touchBar = [[NSTouchBar alloc] init];
    self.touchBar.defaultItemIdentifiers = @[kPickerItemIdentifier];
    self.touchBar.templateItems = [NSSet setWithObject:self.item];
}

- (void)clearRow {
    for (NSView *v in [self.stack.arrangedSubviews copy]) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

- (NSButton *)buttonWithTitle:(NSString *)title image:(NSImage *)image
                        width:(CGFloat)width action:(SEL)action tag:(NSInteger)tag {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    if (image) {
        NSImage *sized = [image copy];
        sized.size = NSMakeSize(kIconSize, kIconSize);
        b.image = sized;
        b.imagePosition = NSImageLeft;
    }
    b.tag = tag;
    b.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    b.lineBreakMode = NSLineBreakByTruncatingTail;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:width].active = YES;
    [b.heightAnchor constraintEqualToConstant:kRowHeight].active = YES;
    return b;
}

#pragma mark - Level 1: applications

- (void)showAppLevel {
    [self clearRow];
    self.windows = nil;

    [self.stack addArrangedSubview:
        [self buttonWithTitle:@"✕" image:nil width:44 action:@selector(closeTapped:) tag:-1]];

    NSInteger i = 0;
    for (AppGroup *g in self.groups) {
        NSUInteger count = [g approximateWindowCount];
        NSString *title = count > 1 ? [NSString stringWithFormat:@"%@ (%lu)", g.name, (unsigned long)count]
                                    : g.name;
        [self.stack addArrangedSubview:
            [self buttonWithTitle:title image:g.icon width:kAppButtonW
                           action:@selector(appTapped:) tag:i]];
        i++;
    }
    [self.stack layoutSubtreeIfNeeded];
    self.stack.frame = NSMakeRect(0, 0, self.stack.fittingSize.width, kRowHeight);
}

- (void)appTapped:(NSButton *)sender {
    [self restartTimeout];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.groups.count) return;
    AppGroup *group = self.groups[sender.tag];

    NSArray<AppWindow *> *windows = [group windows];
    if (windows.count > 1) {
        [self showWindowLevelFor:group windows:windows];
        return;
    }

    // One window, or no Accessibility to enumerate them: just activate the app.
    [group activate];
    [self dismiss];
}

#pragma mark - Level 2: that application's windows

- (void)showWindowLevelFor:(AppGroup *)group windows:(NSArray<AppWindow *> *)windows {
    [self clearRow];
    self.windows = windows;

    [self.stack addArrangedSubview:
        [self buttonWithTitle:@"‹" image:nil width:44 action:@selector(backTapped:) tag:-1]];

    NSInteger i = 0;
    for (AppWindow *w in windows) {
        [self.stack addArrangedSubview:
            [self buttonWithTitle:w.title image:group.icon width:kWinButtonW
                           action:@selector(windowTapped:) tag:i]];
        i++;
    }
    [self.stack layoutSubtreeIfNeeded];
    self.stack.frame = NSMakeRect(0, 0, self.stack.fittingSize.width, kRowHeight);
    NSLog(@"TouchBarStatus: picker showing %lu windows of %@",
          (unsigned long)windows.count, group.name);
}

- (void)windowTapped:(NSButton *)sender {
    [self restartTimeout];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.windows.count) return;
    AppWindow *w = self.windows[sender.tag];
    NSLog(@"TouchBarStatus: focusing window '%@'", w.title);
    [w focus];
    [self dismiss];
}

- (void)backTapped:(NSButton *)sender {
    [self restartTimeout];
    [self showAppLevel];
}

- (void)closeTapped:(NSButton *)sender {
    [self dismiss];
}

@end
