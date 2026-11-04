//  BTBGGPanels.m — GameGuardian panel screens: value editor, search regions, saved list, hex memory view.

#import "BTBGGUI.h"
#import <mach-o/dyld.h>

static void Notice(UIViewController *host, NSString *title, NSString *message) {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[host presentViewController:a animated:YES completion:nil];
}

static NSString *FreezeMark(BTBGGEngine *e, uint64_t address) { return [e isFrozen:address] ? @"  ❄︎" : @""; }

// MARK: - Value editor

void BTBGGPresentValueEditor(UIViewController *host, uint64_t address, BTBGGType type, void (^changed)(void)) {
	BTBGGEngine *e = [BTBGGEngine shared];
	uint64_t now = 0;
	BOOL readable = [e readValue:address type:type raw:&now];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Change the number", @"Изменить число")
		message:[NSString stringWithFormat:BL(@"%@ at %@\n“Freeze” keeps the game from changing it back.", @"%@ по адресу %@\n«Заморозить» не даёт игре вернуть значение."), [BTBGGEngine nameOfType:type], [e describeAddress:address]]
		preferredStyle:UIAlertControllerStyleAlert];
	__block UITextField *field = nil;
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) {
		f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
		if (readable) f.text = [BTBGGEngine format:now type:type];
		field = f;
	}];
	void (^apply)(BOOL, BTBGGFreezeMode) = ^(BOOL freeze, BTBGGFreezeMode mode) {
		uint64_t raw;
		if (![BTBGGEngine parse:field.text type:type raw:&raw]) { Notice(host, BL(@"Not a number", @"Это не число"), BL(@"Type a number that fits this type.", @"Введи число, подходящее к этому типу.")); return; }
		if (![e writeValue:address type:type raw:raw]) { Notice(host, BL(@"Could not write", @"Не удалось записать"), BL(@"This memory cannot be changed.", @"Эту память нельзя изменить.")); return; }
		if (freeze) [e freezeAddress:address type:type raw:raw mode:mode]; else [e unfreezeAddress:address];
		if (changed) changed();
	};
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Change", @"Изменить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(NO, BTBGGFreezeExact); }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Change and freeze", @"Изменить и заморозить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(YES, BTBGGFreezeExact); }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Freeze: never below this", @"Заморозить: не ниже этого") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(YES, BTBGGFreezeAtLeast); }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Freeze: never above this", @"Заморозить: не выше этого") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { apply(YES, BTBGGFreezeAtMost); }]];
	if ([e isFrozen:address]) {
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Unfreeze", @"Разморозить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
			[e unfreezeAddress:address];
			if (changed) changed();
		}]];
	}
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Save to the list", @"Сохранить в список") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		[e addToListAddress:address type:type label:nil];
		[e persistList];
		if (changed) changed();
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Open in memory view", @"Открыть в просмотре памяти") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { BTBGGShowMemory(address); }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[host presentViewController:a animated:YES completion:nil];
}

// MARK: - Regions

NSString *BTBGGRegionSummary(NSUInteger mask) {
	if ((mask & BTBGGRegionAll) == BTBGGRegionAll) return BL(@"all", @"все");
	if ((mask & BTBGGRegionAll) == BTBGGRegionDefault) return BL(@"standard", @"обычные");
	NSMutableArray *names = [NSMutableArray array];
	if (mask & BTBGGRegionHeap) [names addObject:BL(@"Heap", @"Куча")];
	if (mask & BTBGGRegionAnonymous) [names addObject:BL(@"Anon", @"Аноним.")];
	if (mask & BTBGGRegionStack) [names addObject:BL(@"Stack", @"Стек")];
	if (mask & BTBGGRegionAppData) [names addObject:BL(@"App", @"Прил.")];
	if (mask & BTBGGRegionSystemData) [names addObject:BL(@"System", @"Система")];
	if (mask & BTBGGRegionOther) [names addObject:BL(@"Other", @"Прочее")];
	return names.count ? [names componentsJoinedByString:@"+"] : BL(@"none", @"нет");
}

@interface BTBGGRegionsVC : UITableViewController
@end

