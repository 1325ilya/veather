//  BTBGGUI.h — pieces of the GameGuardian panel shared between its files.

#import <UIKit/UIKit.h>
#import "BTBGGEngine.h"

#define BL(en, ru) BTBGGL(en, ru)

static inline UIColor *BTBGGAccent(void) { return [UIColor colorWithRed:0.49 green:0.36 blue:1 alpha:1]; }

static inline UIButton *BTBGGBigButton(NSString *title, BOOL filled, id target, SEL action) {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	[b setTitle:title forState:UIControlStateNormal];
	b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
	b.titleLabel.adjustsFontSizeToFitWidth = YES;
	b.titleLabel.minimumScaleFactor = 0.7;
	b.backgroundColor = filled ? BTBGGAccent() : [BTBGGAccent() colorWithAlphaComponent:0.15];
	[b setTitleColor:filled ? UIColor.whiteColor : BTBGGAccent() forState:UIControlStateNormal];
	b.layer.cornerRadius = 14;
	[b.heightAnchor constraintEqualToConstant:50].active = YES;
	if (action) [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	return b;
}

static inline UILabel *BTBGGLabel(UIFont *font, UIColor *color) {
	UILabel *l = [UILabel new];
	l.font = font;
	l.textColor = color;
	l.numberOfLines = 0;
	return l;
}

// MARK: panel (BTBGameGuard.m)
void BTBGGOpenPanel(void);
void BTBGGClosePanel(void);
BOOL BTBGGPanelIsOpen(void);
void BTBGGSelectTab(NSInteger index);       // 0 search, 1 saved list, 2 scripts, 3 memory
void BTBGGShowMemory(uint64_t address);
void BTBGGRestoreKeyWindow(void);           // gives focus back to the panel (if open) or the game after a dialog
extern NSString *const BTBGGResultsChangedNotification;
void BTBGGNotifyResultsChanged(void);

// MARK: shared screens (BTBGGPanels.m, BTBGGScriptsVC.m)
/// The "change / freeze / save" sheet for one address. `changed` runs after anything was modified.
void BTBGGPresentValueEditor(UIViewController *host, uint64_t address, BTBGGType type, void (^changed)(void));
NSString *BTBGGRegionSummary(NSUInteger mask);
UIViewController *BTBGGMakeRegionsVC(void);
UIViewController *BTBGGMakeSavedListVC(void);
UIViewController *BTBGGMakeMemoryVC(void);
UIViewController *BTBGGMakeScriptsVC(void);
void BTBGGMemoryShowAddress(UIViewController *memoryVC, uint64_t address);

// MARK: scripts (BTBGGLua.m)
extern NSString *const BTBGGScriptStateNotification;  // running state or log changed
@interface BTBGGScriptRunner : NSObject
+ (instancetype)shared;
@property (atomic, readonly) BOOL running;
@property (atomic, readonly, copy) NSString *runningName;
- (NSString *)log;
- (void)clearLog;
- (void)runSource:(NSString *)source name:(NSString *)name;
- (void)stop;
+ (NSString *)scriptsDirectory;
@end
