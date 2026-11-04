//  BTBGGScriptsVC.m — the "Scripts" tab: a list of Lua scripts, an editor and the run log.

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
	self.view.backgroundColor = UIColor.systemBackgroundColor;
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
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation BTBGGScriptEditorVC {
	NSString *_path;
	UITextView *_text;
}

- (instancetype)initWithPath:(NSString *)path {
	if ((self = [super init])) _path = path;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _path.lastPathComponent;
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	_text = [[UITextView alloc] initWithFrame:self.view.bounds];
	_text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_text.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
	_text.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_text.autocorrectionType = UITextAutocorrectionTypeNo;
	_text.smartQuotesType = UITextSmartQuotesTypeNo;
	_text.smartDashesType = UITextSmartDashesTypeNo;
	_text.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	_text.text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:nil] ?: @"";
	[self.view addSubview:_text];
	UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:BL(@"Save", @"Сохранить") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
	UIBarButtonItem *run = [[UIBarButtonItem alloc] initWithTitle:BL(@"Run", @"Запуск") style:UIBarButtonItemStylePlain target:self action:@selector(run)];
	self.navigationItem.rightBarButtonItems = @[save, run];
}

- (BOOL)writeFile {
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
	[[BTBGGScriptRunner shared] runSource:_text.text name:_path.lastPathComponent];
	[self.navigationController pushViewController:[BTBGGScriptLogVC new] animated:YES];
}

@end

// MARK: - List

@interface BTBGGScriptsVC : UITableViewController <UIDocumentPickerDelegate>
@end

@implementation BTBGGScriptsVC {
	NSArray<NSString *> *_files;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	__weak typeof(self) weak = self;
	NSArray *items = @[
		[UIAction actionWithTitle:BL(@"New script", @"Новый скрипт") image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(UIAction *x) { [weak askNameThen:nil]; }],
		[UIAction actionWithTitle:BL(@"From the clipboard", @"Из буфера обмена") image:[UIImage systemImageNamed:@"doc.on.clipboard"] identifier:nil handler:^(UIAction *x) { [weak fromClipboard]; }],
		[UIAction actionWithTitle:BL(@"Import a file", @"Импорт файла") image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction *x) { [weak importFile]; }],
		[UIAction actionWithTitle:BL(@"Log", @"Журнал") image:[UIImage systemImageNamed:@"text.alignleft"] identifier:nil handler:^(UIAction *x) { [weak openLog]; }],
	];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:items]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged) name:BTBGGScriptStateNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	NSString *dir = [BTBGGScriptRunner scriptsDirectory];
	NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] ?: @[];
	NSMutableArray *files = [NSMutableArray array];
	for (NSString *f in all) {
		NSString *ext = f.pathExtension.lowercaseString;
		if ([ext isEqualToString:@"lua"] || [ext isEqualToString:@"txt"]) [files addObject:f];
	}
	_files = [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	[self updateBanner];
	[self.tableView reloadData];
}

- (void)stateChanged {
	[self updateBanner];
}

- (void)updateBanner {
	BTBGGScriptRunner *r = [BTBGGScriptRunner shared];
	if (!r.running) { self.tableView.tableHeaderView = nil; return; }
	UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 56)];
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
	row.frame = CGRectMake(20, 0, bar.bounds.size.width - 40, 56);
	row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[bar addSubview:row];
	self.tableView.tableHeaderView = bar;
}

- (void)stopScript { [[BTBGGScriptRunner shared] stop]; }
- (void)openLog { [self.navigationController pushViewController:[BTBGGScriptLogVC new] animated:YES]; }

- (NSString *)pathFor:(NSString *)file { return [[BTBGGScriptRunner scriptsDirectory] stringByAppendingPathComponent:file]; }

#pragma mark Creating

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
		NSString *path = UniquePath([BTBGGScriptRunner scriptsDirectory], name);
		NSString *body = content ?: BL(@"-- New script\n", @"-- Новый скрипт\n");
		[body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[self reload];
		[self.navigationController pushViewController:[[BTBGGScriptEditorVC alloc] initWithPath:path] animated:YES];
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
		if ([[NSFileManager defaultManager] copyItemAtPath:url.path toPath:UniquePath([BTBGGScriptRunner scriptsDirectory], name) error:nil]) n++;
	}
	[self reload];
	if (n == 0) ScriptNotice(self, BL(@"Nothing imported", @"Ничего не импортировано"), BL(@"Pick a .lua or text file.", @"Выбери файл .lua или текстовый."));
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (_files.count == 0) {
		UILabel *l = BTBGGLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);
		l.textAlignment = NSTextAlignmentCenter;
		l.text = BL(@"No scripts yet.\nUse the menu at the top left to create one, paste from the clipboard or import a file.", @"Скриптов пока нет.\nВ меню слева сверху можно создать скрипт, вставить из буфера обмена или импортировать файл.");
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
	return (NSInteger)_files.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	return _files.count ? BL(@"Scripts use a GameGuardian-style gg API (gg.searchNumber, gg.getResults, gg.setValues, gg.alert…). Use them only in offline games.", @"Скрипты используют API в стиле GameGuardian (gg.searchNumber, gg.getResults, gg.setValues, gg.alert…). Применяй их только в оффлайн-играх.") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	NSString *file = _files[ip.row];
	cell.textLabel.text = file;
	NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[self pathFor:file] error:nil];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.text = [NSByteCountFormatter stringFromByteCount:[attrs[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
	BOOL running = [BTBGGScriptRunner shared].running && [[BTBGGScriptRunner shared].runningName isEqualToString:file];
	cell.accessoryType = running ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	NSString *file = _files[ip.row];
	NSString *path = [self pathFor:file];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:file message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Run", @"Запустить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self runFile:file]; }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Edit", @"Править") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		[self.navigationController pushViewController:[[BTBGGScriptEditorVC alloc] initWithPath:path] animated:YES];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Share", @"Поделиться") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
		vc.popoverPresentationController.sourceView = self.view;
		[self presentViewController:vc animated:YES completion:nil];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Delete", @"Удалить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self deleteFile:file]; }]];
	[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	NSString *file = _files[ip.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:BL(@"Delete", @"Удалить") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
		[self deleteFile:file];
		done(YES);
	}];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
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
	[r runSource:src name:file];
	[self openLog];
}

- (void)deleteFile:(NSString *)file {
	[[NSFileManager defaultManager] removeItemAtPath:[self pathFor:file] error:nil];
	[self reload];
}

@end

UIViewController *BTBGGMakeScriptsVC(void) { return [BTBGGScriptsVC new]; }
