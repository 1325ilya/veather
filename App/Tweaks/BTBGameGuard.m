//  BTBGameGuard.m — /gameguard: a memory scanner/editor for OFFLINE single-player games.
//  Four-finger long press (or the floating "GG" button) opens a panel with four tabs:
//    Search — find a number (Byte…Qword, Float, Double, XOR, ranges, groups, Auto) in chosen memory regions,
//             narrow it down, change or freeze it.
//    List   — saved addresses that stay between launches when they live in the app's code.
//    Scripts — Lua scripts that use a GameGuardian-style gg.* API (see BTBGGLua.m).
//    Memory — hex view/editor.
//  Works only on the process it is injected into. Do not use it in online games.

#import "BTBCommon.h"
#import "BTBGGUI.h"
#import <UIKit/UIKit.h>

NSString *const BTBGGResultsChangedNotification = @"BTBGGResultsChanged";

void BTBGGNotifyResultsChanged(void) {
	BTBOnMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:BTBGGResultsChangedNotification object:nil]; });
}

// MARK: - Panel window

// Overlay window that only reacts to touches on its own button; everything else goes to the game.
@interface BTBGGWindow : UIWindow
@property (nonatomic, weak) UIView *button;
@end

@implementation BTBGGWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	if (self.button && !self.button.hidden && CGRectContainsPoint(CGRectInset(self.button.frame, -8, -8), point)) {
		return [self.button hitTest:[self.button convertPoint:point fromView:self] withEvent:event];
	}
	return nil;
}
@end

@interface BTBGGPanelHelper : NSObject
+ (instancetype)shared;
- (void)close;
- (void)openSettings;
@end

static BTBGGWindow *gOverlay;
static UIWindow *gPanelWindow;
static __weak UIWindow *gGameWindow;
static UITabBarController *gTabs;
static BOOL gButtonHidden;                 // "hide the button until the game restarts"
static CGPoint gButtonCenter = {-1, -1};   // where the user left the floating button

static UIWindowScene *ActiveScene(void) {
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
	}
	return nil;
}

@interface BTBGGSearchVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

static UINavigationController *MakeNav(UIViewController *vc, NSString *title, NSString *symbol) {
	vc.title = title;
	UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:BL(@"Close", @"Закрыть") style:UIBarButtonItemStylePlain target:[BTBGGPanelHelper shared] action:@selector(close)];
	UIBarButtonItem *gear = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:[BTBGGPanelHelper shared] action:@selector(openSettings)];
	vc.navigationItem.rightBarButtonItems = @[close, gear];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.navigationBar.tintColor = BTBGGAccent();
	nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:symbol] tag:0];
	return nav;
}

static UITabBarController *Tabs(void) {
	if (gTabs) return gTabs;
	UITabBarController *t = [UITabBarController new];
	t.viewControllers = @[
		MakeNav([BTBGGSearchVC new], BL(@"Search", @"Поиск"), @"magnifyingglass"),
		MakeNav(BTBGGMakeSavedListVC(), BL(@"List", @"Список"), @"list.bullet"),
		MakeNav(BTBGGMakeScriptsVC(), BL(@"Scripts", @"Скрипты"), @"scroll"),
		MakeNav(BTBGGMakeMemoryVC(), BL(@"Memory", @"Память"), @"memorychip"),
		MakeNav(BTBGGMakeConverterVC(), BL(@"Convert", @"Конвертер"), @"arrow.left.arrow.right"),
	];
	t.view.tintColor = BTBGGAccent();
	gTabs = t;
	return t;
}

@implementation BTBGGPanelHelper
+ (instancetype)shared {
	static BTBGGPanelHelper *h;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ h = [BTBGGPanelHelper new]; });
	return h;
}
- (void)close { BTBGGClosePanel(); }
- (void)openSettings {
	UINavigationController *nav = (UINavigationController *)gTabs.selectedViewController;
	if (![nav isKindOfClass:[UINavigationController class]]) return;
	if ([NSStringFromClass([nav.topViewController class]) isEqualToString:@"BTBGGSettingsVC"]) return;
	[nav pushViewController:BTBGGMakeSettingsVC() animated:YES];
}
@end

BOOL BTBGGPanelIsOpen(void) { return gPanelWindow != nil; }

void BTBGGOpenPanel(void) {
	if (gPanelWindow) return;
	UIWindowScene *scene = ActiveScene();
	if (!scene) return;
	// the game's window, never our own overlay (a tap on the GG button can make the overlay key)
	for (UIWindow *w in scene.windows) if (![w isKindOfClass:[BTBGGWindow class]] && w.windowLevel <= UIWindowLevelNormal && !w.hidden) { gGameWindow = w; if (w.isKeyWindow) break; }
	// The panel lives in its own window instead of being presented on the game's view controller:
	// game engines (Unity, Unreal) often manage their own controllers and swallow presentations or touches.
	UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
	window.frame = scene.coordinateSpace.bounds;
	window.windowLevel = UIWindowLevelAlert + 200;
	window.backgroundColor = BTBGGBackground();
	window.alpha = BTBGGPanelAlpha();
	window.rootViewController = Tabs();
	gPanelWindow = window;
	[window makeKeyAndVisible];
}

