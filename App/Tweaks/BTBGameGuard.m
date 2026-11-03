//  BTBGameGuard.m — /gameguard: a memory scanner/editor for OFFLINE single-player games.
//  Four-finger long press opens a panel: search the app's own memory for a value
//  (score, coins, lives…), change what is left after a few scans, optionally freeze it.
//  Works only on the process it is injected into. Do not use it in online games.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <os/proc.h>

typedef NS_ENUM(NSInteger, BTBType) { BTBTypeInt32, BTBTypeFloat, BTBTypeDouble };
typedef NS_ENUM(NSInteger, BTBMode) { BTBModeExact, BTBModeChanged, BTBModeSame, BTBModeBigger, BTBModeSmaller, BTBModeUnknown };

typedef struct { uint64_t address; uint64_t raw; } BTBHit;

// No fixed result limit: the store is a big lazily-committed virtual range (memory is only used as
// results are written). The scan stops by itself when the app is about to run out of memory.
static size_t gMaxHits = 0;
static const size_t kMemoryFloor = 200u << 20; // stop when less than ~200 MB is left
static const size_t kChunk = 1 << 20;

static size_t BTBSize(BTBType t) { return t == BTBTypeDouble ? 8 : 4; }

static BOOL BTBParse(NSString *text, BTBType t, uint64_t *raw) {
	NSString *s = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	if (s.length == 0) return NO;
	*raw = 0;
	switch (t) {
		case BTBTypeInt32: { int32_t v = (int32_t)s.longLongValue; memcpy(raw, &v, 4); return YES; }
		case BTBTypeFloat: { float v = s.floatValue; memcpy(raw, &v, 4); return YES; }
		case BTBTypeDouble: { double v = s.doubleValue; memcpy(raw, &v, 8); return YES; }
	}
	return NO;
}

static NSString *BTBFormat(uint64_t raw, BTBType t) {
	switch (t) {
		case BTBTypeInt32: { int32_t v; memcpy(&v, &raw, 4); return [NSString stringWithFormat:@"%d", v]; }
		case BTBTypeFloat: { float v; memcpy(&v, &raw, 4); return [NSString stringWithFormat:@"%g", v]; }
		case BTBTypeDouble: { double v; memcpy(&v, &raw, 8); return [NSString stringWithFormat:@"%g", v]; }
	}
	return @"";
}

// -1 less, 0 equal, 1 greater
static int BTBCompare(uint64_t a, uint64_t b, BTBType t) {
	switch (t) {
		case BTBTypeInt32: { int32_t x, y; memcpy(&x, &a, 4); memcpy(&y, &b, 4); return x < y ? -1 : (x > y); }
		case BTBTypeFloat: { float x, y; memcpy(&x, &a, 4); memcpy(&y, &b, 4); return x < y ? -1 : (x > y); }
		case BTBTypeDouble: { double x, y; memcpy(&x, &a, 8); memcpy(&y, &b, 8); return x < y ? -1 : (x > y); }
	}
	return 0;
}

static BOOL BTBReadMemory(uint64_t address, void *buffer, size_t size) {
	vm_size_t outSize = 0;
	return vm_read_overwrite(mach_task_self(), (vm_address_t)address, size, (vm_address_t)buffer, &outSize) == KERN_SUCCESS && outSize == size;
}

static BOOL BTBWriteMemory(uint64_t address, uint64_t raw, size_t size) {
	return vm_write(mach_task_self(), (vm_address_t)address, (vm_offset_t)&raw, (mach_msg_type_number_t)size) == KERN_SUCCESS;
}

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

@interface BTBGameGuard : UIViewController <UITableViewDataSource, UITableViewDelegate>
+ (instancetype)shared;
- (void)attachToWindow:(UIWindow *)window;
- (void)attachToAllWindows;
- (void)showFloatingButton;
- (void)openPanel;
@end

