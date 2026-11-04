//  BTBGGScriptsVC.m — the "Scripts" tab: shared / this game, GG scripts / plain Lua, folders, an editor and the run log.

#import "BTBGGUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static void ScriptNotice(UIViewController *host, NSString *title, NSString *message) {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[host presentViewController:a animated:YES completion:nil];
}

static NSString *CleanName(NSString *name) {
	NSString *n = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	n = [[n componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:"]] componentsJoinedByString:@"_"];
	while ([n hasPrefix:@"."]) n = [n substringFromIndex:1];
	if (n.length == 0) return nil;
	if (n.pathExtension.length == 0) n = [n stringByAppendingPathExtension:@"lua"];
	return n;
}

static NSString *UniquePath(NSString *dir, NSString *name) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *path = [dir stringByAppendingPathComponent:name];
	NSInteger i = 2;
	while ([fm fileExistsAtPath:path]) {
		path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld.%@", name.stringByDeletingPathExtension, (long)i++, name.pathExtension]];
	}
	return path;
}

// MARK: - Log

@interface BTBGGScriptLogVC : UIViewController
@end

@implementation BTBGGScriptLogVC {
	UITextView *_text;
	UIBarButtonItem *_stopItem;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = BL(@"Script log", @"Журнал скриптов");
	self.view.backgroundColor = BTBGGBackground();
	_text = [[UITextView alloc] initWithFrame:self.view.bounds];
	_text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_text.editable = NO;
	_text.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	_text.alwaysBounceVertical = YES;
	[self.view addSubview:_text];
	UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:BL(@"Clear", @"Очистить") style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
	_stopItem = [[UIBarButtonItem alloc] initWithTitle:BL(@"Stop", @"Стоп") style:UIBarButtonItemStylePlain target:self action:@selector(stop)];
	self.navigationItem.rightBarButtonItems = @[_stopItem, clear];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:BTBGGScriptStateNotification object:nil];
	[self refresh];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)refresh {
	NSString *log = [[BTBGGScriptRunner shared] log];
	_text.text = log.length ? log : BL(@"Nothing yet. Output of print() and errors appear here.", @"Пока пусто. Здесь появится вывод print() и ошибки.");
	_text.textColor = log.length ? UIColor.labelColor : UIColor.secondaryLabelColor;
	_stopItem.enabled = [BTBGGScriptRunner shared].running;
	if (log.length) [_text scrollRangeToVisible:NSMakeRange(_text.text.length, 0)];
}

- (void)clear { [[BTBGGScriptRunner shared] clearLog]; }
- (void)stop { [[BTBGGScriptRunner shared] stop]; }

@end

// MARK: - Editor

@interface BTBGGScriptEditorVC : UIViewController
- (instancetype)initWithPath:(NSString *)path readOnly:(BOOL)readOnly plain:(BOOL)plain;
@end

@implementation BTBGGScriptEditorVC {
	NSString *_path;
	BOOL _readOnly, _plain;
	UITextView *_text;
}

- (instancetype)initWithPath:(NSString *)path readOnly:(BOOL)readOnly plain:(BOOL)plain {
	if ((self = [super init])) { _path = path; _readOnly = readOnly; _plain = plain; }
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _path.lastPathComponent;
	self.view.backgroundColor = BTBGGBackground();
	_text = [[UITextView alloc] initWithFrame:self.view.bounds];
	_text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_text.backgroundColor = UIColor.clearColor;
	_text.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
	_text.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_text.autocorrectionType = UITextAutocorrectionTypeNo;
	_text.smartQuotesType = UITextSmartQuotesTypeNo;
	_text.smartDashesType = UITextSmartDashesTypeNo;
	_text.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	_text.editable = !_readOnly;
	_text.text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:nil] ?: @"";
	[self.view addSubview:_text];
	UIBarButtonItem *run = [[UIBarButtonItem alloc] initWithTitle:BL(@"Run", @"Запуск") style:UIBarButtonItemStylePlain target:self action:@selector(run)];
	if (_readOnly) {
		UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"] style:UIBarButtonItemStylePlain target:self action:@selector(copyText)];
		self.navigationItem.rightBarButtonItems = @[run, copy];
	} else {
		UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:BL(@"Save", @"Сохранить") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
		self.navigationItem.rightBarButtonItems = @[save, run];
	}
}

