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
		BTBGGPresentSaveItem(host, address, type, changed);
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
	self.tableView.backgroundColor = BTBGGBackground();
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

// MARK: - Folder picker

@interface BTBGGFolderPickerVC : UITableViewController
- (instancetype)initWithPath:(NSString *)path origin:(UIViewController *)origin picked:(void (^)(NSString *))picked;
@end

@implementation BTBGGFolderPickerVC {
	NSString *_path;
	__weak UIViewController *_origin;
	void (^_picked)(NSString *);
	NSArray<NSString *> *_subs;
}

- (instancetype)initWithPath:(NSString *)path origin:(UIViewController *)origin picked:(void (^)(NSString *))picked {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _path = path ?: @""; _origin = origin; _picked = [picked copy]; }
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.backgroundColor = BTBGGBackground();
	self.title = _path.length ? _path.lastPathComponent : BL(@"Saved values", @"Сохранённые значения");
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:BL(@"Choose", @"Выбрать") style:UIBarButtonItemStyleDone target:self action:@selector(choose)],
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain target:self action:@selector(newFolder)],
	];
	[self reload];
}

- (void)reload {
	_subs = [[BTBGGEngine shared] subfoldersOf:_path];
	[self.tableView reloadData];
}

- (void)choose {
	void (^cb)(NSString *) = _picked;
	UIViewController *o = _origin;
	if (o && [self.navigationController.viewControllers containsObject:o]) [self.navigationController popToViewController:o animated:YES];
	if (cb) cb(_path);
}

- (void)newFolder {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"New folder", @"Новая папка") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = BL(@"e.g. Speed", @"например, Скорость"); }];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Create", @"Создать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSString *name = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
		if (name.length == 0) return;
		[[BTBGGEngine shared] addFolder:self->_path.length ? [self->_path stringByAppendingPathComponent:name] : name];
		[[BTBGGEngine shared] persistList];
		[self reload];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_subs.count; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	return _subs.count ? BL(@"Tap a folder to open it, then “Choose”.", @"Нажми на папку, чтобы открыть, затем «Выбрать».") : BL(@"No folders inside. Choose this one or create a new folder with the button at the top.", @"Внутри нет папок. Выбери эту или создай новую кнопкой сверху.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.text = _subs[ip.row].lastPathComponent;
	cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
	cell.imageView.tintColor = BTBGGAccent();
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	[self.navigationController pushViewController:[[BTBGGFolderPickerVC alloc] initWithPath:_subs[ip.row] origin:_origin picked:_picked] animated:YES];
}

@end

void BTBGGPickFolder(UINavigationController *nav, NSString *current, void (^picked)(NSString *path)) {
	[nav pushViewController:[[BTBGGFolderPickerVC alloc] initWithPath:@"" origin:nav.topViewController picked:picked] animated:YES];
}

// MARK: - Save sheet (name, note, folder, recipe)

@interface BTBGGSaveItemVC : UIViewController
- (instancetype)initWithAddress:(uint64_t)address type:(BTBGGType)type done:(void (^)(void))done;
- (void)setFolderValue:(NSString *)path;
@end

@implementation BTBGGSaveItemVC {
	uint64_t _address;
	BTBGGType _type;
	void (^_done)(void);
	UITextField *_name, *_note;
	UIButton *_folderButton;
	UISwitch *_recipeSwitch;
	NSString *_folder;
}

- (instancetype)initWithAddress:(uint64_t)address type:(BTBGGType)type done:(void (^)(void))done {
	if ((self = [super init])) { _address = address; _type = type; _done = [done copy]; _folder = @""; }
	return self;
}