@implementation BTBGameGuard {
	UISegmentedControl *_typeControl;
	UITextField *_field;
	UILabel *_step, *_hint, *_status;
	UIButton *_primary, *_reset, *_more, *_unknown;
	UIStackView *_secondaryRow;
	UITableView *_table;
	BTBHit *_store;              // vm_allocate'd, so scans can skip it (it would find itself)
	size_t _count;
	uint8_t *_readBuffer;        // same
	BTBType _hitType;
	BTBMode _mode;
	BOOL _refining;
	BOOL _busy;
	BOOL _unknownFlow;           // the value is hidden: keep narrowing by changed/bigger/smaller
	NSMutableDictionary<NSNumber *, NSNumber *> *_frozen; // address -> raw
	NSTimer *_freezeTimer;
}

+ (instancetype)shared {
	static BTBGameGuard *g;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ g = [BTBGameGuard new]; });
	return g;
}

#pragma mark - Trigger

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
	if (g.state != UIGestureRecognizerStateBegan) return;
	[self openPanel];
}

static BTBGGWindow *gOverlay;

/// A small draggable "GG" button: works even where a multi-finger gesture can't be recognised.
- (void)showFloatingButton {
	if (gOverlay) return;
	UIWindowScene *scene = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
	}
	if (!scene) return;
	BTBGGWindow *window = [[BTBGGWindow alloc] initWithWindowScene:scene];
	window.frame = scene.coordinateSpace.bounds;
	window.windowLevel = UIWindowLevelAlert + 100;
	window.backgroundColor = UIColor.clearColor;
	window.rootViewController = [UIViewController new];
	window.rootViewController.view.backgroundColor = UIColor.clearColor;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.frame = CGRectMake(12, 140, 46, 46);
	button.backgroundColor = [UIColor colorWithRed:0.49 green:0.36 blue:1 alpha:0.9];
	button.layer.cornerRadius = 23;
	button.layer.shadowOpacity = 0.35;
	button.layer.shadowRadius = 6;
	button.layer.shadowOffset = CGSizeMake(0, 2);
	[button setTitle:@"GG" forState:UIControlStateNormal];
	[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	[button addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
	[button addGestureRecognizer:pan];
	[window.rootViewController.view addSubview:button];
	window.button = button;
	window.hidden = NO;
	gOverlay = window;
}

- (void)dragButton:(UIPanGestureRecognizer *)pan {
	UIView *button = pan.view;
	CGPoint t = [pan translationInView:button.superview];
	button.center = CGPointMake(button.center.x + t.x, button.center.y + t.y);
	[pan setTranslation:CGPointZero inView:button.superview];
}

static UIWindow *gPanelWindow;
static __weak UIWindow *gGameWindow;

/// The panel lives in its own window instead of being presented on the game's view controller:
/// game engines (Unity, Unreal) often manage their own controllers and swallow presentations or touches.
- (void)openPanel {
	if (gPanelWindow) return;
	UIWindowScene *scene = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
	}
	if (!scene) return;
	// the game's window, never our own overlay (a tap on the GG button can make the overlay key)
	for (UIWindow *w in scene.windows) if (![w isKindOfClass:[BTBGGWindow class]] && w.windowLevel <= UIWindowLevelNormal && !w.hidden) { gGameWindow = w; if (w.isKeyWindow) break; }
	UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
	window.frame = scene.coordinateSpace.bounds;
	window.windowLevel = UIWindowLevelAlert + 200;
	window.backgroundColor = UIColor.systemBackgroundColor;
	window.rootViewController = self;
	gPanelWindow = window;
	[window makeKeyAndVisible];
}

#pragma mark - UI

static BOOL BTBRussian(void) {
	NSString *lang = NSLocale.preferredLanguages.firstObject;
	return [lang hasPrefix:@"ru"];
}
static NSString *L(NSString *en, NSString *ru) { return BTBRussian() ? ru : en; }

static UIColor *BTBAccent(void) { return [UIColor colorWithRed:0.49 green:0.36 blue:1 alpha:1]; }

