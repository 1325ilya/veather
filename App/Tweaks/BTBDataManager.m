//  BTBDataManager.m — /backup: in-app data manager.
//  Three-finger long press (1s) anywhere opens a menu to back up the app's
//  data (Documents, Library, tmp) to a folder in Files and restore it later.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface BTBDataManager : NSObject <UIDocumentPickerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL restoring;
@property (nonatomic, strong) NSURL *exportURL;
+ (instancetype)shared;
@end

static UIViewController *BTBTopController(void) {
	UIWindow *key = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) { key = w; break; }
		}
	}
	UIViewController *vc = key.rootViewController;
	while (vc.presentedViewController) vc = vc.presentedViewController;
	return vc;
}

@implementation BTBDataManager

+ (instancetype)shared {
	static BTBDataManager *m;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [BTBDataManager new]; });
	return m;
}

- (NSURL *)home { return [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]; }
- (NSArray<NSString *> *)folders { return @[@"Documents", @"Library", @"tmp"]; }

- (void)attachToWindow:(UIWindow *)window {
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

- (void)showMenu {
	UIViewController *top = BTBTopController();
	if (!top) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Data Manager"
		message:@"Veather: back up or restore this app's data (documents, settings, saves)."
		preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"Back Up to Files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self backup]; }]];
	[a addAction:[UIAlertAction actionWithTitle:@"Restore from Files" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self pickRestore]; }]];
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[top presentViewController:a animated:YES completion:nil];
}

- (void)backup {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"app";
	NSDateFormatter *df = [NSDateFormatter new];
	df.dateFormat = @"yyyy-MM-dd_HH-mm";
	NSString *name = [NSString stringWithFormat:@"%@_backup_%@", bundleID, [df stringFromDate:NSDate.date]];
	NSURL *staging = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:name isDirectory:YES];
	[fm removeItemAtURL:staging error:nil];
	[fm createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:nil];
	for (NSString *folder in self.folders) {
		if ([folder isEqualToString:@"tmp"]) continue;
		NSURL *src = [self.home URLByAppendingPathComponent:folder];
		NSURL *dst = [staging URLByAppendingPathComponent:folder];
		if ([folder isEqualToString:@"Library"]) {
			[fm createDirectoryAtURL:dst withIntermediateDirectories:YES attributes:nil error:nil];
			for (NSURL *child in [fm contentsOfDirectoryAtURL:src includingPropertiesForKeys:nil options:0 error:nil]) {
				if ([child.lastPathComponent isEqualToString:@"Caches"]) continue;
				[fm copyItemAtURL:child toURL:[dst URLByAppendingPathComponent:child.lastPathComponent] error:nil];
			}
		} else {
			[fm copyItemAtURL:src toURL:dst error:nil];
		}
	}
	self.exportURL = staging;
	self.restoring = NO;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[staging] asCopy:YES];
	picker.delegate = self;
	[BTBTopController() presentViewController:picker animated:YES completion:nil];
}

- (void)pickRestore {
	self.restoring = YES;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
	picker.delegate = self;
	[BTBTopController() presentViewController:picker animated:YES completion:nil];
}

- (void)restoreFrom:(NSURL *)folder {
	NSURL *scopedURL = folder;
	BOOL scoped = [scopedURL startAccessingSecurityScopedResource];
	NSFileManager *fm = NSFileManager.defaultManager;
	NSUInteger restored = 0;
	// the user may pick the backup folder itself or a folder that contains it
	if (![fm fileExistsAtPath:[folder URLByAppendingPathComponent:@"Documents"].path]
		&& ![fm fileExistsAtPath:[folder URLByAppendingPathComponent:@"Library"].path]) {
		for (NSURL *child in [fm contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil]) {
			if ([child.lastPathComponent rangeOfString:@"_backup_"].location != NSNotFound) { folder = child; break; }
		}
	}
	
	for (NSString *name in self.folders) {
		NSURL *src = [folder URLByAppendingPathComponent:name];
		if (![fm fileExistsAtPath:src.path]) continue;
		NSURL *dst = [self.home URLByAppendingPathComponent:name];
		[fm createDirectoryAtURL:dst withIntermediateDirectories:YES attributes:nil error:nil];
		for (NSURL *child in [fm contentsOfDirectoryAtURL:src includingPropertiesForKeys:nil options:0 error:nil]) {
			if ([name isEqualToString:@"Library"] && [child.lastPathComponent isEqualToString:@"Preferences"]) {
				restored += [self restorePreferencesFrom:child];
				continue;
			}
			NSURL *target = [dst URLByAppendingPathComponent:child.lastPathComponent];
			[fm removeItemAtURL:target error:nil];
			if ([fm copyItemAtURL:child toURL:target error:nil]) restored++;
		}
	}
	if (scoped) [scopedURL stopAccessingSecurityScopedResource];
	
	NSString *msg = restored > 0
		? @"Data restored. The app will now close; open it again."
		: @"Nothing was restored. Choose a folder created by \"Back Up to Files\".";
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Data Manager" message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		if (restored > 0) exit(0);
	}]];
	[BTBTopController() presentViewController:a animated:YES completion:nil];
}

/// Preferences live in cfprefsd's cache; copying the plist files would be overwritten on exit.
- (NSUInteger)restorePreferencesFrom:(NSURL *)folder {
	NSUInteger count = 0;
	NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
	for (NSURL *plist in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil]) {
		if (![plist.pathExtension isEqualToString:@"plist"]) continue;
		NSDictionary *values = [NSDictionary dictionaryWithContentsOfURL:plist];
		if (!values) continue;
		NSString *domain = plist.URLByDeletingPathExtension.lastPathComponent;
		if ([domain isEqualToString:bundleID] || [domain isEqualToString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"BTBOriginalBundleID"]]) {
			NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
			[defaults setPersistentDomain:values forName:bundleID];
			[defaults synchronize];
		} else {
			NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:domain];
			for (NSString *key in values) [suite setObject:values[key] forKey:key];
			[suite synchronize];
		}
		count++;
	}
	return count;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (self.restoring) {
		NSURL *folder = urls.firstObject;
		if (folder) [self restoreFrom:folder];
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
	}];
}
