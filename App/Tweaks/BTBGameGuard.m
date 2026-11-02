//  BTBGameGuard.m — /gameguard: a memory scanner/editor for OFFLINE single-player games.
//  Four-finger long press opens a panel: search the app's own memory for a value
//  (score, coins, lives…), change what is left after a few scans, optionally freeze it.
//  Works only on the process it is injected into. Do not use it in online games.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>
#import <mach/mach.h>

typedef NS_ENUM(NSInteger, BTBType) { BTBTypeInt32, BTBTypeFloat, BTBTypeDouble };
typedef NS_ENUM(NSInteger, BTBMode) { BTBModeExact, BTBModeChanged, BTBModeSame, BTBModeBigger, BTBModeSmaller };

typedef struct { uint64_t address; uint64_t raw; } BTBHit;

static const size_t kMaxHits = 2000000;
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

static UIViewController *BTBTop(void) {
	UIWindow *key = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) { key = w; break; }
	}
	UIViewController *vc = key.rootViewController;
	while (vc.presentedViewController) vc = vc.presentedViewController;
	return vc;
}

@interface BTBGameGuard : UIViewController <UITableViewDataSource, UITableViewDelegate>
+ (instancetype)shared;
- (void)attachToWindow:(UIWindow *)window;
- (void)attachToAllWindows;
@end

@implementation BTBGameGuard {
	UISegmentedControl *_typeControl, *_modeControl;
	UITextField *_field;
	UILabel *_status;
	UITableView *_table;
	UIButton *_scanButton, *_nextButton;
	BTBHit *_store;              // vm_allocate'd, so scans can skip it (it would find itself)
	size_t _count;
	uint8_t *_readBuffer;        // same
	BTBType _hitType;
	BOOL _busy;
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
	if (self.presentingViewController || self.view.window) return;
	UIViewController *top = BTBTop();
	if (!top) return;
	self.modalPresentationStyle = UIModalPresentationPageSheet;
	if (@available(iOS 15.0, *)) {
		UISheetPresentationController *sheet = self.sheetPresentationController;
		sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
	}
	[top presentViewController:self animated:YES completion:nil];
}

