//  BTBGGLua.m — Lua 5.4 scripting for the GameGuardian tweak.
//  Scripts use a GameGuardian-style `gg` table (searchNumber, getResults, setValues, editAll, alert,
//  prompt, choice, …). They work on the same memory engine and saved list as the panel.
//
//  Not provided on purpose: speed/time manipulation, pausing the game's threads, network access,
//  running programs. Calling such a function raises a clear error instead of silently doing nothing.

#import "BTBCommon.h"
#import "BTBGGUI.h"
#import <UIKit/UIKit.h>
#import <math.h>
#import <time.h>
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include "lua/lualib.h"

NSString *const BTBGGScriptStateNotification = @"BTBGGScriptState";

// MARK: - GG constants

enum {
	GG_TYPE_BYTE = 1, GG_TYPE_WORD = 2, GG_TYPE_DWORD = 4, GG_TYPE_XOR = 8,
	GG_TYPE_FLOAT = 16, GG_TYPE_QWORD = 32, GG_TYPE_DOUBLE = 64, GG_TYPE_AUTO = 127,
};
enum {
	GG_REGION_C_HEAP = 1, GG_REGION_JAVA_HEAP = 2, GG_REGION_C_ALLOC = 4, GG_REGION_C_DATA = 8,
	GG_REGION_C_BSS = 16, GG_REGION_ANONYMOUS = 32, GG_REGION_STACK = 64, GG_REGION_CODE_APP = 16384,
	GG_REGION_CODE_SYS = 32768, GG_REGION_JAVA = 65536, GG_REGION_BAD = 131072, GG_REGION_ASHMEM = 524288,
	GG_REGION_VIDEO = 1048576, GG_REGION_OTHER = -2080896,
};
enum {
	GG_SIGN_EQUAL = 1, GG_SIGN_NOT_EQUAL = 2, GG_SIGN_LESS_OR_EQUAL = 3, GG_SIGN_GREATER_OR_EQUAL = 4,
	GG_SIGN_FUZZY_EQUAL = 5, GG_SIGN_FUZZY_NOT_EQUAL = 6, GG_SIGN_FUZZY_GREATER = 7, GG_SIGN_FUZZY_LESS = 8,
};

static lua_Integer GGType(BTBGGType t) {
	switch (t) {
		case BTBGGTypeByte: return GG_TYPE_BYTE;
		case BTBGGTypeWord: return GG_TYPE_WORD;
		case BTBGGTypeDword: return GG_TYPE_DWORD;
		case BTBGGTypeXor: return GG_TYPE_XOR;
		case BTBGGTypeFloat: return GG_TYPE_FLOAT;
		case BTBGGTypeQword: return GG_TYPE_QWORD;
		case BTBGGTypeDouble: return GG_TYPE_DOUBLE;
		case BTBGGTypeAuto: case BTBGGTypeHidden: return GG_TYPE_AUTO;
		case BTBGGTypeUByte: return GG_TYPE_BYTE;
		case BTBGGTypeUWord: return GG_TYPE_WORD;
		case BTBGGTypeUDword: case BTBGGTypeNotDword: case BTBGGTypeNegDword: return GG_TYPE_DWORD;
		case BTBGGTypeUQword: case BTBGGTypeNotQword: case BTBGGTypeNegQword: return GG_TYPE_QWORD;
	}
	return GG_TYPE_DWORD;
}

static BTBGGType EngType(lua_Integer v) {
	if (v == GG_TYPE_AUTO) return BTBGGTypeAuto;
	if (v & GG_TYPE_DWORD) return BTBGGTypeDword;
	if (v & GG_TYPE_FLOAT) return BTBGGTypeFloat;
	if (v & GG_TYPE_QWORD) return BTBGGTypeQword;
	if (v & GG_TYPE_DOUBLE) return BTBGGTypeDouble;
	if (v & GG_TYPE_WORD) return BTBGGTypeWord;
	if (v & GG_TYPE_BYTE) return BTBGGTypeByte;
	if (v & GG_TYPE_XOR) return BTBGGTypeXor;
	return BTBGGTypeDword;
}

static NSUInteger EngRegions(lua_Integer v) {
	NSUInteger m = 0;
	if (v & (GG_REGION_C_HEAP | GG_REGION_C_ALLOC | GG_REGION_JAVA_HEAP | GG_REGION_JAVA)) m |= BTBGGRegionHeap;
	if (v & GG_REGION_ANONYMOUS) m |= BTBGGRegionAnonymous;
	if (v & (GG_REGION_C_DATA | GG_REGION_C_BSS | GG_REGION_CODE_APP)) m |= BTBGGRegionAppData;
	if (v & GG_REGION_STACK) m |= BTBGGRegionStack;
	if (v & GG_REGION_CODE_SYS) m |= BTBGGRegionSystemData;
	if (((v & GG_REGION_OTHER) == GG_REGION_OTHER) || (v & (GG_REGION_VIDEO | GG_REGION_ASHMEM | GG_REGION_BAD))) m |= BTBGGRegionOther;
	return m ? m : BTBGGRegionDefault;
}

static lua_Integer GGRegionOf(NSUInteger cls) {
	switch (cls) {
		case BTBGGRegionHeap: return GG_REGION_C_ALLOC;
		case BTBGGRegionAnonymous: return GG_REGION_ANONYMOUS;
		case BTBGGRegionStack: return GG_REGION_STACK;
		case BTBGGRegionAppData: return GG_REGION_C_DATA;
		case BTBGGRegionSystemData: return GG_REGION_CODE_SYS;
		default: return GG_REGION_OTHER;
	}
}

// MARK: - Runner state

static void RegisterAPI(lua_State *L);
static void StopHook(lua_State *L, lua_Debug *ar);

static volatile BOOL gStop = NO;
static BOOL gExit = NO;                       // gg.exit() was called: not an error
static lua_Integer gRanges = GG_REGION_C_HEAP | GG_REGION_C_ALLOC | GG_REGION_ANONYMOUS | GG_REGION_C_DATA;
static dispatch_semaphore_t gDialogSem;       // the script thread waits on it while a dialog is open

@interface BTBGGScriptRunner ()
@property (atomic) BOOL running;
@property (atomic, copy) NSString *runningName;
@end

static void PostState(void) {
	BTBOnMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:BTBGGScriptStateNotification object:nil]; });
}

@implementation BTBGGScriptRunner {
	NSMutableString *_log;
	NSLock *_logLock;
}

+ (instancetype)shared {
	static BTBGGScriptRunner *r;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ r = [BTBGGScriptRunner new]; });
	return r;
}

- (instancetype)init {
	if ((self = [super init])) {
		_log = [NSMutableString string];
		_logLock = [NSLock new];
	}
	return self;
}