- (UITextField *)field:(NSString *)placeholder {
	UITextField *f = [UITextField new];
	f.borderStyle = UITextBorderStyleRoundedRect;
	f.placeholder = placeholder;
	f.clearButtonMode = UITextFieldViewModeWhileEditing;
	[f.heightAnchor constraintEqualToConstant:44].active = YES;
	return f;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = BL(@"Save the value", @"Сохранить значение");
	self.view.backgroundColor = BTBGGBackground();
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:BL(@"Cancel", @"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:BL(@"Save", @"Сохранить") style:UIBarButtonItemStyleDone target:self action:@selector(save)];

	UILabel *info = BTBGGLabel([UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular], UIColor.secondaryLabelColor);
	info.text = [NSString stringWithFormat:@"%@ · 0x%llx", [BTBGGEngine nameOfType:_type], _address];
	_name = [self field:BL(@"Name, e.g. Player", @"Название, например, Игрок")];
	_note = [self field:BL(@"Note (optional)", @"Заметка (необязательно)")];

	_folderButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_folderButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	_folderButton.titleLabel.font = [UIFont systemFontOfSize:17];
	[_folderButton addTarget:self action:@selector(pickFolder) forControlEvents:UIControlEventTouchUpInside];
	[_folderButton.heightAnchor constraintEqualToConstant:44].active = YES;
	[self updateFolderTitle];

	NSMutableArray *views = [NSMutableArray arrayWithObjects:info, _name, _note, _folderButton, nil];
	if ([BTBGGEngine shared].recipeSteps.count > 0) {
		_recipeSwitch = [UISwitch new];
		_recipeSwitch.on = YES;
		_recipeSwitch.onTintColor = BTBGGAccent();
		UILabel *l = BTBGGLabel([UIFont systemFontOfSize:15], UIColor.labelColor);
		l.text = BL(@"Also save the search recipe (a GG script that finds this value again)", @"Сохранить и рецепт поиска (GG-скрипт, который находит это значение заново)");
		UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, _recipeSwitch]];
		row.spacing = 12;
		row.alignment = UIStackViewAlignmentCenter;
		[views addObject:row];
	}
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 14;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:stack];
	UILayoutGuide *g = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
		[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
		[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
	]];
}

- (void)updateFolderTitle {
	NSString *shown = _folder.length ? _folder : BL(@"Root", @"Корень");
	[_folderButton setTitle:[NSString stringWithFormat:BL(@"Folder: %@  ›", @"Папка: %@  ›"), shown] forState:UIControlStateNormal];
}

- (void)pickFolder {
	[self.view endEditing:YES];
	__weak typeof(self) weak = self;
	BTBGGPickFolder(self.navigationController, _folder, ^(NSString *path) {
		[weak setFolderValue:path];
	});
}

- (void)setFolderValue:(NSString *)path { _folder = path ?: @""; [self updateFolderTitle]; }

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)save {
	BTBGGEngine *e = [BTBGGEngine shared];
	NSString *name = [_name.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *note = [_note.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	BTBGGItem *item = [e addToListAddress:_address type:_type label:name note:note folder:_folder];
	if (_recipeSwitch.on && item) {
		NSString *title = name.length ? name : [e describeAddress:_address];
		NSString *rel = BTBGGSaveRecipe(title, BTBGGRecipeSource(title, e.recipeSteps));
		if (rel) item.recipe = rel;
	}
	[e persistList];
	void (^done)(void) = _done;
	[self dismissViewControllerAnimated:YES completion:^{ if (done) done(); }];
}

@end

void BTBGGPresentSaveItem(UIViewController *host, uint64_t address, BTBGGType type, void (^done)(void)) {
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[BTBGGSaveItemVC alloc] initWithAddress:address type:type done:done]];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[host presentViewController:nav animated:YES completion:nil];
}

// MARK: - Saved list

@interface BTBGGSavedListVC : UITableViewController
- (instancetype)initWithFolder:(NSString *)folder;
@end

@implementation BTBGGSavedListVC {
	NSTimer *_timer;
	NSString *_folder;
	NSArray<NSString *> *_subs;
	NSArray<BTBGGItem *> *_items;
}

- (instancetype)init { return [self initWithFolder:@""]; }

