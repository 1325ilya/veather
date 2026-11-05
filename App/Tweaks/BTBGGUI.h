//  BTBGGUI.h — pieces of the GameGuardian panel shared between its files.

#import <UIKit/UIKit.h>
#import "BTBGGEngine.h"

#define BL(en, ru) BTBGGL(en, ru)

// MARK: style (BTBGGSettings.m)
typedef NS_ENUM(NSInteger, BTBGGStyleKind) { BTBGGStyleNew = 0, BTBGGStyleLegacy = 1 };
BTBGGStyleKind BTBGGCurrentStyle(void);
void BTBGGSetStyle(BTBGGStyleKind style);
CGFloat BTBGGPanelAlpha(void);                 // 0.3 … 1
void BTBGGSetPanelAlpha(CGFloat alpha);
UIColor *BTBGGAccent(void);                    // main colour of the current style
UIColor *BTBGGAccent2(void);                   // second colour of the gradient
UIColor *BTBGGBackground(void);                // screen background of the current style
UIViewController *BTBGGMakeSettingsVC(void);

/// A button that draws a gradient in the new style and a flat colour in the legacy one.
@interface BTBGGGradientButton : UIButton
@property (nonatomic) BOOL filled;
- (void)applyStyle;
@end

static inline UIButton *BTBGGBigButton(NSString *title, BOOL filled, id target, SEL action) {
	BTBGGGradientButton *b = [BTBGGGradientButton buttonWithType:UIButtonTypeSystem];
	[b setTitle:title forState:UIControlStateNormal];
	b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
	b.titleLabel.adjustsFontSizeToFitWidth = YES;
	b.titleLabel.minimumScaleFactor = 0.7;
	b.filled = filled;
	[b applyStyle];
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
void BTBGGApplyPanelAlpha(void);
/// Puts a small "Max" button inside the text field: it types the biggest number that fits the type.
void BTBGGAttachMaxButton(UITextField *field, BTBGGType type);
/// Whether a four-finger long press opens the panel (a setting).
BOOL BTBGGFourFingerEnabled(void);
void BTBGGSetFourFingerEnabled(BOOL enabled);            // after the transparency setting changed
void BTBGGRebuildPanel(BOOL openSettings);  // after the style changed
void BTBGGHideFloatingButton(void);         // until the game is restarted
BOOL BTBGGFloatingButtonHidden(void);
extern NSString *const BTBGGResultsChangedNotification;
void BTBGGNotifyResultsChanged(void);

// MARK: shared screens (BTBGGPanels.m, BTBGGScriptsVC.m)
/// The "change / freeze / save" sheet for one address. `changed` runs after anything was modified.
void BTBGGPresentValueEditor(UIViewController *host, uint64_t address, BTBGGType type, void (^changed)(void));
NSString *BTBGGRegionSummary(NSUInteger mask);
UIViewController *BTBGGMakeRegionsVC(void);
UIViewController *BTBGGMakeSavedListVC(void);
/// The "name, note, folder" sheet for saving an address to the list. `done` runs after saving.
void BTBGGPresentSaveItem(UIViewController *host, uint64_t address, BTBGGType type, void (^done)(void));
/// Picks a folder of the saved list ("" is the root). The picker is pushed on `nav`.
void BTBGGPickFolder(UINavigationController *nav, NSString *current, void (^picked)(NSString *path));
UIViewController *BTBGGMakeMemoryVC(void);
UIViewController *BTBGGMakeScriptsVC(void);
UIViewController *BTBGGMakeConverterVC(void);
void BTBGGMemoryShowAddress(UIViewController *memoryVC, uint64_t address);

// MARK: scripts (BTBGGLua.m)
extern NSString *const BTBGGScriptStateNotification;  // running state or log changed
@interface BTBGGScriptRunner : NSObject
+ (instancetype)shared;
- (void)runSource:(NSString *)source name:(NSString *)name plainLua:(BOOL)plain; // plain: without the gg table
@property (atomic, readonly) BOOL running;
@property (atomic, readonly, copy) NSString *runningName;
- (NSString *)log;
- (void)clearLog;
- (void)runSource:(NSString *)source name:(NSString *)name;
- (void)stop;
+ (NSString *)scriptsDirectory;
@end

// MARK: storage and recipes (BTBGGStore.m)
/// Scripts of this game live in Application Support/Veather/GameGuard/Scripts/{GG,Lua};
/// shared ones are copied into the app by Veather when it signs the game (read only).
NSString *BTBGGScriptsRoot(BOOL shared, BOOL gg);
BOOL BTBGGSharedScriptsPresent(void);
/// Lua source that repeats a recorded search (see BTBGGEngine recipeSteps).
NSString *BTBGGRecipeSource(NSString *title, NSArray<NSDictionary *> *steps);
/// Saves `source` as a GG script of this game in "Рецепты"; returns the path relative to the GG folder, or nil.
NSString *BTBGGSaveRecipe(NSString *baseName, NSString *source);
/// Runs a recipe saved by BTBGGSaveRecipe.
BOOL BTBGGRunRecipe(NSString *relativePath);