+ (NSString *)scriptsDirectory {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Veather/GameGuard/Scripts"];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:dir]) {
		[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
		// a harmless example that shows the API: it only searches and counts
		NSString *example = BL(
			@"-- Example: asks for a number, searches for it and shows how many places hold it.\n-- It changes nothing.\nlocal r = gg.prompt({\"Number to look for\"}, {\"\"}, {\"number\"})\nif not r then return end\ngg.setRanges(gg.REGION_ANONYMOUS | gg.REGION_C_ALLOC | gg.REGION_C_DATA)\ngg.searchNumber(r[1], gg.TYPE_DWORD)\ngg.alert(\"Found: \" .. gg.getResultCount())\ngg.clearResults()\n",
			@"-- Пример: спрашивает число, ищет его и показывает, сколько мест нашлось.\n-- Ничего не меняет.\nlocal r = gg.prompt({\"Какое число искать\"}, {\"\"}, {\"number\"})\nif not r then return end\ngg.setRanges(gg.REGION_ANONYMOUS | gg.REGION_C_ALLOC | gg.REGION_C_DATA)\ngg.searchNumber(r[1], gg.TYPE_DWORD)\ngg.alert(\"Найдено: \" .. gg.getResultCount())\ngg.clearResults()\n");
		[example writeToFile:[dir stringByAppendingPathComponent:@"example.lua"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	}
	return dir;
}

- (NSString *)log {
	[_logLock lock];
	NSString *s = [_log copy];
	[_logLock unlock];
	return s;
}

- (void)appendLog:(NSString *)text {
	[_logLock lock];
	[_log appendString:text];
	if (_log.length > 60000) [_log deleteCharactersInRange:NSMakeRange(0, _log.length - 40000)];
	[_logLock unlock];
	PostState();
}

- (void)clearLog {
	[_logLock lock];
	[_log setString:@""];
	[_logLock unlock];
	PostState();
}

- (void)stop {
	if (!self.running) return;
	gStop = YES;
	[BTBGGEngine shared].cancel = YES;
	if (gDialogSem) dispatch_semaphore_signal(gDialogSem);
}

- (void)runSource:(NSString *)source name:(NSString *)name {
	if (self.running) { [self appendLog:BL(@"A script is already running.\n", @"Скрипт уже запущен.\n")]; return; }
	self.running = YES;
	self.runningName = name;
	gStop = NO;
	gExit = NO;
	[BTBGGEngine shared].cancel = NO;
	[self appendLog:[NSString stringWithFormat:BL(@"▶︎ %@\n", @"▶︎ %@\n"), name]];
	NSThread *thread = [[NSThread alloc] initWithBlock:^{
		@autoreleasepool {
			lua_State *L = luaL_newstate();
			if (!L) {
				[self appendLog:BL(@"Out of memory.\n", @"Не хватает памяти.\n")];
			} else {
				RegisterAPI(L);
				lua_sethook(L, StopHook, LUA_MASKCOUNT, 1000);
				const char *code = source.UTF8String;
				BOOL failed = luaL_loadbufferx(L, code, strlen(code), [[@"=" stringByAppendingString:name] UTF8String], "t") != LUA_OK
					|| lua_pcall(L, 0, 0, 0) != LUA_OK;
				if (failed) {
					const char *msg = lua_tostring(L, -1);
					if (!gExit) [self appendLog:[NSString stringWithFormat:@"✖︎ %s\n", msg ?: "error"]];
				}
				lua_close(L);
			}
		}
		[BTBGGEngine shared].cancel = NO;
		[self appendLog:gStop ? BL(@"■ Stopped\n", @"■ Остановлено\n") : BL(@"✓ Finished\n", @"✓ Завершён\n")];
		self.running = NO;
		self.runningName = nil;
		PostState();
		BTBGGNotifyResultsChanged();
	}];
	thread.stackSize = 2 << 20;
	thread.qualityOfService = NSQualityOfServiceUserInitiated;
	thread.name = @"Veather.GG.Lua";
	[thread start];
}

@end

static BTBGGScriptRunner *Runner(void) { return [BTBGGScriptRunner shared]; }

// MARK: - Dialogs (shown from the script thread, answered on the main thread)

static UIWindow *gDialogWindow;
static UIWindow *gToastWindow;

@interface BTBGGPassThroughWindow : UIWindow
@end
@implementation BTBGGPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

static UIWindowScene *ActiveScene(void) {
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
	}
	return nil;
}

/// Main thread. Presents `vc`, waiting for a previous dialog to finish dismissing first.
static void PresentDialog(UIViewController *vc, void (^failed)(void), int attempt) {
	UIWindowScene *scene = ActiveScene();
	if (!scene || attempt > 40) { if (failed) failed(); return; }
	if (!gDialogWindow) {
		UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
		w.frame = scene.coordinateSpace.bounds;
		w.windowLevel = UIWindowLevelAlert + 400;
		w.backgroundColor = UIColor.clearColor;
		w.rootViewController = [UIViewController new];
		w.rootViewController.view.backgroundColor = UIColor.clearColor;
		gDialogWindow = w;
	}
	gDialogWindow.hidden = NO;
	[gDialogWindow makeKeyAndVisible];
	if (gDialogWindow.rootViewController.presentedViewController) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ PresentDialog(vc, failed, attempt + 1); });
		return;
	}
	[gDialogWindow.rootViewController presentViewController:vc animated:YES completion:nil];
}

static void DialogFinished(void) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (gDialogWindow && !gDialogWindow.rootViewController.presentedViewController) {
			gDialogWindow.hidden = YES;
			gDialogWindow = nil;
			BTBGGRestoreKeyWindow();
		}
	});
}

/// Runs `show` on the main thread, which must call `done` exactly once when the user answered.
/// Blocks the script thread until then. Returns NO when the script was stopped meanwhile.
static BOOL ShowAndWait(void (^show)(void (^done)(void), void (^failed)(void))) {
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	gDialogSem = sem;
	dispatch_async(dispatch_get_main_queue(), ^{
		show(^{ DialogFinished(); dispatch_semaphore_signal(sem); }, ^{ dispatch_semaphore_signal(sem); });
	});
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	gDialogSem = nil;
	if (gStop) {
		dispatch_async(dispatch_get_main_queue(), ^{ [gDialogWindow.rootViewController dismissViewControllerAnimated:NO completion:nil]; DialogFinished(); });
		return NO;
	}
	return YES;
}

static void CheckStopped(lua_State *L) { if (gStop) luaL_error(L, "script stopped"); }

@interface BTBGGMultiChoiceVC : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *items;
@property (nonatomic) NSMutableIndexSet *selected;
@property (nonatomic, copy) void (^completion)(NSIndexSet *result);
@end