- (instancetype)initWithFolder:(NSString *)folder {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _folder = folder ?: @"";
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.backgroundColor = BTBGGBackground();
	if (_folder.length) self.title = _folder.lastPathComponent;
	__weak typeof(self) weak = self;
	NSMutableArray *items = [NSMutableArray arrayWithArray:@[
		[UIAction actionWithTitle:BL(@"New folder", @"Новая папка") image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil handler:^(UIAction *x) { [weak newFolder]; }],
		[UIAction actionWithTitle:BL(@"Freeze all here", @"Заморозить все здесь") image:nil identifier:nil handler:^(UIAction *x) { [weak freezeAll]; }],
		[UIAction actionWithTitle:BL(@"Unfreeze all", @"Разморозить все") image:nil identifier:nil handler:^(UIAction *x) { [[BTBGGEngine shared] unfreezeAll]; [weak.tableView reloadData]; }],
		[UIAction actionWithTitle:BL(@"Share the list", @"Поделиться списком") image:nil identifier:nil handler:^(UIAction *x) { [weak shareList]; }],
		[UIAction actionWithTitle:BL(@"Import from clipboard", @"Импорт из буфера обмена") image:nil identifier:nil handler:^(UIAction *x) { [weak importList]; }],
	]];
	if (_folder.length == 0) [items addObject:[UIAction actionWithTitle:BL(@"Clear the list", @"Очистить список") image:nil identifier:nil handler:^(UIAction *x) { [weak confirmClear]; }]];
	UIBarButtonItem *menu = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:items]];
	if (_folder.length) self.navigationItem.rightBarButtonItem = menu; else self.navigationItem.leftBarButtonItem = menu;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
	__weak typeof(self) weak = self;
	_timer = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *t) { [weak updateVisibleValues]; }];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_timer invalidate];
	_timer = nil;
}

- (void)reload {
	BTBGGEngine *e = [BTBGGEngine shared];
	if (_folder.length && ![[e allFolders] containsObject:_folder]) { [self.navigationController popViewControllerAnimated:NO]; return; }
	_subs = [e subfoldersOf:_folder];
	_items = [e itemsInFolder:_folder];
	[self.tableView reloadData];
}

- (void)updateVisibleValues {
	for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
		if (ip.section != 1) continue;
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
		if (ip.row < (NSInteger)_items.count && [cell.accessoryView isKindOfClass:[UILabel class]]) [self fillValue:(UILabel *)cell.accessoryView item:_items[ip.row]];
	}
}