@implementation BTBGGRegionsVC

+ (NSArray<NSArray *> *)rows {
	return @[
		@[@(BTBGGRegionHeap), BL(@"Heap", @"Куча (Heap)"), BL(@"Ordinary memory of the app: most scores, coins and lives live here.", @"Обычная память приложения: здесь лежит большинство очков, монет и жизней.")],
		@[@(BTBGGRegionAnonymous), BL(@"Anonymous memory", @"Анонимная память"), BL(@"Memory that game engines (Unity, Unreal) allocate themselves.", @"Память, которую выделяют сами игровые движки (Unity, Unreal).")],
		@[@(BTBGGRegionAppData), BL(@"App data", @"Данные приложения"), BL(@"Global variables of the app’s own code. Addresses here stay the same between launches.", @"Глобальные переменные кода приложения. Адреса здесь не меняются между запусками.")],
		@[@(BTBGGRegionStack), BL(@"Stack", @"Стек"), BL(@"Temporary values of running functions. Rarely useful.", @"Временные значения работающих функций. Нужен редко.")],
		@[@(BTBGGRegionSystemData), BL(@"System libraries", @"Системные библиотеки"), BL(@"Data of iOS itself. Slow and mostly noise.", @"Данные самой iOS. Медленно и в основном мусор.")],
		@[@(BTBGGRegionOther), BL(@"Other", @"Прочее"), BL(@"Mapped files, graphics memory and the rest.", @"Отображённые файлы, графическая память и остальное.")],
	];
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = BL(@"Search regions", @"Регионы поиска");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? (NSInteger)[BTBGGRegionsVC rows].count : 3; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return s == 0 ? BL(@"Where to look", @"Где искать") : BL(@"Shortcuts", @"Быстрый выбор"); }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	return s == 0 ? BL(@"Fewer regions means a faster search with fewer false hits.", @"Чем меньше регионов, тем быстрее поиск и меньше лишних результатов.") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	BTBGGEngine *e = [BTBGGEngine shared];
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	if (ip.section == 0) {
		NSArray *row = [BTBGGRegionsVC rows][ip.row];
		cell.textLabel.text = row[1];
		cell.detailTextLabel.text = row[2];
		cell.accessoryType = (e.regions & [row[0] unsignedIntegerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if (ip.row == 0) {
		cell.textLabel.text = BL(@"Standard", @"Обычные");
		cell.detailTextLabel.text = BL(@"Heap, anonymous memory and app data.", @"Куча, анонимная память и данные приложения.");
		cell.accessoryType = (e.regions & BTBGGRegionAll) == BTBGGRegionDefault ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if (ip.row == 1) {
		cell.textLabel.text = BL(@"Everything", @"Всё");
		cell.detailTextLabel.text = BL(@"Slowest, finds the most.", @"Медленнее всего, находит больше всего.");
		cell.accessoryType = (e.regions & BTBGGRegionAll) == BTBGGRegionAll ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else {
		cell.textLabel.text = BL(@"Address range…", @"Диапазон адресов…");
		BOOL limited = e.addressFrom != 0 || e.addressTo != UINT64_MAX;
		cell.detailTextLabel.text = limited ? [NSString stringWithFormat:@"0x%llx – 0x%llx", e.addressFrom, e.addressTo] : BL(@"No limit.", @"Без ограничений.");
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	BTBGGEngine *e = [BTBGGEngine shared];
	if (ip.section == 0) {
		NSUInteger bit = [[BTBGGRegionsVC rows][ip.row][0] unsignedIntegerValue];
		NSUInteger mask = e.regions ^ bit;
		if ((mask & BTBGGRegionAll) == 0) mask = bit; // keep at least one
		e.regions = mask;
	} else if (ip.row == 0) {
		e.regions = BTBGGRegionDefault;
	} else if (ip.row == 1) {
		e.regions = BTBGGRegionAll;
	} else {
		[self editRange];
		return;
	}
	[tv reloadData];
}

- (void)editRange {
	BTBGGEngine *e = [BTBGGEngine shared];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Address range", @"Диапазон адресов")
		message:BL(@"Hex addresses. Leave empty for no limit.", @"Адреса в hex. Оставь пустым, чтобы не ограничивать.") preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) {
		f.placeholder = BL(@"from, e.g. 0x100000000", @"от, например 0x100000000");
		f.autocapitalizationType = UITextAutocapitalizationTypeNone;
		if (e.addressFrom) f.text = [NSString stringWithFormat:@"0x%llx", e.addressFrom];
	}];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) {
		f.placeholder = BL(@"to, e.g. 0x180000000", @"до, например 0x180000000");
		f.autocapitalizationType = UITextAutocapitalizationTypeNone;
		if (e.addressTo != UINT64_MAX) f.text = [NSString stringWithFormat:@"0x%llx", e.addressTo];
	}];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSString *from = [wa.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		NSString *to = [wa.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		e.addressFrom = from.length ? strtoull(from.UTF8String, NULL, 16) : 0;
		e.addressTo = to.length ? strtoull(to.UTF8String, NULL, 16) : UINT64_MAX;
		if (e.addressTo <= e.addressFrom) { e.addressFrom = 0; e.addressTo = UINT64_MAX; }
		[self.tableView reloadData];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end

UIViewController *BTBGGMakeRegionsVC(void) { return [BTBGGRegionsVC new]; }

// MARK: - Saved list

@interface BTBGGSavedListVC : UITableViewController
@end

@implementation BTBGGSavedListVC {
	NSTimer *_timer;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	__weak typeof(self) weak = self;
	NSArray *items = @[
		[UIAction actionWithTitle:BL(@"Freeze all", @"Заморозить все") image:nil identifier:nil handler:^(UIAction *x) { [weak freezeAll]; }],
		[UIAction actionWithTitle:BL(@"Unfreeze all", @"Разморозить все") image:nil identifier:nil handler:^(UIAction *x) { [[BTBGGEngine shared] unfreezeAll]; [weak.tableView reloadData]; }],
		[UIAction actionWithTitle:BL(@"Share the list", @"Поделиться списком") image:nil identifier:nil handler:^(UIAction *x) { [weak shareList]; }],
		[UIAction actionWithTitle:BL(@"Import from clipboard", @"Импорт из буфера обмена") image:nil identifier:nil handler:^(UIAction *x) { [weak importList]; }],
		[UIAction actionWithTitle:BL(@"Clear the list", @"Очистить список") image:nil identifier:nil handler:^(UIAction *x) { [weak confirmClear]; }],
	];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:items]];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
	__weak typeof(self) weak = self;
	_timer = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *t) { [weak updateVisibleValues]; }];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_timer invalidate];
	_timer = nil;
}