@implementation BTBGGMultiChoiceVC
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:BL(@"Cancel", @"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"OK" style:UIBarButtonItemStyleDone target:self action:@selector(ok)];
	self.modalInPresentation = YES;
}
- (void)cancel { [self finish:nil]; }
- (void)ok { [self finish:[self.selected copy]]; }
- (void)finish:(NSIndexSet *)result {
	void (^c)(NSIndexSet *) = self.completion;
	self.completion = nil;
	[self dismissViewControllerAnimated:YES completion:^{ if (c) c(result); }];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.text = self.items[ip.row];
	cell.textLabel.numberOfLines = 0;
	cell.accessoryType = [self.selected containsIndex:(NSUInteger)ip.row] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if ([self.selected containsIndex:(NSUInteger)ip.row]) [self.selected removeIndex:(NSUInteger)ip.row]; else [self.selected addIndex:(NSUInteger)ip.row];
	[tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}
@end

// MARK: - Lua helpers

/// UTF-8 C string to NSString, never nil (invalid UTF-8 becomes an empty string).
static NSString *SafeStr(const char *c) { return (c ? [NSString stringWithUTF8String:c] : nil) ?: @""; }

static NSString *ArgText(lua_State *L, int idx) {
	if (lua_type(L, idx) == LUA_TNUMBER) {
		if (lua_isinteger(L, idx)) return [NSString stringWithFormat:@"%lld", (long long)lua_tointeger(L, idx)];
		double d = lua_tonumber(L, idx);
		if (d == floor(d) && fabs(d) < 1e15) return [NSString stringWithFormat:@"%lld", (long long)d];
		return [NSString stringWithFormat:@"%.17g", d];
	}
	return SafeStr(luaL_checkstring(L, idx));
}

static lua_Integer OptInt(lua_State *L, int idx, lua_Integer def) {
	if (lua_isnoneornil(L, idx)) return def;
	return lua_isinteger(L, idx) ? lua_tointeger(L, idx) : (lua_Integer)luaL_checknumber(L, idx);
}

static void PushValue(lua_State *L, uint64_t raw, BTBGGType t) {
	if ([BTBGGEngine isFloatType:t]) lua_pushnumber(L, [BTBGGEngine doubleValue:raw type:t]);
	else lua_pushinteger(L, [BTBGGEngine integerValue:raw type:t]);
}

static uint64_t RawFromLua(lua_State *L, int idx, BTBGGType t) {
	if ([BTBGGEngine isFloatType:t]) return [BTBGGEngine rawFromDouble:lua_tonumber(L, idx) type:t];
	lua_Integer v = lua_isinteger(L, idx) ? lua_tointeger(L, idx) : (lua_Integer)lua_tonumber(L, idx);
	return [BTBGGEngine rawFromInteger:v type:t];
}

/// Reads a table of {address=, flags=, value=, name=, freeze=} entries into dictionaries.
static NSMutableArray<NSDictionary *> *ReadItems(lua_State *L, int idx) {
	luaL_checktype(L, idx, LUA_TTABLE);
	idx = lua_absindex(L, idx);
	NSMutableArray *out = [NSMutableArray array];
	lua_Integer n = luaL_len(L, idx);
	for (lua_Integer i = 1; i <= n; i++) {
		lua_geti(L, idx, i);
		if (lua_istable(L, -1)) {
			int item = lua_gettop(L);
			NSMutableDictionary *d = [NSMutableDictionary dictionary];
			lua_getfield(L, item, "address");
			BOOL hasAddress = lua_isnumber(L, -1);
			if (hasAddress) d[@"address"] = @((uint64_t)(lua_isinteger(L, -1) ? lua_tointeger(L, -1) : (lua_Integer)lua_tonumber(L, -1)));
			lua_pop(L, 1);
			lua_getfield(L, item, "flags");
			BTBGGType type = lua_isnumber(L, -1) ? EngType((lua_Integer)lua_tonumber(L, -1)) : BTBGGTypeDword;
			if (type == BTBGGTypeAuto) type = BTBGGTypeDword;
			lua_pop(L, 1);
			d[@"type"] = @((int)type);
			lua_getfield(L, item, "value");
			if (lua_isnumber(L, -1)) d[@"raw"] = @(RawFromLua(L, -1, type));
			lua_pop(L, 1);
			lua_getfield(L, item, "name");
			if (lua_type(L, -1) == LUA_TSTRING) d[@"name"] = SafeStr(lua_tostring(L, -1));
			lua_pop(L, 1);
			lua_getfield(L, item, "freeze");
			if (lua_toboolean(L, -1)) d[@"freeze"] = @YES;
			lua_pop(L, 1);
			if (hasAddress) [out addObject:d];
		}
		lua_pop(L, 1);
	}
	return out;
}

/// The from/to arguments (positions `idx` and `idx + 1`) of a search call. Parsed before the engine lock
/// is taken: a bad argument raises a Lua error, which must not leave the lock held.
typedef struct { uint64_t from, to; } AddrRange;
static AddrRange ParseRange(lua_State *L, int idx) {
	lua_Integer from = OptInt(L, idx, 0), to = OptInt(L, idx + 1, -1);
	AddrRange r = {from > 0 ? (uint64_t)from : 0, to > 0 ? (uint64_t)to : UINT64_MAX};
	return r;
}
static AddrRange ApplyRange(AddrRange next) {
	BTBGGEngine *e = [BTBGGEngine shared];
	AddrRange old = {e.addressFrom, e.addressTo};
	e.addressFrom = next.from;
	e.addressTo = next.to;
	return old;
}
static void RestoreRange(AddrRange old) {
	BTBGGEngine *e = [BTBGGEngine shared];
	e.addressFrom = old.from;
	e.addressTo = old.to;
}

/// Keeps only the first `limit` results (engine lock held).
static void LimitResults(BTBGGEngine *e, lua_Integer limit) {
	if (limit <= 0 || e.count <= (size_t)limit) return;
	BTBGGHit *copy = malloc((size_t)limit * sizeof(BTBGGHit));
	if (!copy) return;
	for (lua_Integer i = 0; i < limit; i++) copy[i] = [e hitAtIndex:(size_t)i];
	[e loadHits:copy count:(size_t)limit];
	free(copy);
}

// MARK: - gg.* functions

static int gg_setRanges(lua_State *L) {
	lua_Integer v = luaL_checkinteger(L, 1);
	gRanges = v;
	[BTBGGEngine shared].regions = EngRegions(v);
	return 0;
}
static int gg_getRanges(lua_State *L) { lua_pushinteger(L, gRanges); return 1; }

static int gg_searchNumber(lua_State *L) {
	NSString *text = ArgText(L, 1);
	lua_Integer typeArg = OptInt(L, 2, GG_TYPE_DWORD);
	BOOL encrypted = lua_toboolean(L, 3);
	lua_Integer limit = OptInt(L, 7, 0);
	BTBGGType type = encrypted ? BTBGGTypeXor : EngType(typeArg);
	AddrRange range = ParseRange(L, 5);
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	e.cancel = NO;
	AddrRange saved = ApplyRange(range);
	NSString *err = nil;
	BOOL ok = [e search:text type:type unknown:NO error:&err];
	RestoreRange(saved);
	if (ok) LimitResults(e, limit);
	[e unlock];
	if (!ok) return luaL_error(L, "%s", err.UTF8String ?: "search failed");
	CheckStopped(L);
	return 0;
}

static int gg_refineNumber(lua_State *L) {
	NSString *text = ArgText(L, 1);
	lua_Integer sign = OptInt(L, 4, GG_SIGN_EQUAL);
	lua_Integer limit = OptInt(L, 7, 0);
	BTBGGMode mode = BTBGGModeExact;
	if ([text containsString:@"~"]) mode = BTBGGModeRange;
	if (sign == GG_SIGN_NOT_EQUAL) mode = BTBGGModeNotEqual;
	else if (sign == GG_SIGN_LESS_OR_EQUAL) mode = BTBGGModeAtMost;
	else if (sign == GG_SIGN_GREATER_OR_EQUAL) mode = BTBGGModeAtLeast;
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	e.cancel = NO;
	NSString *err = nil;
	BOOL ok = [e refine:text mode:mode error:&err];
	if (ok) LimitResults(e, limit);
	[e unlock];
	if (!ok) return luaL_error(L, "%s", err.UTF8String ?: "refine failed");
	CheckStopped(L);
	return 0;
}

static int gg_startFuzzy(lua_State *L) {
	BTBGGType type = EngType(OptInt(L, 1, GG_TYPE_DWORD));
	lua_Integer limit = OptInt(L, 4, 0);
	AddrRange range = ParseRange(L, 2);
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	e.cancel = NO;
	AddrRange saved = ApplyRange(range);
	NSString *err = nil;
	BOOL ok = [e search:@"" type:type unknown:YES error:&err];
	RestoreRange(saved);
	if (ok) LimitResults(e, limit);
	[e unlock];
	if (!ok) return luaL_error(L, "%s", err.UTF8String ?: "search failed");
	CheckStopped(L);
	return 0;
}

static int gg_searchFuzzy(lua_State *L) {
	lua_Integer sign = OptInt(L, 2, GG_SIGN_FUZZY_EQUAL);
	NSString *diff = lua_isnoneornil(L, 1) ? @"0" : ArgText(L, 1);
	BOOL hasDiff = ![diff isEqualToString:@"0"] && ![diff isEqualToString:@""];
	BTBGGMode mode = BTBGGModeUnchanged;
	switch (sign) {
		case GG_SIGN_FUZZY_NOT_EQUAL: mode = BTBGGModeChanged; break;
		case GG_SIGN_FUZZY_GREATER: mode = hasDiff ? BTBGGModeIncreasedBy : BTBGGModeGreater; break;
		case GG_SIGN_FUZZY_LESS: mode = hasDiff ? BTBGGModeDecreasedBy : BTBGGModeSmaller; break;
		default: break;
	}
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	e.cancel = NO;
	NSString *err = nil;
	BOOL ok = [e refine:diff mode:mode error:&err];
	[e unlock];
	if (!ok) return luaL_error(L, "%s", err.UTF8String ?: "refine failed");
	CheckStopped(L);
	return 0;
}

static int gg_getResultCount(lua_State *L) { lua_pushinteger(L, (lua_Integer)[BTBGGEngine shared].count); return 1; }

static int gg_clearResults(lua_State *L) {
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	[e clearResults];
	[e unlock];
	return 0;
}

typedef struct { uint64_t address; BTBGGType type; uint64_t raw; } ResultRow;

static int gg_getResults(lua_State *L) {
	lua_Integer count = luaL_checkinteger(L, 1);
	lua_Integer skip = OptInt(L, 2, 0);
	lua_Integer addrMin = OptInt(L, 3, 0), addrMax = OptInt(L, 4, -1);
	BOOL hasMin = !lua_isnoneornil(L, 5), hasMax = !lua_isnoneornil(L, 6);
	double valueMin = hasMin ? luaL_checknumber(L, 5) : 0, valueMax = hasMax ? luaL_checknumber(L, 6) : 0;
	lua_Integer typeMask = OptInt(L, 7, GG_TYPE_AUTO);
	if (count < 0) count = 0;
	if (count > 200000) count = 200000;
	ResultRow *rows = malloc((size_t)MAX(count, 1) * sizeof(ResultRow));
	size_t n = 0;
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	size_t total = e.count;
	for (size_t i = 0; i < total && n < (size_t)count; i++) {
		BTBGGHit h = [e hitAtIndex:i];
		uint64_t a = BTBGGHitAddress(h);
		BTBGGType t = BTBGGHitType(h);
		if (addrMin > 0 && a < (uint64_t)addrMin) continue;
		if (addrMax > 0 && a > (uint64_t)addrMax) continue;
		if (typeMask != GG_TYPE_AUTO && !(typeMask & GGType(t))) continue;
		uint64_t raw = h.raw;
		[e readValue:a type:t raw:&raw];
		if (hasMin || hasMax) {
			double v = [BTBGGEngine doubleValue:raw type:t];
			if (hasMin && v < valueMin) continue;
			if (hasMax && v > valueMax) continue;
		}
		if (skip > 0) { skip--; continue; }
		rows[n].address = a;
		rows[n].type = t;
		rows[n].raw = raw;
		n++;
	}
	[e unlock];
	lua_createtable(L, (int)n, 0);
	for (size_t i = 0; i < n; i++) {
		lua_createtable(L, 0, 3);
		lua_pushinteger(L, (lua_Integer)rows[i].address); lua_setfield(L, -2, "address");
		PushValue(L, rows[i].raw, rows[i].type); lua_setfield(L, -2, "value");
		lua_pushinteger(L, GGType(rows[i].type)); lua_setfield(L, -2, "flags");
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	free(rows);
	return 1;
}

static int gg_getValues(lua_State *L) {
	NSArray *items = ReadItems(L, 1);
	BTBGGEngine *e = [BTBGGEngine shared];
	size_t n = items.count;
	uint64_t *raws = calloc(MAX(n, 1), sizeof(uint64_t));
	BOOL *ok = calloc(MAX(n, 1), sizeof(BOOL));
	for (size_t i = 0; i < n; i++) ok[i] = [e readValue:[items[i][@"address"] unsignedLongLongValue] type:(BTBGGType)[items[i][@"type"] intValue] raw:&raws[i]];
	lua_createtable(L, (int)n, 0);
	for (size_t i = 0; i < n; i++) {
		BTBGGType t = (BTBGGType)[items[i][@"type"] intValue];
		lua_createtable(L, 0, 3);
		lua_pushinteger(L, (lua_Integer)[items[i][@"address"] unsignedLongLongValue]); lua_setfield(L, -2, "address");
		lua_pushinteger(L, GGType(t)); lua_setfield(L, -2, "flags");
		if (ok[i]) { PushValue(L, raws[i], t); lua_setfield(L, -2, "value"); }
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	free(raws);
	free(ok);
	return 1;
}

static int gg_setValues(lua_State *L) {
	NSArray *items = ReadItems(L, 1);
	BTBGGEngine *e = [BTBGGEngine shared];
	BOOL all = YES;
	for (NSDictionary *d in items) {
		if (!d[@"raw"]) { all = NO; continue; }
		uint64_t a = [d[@"address"] unsignedLongLongValue], raw = [d[@"raw"] unsignedLongLongValue];
		BTBGGType t = (BTBGGType)[d[@"type"] intValue];
		if (![e writeValue:a type:t raw:raw]) { all = NO; continue; }
		if (d[@"freeze"]) [e freezeAddress:a type:t raw:raw mode:BTBGGFreezeExact];
	}
	if (!all) return luaL_error(L, "%s", BTBGGL(@"some values could not be written", @"часть значений не удалось записать").UTF8String);
	lua_pushboolean(L, 1);
	return 1;
}

static int gg_editAll(lua_State *L) {
	NSString *text = ArgText(L, 1);
	lua_Integer typeArg = OptInt(L, 2, GG_TYPE_DWORD);
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	e.cancel = NO;
	NSUInteger n = [e editAll:text freeze:NO mode:BTBGGFreezeExact typeFilter:typeArg == GG_TYPE_AUTO ? -1 : (int)EngType(typeArg)];
	[e unlock];
	lua_pushinteger(L, (lua_Integer)n);
	return 1;
}

static int gg_loadResults(lua_State *L) {
	NSArray *items = ReadItems(L, 1);
	BTBGGEngine *e = [BTBGGEngine shared];
	size_t n = items.count;
	BTBGGHit *hits = malloc(MAX(n, 1) * sizeof(BTBGGHit));
	for (size_t i = 0; i < n; i++) {
		uint64_t a = [items[i][@"address"] unsignedLongLongValue];
		BTBGGType t = (BTBGGType)[items[i][@"type"] intValue];
		uint64_t raw = 0;
		if (items[i][@"raw"]) raw = [items[i][@"raw"] unsignedLongLongValue]; else [e readValue:a type:t raw:&raw];
		hits[i].addrType = a | ((uint64_t)t << 56);
		hits[i].raw = raw;
	}
	[e lock];
	[e loadHits:hits count:n];
	[e unlock];
	free(hits);
	return 0;
}

static int gg_removeResults(lua_State *L) {
	NSArray *items = ReadItems(L, 1);
	NSMutableSet *set = [NSMutableSet set];
	for (NSDictionary *d in items) [set addObject:d[@"address"]];
	BTBGGEngine *e = [BTBGGEngine shared];
	[e lock];
	[e removeHitsWithAddresses:set];
	[e unlock];
	return 0;
}

static int gg_addListItems(lua_State *L) {
	NSArray *items = ReadItems(L, 1);
	BTBGGEngine *e = [BTBGGEngine shared];
	for (NSDictionary *d in items) {
		uint64_t a = [d[@"address"] unsignedLongLongValue];
		BTBGGType t = (BTBGGType)[d[@"type"] intValue];
		[e addToListAddress:a type:t label:d[@"name"]];
		if (d[@"freeze"]) {
			uint64_t raw = 0;
			if (d[@"raw"]) { raw = [d[@"raw"] unsignedLongLongValue]; [e writeValue:a type:t raw:raw]; }
			else if (![e readValue:a type:t raw:&raw]) continue;
			[e freezeAddress:a type:t raw:raw mode:BTBGGFreezeExact];
		}
	}
	[e persistList];
	return 0;
}

static int gg_getListItems(lua_State *L) {
	BTBGGEngine *e = [BTBGGEngine shared];
	NSArray<BTBGGItem *> *list = [e.list copy];
	lua_createtable(L, (int)list.count, 0);
	lua_Integer i = 1;
	for (BTBGGItem *it in list) {
		uint64_t raw = 0;
		BOOL ok = [e readValue:it.address type:it.type raw:&raw];
		lua_createtable(L, 0, 5);
		lua_pushinteger(L, (lua_Integer)it.address); lua_setfield(L, -2, "address");
		lua_pushinteger(L, GGType(it.type)); lua_setfield(L, -2, "flags");
		if (ok) { PushValue(L, raw, it.type); lua_setfield(L, -2, "value"); }
		lua_pushstring(L, (it.label ?: @"").UTF8String); lua_setfield(L, -2, "name");
		lua_pushboolean(L, [e isFrozen:it.address]); lua_setfield(L, -2, "freeze");
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

static int gg_removeListItems(lua_State *L) {
	NSArray *items = ReadItems(L, 1);
	NSMutableSet *set = [NSMutableSet set];
	for (NSDictionary *d in items) [set addObject:d[@"address"]];
	BTBGGEngine *e = [BTBGGEngine shared];
	NSMutableArray *gone = [NSMutableArray array];
	for (BTBGGItem *it in e.list) if ([set containsObject:@(it.address)]) [gone addObject:it];
	[e removeListItems:gone];
	[e persistList];
	return 0;
}

static int gg_clearList(lua_State *L) {
	BTBGGEngine *e = [BTBGGEngine shared];
	[e clearList];
	[e persistList];
	return 0;
}

static int gg_getRangesList(lua_State *L) {
	NSString *filter = lua_isnoneornil(L, 1) ? @"" : SafeStr(luaL_checkstring(L, 1));
	NSArray *regions = [[BTBGGEngine shared] regionList];
	lua_newtable(L);
	lua_Integer i = 1;
	for (NSDictionary *r in regions) {
		NSString *name = r[@"name"];
		if (filter.length && [name rangeOfString:filter options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
		if (i > 5000) break;
		lua_createtable(L, 0, 5);
		lua_pushinteger(L, (lua_Integer)[r[@"start"] unsignedLongLongValue]); lua_setfield(L, -2, "start");
		lua_pushinteger(L, (lua_Integer)[r[@"end"] unsignedLongLongValue]); lua_setfield(L, -2, "end");
		lua_pushinteger(L, GGRegionOf([r[@"mask"] unsignedIntegerValue])); lua_setfield(L, -2, "type");
		lua_pushstring(L, name.UTF8String); lua_setfield(L, -2, "name");
		lua_pushstring(L, name.UTF8String); lua_setfield(L, -2, "internalName");
		lua_pushfstring(L, "%c%c%cp", [r[@"readable"] boolValue] ? 'r' : '-', [r[@"writable"] boolValue] ? 'w' : '-', [r[@"executable"] boolValue] ? 'x' : '-');
		lua_setfield(L, -2, "state");
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

static int gg_getTargetInfo(lua_State *L) {
	NSBundle *b = NSBundle.mainBundle;
	NSDictionary *info = b.infoDictionary;
	NSString *label = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"";
	lua_createtable(L, 0, 8);
	lua_pushstring(L, label.UTF8String); lua_setfield(L, -2, "label");
	lua_pushstring(L, (b.bundleIdentifier ?: @"").UTF8String); lua_setfield(L, -2, "packageName");
	lua_pushstring(L, [(info[@"CFBundleShortVersionString"] ?: @"") UTF8String]); lua_setfield(L, -2, "versionName");
	lua_pushinteger(L, [info[@"CFBundleVersion"] integerValue]); lua_setfield(L, -2, "versionCode");
	lua_pushstring(L, NSProcessInfo.processInfo.processName.UTF8String); lua_setfield(L, -2, "processName");
	lua_pushinteger(L, NSProcessInfo.processInfo.processIdentifier); lua_setfield(L, -2, "pid");
	lua_pushboolean(L, 1); lua_setfield(L, -2, "x64");
	lua_pushboolean(L, 0); lua_setfield(L, -2, "debuggable");
	return 1;
}

static int gg_isVisible(lua_State *L) { lua_pushboolean(L, BTBGGPanelIsOpen()); return 1; }
static int gg_setVisible(lua_State *L) {
	BOOL show = lua_toboolean(L, 1);
	BTBOnMain(^{ if (show) BTBGGOpenPanel(); else BTBGGClosePanel(); });
	return 0;
}

static int gg_sleep(lua_State *L) {
	lua_Integer ms = luaL_checkinteger(L, 1);
	while (ms > 0 && !gStop) {
		lua_Integer slice = MIN(ms, 20);
		[NSThread sleepForTimeInterval:slice / 1000.0];
		ms -= slice;
	}
	CheckStopped(L);
	return 0;
}

static int gg_exit(lua_State *L) {
	gExit = YES;
	return luaL_error(L, "exit");
}

static int gg_getLocale(lua_State *L) { lua_pushstring(L, [BTBGGL(@"en", @"ru") UTF8String]); return 1; }

static int gg_getFile(lua_State *L) { lua_pushstring(L, [BTBGGScriptRunner scriptsDirectory].UTF8String); return 1; }

static int gg_copyText(lua_State *L) {
	NSString *text = SafeStr(luaL_checkstring(L, 1));
	BTBOnMain(^{ UIPasteboard.generalPasteboard.string = text; });
	return 0;
}

static int gg_toast(lua_State *L) {
	NSString *text = SafeStr(luaL_checkstring(L, 1));
	BOOL fast = lua_toboolean(L, 2);
	BTBOnMain(^{
		UIWindowScene *scene = ActiveScene();
		if (!scene) return;
		if (!gToastWindow) {
			UIWindow *w = [[BTBGGPassThroughWindow alloc] initWithWindowScene:scene];
			w.frame = scene.coordinateSpace.bounds;
			w.windowLevel = UIWindowLevelAlert + 500;
			w.backgroundColor = UIColor.clearColor;
			w.rootViewController = [UIViewController new];
			w.rootViewController.view.backgroundColor = UIColor.clearColor;
			w.hidden = NO;
			gToastWindow = w;
		}
		UIView *host = gToastWindow.rootViewController.view;
		for (UIView *v in [host.subviews copy]) [v removeFromSuperview];
		UILabel *label = BTBGGLabel([UIFont systemFontOfSize:15 weight:UIFontWeightMedium], UIColor.whiteColor);
		label.text = text;
		label.textAlignment = NSTextAlignmentCenter;
		UIView *bubble = [UIView new];
		bubble.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
		bubble.layer.cornerRadius = 14;
		bubble.translatesAutoresizingMaskIntoConstraints = NO;
		label.translatesAutoresizingMaskIntoConstraints = NO;
		[bubble addSubview:label];
		[host addSubview:bubble];
		[NSLayoutConstraint activateConstraints:@[
			[label.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:10],
			[label.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-10],
			[label.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:16],
			[label.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-16],
			[bubble.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
			[bubble.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-70],
			[bubble.widthAnchor constraintLessThanOrEqualToAnchor:host.widthAnchor constant:-40],
		]];
		[UIView animateWithDuration:0.3 delay:fast ? 1.0 : 2.5 options:0 animations:^{ bubble.alpha = 0; } completion:^(BOOL f) { [bubble removeFromSuperview]; }];
	});
	return 0;
}

static int gg_alert(lua_State *L) {
	NSString *text = SafeStr(luaL_checkstring(L, 1));
	NSString *positive = lua_isnoneornil(L, 2) ? @"OK" : SafeStr(luaL_checkstring(L, 2));
	NSString *negative = lua_isnoneornil(L, 3) ? nil : SafeStr(luaL_checkstring(L, 3));
	NSString *neutral = lua_isnoneornil(L, 4) ? nil : SafeStr(luaL_checkstring(L, 4));
	__block int result = 0;
	BOOL ok = ShowAndWait(^(void (^done)(void), void (^failed)(void)) {
		UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:positive style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { result = 1; done(); }]];
		if (negative) [a addAction:[UIAlertAction actionWithTitle:negative style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { result = 2; done(); }]];
		if (neutral) [a addAction:[UIAlertAction actionWithTitle:neutral style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { result = 3; done(); }]];
		PresentDialog(a, failed, 0);
	});
	if (!ok) return luaL_error(L, "script stopped");
	if (result == 0) lua_pushnil(L); else lua_pushinteger(L, result);
	return 1;
}

static int gg_prompt(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	int n = (int)luaL_len(L, 1);
	NSMutableArray *labels = [NSMutableArray array], *defaults = [NSMutableArray array], *kinds = [NSMutableArray array];
	for (int i = 1; i <= n; i++) {
		lua_geti(L, 1, i);
		[labels addObject:lua_isstring(L, -1) ? SafeStr(lua_tostring(L, -1)) : @""];
		lua_pop(L, 1);
		NSString *def = @"", *kind = @"text";
		if (lua_istable(L, 2)) {
			lua_geti(L, 2, i);
			if (lua_type(L, -1) == LUA_TBOOLEAN) def = lua_toboolean(L, -1) ? @"1" : @"0";
			else if (lua_isnumber(L, -1) || lua_isstring(L, -1)) def = ArgText(L, -1);
			lua_pop(L, 1);
		}
		if (lua_istable(L, 3)) {
			lua_geti(L, 3, i);
			if (lua_isstring(L, -1)) kind = SafeStr(lua_tostring(L, -1));
			lua_pop(L, 1);
		}
		[defaults addObject:def];
		[kinds addObject:kind];
	}
	__block NSArray<NSString *> *values = nil;
	NSMutableString *message = [NSMutableString string];
	for (int i = 0; i < n; i++) {
		BOOL box = [kinds[i] isEqualToString:@"checkbox"];
		[message appendFormat:@"%@%d — %@%@", i ? @"\n" : @"", i + 1, labels[i], box ? BL(@" (1 = yes, 0 = no)", @" (1 = да, 0 = нет)") : @""];
	}
	BOOL ok = ShowAndWait(^(void (^done)(void), void (^failed)(void)) {
		UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
		for (int i = 0; i < n; i++) {
			[a addTextFieldWithConfigurationHandler:^(UITextField *f) {
				f.placeholder = labels[i];
				f.text = defaults[i];
				NSString *k = kinds[i];
				f.keyboardType = ([k isEqualToString:@"number"] || [k isEqualToString:@"checkbox"]) ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
				f.autocapitalizationType = UITextAutocapitalizationTypeNone;
				f.autocorrectionType = UITextAutocorrectionTypeNo;
			}];
		}
		__weak UIAlertController *wa = a;
		[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
			NSMutableArray *out = [NSMutableArray array];
			for (UITextField *f in wa.textFields) [out addObject:f.text ?: @""];
			values = out;
			done();
		}]];
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(); }]];
		PresentDialog(a, failed, 0);
	});
	if (!ok) return luaL_error(L, "script stopped");
	if (!values) { lua_pushnil(L); return 1; }
	lua_createtable(L, n, 0);
	for (int i = 0; i < n; i++) {
		NSString *v = values[i], *k = kinds[i];
		if ([k isEqualToString:@"number"]) {
			NSString *t = [[v stringByReplacingOccurrencesOfString:@"," withString:@"."] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
			if (t.length == 0 || !lua_stringtonumber(L, t.UTF8String)) lua_pushnil(L);
		} else if ([k isEqualToString:@"checkbox"]) {
			NSString *low = v.lowercaseString;
			lua_pushboolean(L, [low isEqualToString:@"1"] || [low isEqualToString:@"true"] || [low isEqualToString:@"yes"] || [low isEqualToString:@"да"]);
		} else {
			lua_pushstring(L, v.UTF8String);
		}
		lua_rawseti(L, -2, i + 1);
	}
	return 1;
}

static int gg_choice(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	int n = (int)luaL_len(L, 1);
	NSMutableArray *items = [NSMutableArray array];
	for (int i = 1; i <= n; i++) {
		lua_geti(L, 1, i);
		[items addObject:lua_isstring(L, -1) ? SafeStr(lua_tostring(L, -1)) : @""];
		lua_pop(L, 1);
	}
	NSString *message = lua_isnoneornil(L, 3) ? nil : SafeStr(luaL_checkstring(L, 3));
	__block int result = 0;
	BOOL ok = ShowAndWait(^(void (^done)(void), void (^failed)(void)) {
		UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
		for (int i = 0; i < n; i++) {
			[a addAction:[UIAlertAction actionWithTitle:items[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { result = i + 1; done(); }]];
		}
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(); }]];
		PresentDialog(a, failed, 0);
	});
	if (!ok) return luaL_error(L, "script stopped");
	if (result == 0) lua_pushnil(L); else lua_pushinteger(L, result);
	return 1;
}

static int gg_multiChoice(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	int n = (int)luaL_len(L, 1);
	NSMutableArray *items = [NSMutableArray array];
	NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
	for (int i = 1; i <= n; i++) {
		lua_geti(L, 1, i);
		[items addObject:lua_isstring(L, -1) ? SafeStr(lua_tostring(L, -1)) : @""];
		lua_pop(L, 1);
		if (lua_istable(L, 2)) {
			lua_geti(L, 2, i);
			if (lua_toboolean(L, -1)) [selected addIndex:(NSUInteger)(i - 1)];
			lua_pop(L, 1);
		}
	}
	NSString *message = lua_isnoneornil(L, 3) ? nil : SafeStr(luaL_checkstring(L, 3));
	__block NSIndexSet *result = nil;
	BOOL ok = ShowAndWait(^(void (^done)(void), void (^failed)(void)) {
		BTBGGMultiChoiceVC *vc = [BTBGGMultiChoiceVC new];
		vc.items = items;
		vc.selected = selected;
		vc.title = message ?: @"";
		vc.completion = ^(NSIndexSet *r) { result = r; done(); };
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
		PresentDialog(nav, failed, 0);
	});
	if (!ok) return luaL_error(L, "script stopped");
	if (!result) { lua_pushnil(L); return 1; }
	lua_newtable(L);
	[result enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		lua_pushboolean(L, 1);
		lua_rawseti(L, -2, (lua_Integer)idx + 1);
	}];
	return 1;
}

// MARK: - print and a small os table

static int btb_print(lua_State *L) {
	int n = lua_gettop(L);
	NSMutableString *line = [NSMutableString string];
	for (int i = 1; i <= n; i++) {
		size_t len = 0;
		const char *s = luaL_tolstring(L, i, &len);
		[line appendFormat:@"%@%@", i > 1 ? @"\t" : @"", [[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding] ?: @"?"];
		lua_pop(L, 1);
	}
	[line appendString:@"\n"];
	[Runner() appendLog:line];
	return 0;
}

static int os_time(lua_State *L) { lua_pushinteger(L, (lua_Integer)time(NULL)); return 1; }
static int os_clock(lua_State *L) { lua_pushnumber(L, (lua_Number)clock() / (lua_Number)CLOCKS_PER_SEC); return 1; }
static int os_difftime(lua_State *L) { lua_pushnumber(L, (lua_Number)(luaL_checkinteger(L, 1) - luaL_optinteger(L, 2, 0))); return 1; }
static int os_date(lua_State *L) {
	const char *fmt = luaL_optstring(L, 1, "%c");
	time_t t = (time_t)luaL_optinteger(L, 2, (lua_Integer)time(NULL));
	if (*fmt == '!') fmt++;
	struct tm tmv;
	localtime_r(&t, &tmv);
	char buf[256];
	size_t n = strftime(buf, sizeof(buf), fmt, &tmv);
	lua_pushlstring(L, buf, n);
	return 1;
}

static const luaL_Reg kGG[] = {
	{"setRanges", gg_setRanges}, {"getRanges", gg_getRanges}, {"getRangesList", gg_getRangesList},
	{"searchNumber", gg_searchNumber}, {"refineNumber", gg_refineNumber},
	{"startFuzzy", gg_startFuzzy}, {"searchFuzzy", gg_searchFuzzy},
	{"getResultCount", gg_getResultCount}, {"getResultsCount", gg_getResultCount},
	{"getResults", gg_getResults}, {"clearResults", gg_clearResults},
	{"getValues", gg_getValues}, {"setValues", gg_setValues}, {"editAll", gg_editAll},
	{"loadResults", gg_loadResults}, {"removeResults", gg_removeResults},
	{"addListItems", gg_addListItems}, {"getListItems", gg_getListItems},
	{"removeListItems", gg_removeListItems}, {"clearList", gg_clearList},
	{"getTargetInfo", gg_getTargetInfo}, {"isVisible", gg_isVisible}, {"setVisible", gg_setVisible},
	{"sleep", gg_sleep}, {"exit", gg_exit}, {"getLocale", gg_getLocale}, {"getFile", gg_getFile},
	{"copyText", gg_copyText}, {"toast", gg_toast},
	{"alert", gg_alert}, {"prompt", gg_prompt}, {"choice", gg_choice}, {"multiChoice", gg_multiChoice},
	{NULL, NULL},
};

static void SetInt(lua_State *L, const char *name, lua_Integer v) { lua_pushinteger(L, v); lua_setfield(L, -2, name); }

static void RegisterAPI(lua_State *L) {
	luaL_requiref(L, "_G", luaopen_base, 1); lua_pop(L, 1);
	luaL_requiref(L, LUA_COLIBNAME, luaopen_coroutine, 1); lua_pop(L, 1);
	luaL_requiref(L, LUA_TABLIBNAME, luaopen_table, 1); lua_pop(L, 1);
	luaL_requiref(L, LUA_STRLIBNAME, luaopen_string, 1); lua_pop(L, 1);
	luaL_requiref(L, LUA_MATHLIBNAME, luaopen_math, 1); lua_pop(L, 1);
	luaL_requiref(L, LUA_UTF8LIBNAME, luaopen_utf8, 1); lua_pop(L, 1);

	lua_pushcfunction(L, btb_print);
	lua_setglobal(L, "print");

	lua_newtable(L);
	lua_pushcfunction(L, os_time); lua_setfield(L, -2, "time");
	lua_pushcfunction(L, os_clock); lua_setfield(L, -2, "clock");
	lua_pushcfunction(L, os_difftime); lua_setfield(L, -2, "difftime");
	lua_pushcfunction(L, os_date); lua_setfield(L, -2, "date");
	lua_setglobal(L, "os");

	luaL_newlib(L, kGG);
	SetInt(L, "TYPE_BYTE", GG_TYPE_BYTE); SetInt(L, "TYPE_WORD", GG_TYPE_WORD); SetInt(L, "TYPE_DWORD", GG_TYPE_DWORD);
	SetInt(L, "TYPE_XOR", GG_TYPE_XOR); SetInt(L, "TYPE_FLOAT", GG_TYPE_FLOAT); SetInt(L, "TYPE_QWORD", GG_TYPE_QWORD);
	SetInt(L, "TYPE_DOUBLE", GG_TYPE_DOUBLE); SetInt(L, "TYPE_AUTO", GG_TYPE_AUTO);
	SetInt(L, "REGION_C_HEAP", GG_REGION_C_HEAP); SetInt(L, "REGION_JAVA_HEAP", GG_REGION_JAVA_HEAP);
	SetInt(L, "REGION_C_ALLOC", GG_REGION_C_ALLOC); SetInt(L, "REGION_C_DATA", GG_REGION_C_DATA);
	SetInt(L, "REGION_C_BSS", GG_REGION_C_BSS); SetInt(L, "REGION_ANONYMOUS", GG_REGION_ANONYMOUS);
	SetInt(L, "REGION_STACK", GG_REGION_STACK); SetInt(L, "REGION_CODE_APP", GG_REGION_CODE_APP);
	SetInt(L, "REGION_CODE_SYS", GG_REGION_CODE_SYS); SetInt(L, "REGION_JAVA", GG_REGION_JAVA);
	SetInt(L, "REGION_BAD", GG_REGION_BAD); SetInt(L, "REGION_ASHMEM", GG_REGION_ASHMEM);
	SetInt(L, "REGION_VIDEO", GG_REGION_VIDEO); SetInt(L, "REGION_OTHER", GG_REGION_OTHER);
	SetInt(L, "SIGN_EQUAL", GG_SIGN_EQUAL); SetInt(L, "SIGN_NOT_EQUAL", GG_SIGN_NOT_EQUAL);
	SetInt(L, "SIGN_LESS_OR_EQUAL", GG_SIGN_LESS_OR_EQUAL); SetInt(L, "SIGN_GREATER_OR_EQUAL", GG_SIGN_GREATER_OR_EQUAL);
	SetInt(L, "SIGN_FUZZY_EQUAL", GG_SIGN_FUZZY_EQUAL); SetInt(L, "SIGN_FUZZY_NOT_EQUAL", GG_SIGN_FUZZY_NOT_EQUAL);
	SetInt(L, "SIGN_FUZZY_GREATER", GG_SIGN_FUZZY_GREATER); SetInt(L, "SIGN_FUZZY_LESS", GG_SIGN_FUZZY_LESS);
	NSString *dir = [BTBGGScriptRunner scriptsDirectory];
	lua_pushstring(L, dir.UTF8String); lua_setfield(L, -2, "EXT_STORAGE");
	lua_pushstring(L, NSTemporaryDirectory().UTF8String); lua_setfield(L, -2, "TMP_STORAGE");
	lua_pushstring(L, dir.UTF8String); lua_setfield(L, -2, "FILES_DIR");
	lua_pushstring(L, "Veather"); lua_setfield(L, -2, "VERSION");
	lua_setglobal(L, "gg");

	// functions that GameGuardian has but Veather deliberately does not: say so instead of failing quietly
	luaL_dostring(L, "setmetatable(gg, {__index = function(_, k) error('gg.' .. tostring(k) .. ' is not supported in Veather', 2) end})");
}

static void StopHook(lua_State *L, lua_Debug *ar) {
	if (gStop) luaL_error(L, "script stopped");
}
