//  BTBDataManager.m — /backup: in-app data manager.
//  Three-finger long press (or the small "DM" button) opens a menu to back up the app's
//  data (Documents, Library, without caches) into ONE file in Files and restore it later.
//  One file instead of a folder: every Files provider lets you pick a file.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static BOOL BTBDMRussian(void) {
	return [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"];
}
static NSString *LD(NSString *en, NSString *ru) { return BTBDMRussian() ? ru : en; }

static NSString *const kArchiveMagic = @"BTBD1";

// MARK: - Own window for menus and pickers
// The game's view controller (Unity, Unreal…) is a bad place to present from: it may swallow
// presentations or touches. A transparent window of our own is neutral and never blocks the game.

@interface BTBDMHostWindow : UIWindow
@end

@implementation BTBDMHostWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	if (!self.rootViewController.presentedViewController) return nil;
	return [super hitTest:point withEvent:event];
}
@end

static BTBDMHostWindow *gHost;

static UIWindowScene *BTBDMActiveScene(void) {
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
	}
	return nil;
}

static UIViewController *BTBDMHostController(void) {
	if (!gHost) {
		UIWindowScene *scene = BTBDMActiveScene();
		if (!scene) return nil;
		BTBDMHostWindow *w = [[BTBDMHostWindow alloc] initWithWindowScene:scene];
		w.frame = scene.coordinateSpace.bounds;
		w.windowLevel = UIWindowLevelAlert + 300;
		w.backgroundColor = UIColor.clearColor;
		w.rootViewController = [UIViewController new];
		w.rootViewController.view.backgroundColor = UIColor.clearColor;
		w.hidden = NO;
		gHost = w;
	}
	UIViewController *vc = gHost.rootViewController;
	while (vc.presentedViewController) vc = vc.presentedViewController;
	return vc;
}

// MARK: - Floating button window

@interface BTBDMButtonWindow : UIWindow
@property (nonatomic, weak) UIView *button;
@end

@implementation BTBDMButtonWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	if (self.button && CGRectContainsPoint(CGRectInset(self.button.frame, -8, -8), point)) {
		return [self.button hitTest:[self.button convertPoint:point fromView:self] withEvent:event];
	}
	return nil;
}
@end

@interface BTBDataManager : NSObject <UIDocumentPickerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL restoring;
@property (nonatomic, strong) NSURL *exportURL;
@property (nonatomic, assign) BOOL busy;
+ (instancetype)shared;
- (void)attachToWindow:(UIWindow *)window;
- (void)attachToAllWindows;
- (void)showFloatingButton;
@end

@implementation BTBDataManager

+ (instancetype)shared {
	static BTBDataManager *m;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [BTBDataManager new]; });
	return m;
}

- (NSURL *)home { return [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]; }

/// The real bundle identifier: the sideload tweak makes NSBundle report the original one.
static NSString *BTBRealBundleID(void) {
	CFStringRef ref = CFBundleGetIdentifier(CFBundleGetMainBundle());
	return ref ? (__bridge NSString *)ref : (NSBundle.mainBundle.bundleIdentifier ?: @"app");
}

// MARK: Triggers

- (void)attachToWindow:(UIWindow *)window {
	if ([window isKindOfClass:[BTBDMHostWindow class]] || [window isKindOfClass:[BTBDMButtonWindow class]]) return;
	for (UIGestureRecognizer *g in window.gestureRecognizers) {
		if ([g.name isEqualToString:@"BTBDataManager"]) return;
	}
	UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handle:)];
	g.name = @"BTBDataManager";
	g.numberOfTouchesRequired = 3;
	g.minimumPressDuration = 0.8;
	g.allowableMovement = 40;
	g.cancelsTouchesInView = NO;
	g.delaysTouchesBegan = NO;
	g.delegate = self;
	[window addGestureRecognizer:g];
}

// work together with scroll views, games and the app's own gestures
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
	return YES;
}