- (void)copyText { UIPasteboard.generalPasteboard.string = _text.text; }

- (BOOL)writeFile {
	if (_readOnly) return YES;
	NSError *err = nil;
	if (![_text.text writeToFile:_path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
		ScriptNotice(self, BL(@"Could not save", @"Не удалось сохранить"), err.localizedDescription);
		return NO;
	}
	return YES;
}

- (void)save { if ([self writeFile]) [self.view endEditing:YES]; }

- (void)run {
	if ([BTBGGScriptRunner shared].running) { ScriptNotice(self, BL(@"A script is running", @"Скрипт уже работает"), BL(@"Stop it first (Scripts tab → Log).", @"Сначала останови его (вкладка «Скрипты» → Журнал).")); return; }
	if (![self writeFile]) return;
	[self.view endEditing:YES];
	[[BTBGGScriptRunner shared] runSource:_text.text name:_path.lastPathComponent plainLua:_plain];
	[self.navigationController pushViewController:[BTBGGScriptLogVC new] animated:YES];
}

@end

// MARK: - List

// What the root list shows; kept while the panel lives so reopening it lands in the same place.
static NSInteger gScope = 1;   // 0 shared, 1 this game
static NSInteger gKind = 0;    // 0 GG scripts, 1 plain Lua

@interface BTBGGScriptsVC : UITableViewController <UIDocumentPickerDelegate>
- (instancetype)initWithShared:(BOOL)shared gg:(BOOL)gg subpath:(NSString *)subpath;
@end

@implementation BTBGGScriptsVC {
	BOOL _isRoot;
	BOOL _shared, _gg;
	NSString *_subpath;
	NSArray<NSString *> *_folders;
	NSArray<NSString *> *_files;
	UISegmentedControl *_scopeSeg, *_kindSeg;
}

- (instancetype)init {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _isRoot = YES; _subpath = @""; }
	return self;
}

- (instancetype)initWithShared:(BOOL)shared gg:(BOOL)gg subpath:(NSString *)subpath {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _shared = shared; _gg = gg; _subpath = subpath ?: @""; }
	return self;
}

- (BOOL)isShared { return _isRoot ? gScope == 0 : _shared; }
- (BOOL)isGG { return _isRoot ? gKind == 0 : _gg; }

- (NSString *)dir {
	NSString *root = BTBGGScriptsRoot([self isShared], [self isGG]);
	return _subpath.length ? [root stringByAppendingPathComponent:_subpath] : root;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.backgroundColor = BTBGGBackground();
	if (!_isRoot) self.title = _subpath.lastPathComponent;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateHeader) name:BTBGGScriptStateNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)buildMenu {
	__weak typeof(self) weak = self;
	NSMutableArray *items = [NSMutableArray array];
	if (![self isShared]) {
		[items addObject:[UIAction actionWithTitle:BL(@"New folder", @"Новая папка") image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil handler:^(UIAction *x) { [weak askFolderName]; }]];
		[items addObject:[UIAction actionWithTitle:BL(@"New script", @"Новый скрипт") image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(UIAction *x) { [weak askNameThen:nil]; }]];
		[items addObject:[UIAction actionWithTitle:BL(@"From the clipboard", @"Из буфера обмена") image:[UIImage systemImageNamed:@"doc.on.clipboard"] identifier:nil handler:^(UIAction *x) { [weak fromClipboard]; }]];
		[items addObject:[UIAction actionWithTitle:BL(@"Import a file", @"Импорт файла") image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction *x) { [weak importFile]; }]];
	}
	[items addObject:[UIAction actionWithTitle:BL(@"Log", @"Журнал") image:[UIImage systemImageNamed:@"text.alignleft"] identifier:nil handler:^(UIAction *x) { [weak openLog]; }]];
	self.navigationItem.leftBarButtonItem = _isRoot ? [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:items]] : nil;
	if (!_isRoot) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:items]];
}