- (NSArray<BTBGGItem *> *)items { return [BTBGGEngine shared].list; }

- (void)updateVisibleValues {
	for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
		if (ip.row < (NSInteger)self.items.count && [cell.accessoryView isKindOfClass:[UILabel class]]) [self fillValue:(UILabel *)cell.accessoryView item:self.items[ip.row]];
	}
}

- (void)fillValue:(UILabel *)label item:(BTBGGItem *)item {
	BTBGGEngine *e = [BTBGGEngine shared];
	uint64_t raw = 0;
	label.text = [([e readValue:item.address type:item.type raw:&raw] ? [BTBGGEngine format:raw type:item.type] : @"?") stringByAppendingString:FreezeMark(e, item.address)];
	[label sizeToFit];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	NSInteger n = (NSInteger)self.items.count;
	if (n == 0) {
		UILabel *l = BTBGGLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);
		l.textAlignment = NSTextAlignmentCenter;
		l.text = BL(@"The list is empty.\nIn the search results, tap a line and choose “Save to the list”.\nAddresses inside the app’s code stay after a restart; heap addresses do not.", @"Список пуст.\nВ результатах поиска нажми на строку и выбери «Сохранить в список».\nАдреса внутри кода приложения остаются после перезапуска, адреса в куче — нет.");
		UIView *wrap = [UIView new];
		l.translatesAutoresizingMaskIntoConstraints = NO;
		[wrap addSubview:l];
		[NSLayoutConstraint activateConstraints:@[
			[l.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:30],
			[l.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-30],
			[l.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor constant:-40],
		]];
		tv.backgroundView = wrap;
	} else {
		tv.backgroundView = nil;
	}
	return n;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	BTBGGEngine *e = [BTBGGEngine shared];
	BTBGGItem *item = self.items[ip.row];
	cell.textLabel.text = item.label.length ? item.label : [e describeAddress:item.address];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx%@", [BTBGGEngine nameOfType:item.type], item.address, item.module ? @"" : BL(@" · this launch only", @" · только этот запуск")];
	UILabel *value = BTBGGLabel([UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightSemibold], UIColor.labelColor);
	value.numberOfLines = 1;
	[self fillValue:value item:item];
	cell.accessoryView = value;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	BTBGGItem *item = self.items[ip.row];
	BTBGGPresentValueEditor(self, item.address, item.type, ^{ [tv reloadData]; });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	BTBGGItem *item = self.items[ip.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:BL(@"Delete", @"Удалить") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[[BTBGGEngine shared] removeListItems:@[item]];
		[[BTBGGEngine shared] persistList];
		[tv reloadData];
		done(YES);
	}];
	UIContextualAction *view = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Memory", @"Память") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		BTBGGShowMemory(item.address);
		done(YES);
	}];
	view.backgroundColor = BTBGGAccent();
	return [UISwipeActionsConfiguration configurationWithActions:@[del, view]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	BTBGGItem *item = self.items[ip.row];
	UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Rename", @"Название") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:BL(@"Name", @"Название") message:nil preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = item.label; f.placeholder = BL(@"e.g. Coins", @"например, Монеты"); }];
		__weak UIAlertController *wa = alert;
		[alert addAction:[UIAlertAction actionWithTitle:BL(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
			item.label = wa.textFields.firstObject.text ?: @"";
			[[BTBGGEngine shared] persistList];
			[tv reloadData];
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		done(YES);
	}];
	rename.backgroundColor = UIColor.systemOrangeColor;
	return [UISwipeActionsConfiguration configurationWithActions:@[rename]];
}

- (void)freezeAll {
	BTBGGEngine *e = [BTBGGEngine shared];
	for (BTBGGItem *item in self.items) {
		uint64_t raw;
		if ([e readValue:item.address type:item.type raw:&raw]) [e freezeAddress:item.address type:item.type raw:raw mode:BTBGGFreezeExact];
	}
	[self.tableView reloadData];
}

- (void)shareList {
	if (self.items.count == 0) return;
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[[BTBGGEngine shared] listJSON]] applicationActivities:nil];
	vc.popoverPresentationController.sourceView = self.view;
	[self presentViewController:vc animated:YES completion:nil];
}

