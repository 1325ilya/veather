//  BTBDataManager.m — /backup: in-app data manager.
//  Three-finger long press (1s) anywhere opens a menu to back up the app's
//  data (Documents, Library, tmp) to a folder in Files and restore it later.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface BTBDataManager : NSObject <UIDocumentPickerDelegate>
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
	g.minimumPressDuration = 1.0;
	g.cancelsTouchesInView = NO;
	[window addGestureRecognizer:g];
}

- (void)handle:(UILongPressGestureRecognizer *)g {
	if (g.state != UIGestureRecognizerStateBegan) return;
	[self showMenu];
}

- (void)showMenu {
	UIViewController *top = BTBTopController();
	if (!top) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Data Manager"
		message:@"BetterThanBox: back up or restore this app's data (documents, settings, saves)."
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
	BOOL scoped = [folder startAccessingSecurityScopedResource];
	NSFileManager *fm = NSFileManager.defaultManager;
	NSUInteger restored = 0;
	for (NSString *name in self.folders) {
		NSURL *src = [folder URLByAppendingPathComponent:name];
		if (![fm fileExistsAtPath:src.path]) continue;
		NSURL *dst = [self.home URLByAppendingPathComponent:name];
		for (NSURL *child in [fm contentsOfDirectoryAtURL:src includingPropertiesForKeys:nil options:0 error:nil]) {
			NSURL *target = [dst URLByAppendingPathComponent:child.lastPathComponent];
			[fm removeItemAtURL:target error:nil];
			if ([fm copyItemAtURL:child toURL:target error:nil]) restored++;
		}
	}
	if (scoped) [folder stopAccessingSecurityScopedResource];
	
	NSString *msg = restored > 0
		? @"Data restored. The app will now close; open it again."
		: @"Nothing was restored. Choose a folder created by \"Back Up to Files\".";
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Data Manager" message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		if (restored > 0) exit(0);
	}]];
	[BTBTopController() presentViewController:a animated:YES completion:nil];
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
	[[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		if ([note.object isKindOfClass:[UIWindow class]]) {
			[[BTBDataManager shared] attachToWindow:note.object];
		}
	}];
}