void BTBGGClosePanel(void) {
	UIWindow *panel = gPanelWindow;
	if (!panel) return;
	[panel endEditing:YES];
	gPanelWindow = nil;
	panel.hidden = YES;
	panel.rootViewController = nil;
	[gGameWindow makeKeyWindow];
}

void BTBGGRestoreKeyWindow(void) {
	if (gPanelWindow) [gPanelWindow makeKeyWindow]; else [gGameWindow makeKeyWindow];
}

void BTBGGApplyPanelAlpha(void) {
	BTBOnMain(^{ if (gPanelWindow) gPanelWindow.alpha = BTBGGPanelAlpha(); });
}

static void RestyleFloatingButton(void);

void BTBGGRebuildPanel(BOOL openSettings) {
	BTBOnMain(^{
		NSInteger index = gTabs ? gTabs.selectedIndex : 0;
		gTabs = nil;
		RestyleFloatingButton();
		if (!gPanelWindow) return;
		gPanelWindow.backgroundColor = BTBGGBackground();
		gPanelWindow.rootViewController = Tabs();
		gTabs.selectedIndex = index;
		if (openSettings) [[BTBGGPanelHelper shared] openSettings];
	});
}

void BTBGGHideFloatingButton(void) {
	BTBOnMain(^{
		gButtonHidden = YES;
		gOverlay.hidden = YES;
		gOverlay = nil;
	});
}

BOOL BTBGGFloatingButtonHidden(void) { return gButtonHidden; }

void BTBGGSelectTab(NSInteger index) {
	BTBOnMain(^{
		BTBGGOpenPanel();
		if (gTabs && index >= 0 && index < (NSInteger)gTabs.viewControllers.count) gTabs.selectedIndex = index;
	});
}

void BTBGGShowMemory(uint64_t address) {
	BTBOnMain(^{
		BTBGGOpenPanel();
		if (!gTabs) return;
		gTabs.selectedIndex = 3;
		UINavigationController *nav = gTabs.viewControllers[3];
		[nav popToRootViewControllerAnimated:NO];
		BTBGGMemoryShowAddress(nav.viewControllers.firstObject, address);
	});
}

// MARK: - Trigger and floating button

@interface BTBGameGuard : NSObject
+ (instancetype)shared;
- (void)attachToWindow:(UIWindow *)window;
- (void)attachToAllWindows;
- (void)showFloatingButton;
@end

@implementation BTBGameGuard

+ (instancetype)shared {
	static BTBGameGuard *g;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ g = [BTBGameGuard new]; });
	return g;
}

- (void)attachToWindow:(UIWindow *)window {
	for (UIGestureRecognizer *g in window.gestureRecognizers) if ([g.name isEqualToString:@"BTBGameGuard"]) return;
	UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handle:)];
	g.name = @"BTBGameGuard";
	g.numberOfTouchesRequired = 4;
	g.minimumPressDuration = 0.8;
	g.allowableMovement = 60;
	g.cancelsTouchesInView = NO;
	g.delaysTouchesBegan = NO;
	[window addGestureRecognizer:g];
}

- (void)attachToAllWindows {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) [self attachToWindow:w];
	}
}

- (void)handle:(UILongPressGestureRecognizer *)g {
	if (g.state == UIGestureRecognizerStateBegan && BTBGGFourFingerEnabled()) BTBGGOpenPanel();
}

/// A round draggable button: works even where a multi-finger gesture can't be recognised.
/// It snaps to the nearest screen edge when released.
- (void)showFloatingButton {
	if (gOverlay || gButtonHidden) return;
	UIWindowScene *scene = ActiveScene();
	if (!scene) return;
	BTBGGWindow *window = [[BTBGGWindow alloc] initWithWindowScene:scene];
	window.frame = scene.coordinateSpace.bounds;
	window.windowLevel = UIWindowLevelAlert + 100;
	window.backgroundColor = UIColor.clearColor;
	window.rootViewController = [UIViewController new];
	window.rootViewController.view.backgroundColor = UIColor.clearColor;
	BTBGGGradientButton *button = [BTBGGGradientButton buttonWithType:UIButtonTypeCustom];
	button.filled = YES;
	button.layer.shadowOpacity = 0.35;
	button.layer.shadowRadius = 6;
	button.layer.shadowOffset = CGSizeMake(0, 2);
	[button addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
	[button addGestureRecognizer:pan];
	[window.rootViewController.view addSubview:button];
	window.button = button;
	window.hidden = NO;
	gOverlay = window;
	RestyleFloatingButton();
}

- (void)openPanel { BTBGGOpenPanel(); }

- (void)dragButton:(UIPanGestureRecognizer *)pan {
	UIView *button = pan.view;
	CGPoint t = [pan translationInView:button.superview];
	button.center = CGPointMake(button.center.x + t.x, button.center.y + t.y);
	[pan setTranslation:CGPointZero inView:button.superview];
	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		CGRect bounds = button.superview.bounds;
		UIEdgeInsets safe = button.superview.safeAreaInsets;
		CGFloat r = button.bounds.size.width / 2;
		CGFloat x = button.center.x < bounds.size.width / 2 ? safe.left + r + 6 : bounds.size.width - safe.right - r - 6;
		CGFloat y = MIN(MAX(button.center.y, safe.top + r + 6), bounds.size.height - safe.bottom - r - 6);
		[UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
			button.center = CGPointMake(x, y);
		} completion:nil];
		gButtonCenter = CGPointMake(x, y);
	}
}