- (void)importList {
	NSString *text = UIPasteboard.generalPasteboard.string;
	NSInteger n = text.length ? [[BTBGGEngine shared] importListJSON:text] : -1;
	if (n < 0) { Notice(self, BL(@"Nothing to import", @"Нечего импортировать"), BL(@"Copy a list exported with “Share the list” first.", @"Сначала скопируй список, выгруженный через «Поделиться списком».")); return; }
	[self.tableView reloadData];
	Notice(self, BL(@"Imported", @"Импортировано"), [NSString stringWithFormat:BL(@"Added: %ld. Only addresses inside the app’s code can be restored.", @"Добавлено: %ld. Восстанавливаются только адреса внутри кода приложения."), (long)n]);
}

- (void)confirmClear {
	if (self.items.count == 0) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Clear the list?", @"Очистить список?") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Clear", @"Очистить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
		[[BTBGGEngine shared] clearList];
		[[BTBGGEngine shared] persistList];
		[self.tableView reloadData];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end

UIViewController *BTBGGMakeSavedListVC(void) { return [BTBGGSavedListVC new]; }

// MARK: - Memory view

static const NSUInteger kRowBytes = 8;
static const NSUInteger kRows = 32;

static BOOL ParseHexBytes(NSString *text, NSMutableData *out) {
	NSMutableString *digits = [NSMutableString string];
	for (NSUInteger i = 0; i < text.length; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == ' ' || c == '\n' || c == ',' || c == ':') continue;
		if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
		[digits appendFormat:@"%C", c];
	}
	if (digits.length == 0 || digits.length % 2) return NO;
	for (NSUInteger i = 0; i < digits.length; i += 2) {
		unsigned v = 0;
		[[NSScanner scannerWithString:[digits substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&v];
		uint8_t b = (uint8_t)v;
		[out appendBytes:&b length:1];
	}
	return YES;
}

@interface BTBGGMemoryVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (void)showAddress:(uint64_t)address;
@end

@implementation BTBGGMemoryVC {
	UITextField *_field;
	UITableView *_table;
	uint64_t _base;
	uint8_t _bytes[256];
	BOOL _ok[256];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	_field = [UITextField new];
	_field.borderStyle = UITextBorderStyleRoundedRect;
	_field.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightMedium];
	_field.placeholder = BL(@"address, e.g. 0x1034f0000", @"адрес, например 0x1034f0000");
	_field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_field.autocorrectionType = UITextAutocorrectionTypeNo;
	_field.returnKeyType = UIReturnKeyGo;
	[_field addTarget:self action:@selector(go) forControlEvents:UIControlEventEditingDidEndOnExit];
	UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
	[go setTitle:BL(@"Go", @"Перейти") forState:UIControlStateNormal];
	go.titleLabel.font = [UIFont boldSystemFontOfSize:17];
	[go addTarget:self action:@selector(go) forControlEvents:UIControlEventTouchUpInside];
	UIButton *main = [UIButton buttonWithType:UIButtonTypeSystem];
	[main setTitle:BL(@"App", @"Код") forState:UIControlStateNormal];
	[main addTarget:self action:@selector(gotoMain) forControlEvents:UIControlEventTouchUpInside];
	UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_field, go, main]];
	top.spacing = 12;
	top.alignment = UIStackViewAlignmentCenter;
	top.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
	[prev setTitle:@"◀︎ 256" forState:UIControlStateNormal];
	[prev addTarget:self action:@selector(previous) forControlEvents:UIControlEventTouchUpInside];
	UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
	[next setTitle:@"256 ▶︎" forState:UIControlStateNormal];
	[next addTarget:self action:@selector(nextPage) forControlEvents:UIControlEventTouchUpInside];
	UILabel *tip = BTBGGLabel([UIFont systemFontOfSize:12], UIColor.secondaryLabelColor);
	tip.text = BL(@"Tap a line to edit its bytes", @"Нажми на строку, чтобы изменить байты");
	tip.textAlignment = NSTextAlignmentCenter;
	UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[prev, tip, next]];
	bottom.distribution = UIStackViewDistributionEqualCentering;
	bottom.alignment = UIStackViewAlignmentCenter;
	bottom.translatesAutoresizingMaskIntoConstraints = NO;

	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	_table.dataSource = self;
	_table.delegate = self;
	_table.rowHeight = 30;
	_table.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:top];
	[self.view addSubview:_table];
	[self.view addSubview:bottom];
	UILayoutGuide *g = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[top.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
		[top.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
		[top.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
		[_table.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
		[_table.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
		[_table.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
		[_table.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-4],
		[bottom.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
		[bottom.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
		[bottom.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-6],
	]];
	[self loadPage];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self loadPage];
}

- (void)showAddress:(uint64_t)address {
	_base = address & ~(uint64_t)(kRowBytes - 1);
	[self loadViewIfNeeded];
	_field.text = [NSString stringWithFormat:@"0x%llx", address];
	[self loadPage];
}

- (void)loadPage {
	BTBGGEngine *e = [BTBGGEngine shared];
	memset(_bytes, 0, sizeof(_bytes));
	memset(_ok, 0, sizeof(_ok));
	if (_base != 0) {
		if ([e readBytes:_base into:_bytes length:sizeof(_bytes)]) memset(_ok, 1, sizeof(_ok));
		else for (NSUInteger r = 0; r < kRows; r++) {
			if ([e readBytes:_base + r * kRowBytes into:_bytes + r * kRowBytes length:kRowBytes]) memset(_ok + r * kRowBytes, 1, kRowBytes);
		}
	}
	[_table reloadData];
}

- (void)go {
	[_field resignFirstResponder];
	NSString *s = [_field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	if (s.length == 0) return;
	const char *c = s.UTF8String;
	if (c[0] == 'h' || c[0] == 'H') c++;
	uint64_t a = strtoull(c, NULL, 16);
	if (a < 0x1000) { Notice(self, BL(@"Invalid address", @"Неверный адрес"), BL(@"Type a hex address, e.g. 0x1034f0000.", @"Введи адрес в hex, например 0x1034f0000.")); return; }
	_base = a & ~(uint64_t)(kRowBytes - 1);
	[self loadPage];
}

- (void)gotoMain {
	const struct mach_header *h = _dyld_get_image_header(0);
	if (!h) return;
	_base = (uint64_t)(uintptr_t)h;
	_field.text = [NSString stringWithFormat:@"0x%llx", _base];
	[self loadPage];
}

- (void)previous { if (_base >= sizeof(_bytes) + 0x1000) { _base -= sizeof(_bytes); [self loadPage]; } }
- (void)nextPage { if (_base) { _base += sizeof(_bytes); [self loadPage]; } }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _base ? (NSInteger)kRows : 0; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"m"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"m"];
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	cell.textLabel.adjustsFontSizeToFitWidth = YES;
	NSMutableString *hex = [NSMutableString string], *ascii = [NSMutableString string];
	for (NSUInteger i = 0; i < kRowBytes; i++) {
		NSUInteger k = (NSUInteger)ip.row * kRowBytes + i;
		if (_ok[k]) {
			[hex appendFormat:@"%02X ", _bytes[k]];
			[ascii appendFormat:@"%c", (_bytes[k] >= 32 && _bytes[k] < 127) ? _bytes[k] : '.'];
		} else {
			[hex appendString:@"?? "];
			[ascii appendString:@"?"];
		}
	}
	cell.textLabel.text = [NSString stringWithFormat:@"%09llx  %@ %@", _base + (uint64_t)ip.row * kRowBytes, hex, ascii];
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	uint64_t addr = _base + (uint64_t)ip.row * kRowBytes;
	NSUInteger k = (NSUInteger)ip.row * kRowBytes;
	if (!_ok[k]) return;
	uint32_t d; float f; uint64_t q;
	memcpy(&d, _bytes + k, 4);
	memcpy(&f, _bytes + k, 4);
	memcpy(&q, _bytes + k, 8);
	NSMutableString *hex = [NSMutableString string];
	for (NSUInteger i = 0; i < kRowBytes; i++) [hex appendFormat:@"%@%02X", i ? @" " : @"", _bytes[k + i]];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"0x%llx", addr]
		message:[NSString stringWithFormat:@"Dword %d · Float %g\nQword %lld", (int32_t)d, f, (long long)q] preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.text = hex;
		tf.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
		tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Write", @"Записать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSMutableData *data = [NSMutableData data];
		if (!ParseHexBytes(wa.textFields.firstObject.text, data) || data.length > kRowBytes) {
			Notice(self, BL(@"Not valid bytes", @"Неверные байты"), BL(@"Type up to 8 bytes in hex, e.g. 0A FF 00 3C.", @"Введи до 8 байт в hex, например 0A FF 00 3C."));
			return;
		}
		if (![[BTBGGEngine shared] writeBytes:addr from:data.bytes length:data.length]) Notice(self, BL(@"Could not write", @"Не удалось записать"), BL(@"This memory cannot be changed.", @"Эту память нельзя изменить."));
		[self loadPage];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Save Dword to the list", @"Dword в список") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		[[BTBGGEngine shared] addToListAddress:addr type:BTBGGTypeDword label:nil];
		[[BTBGGEngine shared] persistList];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end

UIViewController *BTBGGMakeMemoryVC(void) { return [BTBGGMemoryVC new]; }

void BTBGGMemoryShowAddress(UIViewController *memoryVC, uint64_t address) {
	if ([memoryVC isKindOfClass:[BTBGGMemoryVC class]]) [(BTBGGMemoryVC *)memoryVC showAddress:address];
}