- (void)reload {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = [self dir];
	NSMutableArray *folders = [NSMutableArray array], *files = [NSMutableArray array];
	for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
		if ([f hasPrefix:@"."]) continue;
		BOOL isDir = NO;
		[fm fileExistsAtPath:[dir stringByAppendingPathComponent:f] isDirectory:&isDir];
		NSString *ext = f.pathExtension.lowercaseString;
		if (isDir) [folders addObject:f];
		else if ([ext isEqualToString:@"lua"] || [ext isEqualToString:@"txt"]) [files addObject:f];
	}
	_folders = [folders sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	_files = [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	[self buildMenu];
	[self updateHeader];
	[self.tableView reloadData];
}

- (void)segChanged {
	gScope = _scopeSeg.selectedSegmentIndex;
	gKind = _kindSeg.selectedSegmentIndex;
	[self reload];
}

- (void)updateHeader {
	BTBGGScriptRunner *r = [BTBGGScriptRunner shared];
	NSMutableArray *rows = [NSMutableArray array];
	if (_isRoot) {
		_scopeSeg = [[UISegmentedControl alloc] initWithItems:@[BL(@"Shared", @"Общие"), BL(@"This game", @"Эта игра")]];
		_scopeSeg.selectedSegmentIndex = gScope;
		_kindSeg = [[UISegmentedControl alloc] initWithItems:@[@"GG-Lua", @"Lua"]];
		_kindSeg.selectedSegmentIndex = gKind;
		_scopeSeg.selectedSegmentTintColor = BTBGGAccent();
		_kindSeg.selectedSegmentTintColor = BTBGGAccent();
		[_scopeSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
		[_kindSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
		[_scopeSeg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
		[_kindSeg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
		[rows addObject:_scopeSeg];
		[rows addObject:_kindSeg];
	}
	if (r.running) {
		UILabel *l = BTBGGLabel([UIFont boldSystemFontOfSize:15], UIColor.labelColor);
		l.text = [NSString stringWithFormat:BL(@"Running: %@", @"Работает: %@"), r.runningName ?: @""];
		l.numberOfLines = 1;
		UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
		[stop setTitle:BL(@"Stop", @"Стоп") forState:UIControlStateNormal];
		[stop setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
		[stop addTarget:self action:@selector(stopScript) forControlEvents:UIControlEventTouchUpInside];
		UIButton *log = [UIButton buttonWithType:UIButtonTypeSystem];
		[log setTitle:BL(@"Log", @"Журнал") forState:UIControlStateNormal];
		[log addTarget:self action:@selector(openLog) forControlEvents:UIControlEventTouchUpInside];
		UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, log, stop]];
		row.spacing = 14;
		row.alignment = UIStackViewAlignmentCenter;
		[rows addObject:row];
	}
	if (rows.count == 0) { self.tableView.tableHeaderView = nil; return; }
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 10;
	CGFloat w = self.tableView.bounds.size.width;
	UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 10)];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[bar addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:20],
		[stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-20],
		[stack.topAnchor constraintEqualToAnchor:bar.topAnchor constant:8],
	]];
	CGSize fit = [stack systemLayoutSizeFittingSize:CGSizeMake(w - 40, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
	bar.frame = CGRectMake(0, 0, w, fit.height + 16);
	self.tableView.tableHeaderView = bar;
}

- (void)stopScript { [[BTBGGScriptRunner shared] stop]; }
- (void)openLog { [self.navigationController pushViewController:[BTBGGScriptLogVC new] animated:YES]; }

- (NSString *)pathFor:(NSString *)file { return [[self dir] stringByAppendingPathComponent:file]; }

#pragma mark Creating

- (void)askFolderName {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"New folder", @"Новая папка") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = BL(@"Folder name", @"Название папки"); }];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Create", @"Создать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSString *name = CleanName(wa.textFields.firstObject.text);
		name = name.stringByDeletingPathExtension;
		if (name.length == 0) return;
		[[NSFileManager defaultManager] createDirectoryAtPath:[self pathFor:name] withIntermediateDirectories:YES attributes:nil error:nil];
		[self reload];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)askNameThen:(NSString *)content {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Script name", @"Название скрипта") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) {
		f.placeholder = BL(@"e.g. coins.lua", @"например, coins.lua");
		f.autocapitalizationType = UITextAutocapitalizationTypeNone;
		f.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Create", @"Создать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSString *name = CleanName(wa.textFields.firstObject.text);
		if (!name) return;
		NSString *path = UniquePath([self dir], name);
		NSString *body = content ?: BL(@"-- New script\n", @"-- Новый скрипт\n");
		[body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[self reload];
		[self.navigationController pushViewController:[[BTBGGScriptEditorVC alloc] initWithPath:path readOnly:NO plain:![self isGG]] animated:YES];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)fromClipboard {
	NSString *text = UIPasteboard.generalPasteboard.string;
	if (text.length == 0) { ScriptNotice(self, BL(@"Clipboard is empty", @"Буфер обмена пуст"), BL(@"Copy the script text first.", @"Сначала скопируй текст скрипта.")); return; }
	[self askNameThen:text];
}

- (void)importFile {
	NSMutableArray *types = [NSMutableArray arrayWithObjects:UTTypePlainText, UTTypeData, nil];
	UTType *lua = [UTType typeWithFilenameExtension:@"lua"];
	if (lua) [types insertObject:lua atIndex:0];
	UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
	p.delegate = self;
	p.allowsMultipleSelection = YES;
	[self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSInteger n = 0;
	for (NSURL *url in urls) {
		NSString *name = CleanName(url.lastPathComponent);
		if (!name) continue;
		if ([[NSFileManager defaultManager] copyItemAtPath:url.path toPath:UniquePath([self dir], name) error:nil]) n++;
	}
	[self reload];
	if (n == 0) ScriptNotice(self, BL(@"Nothing imported", @"Ничего не импортировано"), BL(@"Pick a .lua or text file.", @"Выбери файл .lua или текстовый."));
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (s == 0) {
		if (_folders.count == 0 && _files.count == 0) {
			UILabel *l = BTBGGLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);
			l.textAlignment = NSTextAlignmentCenter;
			if ([self isShared]) {
				l.text = BL(@"No shared scripts in this game.\nChoose the folder in Veather → Settings → GameGuardian, then sign the game again.", @"В этой игре нет общих скриптов.\nВыбери папку в Veather → Настройки → GameGuardian и подпиши игру заново.");
			} else {
				l.text = BL(@"No scripts yet.\nUse the menu at the top to create one, paste from the clipboard or import a file.", @"Скриптов пока нет.\nВ меню сверху можно создать скрипт, вставить из буфера обмена или импортировать файл.");
			}
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
		return (NSInteger)_folders.count;
	}
	return (NSInteger)_files.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s != 1 || (_folders.count == 0 && _files.count == 0)) return nil;
	if ([self isGG]) return BL(@"GG-Lua scripts use the GameGuardian-style gg API (gg.searchNumber, gg.getResults, gg.setValues, gg.alert…). Use them only in offline games.", @"GG-Lua скрипты используют API в стиле GameGuardian (gg.searchNumber, gg.getResults, gg.setValues, gg.alert…). Применяй их только в оффлайн-играх.");
	return BL(@"Plain Lua: no gg table, only the standard libraries and print().", @"Обычный Lua: без таблицы gg, только стандартные библиотеки и print().");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.backgroundColor = BTBGGCurrentStyle() == BTBGGStyleNew ? [UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:0.85] : UIColor.secondarySystemGroupedBackgroundColor;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	if (ip.section == 0) {
		NSString *name = _folders[ip.row];
		cell.textLabel.text = name;
		cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
		cell.imageView.tintColor = BTBGGAccent();
		NSInteger n = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self pathFor:name] error:nil].count;
		cell.detailTextLabel.text = [NSString stringWithFormat:BL(@"%ld items", @"элементов: %ld"), (long)n];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	NSString *file = _files[ip.row];
	cell.textLabel.text = file;
	cell.imageView.image = [UIImage systemImageNamed:@"doc.text"];
	cell.imageView.tintColor = UIColor.secondaryLabelColor;
	NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[self pathFor:file] error:nil];
	cell.detailTextLabel.text = [NSByteCountFormatter stringFromByteCount:[attrs[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
	BOOL running = [BTBGGScriptRunner shared].running && [[BTBGGScriptRunner shared].runningName isEqualToString:file];
	cell.accessoryType = running ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 0) {
		NSString *sub = [_subpath stringByAppendingPathComponent:_folders[ip.row]];
		[self.navigationController pushViewController:[[BTBGGScriptsVC alloc] initWithShared:[self isShared] gg:[self isGG] subpath:sub] animated:YES];
		return;
	}
	NSString *file = _files[ip.row];
	NSString *path = [self pathFor:file];
	BOOL shared = [self isShared];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:file message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Run", @"Запустить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self runFile:file]; }]];
	[a addAction:[UIAlertAction actionWithTitle:shared ? BL(@"View", @"Посмотреть") : BL(@"Edit", @"Править") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		[self.navigationController pushViewController:[[BTBGGScriptEditorVC alloc] initWithPath:path readOnly:shared plain:![self isGG]] animated:YES];
	}]];
	if (shared) {
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Copy to this game", @"Скопировать в эту игру") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
			NSString *dest = BTBGGScriptsRoot(NO, [self isGG]);
			[[NSFileManager defaultManager] copyItemAtPath:path toPath:UniquePath(dest, file) error:nil];
			ScriptNotice(self, BL(@"Copied", @"Скопировано"), BL(@"Now it is in “This game” and can be edited.", @"Теперь он во вкладке «Эта игра» и его можно править."));
		}]];
	} else {
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Share", @"Поделиться") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
			UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
			vc.popoverPresentationController.sourceView = self.view;
			[self presentViewController:vc animated:YES completion:nil];
		}]];
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Rename", @"Переименовать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self renameItem:file isFolder:NO]; }]];
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Delete", @"Удалить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self deleteItem:file]; }]];
	}
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (NSString *)itemAt:(NSIndexPath *)ip { return ip.section == 0 ? _folders[ip.row] : _files[ip.row]; }

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if ([self isShared]) return nil;
	NSString *item = [self itemAt:ip];
	BOOL folder = ip.section == 0;
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:BL(@"Delete", @"Удалить") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[self deleteItem:item];
		done(YES);
	}];
	UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Rename", @"Имя") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[self renameItem:item isFolder:folder];
		done(YES);
	}];
	ren.backgroundColor = UIColor.systemGrayColor;
	return [UISwipeActionsConfiguration configurationWithActions:@[del, ren]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0) return nil;
	NSString *file = _files[ip.row];
	UIContextualAction *run = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:BL(@"Run", @"Запуск") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[self runFile:file];
		done(YES);
	}];
	run.backgroundColor = BTBGGAccent();
	return [UISwipeActionsConfiguration configurationWithActions:@[run]];
}