static UIButton *BTBBigButton(NSString *title, BOOL filled, id target, SEL action) {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	[b setTitle:title forState:UIControlStateNormal];
	b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
	b.backgroundColor = filled ? BTBAccent() : [BTBAccent() colorWithAlphaComponent:0.15];
	[b setTitleColor:filled ? UIColor.whiteColor : BTBAccent() forState:UIControlStateNormal];
	b.layer.cornerRadius = 14;
	[b.heightAnchor constraintEqualToConstant:50].active = YES;
	if (action) [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	return b;
}

static UILabel *BTBLabel(UIFont *font, UIColor *color) {
	UILabel *l = [UILabel new];
	l.font = font;
	l.textColor = color;
	l.numberOfLines = 0;
	return l;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	vm_address_t a = 0;
	for (size_t entries = (size_t)1 << 29; entries >= (1u << 22) && !_store; entries >>= 1) {
		a = 0;
		if (vm_allocate(mach_task_self(), &a, entries * sizeof(BTBHit), VM_FLAGS_ANYWHERE) == KERN_SUCCESS) { _store = (BTBHit *)a; gMaxHits = entries; }
	}
	a = 0;
	if (vm_allocate(mach_task_self(), &a, kChunk, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) _readBuffer = (uint8_t *)a;
	_frozen = [NSMutableDictionary dictionary];
	_mode = BTBModeExact;

	UILabel *title = BTBLabel([UIFont boldSystemFontOfSize:20], UIColor.labelColor);
	title.text = @"GameGuardian";
	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	[close setTitle:L(@"Close", @"Закрыть") forState:UIControlStateNormal];
	close.titleLabel.font = [UIFont systemFontOfSize:17];
	[close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
	UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, close]];
	header.alignment = UIStackViewAlignmentCenter;

	UILabel *warn = BTBLabel([UIFont systemFontOfSize:12], UIColor.systemOrangeColor);
	warn.text = L(@"Offline single-player games only. Online, you can get banned.", @"Только оффлайн-игры для одного игрока. В онлайне могут забанить.");

	_step = BTBLabel([UIFont boldSystemFontOfSize:22], UIColor.labelColor);
	_hint = BTBLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);

	_typeControl = [[UISegmentedControl alloc] initWithItems:@[L(@"Whole number", @"Целое число"), L(@"Decimal", @"Дробное"), L(@"Decimal ×2", @"Дробное ×2")]];
	_typeControl.selectedSegmentIndex = 0;

	_field = [UITextField new];
	_field.borderStyle = UITextBorderStyleRoundedRect;
	_field.font = [UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightMedium];
	_field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	_field.clearButtonMode = UITextFieldViewModeWhileEditing;
	_field.textAlignment = NSTextAlignmentCenter;
	[_field.heightAnchor constraintEqualToConstant:50].active = YES;

	_unknown = [UIButton buttonWithType:UIButtonTypeSystem];
	_unknown.titleLabel.font = [UIFont systemFontOfSize:15];
	_unknown.titleLabel.numberOfLines = 0;
	_unknown.titleLabel.textAlignment = NSTextAlignmentCenter;
	[_unknown addTarget:self action:@selector(toggleUnknown) forControlEvents:UIControlEventTouchUpInside];

	_primary = BTBBigButton(@"", YES, self, @selector(primaryTapped));
	_reset = BTBBigButton(L(@"Start over", @"Сначала"), NO, self, @selector(startOver));
	_more = BTBBigButton(L(@"Other options", @"Другие варианты"), NO, nil, nil);
	[self buildModeMenu];
	UIStackView *secondary = [[UIStackView alloc] initWithArrangedSubviews:@[_reset, _more]];
	secondary.spacing = 10;
	secondary.distribution = UIStackViewDistributionFillEqually;
	_secondaryRow = secondary;

	_status = BTBLabel([UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);

	UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[header, warn, _step, _hint, _typeControl, _field, _unknown, _primary, secondary, _status]];
	top.axis = UILayoutConstraintAxisVertical;
	top.spacing = 10;
	[top setCustomSpacing:14 afterView:warn];
	top.translatesAutoresizingMaskIntoConstraints = NO;

	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_table.dataSource = self;
	_table.delegate = self;
	_table.translatesAutoresizingMaskIntoConstraints = NO;
	_table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	[self.view addSubview:top];
	[self.view addSubview:_table];
	UILayoutGuide *g = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[top.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
		[top.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
		[top.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
		[_table.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
		[_table.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
		[_table.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
		[_table.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
	]];
	[self refreshUI];
}

- (void)buildModeMenu {
	NSArray *items = @[
		@[@(BTBModeExact), L(@"Exact new value", @"Точное новое значение")],
		@[@(BTBModeChanged), L(@"Value changed", @"Значение изменилось")],
		@[@(BTBModeSame), L(@"Value did not change", @"Значение не менялось")],
		@[@(BTBModeBigger), L(@"Value increased", @"Значение выросло")],
		@[@(BTBModeSmaller), L(@"Value decreased", @"Значение уменьшилось")],
	];
	NSMutableArray *actions = [NSMutableArray array];
	for (NSArray *item in items) {
		BTBMode mode = (BTBMode)[item[0] integerValue];
		[actions addObject:[UIAction actionWithTitle:item[1] image:nil identifier:nil handler:^(UIAction *x) {
			self->_mode = mode;
			[self refreshUI];
		}]];
	}
	_more.menu = [UIMenu menuWithChildren:actions];
	_more.showsMenuAsPrimaryAction = YES;
}

- (void)refreshUI {
	BOOL refining = _refining;
	BOOL exact = (_mode == BTBModeExact);
	_typeControl.hidden = refining;
	_secondaryRow.hidden = !refining;
	BOOL unknown = !refining && _mode == BTBModeUnknown;
	_field.hidden = (refining && !exact) || unknown;
	_unknown.hidden = refining;
	[_unknown setTitle:unknown ? L(@"✓ The number is hidden or encrypted (tap to type it instead)", @"✓ Число скрыто или зашифровано (нажми, чтобы ввести число)") : L(@"I can't find it: the number is hidden or encrypted", @"Не находит? Число скрыто или зашифровано") forState:UIControlStateNormal];
	NSUInteger n = [self hitCount];
	if (!refining) {
		_step.text = L(@"1. What are you looking for?", @"1. Что ищем?");
		_hint.text = unknown
			? L(@"Some games hide numbers on purpose. Without typing anything, tap Find all: Veather remembers every value, then you change the number in the game and narrow it down. Works best in a quiet screen (menu) and may take longer.", @"Некоторые игры прячут числа. Ничего не вводи и нажми «Найти всё»: запомню все значения, потом ты меняешь число в игре и сужаешь поиск. Лучше делать на тихом экране (меню), может занять больше времени.")
			: L(@"Type the number you see in the game right now (coins, lives, score) and tap Find.", @"Введи число, которое сейчас видишь в игре (монеты, жизни, очки), и нажми «Найти».");
		_field.placeholder = L(@"e.g. 250", @"например, 250");
		[_primary setTitle:unknown ? L(@"Find all", @"Найти всё") : L(@"Find", @"Найти") forState:UIControlStateNormal];
	} else if (n > 0 && n <= 20) {
		_step.text = L(@"3. Pick the address", @"3. Выбери адрес");
		_hint.text = L(@"Tap a line below to change the number. If it does not work, tap Refine again after changing the number in the game.", @"Нажми на строку ниже, чтобы изменить число. Если не получилось, поменяй число в игре и нажми «Уточнить» ещё раз.");
		_field.placeholder = L(@"the new number from the game", @"новое число из игры");
		[_primary setTitle:L(@"Refine", @"Уточнить") forState:UIControlStateNormal];
	} else {
		_step.text = L(@"2. Change the number in the game", @"2. Измени число в игре");
		NSString *modeText = @"";
		switch (_mode) {
			case BTBModeExact: modeText = L(@"Spend or earn some, type the new number here and tap Refine. Repeat until a few lines are left.", @"Потрать или заработай немного, введи новое число здесь и нажми «Уточнить». Повторяй, пока не останется несколько строк."); break;
			case BTBModeChanged: modeText = L(@"Change the number in the game, then tap Refine: only places whose value changed stay.", @"Измени число в игре и нажми «Уточнить»: останутся места, где значение изменилось."); break;
			case BTBModeSame: modeText = L(@"Do nothing in the game, tap Refine: only places whose value did not change stay.", @"Ничего не меняй в игре и нажми «Уточнить»: останутся места, где значение не менялось."); break;
			case BTBModeBigger: modeText = L(@"Make the number bigger in the game, then tap Refine.", @"Сделай число в игре больше и нажми «Уточнить»."); break;
			case BTBModeSmaller: modeText = L(@"Make the number smaller in the game, then tap Refine.", @"Сделай число в игре меньше и нажми «Уточнить»."); break;
			case BTBModeUnknown: break;
		}
		_hint.text = modeText;
		_field.placeholder = L(@"the new number from the game", @"новое число из игры");
		[_primary setTitle:L(@"Refine", @"Уточнить") forState:UIControlStateNormal];
	}
	NSString *modeTitle = @"";
	switch (_mode) {
		case BTBModeExact: modeTitle = L(@"Other options", @"Другие варианты"); break;
		case BTBModeChanged: modeTitle = L(@"Changed ▾", @"Изменилось ▾"); break;
		case BTBModeSame: modeTitle = L(@"Same ▾", @"Не менялось ▾"); break;
		case BTBModeBigger: modeTitle = L(@"Increased ▾", @"Выросло ▾"); break;
		case BTBModeSmaller: modeTitle = L(@"Decreased ▾", @"Уменьшилось ▾"); break;
		case BTBModeUnknown: modeTitle = L(@"Other options", @"Другие варианты"); break;
	}
	[_more setTitle:modeTitle forState:UIControlStateNormal];
}

- (void)closePanel {
	[self.view endEditing:YES];
	UIWindow *panel = gPanelWindow;
	gPanelWindow = nil;
	panel.hidden = YES;
	panel.rootViewController = nil;
	[gGameWindow makeKeyWindow];
}

- (void)setStatus:(NSString *)text {
	BTBOnMain(^{ self->_status.text = text; });
}

- (BTBHit *)hits { return _store; }
- (NSUInteger)hitCount { return _count; }

- (BOOL)overlapsOwnMemory:(vm_address_t)start size:(vm_size_t)size {
	vm_address_t end = start + size;
	vm_address_t s1 = (vm_address_t)_store, e1 = s1 + gMaxHits * sizeof(BTBHit);
	vm_address_t s2 = (vm_address_t)_readBuffer, e2 = s2 + kChunk;
	return (start < e1 && end > s1) || (start < e2 && end > s2);
}

- (void)toggleUnknown {
	if (_busy || _refining) return;
	_mode = (_mode == BTBModeUnknown) ? BTBModeExact : BTBModeUnknown;
	[self refreshUI];
}

- (void)primaryTapped {
	if (_refining) [self nextScan]; else [self newScan];
}

- (void)startOver {
	if (_busy) return;
	_refining = NO;
	_unknownFlow = NO;
	_count = 0;
	_mode = BTBModeExact;
	_field.text = @"";
	[_frozen removeAllObjects];
	[self updateFreezeTimer];
	_status.text = @"";
	[self refreshUI];
	[_table reloadData];
}

#pragma mark - Scanning

- (void)newScan {
	if (_busy) return;
	BTBType type = (BTBType)_typeControl.selectedSegmentIndex;
	uint64_t target = 0;
	BOOL unknownValue = (_mode == BTBModeUnknown);
	if (!unknownValue && !BTBParse(_field.text, type, &target)) { [self setStatus:L(@"Type the number from the game first.", @"Сначала введи число из игры.")]; return; }
	[self.view endEditing:YES];
	if (!_store || !_readBuffer) { [self setStatus:L(@"Out of memory.", @"Не хватает памяти.")]; return; }
	_busy = YES;
	_count = 0;
	[_table reloadData];
	[self setStatus:L(@"Searching memory… this can take a few seconds.", @"Ищу в памяти… это может занять несколько секунд.")];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		size_t found = 0;
		size_t size = BTBSize(type);
		const size_t chunk = kChunk;
		uint8_t *buffer = self->_readBuffer;
		BTBHit *store = self->_store;
		vm_address_t address = 0;
		BOOL full = NO;
		while (!full) {
			vm_size_t regionSize = 0;
			vm_region_basic_info_data_64_t info;
			mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
			mach_port_t object;
			if (vm_region_64(mach_task_self(), &address, &regionSize, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) break;
			BOOL rw = (info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE);
			if (rw && regionSize < (1ULL << 32) && ![self overlapsOwnMemory:address size:regionSize]) {
				for (vm_size_t off = 0; off < regionSize && !full; off += chunk) {
					size_t n = (size_t)MIN((vm_size_t)chunk, regionSize - off);
					if (!BTBReadMemory(address + off, buffer, n)) continue;
					for (size_t i = 0; i + size <= n; i += size) {
						if (unknownValue) {
							// hidden/encrypted value: remember every non-zero aligned word, narrow it down later
							uint64_t word = 0;
							memcpy(&word, buffer + i, size);
							if (word == 0 || (address + off + i) % size != 0) continue;
							store[found].address = address + off + i;
							store[found].raw = word;
							if (++found >= gMaxHits || ((found & 0xFFFF) == 0 && os_proc_available_memory() < kMemoryFloor)) { full = YES; break; }
						} else if (memcmp(buffer + i, &target, size) == 0) {
							store[found].address = address + off + i;
							store[found].raw = target;
							if (++found >= gMaxHits || ((found & 0xFFFF) == 0 && os_proc_available_memory() < kMemoryFloor)) { full = YES; break; }
						}
					}
				}
			}
			address += regionSize;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_count = found;
			self->_hitType = type;
			self->_busy = NO;
			self->_refining = found > 0;
			self->_unknownFlow = unknownValue && found > 0;
			if (self->_unknownFlow) self->_mode = BTBModeChanged;
			if (found == 0) {
				[self setStatus:L(@"Nothing found. Check the number and the type (try Decimal for numbers with a dot).", @"Ничего не найдено. Проверь число и тип (для чисел с точкой попробуй «Дробное»).")];
			} else {
				[self setStatus:[NSString stringWithFormat:L(@"Found %lu places%@.", @"Найдено мест: %lu%@."), (unsigned long)found,
					full ? L(@" (stopped: the phone is out of memory, try again on a quieter screen)", @" (остановился: не хватает памяти телефона, попробуй на более тихом экране)") : @""]];
				self->_field.text = @"";
			}
			[self refreshUI];
			[self->_table reloadData];
		});
	});
}

- (void)nextScan {
	if (_busy) return;
	if ([self hitCount] == 0) { [self startOver]; return; }
	BTBType type = _hitType;
	BTBMode mode = _mode;
	uint64_t target = 0;
	if (mode == BTBModeExact && !BTBParse(_field.text, type, &target)) { [self setStatus:L(@"Type the new number from the game first.", @"Сначала введи новое число из игры.")]; return; }
	[self.view endEditing:YES];
	_busy = YES;
	[self setStatus:L(@"Filtering…", @"Фильтрую…")];
	size_t total = _count;
	_count = 0;
	[_table reloadData];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		size_t kept = 0;
		BTBHit *src = self->_store; // filtered in place: the write index never passes the read index
		size_t size = BTBSize(type);
		for (size_t i = 0; i < total; i++) {
			uint64_t now = 0;
			if (!BTBReadMemory(src[i].address, &now, size)) continue;
			BOOL keep = NO;
			switch (mode) {
				case BTBModeExact: keep = memcmp(&now, &target, size) == 0; break;
				case BTBModeChanged: keep = memcmp(&now, &src[i].raw, size) != 0; break;
				case BTBModeSame: keep = memcmp(&now, &src[i].raw, size) == 0; break;
				case BTBModeBigger: keep = BTBCompare(now, src[i].raw, type) > 0; break;
				case BTBModeSmaller: keep = BTBCompare(now, src[i].raw, type) < 0; break;
			}
			if (keep) { src[kept].address = src[i].address; src[kept].raw = now; kept++; }
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_count = kept;
			self->_busy = NO;
			if (!self->_unknownFlow) self->_mode = BTBModeExact;
			self->_field.text = @"";
			if (kept == 0) {
				[self setStatus:L(@"Nothing left. Tap Start over and try again.", @"Ничего не осталось. Нажми «Сначала» и попробуй ещё раз.")];
			} else {
				[self setStatus:[NSString stringWithFormat:L(@"Left: %lu places.", @"Осталось мест: %lu."), (unsigned long)kept]];
			}
			[self refreshUI];
			[self->_table reloadData];
		});
	});
}