- (void)fillValue:(UILabel *)label item:(BTBGGItem *)item {
	BTBGGEngine *e = [BTBGGEngine shared];
	if (item.stale) { label.text = @"—"; [label sizeToFit]; return; }
	uint64_t raw = 0;
	label.text = [([e readValue:item.address type:item.type raw:&raw] ? [BTBGGEngine format:raw type:item.type] : @"?") stringByAppendingString:FreezeMark(e, item.address)];
	[label sizeToFit];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (s == 0) {
		if (_subs.count == 0 && _items.count == 0) {
			UILabel *l = BTBGGLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);
			l.textAlignment = NSTextAlignmentCenter;
			l.text = _folder.length ? BL(@"This folder is empty.", @"Эта папка пуста.")
				: BL(@"Nothing saved yet.\nIn the search results, tap a line and choose “Save to the list”: give it a name, a note and a folder.\nValues stay in the list for this game between launches. Heap addresses change every launch, so they stay as a name and a note (and a recipe, if you saved one).", @"Пока ничего не сохранено.\nВ результатах поиска нажми на строку и выбери «Сохранить в список»: задай название, заметку и папку.\nСписок хранится для этой игры между запусками. Адреса в куче меняются при каждом запуске, поэтому остаются как название и заметка (и рецепт, если ты его сохранил).");
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
		return (NSInteger)_subs.count;
	}
	return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	BTBGGEngine *e = [BTBGGEngine shared];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.numberOfLines = 0;
	if (ip.section == 0) {
		NSString *path = _subs[ip.row];
		cell.textLabel.text = path.lastPathComponent;
		cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
		cell.imageView.tintColor = BTBGGAccent();
		cell.detailTextLabel.text = [NSString stringWithFormat:BL(@"%lu values", @"значений: %lu"), (unsigned long)[e countInFolder:path]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	BTBGGItem *item = _items[ip.row];
	cell.textLabel.text = item.label.length ? item.label : (item.stale ? BL(@"(no name)", @"(без названия)") : [e describeAddress:item.address]);
	NSMutableArray *lines = [NSMutableArray array];
	if (item.note.length) [lines addObject:item.note];
	if (item.stale) {
		[lines addObject:item.recipe.length ? BL(@"Heap address of an earlier launch · tap to run the recipe", @"Адрес в куче с прошлого запуска · нажми, чтобы запустить рецепт") : BL(@"Heap address of an earlier launch · find it again", @"Адрес в куче с прошлого запуска · найди заново")];
	} else {
		[lines addObject:[NSString stringWithFormat:@"%@ · 0x%llx%@", [BTBGGEngine nameOfType:item.type], item.address, item.module ? @"" : BL(@" · this launch only", @" · только этот запуск")]];
	}
	cell.detailTextLabel.text = [lines componentsJoinedByString:@"\n"];
	UILabel *value = BTBGGLabel([UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightSemibold], UIColor.labelColor);
	value.numberOfLines = 1;
	[self fillValue:value item:item];
	cell.accessoryView = value;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 0) {
		[self.navigationController pushViewController:[[BTBGGSavedListVC alloc] initWithFolder:_subs[ip.row]] animated:YES];
		return;
	}
	BTBGGItem *item = _items[ip.row];
	if (item.stale) { [self staleSheet:item]; return; }
	BTBGGPresentValueEditor(self, item.address, item.type, ^{ [tv reloadData]; });
}

- (void)staleSheet:(BTBGGItem *)item {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:item.label.length ? item.label : BL(@"Value", @"Значение")
		message:[(item.note.length ? [item.note stringByAppendingString:@"\n\n"] : @"") stringByAppendingString:BL(@"This value was on the heap, and heap addresses change on every launch. Find it again with a search.", @"Это значение лежало в куче, а адреса в куче меняются при каждом запуске. Найди его заново поиском.")]
		preferredStyle:UIAlertControllerStyleAlert];
	if (item.recipe.length) {
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Run the recipe", @"Запустить рецепт") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
			if (BTBGGRunRecipe(item.recipe)) BTBGGSelectTab(2);
			else Notice(self, BL(@"Could not run", @"Не удалось запустить"), BL(@"The recipe is missing or another script is running.", @"Рецепта нет или уже работает другой скрипт."));
		}]];
	}
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Edit name and note", @"Название и заметка") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self editItem:item]; }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)editItem:(BTBGGItem *)item {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:BL(@"Name and note", @"Название и заметка") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = item.label; f.placeholder = BL(@"Name, e.g. Player", @"Название, например, Игрок"); }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = item.note; f.placeholder = BL(@"Note", @"Заметка"); }];
	__weak UIAlertController *wa = alert;
	[alert addAction:[UIAlertAction actionWithTitle:BL(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		item.label = wa.textFields[0].text ?: @"";
		item.note = wa.textFields[1].text ?: @"";
		[[BTBGGEngine shared] persistList];
		[self reload];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	BTBGGEngine *e = [BTBGGEngine shared];
	if (ip.section == 0) {
		NSString *path = _subs[ip.row];
		UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:BL(@"Delete", @"Удалить") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
			NSUInteger n = [e countInFolder:path];
			void (^doDelete)(void) = ^{ [e deleteFolder:path]; [e persistList]; [self reload]; };
			if (n == 0) { doDelete(); done(YES); return; }
			UIAlertController *c = [UIAlertController alertControllerWithTitle:BL(@"Delete the folder?", @"Удалить папку?") message:[NSString stringWithFormat:BL(@"%lu saved values inside will be deleted too.", @"Сохранённые значения внутри (%lu) тоже удалятся."), (unsigned long)n] preferredStyle:UIAlertControllerStyleAlert];
			[c addAction:[UIAlertAction actionWithTitle:BL(@"Delete", @"Удалить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { doDelete(); }]];
			[c addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:c animated:YES completion:nil];
			done(YES);
		}];
		UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Rename", @"Имя") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:BL(@"Rename the folder", @"Название папки") message:nil preferredStyle:UIAlertControllerStyleAlert];
			[alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = path.lastPathComponent; }];
			__weak UIAlertController *wa = alert;
			[alert addAction:[UIAlertAction actionWithTitle:BL(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
				NSString *name = [[wa.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
				if (name.length == 0) return;
				if (![e renameFolder:path to:name]) Notice(self, BL(@"Name is taken", @"Такое имя уже есть"), nil);
				[e persistList];
				[self reload];
			}]];
			[alert addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:alert animated:YES completion:nil];
			done(YES);
		}];
		ren.backgroundColor = UIColor.systemOrangeColor;
		return [UISwipeActionsConfiguration configurationWithActions:@[del, ren]];
	}
	BTBGGItem *item = _items[ip.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:BL(@"Delete", @"Удалить") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[e removeListItems:@[item]];
		[e persistList];
		[self reload];
		done(YES);
	}];
	UIContextualAction *move = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Move", @"Папка") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		BTBGGPickFolder(self.navigationController, item.folder, ^(NSString *path) {
			[e moveItem:item toFolder:path];
			[e persistList];
			[self reload];
		});
		done(YES);
	}];
	move.backgroundColor = UIColor.systemGrayColor;
	NSMutableArray *actions = [NSMutableArray arrayWithObjects:del, move, nil];
	if (!item.stale) {
		UIContextualAction *view = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Memory", @"Память") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
			BTBGGShowMemory(item.address);
			done(YES);
		}];
		view.backgroundColor = BTBGGAccent();
		[actions addObject:view];
	}
	return [UISwipeActionsConfiguration configurationWithActions:actions];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0) return nil;
	BTBGGItem *item = _items[ip.row];
	UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Edit", @"Заметка") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[self editItem:item];
		done(YES);
	}];
	edit.backgroundColor = UIColor.systemOrangeColor;
	return [UISwipeActionsConfiguration configurationWithActions:@[edit]];
}