- (void)runFile:(NSString *)file {
	BTBGGScriptRunner *r = [BTBGGScriptRunner shared];
	if (r.running) { ScriptNotice(self, BL(@"A script is running", @"Скрипт уже работает"), BL(@"Stop it first.", @"Сначала останови его.")); return; }
	NSString *src = [NSString stringWithContentsOfFile:[self pathFor:file] encoding:NSUTF8StringEncoding error:nil];
	if (!src) { ScriptNotice(self, BL(@"Could not read the file", @"Не удалось прочитать файл"), BL(@"It must be UTF-8 text.", @"Это должен быть текст в UTF-8.")); return; }
	[r runSource:src name:file plainLua:![self isGG]];
	[self openLog];
}

- (void)renameItem:(NSString *)item isFolder:(BOOL)folder {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Rename", @"Переименовать") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = item; f.clearButtonMode = UITextFieldViewModeWhileEditing; }];
	__weak UIAlertController *wa = a;
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		NSString *name = CleanName(wa.textFields.firstObject.text);
		if (folder) name = name.stringByDeletingPathExtension;
		if (name.length == 0 || [name isEqualToString:item]) return;
		[[NSFileManager defaultManager] moveItemAtPath:[self pathFor:item] toPath:UniquePath([self dir], name) error:nil];
		[self reload];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)deleteItem:(NSString *)item {
	[[NSFileManager defaultManager] removeItemAtPath:[self pathFor:item] error:nil];
	[self reload];
}

@end

UIViewController *BTBGGMakeScriptsVC(void) { return [BTBGGScriptsVC new]; }