@end

/// Draws the button for the current style: a flat "GG" disc in the legacy style, a gradient disc with a target in the new one.
static void RestyleFloatingButton(void) {
	BTBGGGradientButton *button = (BTBGGGradientButton *)gOverlay.button;
	if (![button isKindOfClass:[BTBGGGradientButton class]]) return;
	BOOL legacy = BTBGGCurrentStyle() == BTBGGStyleLegacy;
	CGFloat size = legacy ? 46 : 54;
	CGPoint center = gButtonCenter.x >= 0 ? gButtonCenter : CGPointMake(12 + size / 2, 140 + size / 2);
	button.bounds = CGRectMake(0, 0, size, size);
	button.center = center;
	button.layer.cornerRadius = size / 2;
	button.clipsToBounds = NO;
	[button applyStyle];
	if (legacy) {
		[button setImage:nil forState:UIControlStateNormal];
		[button setTitle:@"GG" forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
		[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	} else {
		[button setTitle:nil forState:UIControlStateNormal];
		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
		UIImage *icon = [UIImage systemImageNamed:@"scope" withConfiguration:cfg] ?: [UIImage systemImageNamed:@"magnifyingglass" withConfiguration:cfg];
		[button setImage:icon forState:UIControlStateNormal];
		button.tintColor = UIColor.whiteColor;
	}
}

// MARK: - Search tab

static NSArray<NSNumber *> *AllTypes(void) {
	return @[@(BTBGGTypeDword), @(BTBGGTypeFloat), @(BTBGGTypeDouble), @(BTBGGTypeQword), @(BTBGGTypeWord), @(BTBGGTypeByte), @(BTBGGTypeXor), @(BTBGGTypeHidden), @(BTBGGTypeAuto),
		@(BTBGGTypeUDword), @(BTBGGTypeUQword), @(BTBGGTypeUWord), @(BTBGGTypeUByte),
		@(BTBGGTypeNotDword), @(BTBGGTypeNegDword), @(BTBGGTypeNotQword), @(BTBGGTypeNegQword)];
}

static NSString *TypeTitle(BTBGGType t) {
	switch (t) {
		case BTBGGTypeDword: return BL(@"Dword = Int32 — whole number (most common)", @"Dword = Int32 — целое число (чаще всего)");
		case BTBGGTypeFloat: return BL(@"Float — decimal", @"Float — дробное");
		case BTBGGTypeDouble: return BL(@"Double — decimal ×2", @"Double — дробное ×2");
		case BTBGGTypeQword: return BL(@"Qword = Int64 — big whole number", @"Qword = Int64 — большое целое");
		case BTBGGTypeWord: return BL(@"Word = Int16 — small whole number", @"Word = Int16 — малое целое (2 байта)");
		case BTBGGTypeByte: return BL(@"Byte = Int8 — tiny whole number", @"Byte = Int8 — крошечное целое (1 байт)");
		case BTBGGTypeUDword: return BL(@"UInt32 — Dword without a sign", @"UInt32 — Dword без знака");
		case BTBGGTypeUQword: return BL(@"UInt64 — Qword without a sign", @"UInt64 — Qword без знака");
		case BTBGGTypeUWord: return BL(@"UInt16 — Word without a sign", @"UInt16 — Word без знака");
		case BTBGGTypeUByte: return BL(@"UInt8 — Byte without a sign", @"UInt8 — Byte без знака");
		case BTBGGTypeNotDword: return BL(@"~Int32 — stored inverted (bitwise NOT)", @"~Int32 — хранится инвертированным (NOT)");
		case BTBGGTypeNegDword: return BL(@"-Int32 — stored with the opposite sign", @"-Int32 — хранится с обратным знаком");
		case BTBGGTypeNotQword: return BL(@"~Int64 — stored inverted (bitwise NOT)", @"~Int64 — хранится инвертированным (NOT)");
		case BTBGGTypeNegQword: return BL(@"-Int64 — stored with the opposite sign", @"-Int64 — хранится с обратным знаком");
		case BTBGGTypeHidden: return BL(@"Hidden — try XOR, NOT and minus (32/64 bit)", @"Скрытое — перебрать XOR, NOT и минус (32/64 бит)");
		case BTBGGTypeXor: return BL(@"XOR — number hidden by encryption", @"XOR — число спрятано шифром");
		case BTBGGTypeAuto: return BL(@"Auto — try several types", @"Авто — перебрать несколько типов");
	}
	return @"";
}

static BOOL ModeNeedsField(BTBGGMode m) {
	return m == BTBGGModeExact || m == BTBGGModeRange || m == BTBGGModeIncreasedBy || m == BTBGGModeDecreasedBy;
}

@implementation BTBGGSearchVC {
	UITableView *_table;
	UIView *_header;
	UIStackView *_stack;
	UILabel *_step, *_hint, *_status;
	UIButton *_typeButton, *_regionsButton, *_unknownButton, *_primary, *_reset, *_undo, *_modeButton, *_refresh, *_more;
	UIStackView *_optionsRow, *_secondaryRow, *_toolsRow;
	UITextField *_field;
	BTBGGType _type;
	BTBGGMode _mode;
	BOOL _unknown;
	BOOL _busy;
	CGFloat _headerWidth;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = BTBGGBackground();
	_type = BTBGGTypeDword;
	_mode = BTBGGModeExact;

	UILabel *warn = BTBGGLabel([UIFont systemFontOfSize:12], UIColor.systemOrangeColor);
	warn.text = BL(@"Offline single-player games only. Online, you can get banned.", @"Только оффлайн-игры для одного игрока. В онлайне могут забанить.");
	_step = BTBGGLabel([UIFont boldSystemFontOfSize:22], UIColor.labelColor);
	_hint = BTBGGLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);

	_typeButton = BTBGGBigButton(@"", NO, nil, nil);
	_typeButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	_regionsButton = BTBGGBigButton(@"", NO, self, @selector(openRegions));
	_regionsButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	[self buildTypeMenu];
	_optionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[_typeButton, _regionsButton]];
	_optionsRow.spacing = 10;
	_optionsRow.distribution = UIStackViewDistributionFillEqually;

	_field = [UITextField new];
	_field.borderStyle = UITextBorderStyleRoundedRect;
	_field.font = [UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightMedium];
	_field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	_field.clearButtonMode = UITextFieldViewModeWhileEditing;
	_field.textAlignment = NSTextAlignmentCenter;
	[_field.heightAnchor constraintEqualToConstant:50].active = YES;

	_unknownButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_unknownButton.titleLabel.font = [UIFont systemFontOfSize:15];
	_unknownButton.titleLabel.numberOfLines = 0;
	_unknownButton.titleLabel.textAlignment = NSTextAlignmentCenter;
	[_unknownButton addTarget:self action:@selector(toggleUnknown) forControlEvents:UIControlEventTouchUpInside];

	_primary = BTBGGBigButton(@"", YES, self, @selector(primaryTapped));
	_reset = BTBGGBigButton(BL(@"Start over", @"Сначала"), NO, self, @selector(startOver));
	_modeButton = BTBGGBigButton(@"", NO, nil, nil);
	[self buildModeMenu];
	_undo = BTBGGBigButton(BL(@"↶ Undo the last step", @"↶ Отменить шаг"), NO, self, @selector(undoStep));
	_secondaryRow = [[UIStackView alloc] initWithArrangedSubviews:@[_reset, _modeButton]];
	_secondaryRow.spacing = 10;
	_secondaryRow.distribution = UIStackViewDistributionFillEqually;

	_refresh = [UIButton buttonWithType:UIButtonTypeSystem];
	_refresh.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	[_refresh setTitle:BL(@"↻ Refresh", @"↻ Обновить") forState:UIControlStateNormal];
	[_refresh addTarget:self action:@selector(refreshValues) forControlEvents:UIControlEventTouchUpInside];
	_more = [UIButton buttonWithType:UIButtonTypeSystem];
	_more.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	[_more setTitle:BL(@"All results ▾", @"Все результаты ▾") forState:UIControlStateNormal];
	[self buildMoreMenu];
	_toolsRow = [[UIStackView alloc] initWithArrangedSubviews:@[_refresh, _more]];
	_toolsRow.distribution = UIStackViewDistributionFillEqually;

	_status = BTBGGLabel([UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);

	_stack = [[UIStackView alloc] initWithArrangedSubviews:@[warn, _step, _hint, _optionsRow, _field, _unknownButton, _primary, _secondaryRow, _undo, _toolsRow, _status]];
	_stack.axis = UILayoutConstraintAxisVertical;
	_stack.spacing = 10;
	[_stack setCustomSpacing:14 afterView:warn];
	_stack.translatesAutoresizingMaskIntoConstraints = NO;

	_header = [UIView new];
	[_header addSubview:_stack];
	[NSLayoutConstraint activateConstraints:@[
		[_stack.topAnchor constraintEqualToAnchor:_header.topAnchor constant:12],
		[_stack.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor constant:20],
		[_stack.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor constant:-20],
		[_stack.bottomAnchor constraintEqualToAnchor:_header.bottomAnchor constant:-8],
	]];

	_table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	_table.backgroundColor = BTBGGBackground();
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.dataSource = self;
	_table.delegate = self;
	_table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.view addSubview:_table];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resultsChanged) name:BTBGGResultsChangedNotification object:nil];
	[self refreshUI];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self refreshUI];
	[_table reloadData];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updateHeaderHeight];
}