#pragma mark - Results

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	return (NSInteger)MIN([self hitCount], (NSUInteger)(_refining && [self hitCount] <= 200 ? 200 : 20));
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	NSUInteger n = [self hitCount];
	if (n == 0) return nil;
	return n > 200 ? [NSString stringWithFormat:L(@"%lu places — narrow it down first", @"Мест: %lu — сначала сузь поиск"), (unsigned long)n]
		: [NSString stringWithFormat:L(@"%lu places — tap to change", @"Мест: %lu — нажми, чтобы изменить"), (unsigned long)n];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
	BTBHit h = [self hits][ip.row];
	uint64_t now = 0;
	BOOL ok = BTBReadMemory(h.address, &now, BTBSize(_hitType));
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightSemibold];
	cell.textLabel.text = [NSString stringWithFormat:@"%@%@", ok ? BTBFormat(now, _hitType) : @"?", _frozen[@(h.address)] ? @"  ❄︎" : @""];
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"0x%llx", h.address];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	BTBHit h = [self hits][ip.row];
	BTBType type = _hitType;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"Change the number", @"Изменить число")
		message:L(@"Type the value you want.\n“Freeze” keeps it from changing back.", @"Введи нужное значение.\n«Заморозить» не даёт игре вернуть его назад.")
		preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) {
		f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
		uint64_t now = 0;
		if (BTBReadMemory(h.address, &now, BTBSize(type))) f.text = BTBFormat(now, type);
	}];
	void (^apply)(BOOL) = ^(BOOL freeze) {
		uint64_t raw;
		if (!BTBParse(a.textFields.firstObject.text, type, &raw)) return;
		BTBWriteMemory(h.address, raw, BTBSize(type));
		if (freeze) self->_frozen[@(h.address)] = @(raw); else [self->_frozen removeObjectForKey:@(h.address)];
		[self updateFreezeTimer];
		[tv reloadData];
	};
	[a addAction:[UIAlertAction actionWithTitle:L(@"Change", @"Изменить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(NO); }]];
	[a addAction:[UIAlertAction actionWithTitle:L(@"Change and freeze", @"Изменить и заморозить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(YES); }]];
	if (_frozen[@(h.address)]) {
		[a addAction:[UIAlertAction actionWithTitle:L(@"Unfreeze", @"Разморозить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
			[self->_frozen removeObjectForKey:@(h.address)];
			[self updateFreezeTimer];
			[tv reloadData];
		}]];
	}
	[a addAction:[UIAlertAction actionWithTitle:L(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)updateFreezeTimer {
	if (_frozen.count == 0) { [_freezeTimer invalidate]; _freezeTimer = nil; return; }
	if (_freezeTimer) return;
	BTBType type = _hitType;
	_freezeTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
		[self->_frozen enumerateKeysAndObjectsUsingBlock:^(NSNumber *addr, NSNumber *raw, BOOL *stop) {
			BTBWriteMemory(addr.unsignedLongLongValue, raw.unsignedLongLongValue, BTBSize(type));
		}];
	}];
}

@end

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