- (void)attachToAllWindows {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) [self attachToWindow:w];
	}
}

- (void)handle:(UILongPressGestureRecognizer *)g {
	if (g.state != UIGestureRecognizerStateBegan) return;
	[self showMenu];
}

static BTBDMButtonWindow *gButtonWindow;

/// Small draggable "DM" button for games where a three-finger gesture is not recognised.
- (void)showFloatingButton {
	if (gButtonWindow) return;
	UIWindowScene *scene = BTBDMActiveScene();
	if (!scene) return;
	BTBDMButtonWindow *window = [[BTBDMButtonWindow alloc] initWithWindowScene:scene];
	window.frame = scene.coordinateSpace.bounds;
	window.windowLevel = UIWindowLevelAlert + 90;
	window.backgroundColor = UIColor.clearColor;
	window.rootViewController = [UIViewController new];
	window.rootViewController.view.backgroundColor = UIColor.clearColor;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.frame = CGRectMake(12, 196, 46, 46);
	button.backgroundColor = [UIColor colorWithRed:0.13 green:0.62 blue:0.55 alpha:0.9];
	button.layer.cornerRadius = 23;
	button.layer.shadowOpacity = 0.35;
	button.layer.shadowRadius = 6;
	button.layer.shadowOffset = CGSizeMake(0, 2);
	[button setTitle:@"DM" forState:UIControlStateNormal];
	[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	[button addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
	[button addGestureRecognizer:pan];
	[window.rootViewController.view addSubview:button];
	window.button = button;
	window.hidden = NO;
	gButtonWindow = window;
}

- (void)dragButton:(UIPanGestureRecognizer *)pan {
	UIView *button = pan.view;
	CGPoint t = [pan translationInView:button.superview];
	button.center = CGPointMake(button.center.x + t.x, button.center.y + t.y);
	[pan setTranslation:CGPointZero inView:button.superview];
}

// MARK: Menu

- (void)present:(UIViewController *)vc {
	UIViewController *host = BTBDMHostController();
	if (host) [host presentViewController:vc animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message exitAfter:(BOOL)exitAfter {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:LD(@"Data Manager", @"Менеджер данных") message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		if (exitAfter) exit(0);
	}]];
	[self present:a];
}

- (void)showMenu {
	if (self.busy) return;
	UIViewController *host = BTBDMHostController();
	if (!host || gHost.rootViewController.presentedViewController) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:LD(@"Data Manager", @"Менеджер данных")
		message:LD(@"Save this app's data (progress, settings, saves) into one file in Files, or restore it from such a file.",
			@"Сохрани данные этого приложения (прогресс, настройки, сохранения) одним файлом в «Файлы» или восстанови из такого файла.")
		preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:LD(@"Back Up to Files", @"Сохранить в Файлы") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self backup]; }]];
	[a addAction:[UIAlertAction actionWithTitle:LD(@"Restore from a File", @"Восстановить из файла") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self pickRestore]; }]];
	[a addAction:[UIAlertAction actionWithTitle:LD(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
	[host presentViewController:a animated:YES completion:nil];
}

/// A cancellable-looking "working" box so a big backup does not look like a freeze.
- (void)showWorkingThen:(void (^)(UIAlertController *working))block {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:LD(@"Working…", @"Работаю…")
		message:LD(@"Please wait, do not close the app.", @"Подожди, не закрывай приложение.") preferredStyle:UIAlertControllerStyleAlert];
	UIViewController *host = BTBDMHostController();
	if (!host) { block(nil); return; }
	// the work starts only once the box is fully on screen, so it can be dismissed safely
	[host presentViewController:a animated:YES completion:^{ block(a); }];
}

// MARK: Archive format
// "BTBD1\n", then: uint16 idLength + bundle id, then entries:
//   uint8 1, uint16 pathLength, path (relative to the app's home), uint64 size, bytes
// terminated by uint8 0.

static void BTBPutU16(NSMutableData *d, uint16_t v) { uint16_t le = CFSwapInt16HostToLittle(v); [d appendBytes:&le length:2]; }
static void BTBPutU64(NSMutableData *d, uint64_t v) { uint64_t le = CFSwapInt64HostToLittle(v); [d appendBytes:&le length:8]; }

- (NSArray<NSURL *> *)filesToBackUp {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSMutableArray *files = [NSMutableArray array];
	for (NSString *top in @[@"Documents", @"Library"]) {
		NSURL *root = [self.home URLByAppendingPathComponent:top isDirectory:YES];
		NSDirectoryEnumerator *e = [fm enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:0 errorHandler:nil];
		for (NSURL *url in e) {
			NSString *rel = [url.path substringFromIndex:self.home.path.length];
			if ([rel hasPrefix:@"/Library/Caches"] || [rel hasPrefix:@"/Library/SplashBoard"] || [rel hasPrefix:@"/Library/Saved Application State"]) {
				[e skipDescendants];
				continue;
			}
			NSNumber *regular = nil;
			[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
			if (regular.boolValue) [files addObject:url];
		}
	}
	return files;
}

- (BOOL)writeArchiveTo:(NSURL *)dest {
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm removeItemAtURL:dest error:nil];
	if (![fm createFileAtPath:dest.path contents:nil attributes:nil]) return NO;
	NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:dest.path];
	if (!out) return NO;
	NSMutableData *head = [NSMutableData data];
	[head appendData:[[kArchiveMagic stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
	NSData *idData = [BTBRealBundleID() dataUsingEncoding:NSUTF8StringEncoding];
	BTBPutU16(head, (uint16_t)idData.length);
	[head appendData:idData];
	[out writeData:head];

	for (NSURL *url in [self filesToBackUp]) {
		@autoreleasepool {
			NSFileHandle *in = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
			if (!in) continue; // locked or vanished: skip, a backup of the rest is still useful
			NSString *rel = [url.path substringFromIndex:self.home.path.length + 1];
			NSData *relData = [rel dataUsingEncoding:NSUTF8StringEncoding];
			if (relData.length == 0 || relData.length > 60000) { [in closeFile]; continue; }
			unsigned long long size = [[fm attributesOfItemAtPath:url.path error:nil] fileSize];
			NSMutableData *entry = [NSMutableData data];
			uint8_t one = 1;
			[entry appendBytes:&one length:1];
			BTBPutU16(entry, (uint16_t)relData.length);
			[entry appendData:relData];
			BTBPutU64(entry, size);
			[out writeData:entry];
			unsigned long long left = size;
			while (left > 0) {
				@autoreleasepool {
					NSData *chunk = [in readDataOfLength:(NSUInteger)MIN(left, (unsigned long long)(1 << 20))];
					if (chunk.length == 0) { // file shrank while reading: pad so the archive stays valid
						NSMutableData *pad = [NSMutableData dataWithLength:(NSUInteger)MIN(left, (unsigned long long)(1 << 20))];
						[out writeData:pad];
						left -= pad.length;
					} else {
						[out writeData:chunk];
						left -= chunk.length;
					}
				}
			}
			[in closeFile];
		}
	}
	uint8_t zero = 0;
	[out writeData:[NSData dataWithBytes:&zero length:1]];
	[out closeFile];
	return YES;
}

// MARK: Backup

- (void)backup {
	NSString *bundleID = BTBRealBundleID();
	NSDateFormatter *df = [NSDateFormatter new];
	df.dateFormat = @"yyyy-MM-dd_HH-mm";
	NSString *name = [NSString stringWithFormat:@"%@_%@.btbdata", bundleID, [df stringFromDate:NSDate.date]];
	NSURL *dest = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:name];
	self.busy = YES;
	[self showWorkingThen:^(UIAlertController *working) {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			BOOL ok = [self writeArchiveTo:dest];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.busy = NO;
				void (^after)(void) = ^{
					if (!ok) {
						[self showMessage:LD(@"Could not create the backup (not enough space?).", @"Не удалось создать копию (не хватает места?).") exitAfter:NO];
						return;
					}
					self.exportURL = dest;
					self.restoring = NO;
					UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[dest] asCopy:YES];
					picker.delegate = self;
					[self present:picker];
				};
				if (working) [working dismissViewControllerAnimated:YES completion:after]; else after();
			});
		});
	}];
}