#pragma mark - UI

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	vm_address_t a = 0;
	if (vm_allocate(mach_task_self(), &a, kMaxHits * sizeof(BTBHit), VM_FLAGS_ANYWHERE) == KERN_SUCCESS) _store = (BTBHit *)a;
	a = 0;
	if (vm_allocate(mach_task_self(), &a, kChunk, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) _readBuffer = (uint8_t *)a;
	_frozen = [NSMutableDictionary dictionary];

	UILabel *title = [UILabel new];
	title.text = @"GameGuardian · BetterThanBox";
	title.font = [UIFont boldSystemFontOfSize:17];
	UILabel *warn = [UILabel new];
	warn.text = @"Offline single-player games only. Using it online can get your account banned.";
	warn.font = [UIFont systemFontOfSize:12];
	warn.textColor = UIColor.systemOrangeColor;
	warn.numberOfLines = 2;

	_typeControl = [[UISegmentedControl alloc] initWithItems:@[@"Int32", @"Float", @"Double"]];
	_typeControl.selectedSegmentIndex = 0;
	_field = [UITextField new];
	_field.placeholder = @"Value to search (e.g. your coins)";
	_field.borderStyle = UITextBorderStyleRoundedRect;
	_field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	_field.clearButtonMode = UITextFieldViewModeWhileEditing;
	_modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Equals", @"Changed", @"Same", @"Bigger", @"Smaller"]];
	_modeControl.selectedSegmentIndex = 0;

	_scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_scanButton setTitle:@"New scan" forState:UIControlStateNormal];
	[_scanButton addTarget:self action:@selector(newScan) forControlEvents:UIControlEventTouchUpInside];
	_nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_nextButton setTitle:@"Next scan" forState:UIControlStateNormal];
	[_nextButton addTarget:self action:@selector(nextScan) forControlEvents:UIControlEventTouchUpInside];
	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	[close setTitle:@"Close" forState:UIControlStateNormal];
	[close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
	UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_scanButton, _nextButton, close]];
	buttons.distribution = UIStackViewDistributionFillEqually;

	_status = [UILabel new];
	_status.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	_status.textColor = UIColor.secondaryLabelColor;
	_status.numberOfLines = 2;
	_status.text = @"1) Type the value you see in the game and tap New scan. 2) Change it in the game, type the new value, tap Next scan. Repeat until a few results are left, then tap one to edit it.";

	UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[title, warn, _typeControl, _field, _modeControl, buttons, _status]];
	top.axis = UILayoutConstraintAxisVertical;
	top.spacing = 8;
	top.translatesAutoresizingMaskIntoConstraints = NO;

	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	_table.dataSource = self;
	_table.delegate = self;
	_table.translatesAutoresizingMaskIntoConstraints = NO;
	_table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	[self.view addSubview:top];
	[self.view addSubview:_table];
	UILayoutGuide *g = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[top.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
		[top.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
		[top.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
		[_table.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
		[_table.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
		[_table.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
		[_table.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
	]];
}

- (void)closePanel {
	[self.view endEditing:YES];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setStatus:(NSString *)text {
	BTBOnMain(^{ self->_status.text = text; });
}

- (BTBHit *)hits { return _store; }
- (NSUInteger)hitCount { return _count; }

- (BOOL)overlapsOwnMemory:(vm_address_t)start size:(vm_size_t)size {
	vm_address_t end = start + size;
	vm_address_t s1 = (vm_address_t)_store, e1 = s1 + kMaxHits * sizeof(BTBHit);
	vm_address_t s2 = (vm_address_t)_readBuffer, e2 = s2 + kChunk;
	return (start < e1 && end > s1) || (start < e2 && end > s2);
}

#pragma mark - Scanning

- (void)newScan {
	if (_busy) return;
	BTBType type = (BTBType)_typeControl.selectedSegmentIndex;
	uint64_t target;
	if (!BTBParse(_field.text, type, &target)) { [self setStatus:@"Type a value first."]; return; }
	[self.view endEditing:YES];
	if (!_store || !_readBuffer) { [self setStatus:@"Out of memory."]; return; }
	_busy = YES;
	_count = 0;
	[_table reloadData];
	[self setStatus:@"Scanning memory…"];
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
						if (memcmp(buffer + i, &target, size) == 0) {
							store[found].address = address + off + i;
							store[found].raw = target;
							if (++found >= kMaxHits) { full = YES; break; }
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
			[self setStatus:[NSString stringWithFormat:@"%lu results%@. Change the value in the game, then tap Next scan.", (unsigned long)[self hitCount], full ? @" (limit reached — search for a more unusual value)" : @""]];
			[self->_table reloadData];
		});
	});
}

- (void)nextScan {
	if (_busy) return;
	if ([self hitCount] == 0) { [self setStatus:@"Run New scan first."]; return; }
	BTBType type = _hitType;
	BTBMode mode = (BTBMode)_modeControl.selectedSegmentIndex;
	uint64_t target = 0;
	if (mode == BTBModeExact && !BTBParse(_field.text, type, &target)) { [self setStatus:@"Type the new value first."]; return; }
	[self.view endEditing:YES];
	_busy = YES;
	[self setStatus:@"Filtering…"];
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
			NSUInteger n = [self hitCount];
			[self setStatus:n == 0 ? @"No results left. Start over with New scan." : [NSString stringWithFormat:@"%lu results%@", (unsigned long)n, n <= 200 ? @". Tap one to edit it." : @". Scan again to narrow it down."]];
			[self->_table reloadData];
		});
	});
}

#pragma mark - Results

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	return (NSInteger)MIN([self hitCount], (NSUInteger)200);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
	BTBHit h = [self hits][ip.row];
	uint64_t now = 0;
	BOOL ok = BTBReadMemory(h.address, &now, BTBSize(_hitType));
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	cell.textLabel.text = [NSString stringWithFormat:@"0x%llx%@", h.address, _frozen[@(h.address)] ? @"  ❄︎" : @""];
	cell.detailTextLabel.text = ok ? BTBFormat(now, _hitType) : @"?";
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	BTBHit h = [self hits][ip.row];
	BTBType type = _hitType;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"0x%llx", h.address]
		message:@"New value" preferredStyle:UIAlertControllerStyleAlert];
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
	[a addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(NO); }]];
	[a addAction:[UIAlertAction actionWithTitle:@"Set and freeze" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(YES); }]];
	if (_frozen[@(h.address)]) {
		[a addAction:[UIAlertAction actionWithTitle:@"Unfreeze" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
			[self->_frozen removeObjectForKey:@(h.address)];
			[self updateFreezeTimer];
			[tv reloadData];
		}]];
	}
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
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
	}];
}