/// A table header does not size itself: measure it whenever the width or the content changes.
- (void)updateHeaderHeight {
	CGFloat w = _table.bounds.size.width;
	if (w <= 0) return;
	CGFloat h = [_header systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
	if (_table.tableHeaderView == _header && fabs(_header.frame.size.height - h) < 0.5 && _headerWidth == w) return;
	_headerWidth = w;
	_header.frame = CGRectMake(0, 0, w, h);
	_table.tableHeaderView = _header;
}

- (void)resultsChanged {
	if (_busy) return;
	[self refreshUI];
	[_table reloadData];
}

#pragma mark Menus

- (void)buildTypeMenu {
	NSMutableArray *actions = [NSMutableArray array];
	for (NSNumber *n in AllTypes()) {
		BTBGGType t = (BTBGGType)n.integerValue;
		[actions addObject:[UIAction actionWithTitle:TypeTitle(t) image:nil identifier:nil handler:^(UIAction *x) {
			self->_type = t;
			[self refreshUI];
		}]];
	}
	_typeButton.menu = [UIMenu menuWithChildren:actions];
	_typeButton.showsMenuAsPrimaryAction = YES;
}

- (void)buildModeMenu {
	NSArray *items = @[
		@[@(BTBGGModeExact), BL(@"Exact new value", @"Точное новое значение")],
		@[@(BTBGGModeChanged), BL(@"Value changed", @"Значение изменилось")],
		@[@(BTBGGModeUnchanged), BL(@"Value did not change", @"Значение не менялось")],
		@[@(BTBGGModeGreater), BL(@"Value increased", @"Значение выросло")],
		@[@(BTBGGModeSmaller), BL(@"Value decreased", @"Значение уменьшилось")],
		@[@(BTBGGModeIncreasedBy), BL(@"Increased by exactly…", @"Выросло ровно на…")],
		@[@(BTBGGModeDecreasedBy), BL(@"Decreased by exactly…", @"Уменьшилось ровно на…")],
		@[@(BTBGGModeRange), BL(@"Within a range (10~20)", @"В диапазоне (10~20)")],
	];
	NSMutableArray *actions = [NSMutableArray array];
	for (NSArray *item in items) {
		BTBGGMode mode = (BTBGGMode)[item[0] integerValue];
		[actions addObject:[UIAction actionWithTitle:item[1] image:nil identifier:nil handler:^(UIAction *x) {
			self->_mode = mode;
			[self refreshUI];
		}]];
	}
	_modeButton.menu = [UIMenu menuWithChildren:actions];
	_modeButton.showsMenuAsPrimaryAction = YES;
}

- (void)buildMoreMenu {
	__weak typeof(self) weak = self;
	NSArray *actions = @[
		[UIAction actionWithTitle:BL(@"Set all to…", @"Изменить все на…") image:nil identifier:nil handler:^(UIAction *x) { [weak askValueThen:NO]; }],
		[UIAction actionWithTitle:BL(@"Set all to… and freeze", @"Изменить все и заморозить…") image:nil identifier:nil handler:^(UIAction *x) { [weak askValueThen:YES]; }],
		[UIAction actionWithTitle:BL(@"Save all to the list", @"Сохранить все в список") image:nil identifier:nil handler:^(UIAction *x) { [weak saveAll]; }],
		[UIAction actionWithTitle:BL(@"Unfreeze everything", @"Разморозить всё") image:nil identifier:nil handler:^(UIAction *x) {
			[[BTBGGEngine shared] unfreezeAll];
			[weak setStatus:BL(@"Everything is unfrozen.", @"Всё разморожено.")];
			[weak refreshValues];
		}],
	];
	_more.menu = [UIMenu menuWithChildren:actions];
	_more.showsMenuAsPrimaryAction = YES;
}

#pragma mark State

- (NSString *)typeShortTitle { return [BTBGGEngine nameOfType:_type]; }

- (void)refreshUI {
	BTBGGEngine *e = [BTBGGEngine shared];
	NSUInteger n = e.count;
	BOOL refining = n > 0;
	if (!refining && ModeNeedsField(_mode) == NO) _mode = BTBGGModeExact;
	BOOL fieldNeeded = refining ? ModeNeedsField(_mode) : !_unknown;
	_optionsRow.hidden = refining;
	_secondaryRow.hidden = !refining;
	_toolsRow.hidden = !refining;
	_unknownButton.hidden = refining;
	_undo.hidden = ![e canUndo];
	_field.hidden = !fieldNeeded;
	[_typeButton setTitle:[NSString stringWithFormat:BL(@"Type: %@ ▾", @"Тип: %@ ▾"), [self typeShortTitle]] forState:UIControlStateNormal];
	[_regionsButton setTitle:[NSString stringWithFormat:BL(@"Regions: %@ ▾", @"Регионы: %@ ▾"), BTBGGRegionSummary(e.regions)] forState:UIControlStateNormal];
	[_unknownButton setTitle:_unknown ? BL(@"✓ The number is hidden (tap to type it instead)", @"✓ Число скрыто (нажми, чтобы ввести число)") : BL(@"I can't find it: the number is hidden", @"Не находит? Число скрыто или зашифровано") forState:UIControlStateNormal];

	if (!refining) {
		_step.text = BL(@"1. What are you looking for?", @"1. Что ищем?");
		_hint.text = _unknown
			? BL(@"Without typing anything, tap Find all: every value is remembered, then you change the number in the game and narrow it down. Works best on a quiet screen (menu) and may take longer.", @"Ничего не вводи и нажми «Найти всё»: запомню все значения, потом ты меняешь число в игре и сужаешь поиск. Лучше делать на тихом экране (меню), может занять больше времени.")
			: BL(@"Type the number you see in the game (coins, lives, score) and tap Find. Also works: a range like 10~20, or a group like 100;250 (numbers stored close to each other). If the game hides the number, pick type XOR.", @"Введи число, которое видишь в игре (монеты, жизни, очки), и нажми «Найти». Ещё можно: диапазон 10~20 или группу 100;250 (числа лежат рядом в памяти). Если игра прячет число, выбери тип XOR.");
		_field.placeholder = BL(@"e.g. 250", @"например, 250");
		[_primary setTitle:_unknown ? BL(@"Find all", @"Найти всё") : BL(@"Find", @"Найти") forState:UIControlStateNormal];
	} else if (n <= 20) {
		_step.text = BL(@"3. Pick the address", @"3. Выбери адрес");
		_hint.text = BL(@"Tap a line below to change, freeze or save it. If it does not work, change the number in the game and tap Refine again.", @"Нажми на строку ниже, чтобы изменить, заморозить или сохранить. Если не получилось, поменяй число в игре и нажми «Уточнить» ещё раз.");
		[_primary setTitle:BL(@"Refine", @"Уточнить") forState:UIControlStateNormal];
	} else {
		_step.text = BL(@"2. Change the number in the game", @"2. Измени число в игре");
		NSString *t = @"";
		switch (_mode) {
			case BTBGGModeExact: t = BL(@"Spend or earn some, type the new number here and tap Refine. Repeat until a few lines are left.", @"Потрать или заработай немного, введи новое число здесь и нажми «Уточнить». Повторяй, пока не останется несколько строк."); break;
			case BTBGGModeChanged: t = BL(@"Change the number in the game, then tap Refine: only places whose value changed stay.", @"Измени число в игре и нажми «Уточнить»: останутся места, где значение изменилось."); break;
			case BTBGGModeUnchanged: t = BL(@"Do nothing in the game, tap Refine: only places whose value did not change stay.", @"Ничего не меняй в игре и нажми «Уточнить»: останутся места, где значение не менялось."); break;
			case BTBGGModeGreater: t = BL(@"Make the number bigger in the game, then tap Refine.", @"Сделай число в игре больше и нажми «Уточнить»."); break;
			case BTBGGModeSmaller: t = BL(@"Make the number smaller in the game, then tap Refine.", @"Сделай число в игре меньше и нажми «Уточнить»."); break;
			case BTBGGModeIncreasedBy: t = BL(@"Type by how much the number grew in the game (e.g. 50), then tap Refine.", @"Введи, на сколько выросло число в игре (например, 50), и нажми «Уточнить»."); break;
			case BTBGGModeDecreasedBy: t = BL(@"Type by how much the number dropped in the game (e.g. 50), then tap Refine.", @"Введи, на сколько уменьшилось число в игре (например, 50), и нажми «Уточнить»."); break;
			case BTBGGModeRange: t = BL(@"Type a range such as 10~20 and tap Refine: only places with a value in it stay.", @"Введи диапазон, например 10~20, и нажми «Уточнить»: останутся места со значением в нём."); break;
			default: break;
		}
		_hint.text = t;
		[_primary setTitle:BL(@"Refine", @"Уточнить") forState:UIControlStateNormal];
	}
	if (refining) {
		switch (_mode) {
			case BTBGGModeIncreasedBy: _field.placeholder = BL(@"by how much", @"на сколько"); break;
			case BTBGGModeDecreasedBy: _field.placeholder = BL(@"by how much", @"на сколько"); break;
			case BTBGGModeRange: _field.placeholder = BL(@"e.g. 10~20", @"например, 10~20"); break;
			default: _field.placeholder = BL(@"the new number from the game", @"новое число из игры"); break;
		}
	}
	NSString *modeTitle = BL(@"Other options", @"Другие варианты");
	switch (_mode) {
		case BTBGGModeChanged: modeTitle = BL(@"Changed ▾", @"Изменилось ▾"); break;
		case BTBGGModeUnchanged: modeTitle = BL(@"Same ▾", @"Не менялось ▾"); break;
		case BTBGGModeGreater: modeTitle = BL(@"Increased ▾", @"Выросло ▾"); break;
		case BTBGGModeSmaller: modeTitle = BL(@"Decreased ▾", @"Уменьшилось ▾"); break;
		case BTBGGModeIncreasedBy: modeTitle = BL(@"Grew by ▾", @"Выросло на ▾"); break;
		case BTBGGModeDecreasedBy: modeTitle = BL(@"Dropped by ▾", @"Упало на ▾"); break;
		case BTBGGModeRange: modeTitle = BL(@"Range ▾", @"Диапазон ▾"); break;
		default: break;
	}
	[_modeButton setTitle:modeTitle forState:UIControlStateNormal];
	[self.view setNeedsLayout];
	[self updateHeaderHeight];
}

- (void)setStatus:(NSString *)text {
	BTBOnMain(^{ self->_status.text = text; [self updateHeaderHeight]; });
}

- (void)toggleUnknown {
	if (_busy) return;
	_unknown = !_unknown;
	[self refreshUI];
}

- (void)openRegions {
	if (_busy) return;
	[self.navigationController pushViewController:BTBGGMakeRegionsVC() animated:YES];
}

- (void)primaryTapped {
	if ([BTBGGEngine shared].count > 0) [self nextScan]; else [self newScan];
}

- (void)startOver {
	if (_busy) return;
	BTBGGEngine *e = [BTBGGEngine shared];
	if (![e tryLock]) { [self setStatus:BL(@"A script is using the memory right now.", @"Сейчас память занята скриптом.")]; return; }
	[e clearResults];
	[e recipeReset];
	[e unlock];
	_unknown = NO;
	_mode = BTBGGModeExact;
	_field.text = @"";
	_status.text = @"";
	[self refreshUI];
	[_table reloadData];
}

- (void)undoStep {
	if (_busy) return;
	BTBGGEngine *e = [BTBGGEngine shared];
	if (![e tryLock]) { [self setStatus:BL(@"A script is using the memory right now.", @"Сейчас память занята скриптом.")]; return; }
	BOOL ok = [e undoRefine];
	size_t n = e.count;
	[e unlock];
	if (ok) {
		[e recipeRemoveLast];
		_field.text = @"";
		[self setStatus:[NSString stringWithFormat:BL(@"Step undone. Places again: %lu.", @"Шаг отменён. Мест снова: %lu."), (unsigned long)n]];
	} else {
		[self setStatus:BL(@"Nothing to undo.", @"Отменять нечего.")];
	}
	[self refreshUI];
	[_table reloadData];
}

- (void)refreshValues {
	if (_busy) return;
	[_table reloadData];
	[self setStatus:BL(@"Values refreshed.", @"Значения обновлены.")];
}

#pragma mark Scanning

- (void)newScan {
	if (_busy) return;
	NSString *text = _field.text ?: @"";
	BTBGGType type = _type;
	BOOL unknown = _unknown;
	if (!unknown && text.length == 0) { [self setStatus:BL(@"Type the number from the game first.", @"Сначала введи число из игры.")]; return; }
	BTBGGEngine *e = [BTBGGEngine shared];
	if (![e tryLock]) { [self setStatus:BL(@"A script is using the memory right now.", @"Сейчас память занята скриптом.")]; return; }
	[self.view endEditing:YES];
	_busy = YES;
	[_table reloadData];
	[self setStatus:BL(@"Searching memory… this can take a few seconds.", @"Ищу в памяти… это может занять несколько секунд.")];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *error = nil;
		BOOL ok = [e search:text type:type unknown:unknown error:&error];
		size_t found = e.count;
		BOOL early = e.stoppedEarly;
		[e unlock];
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_busy = NO;
			if (!ok) {
				[self setStatus:error ?: @""];
			} else if (found == 0) {
				[self setStatus:BL(@"Nothing found. Check the number and the type (try Float for numbers with a dot), or widen the regions.", @"Ничего не найдено. Проверь число и тип (для чисел с точкой попробуй Float) или расширь регионы.")];
			} else {
				[e recipeReset];
					[e recipeAddStep:@{@"op": unknown ? @"unknown" : @"search", @"type": @(type), @"text": text, @"regions": @(e.regions)}];
					self->_mode = unknown ? BTBGGModeChanged : BTBGGModeExact;
				self->_field.text = @"";
				[self setStatus:[NSString stringWithFormat:BL(@"Found %lu places%@.", @"Найдено мест: %lu%@."), (unsigned long)found,
					early ? BL(@" (stopped: the phone is out of memory, try again on a quieter screen)", @" (остановился: не хватает памяти телефона, попробуй на более тихом экране)") : @""]];
			}
			[self refreshUI];
			[self->_table reloadData];
		});
	});
}