// MARK: Restore

- (void)pickRestore {
	self.restoring = YES;
	UTType *archive = [UTType typeWithFilenameExtension:@"btbdata"] ?: UTTypeData;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[archive, UTTypeData] asCopy:YES];
	picker.delegate = self;
	[self present:picker];
}

static BOOL BTBReadExact(NSFileHandle *h, NSUInteger length, NSData **out) {
	if (length == 0) { *out = [NSData data]; return YES; }
	NSData *d = [h readDataOfLength:length];
	if (d.length != length) return NO;
	*out = d;
	return YES;
}

/// Returns the number of restored files, or -1 when the file is not a backup of this kind.
- (NSInteger)restoreFromArchive:(NSURL *)url preferencesRestored:(BOOL *)prefs {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSFileHandle *in = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
	if (!in) return -1;
	NSData *magic = nil;
	NSData *expected = [[kArchiveMagic stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
	if (!BTBReadExact(in, expected.length, &magic) || ![magic isEqualToData:expected]) { [in closeFile]; return -1; }
	NSData *lenData = nil, *idData = nil;
	if (!BTBReadExact(in, 2, &lenData)) { [in closeFile]; return -1; }
	uint16_t idLen; memcpy(&idLen, lenData.bytes, 2); idLen = CFSwapInt16LittleToHost(idLen);
	if (!BTBReadExact(in, idLen, &idData)) { [in closeFile]; return -1; }
	NSString *backedUpID = [[NSString alloc] initWithData:idData encoding:NSUTF8StringEncoding];
	NSString *currentID = BTBRealBundleID();

	NSInteger restored = 0;
	NSURL *staging = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[@"BTBRestore_" stringByAppendingString:NSUUID.UUID.UUIDString]];
	[fm createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:nil];

	while (YES) {
		@autoreleasepool {
			NSData *kind = nil;
			if (!BTBReadExact(in, 1, &kind)) break;
			if (((const uint8_t *)kind.bytes)[0] == 0) break;
			NSData *pl = nil, *pathData = nil, *sizeData = nil;
			if (!BTBReadExact(in, 2, &pl)) break;
			uint16_t pathLen; memcpy(&pathLen, pl.bytes, 2); pathLen = CFSwapInt16LittleToHost(pathLen);
			if (!BTBReadExact(in, pathLen, &pathData) || !BTBReadExact(in, 8, &sizeData)) break;
			uint64_t size; memcpy(&size, sizeData.bytes, 8); size = CFSwapInt64LittleToHost(size);
			NSString *rel = [[NSString alloc] initWithData:pathData encoding:NSUTF8StringEncoding];

			// the file is first written next to the others in a staging folder, then moved over the old one,
			// so a failure (no space left) never destroys the existing data
			NSURL *tmp = [staging URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
			[fm createFileAtPath:tmp.path contents:nil attributes:nil];
			NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:tmp.path];
			unsigned long long left = size;
			BOOL complete = YES;
			while (left > 0) {
				@autoreleasepool {
					NSData *chunk = [in readDataOfLength:(NSUInteger)MIN(left, (unsigned long long)(1 << 20))];
					if (chunk.length == 0) { complete = NO; left = 0; break; }
					[out writeData:chunk];
					left -= chunk.length;
				}
			}
			[out closeFile];
			if (!complete) { [fm removeItemAtURL:tmp error:nil]; break; }

			BOOL safe = rel.length > 0 && ![rel hasPrefix:@"/"] && [rel rangeOfString:@".."].location == NSNotFound
				&& ([rel hasPrefix:@"Documents/"] || [rel hasPrefix:@"Library/"]);
			if (!safe) { [fm removeItemAtURL:tmp error:nil]; continue; }

			if ([rel hasPrefix:@"Library/Preferences/"] && [rel.pathExtension isEqualToString:@"plist"]) {
				NSDictionary *values = [NSDictionary dictionaryWithContentsOfURL:tmp];
				NSString *domain = rel.lastPathComponent.stringByDeletingPathExtension;
				if (values) {
					// cfprefsd caches preferences: write through NSUserDefaults, not by copying the file
					if ([domain isEqualToString:backedUpID] || [domain isEqualToString:currentID]) {
						NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
						for (NSString *key in values) [d setObject:values[key] forKey:key];
						[d synchronize];
					} else {
						NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:domain];
						for (NSString *key in values) [suite setObject:values[key] forKey:key];
						[suite synchronize];
					}
					*prefs = YES;
					restored++;
				}
				[fm removeItemAtURL:tmp error:nil];
				continue;
			}

			NSURL *target = [self.home URLByAppendingPathComponent:rel];
			[fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
			NSError *error = nil;
			BOOL ok;
			if ([fm fileExistsAtPath:target.path]) {
				ok = [fm replaceItemAtURL:target withItemAtURL:tmp backupItemName:nil options:0 resultingItemURL:nil error:&error];
			} else {
				ok = [fm moveItemAtURL:tmp toURL:target error:&error];
			}
			if (ok) restored++; else [fm removeItemAtURL:tmp error:nil];
		}
	}
	[in closeFile];
	[fm removeItemAtURL:staging error:nil];
	return restored;
}

- (void)restoreFrom:(NSURL *)url {
	self.busy = YES;
	[self showWorkingThen:^(UIAlertController *working) {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			BOOL scoped = [url startAccessingSecurityScopedResource];
			BOOL prefs = NO;
			NSInteger count = [self restoreFromArchive:url preferencesRestored:&prefs];
			if (scoped) [url stopAccessingSecurityScopedResource];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.busy = NO;
				void (^after)(void) = ^{
					if (count < 0) {
						[self showMessage:LD(@"This is not a backup made by Back Up to Files.", @"Это не файл, созданный через «Сохранить в Файлы».") exitAfter:NO];
					} else if (count == 0) {
						[self showMessage:LD(@"Nothing was restored.", @"Ничего не восстановлено.") exitAfter:NO];
					} else {
						[self showMessage:LD(@"Data restored. The app will now close; open it again.", @"Данные восстановлены. Приложение сейчас закроется, открой его снова.") exitAfter:YES];
					}
				};
				if (working) [working dismissViewControllerAnimated:YES completion:after]; else after();
			});
		});
	}];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (self.restoring) {
		NSURL *file = urls.firstObject;
		if (file) [self restoreFrom:file];
	} else if (self.exportURL) {
		[NSFileManager.defaultManager removeItemAtURL:self.exportURL error:nil];
		self.exportURL = nil;
	}
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	if (self.exportURL) {
		[NSFileManager.defaultManager removeItemAtURL:self.exportURL error:nil];
		self.exportURL = nil;
	}
}

@end

void BTBFeatureDataManager(void) {
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	void (^attach)(NSNotification *) = ^(NSNotification *note) {
		if ([note.object isKindOfClass:[UIWindow class]]) {
			[[BTBDataManager shared] attachToWindow:note.object];
		}
	};
	[center addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
	[center addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
	[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		[[BTBDataManager shared] attachToAllWindows];
		dispatch_async(dispatch_get_main_queue(), ^{ [[BTBDataManager shared] showFloatingButton]; });
	}];
}