- (void)newFolder {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"New folder", @"Новая папка") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = BL(@"e.g. Speed", @"например, Скорость"); }];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Create", @"Создать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSString *name = [[wa.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (name.length == 0) return;
		[[BTBGGEngine shared] addFolder:self->_folder.length ? [self->_folder stringByAppendingPathComponent:name] : name];
		[[BTBGGEngine shared] persistList];
		[self reload];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)freezeAll {
	BTBGGEngine *e = [BTBGGEngine shared];
	for (BTBGGItem *item in _items) {
		uint64_t raw;
		if (!item.stale && [e readValue:item.address type:item.type raw:&raw]) [e freezeAddress:item.address type:item.type raw:raw mode:BTBGGFreezeExact];
	}
	[self.tableView reloadData];
}

- (void)shareList {
	if ([BTBGGEngine shared].list.count == 0) return;
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[[BTBGGEngine shared] listJSON]] applicationActivities:nil];
	vc.popoverPresentationController.sourceView = self.view;
	[self presentViewController:vc animated:YES completion:nil];
}

- (void)importList {
	NSString *text = UIPasteboard.generalPasteboard.string;
	NSInteger n = text.length ? [[BTBGGEngine shared] importListJSON:text] : -1;
	if (n < 0) { Notice(self, BL(@"Nothing to import", @"Нечего импортировать"), BL(@"Copy a list exported with “Share the list” first.", @"Сначала скопируй список, выгруженный через «Поделиться списком».")); return; }
	[self reload];
	Notice(self, BL(@"Imported", @"Импортировано"), [NSString stringWithFormat:BL(@"Added: %ld. Only addresses inside the app’s code can be restored; the rest stay as a name and a note.", @"Добавлено: %ld. Восстанавливаются только адреса внутри кода приложения, остальные остаются как название и заметка."), (long)n]);
}

- (void)confirmClear {
	if ([BTBGGEngine shared].list.count == 0) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Clear the list?", @"Очистить список?") message:BL(@"All saved values and folders will be deleted.", @"Все сохранённые значения и папки будут удалены.") preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Clear", @"Очистить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
		[[BTBGGEngine shared] clearList];
		[[BTBGGEngine shared] persistList];
		[self reload];
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
	self.view.backgroundColor = BTBGGBackground();

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
		BTBGGPresentSaveItem(self, addr, BTBGGTypeDword, nil);
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end

UIViewController *BTBGGMakeMemoryVC(void) { return [BTBGGMemoryVC new]; }

void BTBGGMemoryShowAddress(UIViewController *memoryVC, uint64_t address) {
	if ([memoryVC isKindOfClass:[BTBGGMemoryVC class]]) [(BTBGGMemoryVC *)memoryVC showAddress:address];
}