- (void)nextScan {
	if (_busy) return;
	BTBGGEngine *e = [BTBGGEngine shared];
	BTBGGMode mode = _mode;
	NSString *text = _field.text ?: @"";
	if (ModeNeedsField(mode) && text.length == 0) { [self setStatus:BL(@"Type the number first.", @"Сначала введи число.")]; return; }
	if (![e tryLock]) { [self setStatus:BL(@"A script is using the memory right now.", @"Сейчас память занята скриптом.")]; return; }
	[self.view endEditing:YES];
	_busy = YES;
	[_table reloadData];
	[self setStatus:BL(@"Filtering…", @"Фильтрую…")];
	BOOL keepMode = (mode != BTBGGModeExact && !ModeNeedsField(mode)); // fuzzy flow: keep narrowing the same way
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *error = nil;
		BOOL ok = [e refine:text mode:mode error:&error];
		size_t left = e.count;
		[e unlock];
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_busy = NO;
			if (!ok) {
				[self setStatus:error ?: @""];
			} else {
				[e recipeAddStep:@{@"op": @"refine", @"mode": @(mode), @"text": text}];
					if (!keepMode) self->_mode = BTBGGModeExact;
				self->_field.text = @"";
				[self setStatus:left == 0 ? BL(@"Nothing left. Undo the step or tap Start over.", @"Ничего не осталось. Отмени шаг или нажми «Сначала».")
					: [NSString stringWithFormat:BL(@"Left: %lu places.", @"Осталось мест: %lu."), (unsigned long)left]];
			}
			[self refreshUI];
			[self->_table reloadData];
		});
	});
}

#pragma mark Bulk actions

- (void)askValueThen:(BOOL)freeze {
	if (_busy || [BTBGGEngine shared].count == 0) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:freeze ? BL(@"Set all and freeze", @"Изменить все и заморозить") : BL(@"Set all", @"Изменить все")
		message:[NSString stringWithFormat:BL(@"Every one of the %lu places gets this value.", @"Это значение получат все места: %lu."), (unsigned long)[BTBGGEngine shared].count]
		preferredStyle:UIAlertControllerStyleAlert];
	BTBGGType maxType = _type;
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.keyboardType = UIKeyboardTypeNumbersAndPunctuation; BTBGGAttachMaxButton(f, maxType); }];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Apply", @"Применить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		[self applyAll:wa.textFields.firstObject.text freeze:freeze];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)applyAll:(NSString *)text freeze:(BOOL)freeze {
	BTBGGEngine *e = [BTBGGEngine shared];
	if (![e tryLock]) { [self setStatus:BL(@"A script is using the memory right now.", @"Сейчас память занята скриптом.")]; return; }
	_busy = YES;
	[_table reloadData];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSUInteger n = [e editAll:text freeze:freeze mode:BTBGGFreezeExact typeFilter:-1];
		[e unlock];
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_busy = NO;
			[self setStatus:n == 0 ? BL(@"Nothing was changed. Check the number.", @"Ничего не изменилось. Проверь число.")
				: [NSString stringWithFormat:BL(@"Changed: %lu places.", @"Изменено мест: %lu."), (unsigned long)n]];
			[self->_table reloadData];
		});
	});
}

- (void)saveAll {
	BTBGGEngine *e = [BTBGGEngine shared];
	if (_busy || ![e tryLock]) return;
	size_t n = MIN(e.count, (size_t)5000);
	for (size_t i = 0; i < n; i++) {
		BTBGGHit h = [e hitAtIndex:i];
		[e addToListAddress:BTBGGHitAddress(h) type:BTBGGHitType(h) label:nil];
	}
	[e persistList];
	[e unlock];
	[self setStatus:[NSString stringWithFormat:BL(@"Saved to the List tab: %lu.", @"Сохранено на вкладке «Список»: %lu."), (unsigned long)n]];
}

#pragma mark Results table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (_busy) return 0;
	NSUInteger n = [BTBGGEngine shared].count;
	return (NSInteger)MIN(n, (NSUInteger)(n <= 200 ? 200 : 20));
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if (_busy) return nil;
	NSUInteger n = [BTBGGEngine shared].count;
	if (n == 0) return nil;
	return n > 200 ? [NSString stringWithFormat:BL(@"%lu places — narrow it down first", @"Мест: %lu — сначала сузь поиск"), (unsigned long)n]
		: [NSString stringWithFormat:BL(@"%lu places — tap to change", @"Мест: %lu — нажми, чтобы изменить"), (unsigned long)n];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
	BTBGGEngine *e = [BTBGGEngine shared];
	BTBGGHit h = [e hitAtIndex:(size_t)ip.row];
	uint64_t addr = BTBGGHitAddress(h);
	BTBGGType t = BTBGGHitType(h);
	uint64_t now = 0;
	BOOL ok = [e readValue:addr type:t raw:&now];
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightSemibold];
	cell.textLabel.text = [NSString stringWithFormat:@"%@%@", ok ? [BTBGGEngine format:now type:t] : @"?", [e isFrozen:addr] ? @"  ❄︎" : @""];
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx", [BTBGGEngine nameOfType:t], addr];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	BTBGGHit h = [[BTBGGEngine shared] hitAtIndex:(size_t)ip.row];
	BTBGGPresentValueEditor(self, BTBGGHitAddress(h), BTBGGHitType(h), ^{ [tv reloadData]; });
}

@end

// MARK: - Entry point

void BTBFeatureGameGuard(void) {
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	void (^attach)(NSNotification *) = ^(NSNotification *note) {
		if ([note.object isKindOfClass:[UIWindow class]]) [[BTBGameGuard shared] attachToWindow:note.object];
	};
	[center addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
	[center addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
	[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		[[BTBGameGuard shared] attachToAllWindows];
		dispatch_async(dispatch_get_main_queue(), ^{ [[BTBGameGuard shared] showFloatingButton]; });
	}];
}
