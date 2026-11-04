//  BTBGGStore.m — where GameGuardian scripts live, and search recipes.
//
//  This game:  Application Support/Veather/GameGuard/Scripts/GG   (scripts that use the gg.* API)
//                                                          /Lua  (plain Lua)
//  Shared:     <app bundle>/BTBGGShared/GG and /Lua — copied into the game by Veather when it signs it
//              (the folder is chosen in Veather's settings). Read only here.
//
//  A recipe is a GG script that repeats the steps of a search you did by hand.

#import "BTBGGUI.h"

static NSString *LocalBase(void) {
	return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Veather/GameGuard/Scripts"];
}

/// Scripts used to live directly in Scripts/: they are GG scripts, move them into Scripts/GG once.
static void PrepareLocal(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *base = LocalBase();
		NSString *ggDir = [base stringByAppendingPathComponent:@"GG"];
		NSString *luaDir = [base stringByAppendingPathComponent:@"Lua"];
		BOOL fresh = ![fm fileExistsAtPath:ggDir];
		[fm createDirectoryAtPath:ggDir withIntermediateDirectories:YES attributes:nil error:nil];
		[fm createDirectoryAtPath:luaDir withIntermediateDirectories:YES attributes:nil error:nil];
		for (NSString *name in [fm contentsOfDirectoryAtPath:base error:nil] ?: @[]) {
			if ([name isEqualToString:@"GG"] || [name isEqualToString:@"Lua"] || [name hasPrefix:@"."]) continue;
			[fm moveItemAtPath:[base stringByAppendingPathComponent:name] toPath:[ggDir stringByAppendingPathComponent:name] error:nil];
		}
		if (fresh && [(([fm contentsOfDirectoryAtPath:ggDir error:nil]) ?: @[]) count] == 0) {
			// a harmless example that shows the API: it only searches and counts
			NSString *example = BL(
				@"-- Example: asks for a number, searches for it and shows how many places hold it.\n-- It changes nothing.\nlocal r = gg.prompt({\"Number to look for\"}, {\"\"}, {\"number\"})\nif not r then return end\ngg.setRanges(gg.REGION_ANONYMOUS | gg.REGION_C_ALLOC | gg.REGION_C_DATA)\ngg.searchNumber(r[1], gg.TYPE_DWORD)\ngg.alert(\"Found: \" .. gg.getResultCount())\ngg.clearResults()\n",
				@"-- Пример: спрашивает число, ищет его и показывает, сколько мест нашлось.\n-- Ничего не меняет.\nlocal r = gg.prompt({\"Какое число искать\"}, {\"\"}, {\"number\"})\nif not r then return end\ngg.setRanges(gg.REGION_ANONYMOUS | gg.REGION_C_ALLOC | gg.REGION_C_DATA)\ngg.searchNumber(r[1], gg.TYPE_DWORD)\ngg.alert(\"Найдено: \" .. gg.getResultCount())\ngg.clearResults()\n");
			[example writeToFile:[ggDir stringByAppendingPathComponent:@"example.lua"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
		}
	});
}

NSString *BTBGGScriptsRoot(BOOL shared, BOOL gg) {
	if (shared) {
		return [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"BTBGGShared"] stringByAppendingPathComponent:gg ? @"GG" : @"Lua"];
	}
	PrepareLocal();
	return [LocalBase() stringByAppendingPathComponent:gg ? @"GG" : @"Lua"];
}

BOOL BTBGGSharedScriptsPresent(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSNumber *gg in @[@YES, @NO]) {
		NSArray *items = [fm contentsOfDirectoryAtPath:BTBGGScriptsRoot(YES, gg.boolValue) error:nil];
		if (items.count) return YES;
	}
	return NO;
}

// MARK: - Recipe source

static NSString *LuaStr(NSString *s) {
	NSMutableString *o = [NSMutableString stringWithString:@"\""];
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		if (c == '\\') [o appendString:@"\\\\"];
		else if (c == '"') [o appendString:@"\\\""];
		else if (c == '\n') [o appendString:@"\\n"];
		else if (c == '\r') continue;
		else [o appendFormat:@"%C", c];
	}
	[o appendString:@"\""];
	return o;
}

static NSString *LuaType(BTBGGType t, BOOL *encrypted) {
	*encrypted = NO;
	switch (t) {
		case BTBGGTypeByte: case BTBGGTypeUByte: return @"gg.TYPE_BYTE";
		case BTBGGTypeWord: case BTBGGTypeUWord: return @"gg.TYPE_WORD";
		case BTBGGTypeQword: case BTBGGTypeUQword: return @"gg.TYPE_QWORD";
		case BTBGGTypeFloat: return @"gg.TYPE_FLOAT";
		case BTBGGTypeDouble: return @"gg.TYPE_DOUBLE";
		case BTBGGTypeXor: *encrypted = YES; return @"gg.TYPE_DWORD";
		case BTBGGTypeAuto: return @"gg.TYPE_AUTO";
		case BTBGGTypeHidden: case BTBGGTypeNotDword: case BTBGGTypeNegDword: case BTBGGTypeNotQword: case BTBGGTypeNegQword: return @"gg.TYPE_HIDDEN";
		default: return @"gg.TYPE_DWORD";
	}
}

static NSString *LuaRegions(NSUInteger mask) {
	NSMutableArray *parts = [NSMutableArray array];
	if (mask & BTBGGRegionHeap) [parts addObject:@"gg.REGION_C_ALLOC"];
	if (mask & BTBGGRegionAnonymous) [parts addObject:@"gg.REGION_ANONYMOUS"];
	if (mask & BTBGGRegionAppData) [parts addObject:@"gg.REGION_C_DATA"];
	if (mask & BTBGGRegionStack) [parts addObject:@"gg.REGION_STACK"];
	if (mask & BTBGGRegionSystemData) [parts addObject:@"gg.REGION_CODE_SYS"];
	if (mask & BTBGGRegionOther) [parts addObject:@"gg.REGION_OTHER"];
	return parts.count ? [parts componentsJoinedByString:@" | "] : @"gg.REGION_C_ALLOC | gg.REGION_ANONYMOUS | gg.REGION_C_DATA";
}

/// `local <var> = gg.prompt(...)` for one number or text, with the recorded one as the default.
static NSString *PromptLine(NSString *var, NSString *label, NSString *def) {
	BOOL numeric = def.length > 0 && [[NSScanner scannerWithString:def] scanDouble:NULL] && [def rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"~;:"]].location == NSNotFound
		&& ![def.lowercaseString hasPrefix:@"0x"] && ![def.lowercaseString hasPrefix:@"h"];
	return [NSString stringWithFormat:@"local %@ = gg.prompt({%@}, {%@}, {%@})\nif not %@ then gg.exit() end\n", var, LuaStr(label), LuaStr(def ?: @""), numeric ? @"\"number\"" : @"\"text\"", var];
}

NSString *BTBGGRecipeSource(NSString *title, NSArray<NSDictionary *> *steps) {
	NSMutableString *o = [NSMutableString string];
	[o appendFormat:BL(@"-- %@\n-- A search recipe: repeats the steps you did by hand. Edit it if you like.\n-- Offline games only.\n\n", @"-- %@\n-- Рецепт поиска: повторяет шаги, которые вы делали руками. Можно править.\n-- Только для оффлайн-игр.\n\n"), title.length ? title : BL(@"Search recipe", @"Рецепт поиска")];
	[o appendString:BL(@"local WAIT = 20  -- seconds you get in the game between the steps\n", @"local WAIT = 20  -- секунд на действие в игре между шагами\n")];
	[o appendString:@"local function step(text)\n  if gg.alert(text, \"OK\", " ];
	[o appendString:[NSString stringWithFormat:@"%@) ~= 1 then gg.exit() end\n  for i = WAIT, 1, -1 do\n    gg.toast(i .. \" \", true)\n    gg.sleep(1000)\n  end\nend\n\n", LuaStr(BL(@"Stop", @"Стоп"))]];
	[o appendString:@"gg.setVisible(false)\n"];

	NSString *typeExpr = @"gg.TYPE_DWORD";
	BOOL first = YES;
	int n = 0;
	for (NSDictionary *s in steps) {
		NSString *op = s[@"op"];
		n++;
		if ([op isEqualToString:@"search"] || [op isEqualToString:@"unknown"]) {
			BTBGGType t = (BTBGGType)[s[@"type"] integerValue];
			BOOL enc = NO;
			typeExpr = LuaType(t, &enc);
			[o appendFormat:@"\n-- %d. %@\n", n, [op isEqualToString:@"unknown"] ? BL(@"look at every value", @"запомнить все значения") : BL(@"search", @"поиск")];
			[o appendFormat:@"gg.setRanges(%@)\n", LuaRegions([s[@"regions"] unsignedIntegerValue])];
			if ([op isEqualToString:@"unknown"]) {
				[o appendFormat:@"gg.startFuzzy(%@)\n", typeExpr];
			} else {
				[o appendString:PromptLine(@"p", BL(@"Number from the game", @"Число из игры"), s[@"text"])];
				[o appendFormat:@"gg.searchNumber(p[1], %@%@)\n", typeExpr, enc ? @", true" : @""];
			}
			first = NO;
			continue;
		}
		BTBGGMode mode = (BTBGGMode)[s[@"mode"] integerValue];
		NSString *text = s[@"text"] ?: @"";
		[o appendFormat:@"\n-- %d. %@\n", n, BL(@"narrow it down", @"уточнение")];
		if (first) { [o appendString:@"-- (the search itself was done earlier)\n"]; first = NO; }
		switch (mode) {
			case BTBGGModeChanged:
				[o appendFormat:@"step(%@)\ngg.searchFuzzy(\"0\", gg.SIGN_FUZZY_NOT_EQUAL)\n", LuaStr(BL(@"Change the number in the game. After OK you have WAIT seconds.", @"Измени число в игре. После OK у вас WAIT секунд."))];
				break;
			case BTBGGModeUnchanged:
				[o appendFormat:@"step(%@)\ngg.searchFuzzy(\"0\", gg.SIGN_FUZZY_EQUAL)\n", LuaStr(BL(@"Do nothing in the game. After OK wait.", @"Ничего не меняй в игре. После OK подожди."))];
				break;
			case BTBGGModeGreater:
				[o appendFormat:@"step(%@)\ngg.searchFuzzy(\"0\", gg.SIGN_FUZZY_GREATER)\n", LuaStr(BL(@"Make the number bigger in the game. After OK you have WAIT seconds.", @"Сделай число в игре больше. После OK у вас WAIT секунд."))];
				break;
			case BTBGGModeSmaller:
				[o appendFormat:@"step(%@)\ngg.searchFuzzy(\"0\", gg.SIGN_FUZZY_LESS)\n", LuaStr(BL(@"Make the number smaller in the game. After OK you have WAIT seconds.", @"Сделай число в игре меньше. После OK у вас WAIT секунд."))];
				break;
			case BTBGGModeIncreasedBy:
			case BTBGGModeDecreasedBy: {
				BOOL up = mode == BTBGGModeIncreasedBy;
				[o appendFormat:@"step(%@)\n", LuaStr(up ? BL(@"Earn some in the game (a known amount). After OK you have WAIT seconds.", @"Заработай в игре известную сумму. После OK у вас WAIT секунд.")
					: BL(@"Spend a known amount in the game. After OK you have WAIT seconds.", @"Потрать в игре известную сумму. После OK у вас WAIT секунд.")];
				[o appendString:PromptLine(@"d", up ? BL(@"By how much it grew", @"На сколько выросло") : BL(@"By how much it dropped", @"На сколько уменьшилось"), text)];
				[o appendFormat:@"gg.searchFuzzy(tostring(d[1]), %@)\n", up ? @"gg.SIGN_FUZZY_GREATER" : @"gg.SIGN_FUZZY_LESS"];
				break;
			}
			default: {
				// exact, range, not equal, at most, at least: the typed text is the new number
				NSString *sign = @"gg.SIGN_EQUAL";
				if (mode == BTBGGModeNotEqual) sign = @"gg.SIGN_NOT_EQUAL";
				else if (mode == BTBGGModeAtMost) sign = @"gg.SIGN_LESS_OR_EQUAL";
				else if (mode == BTBGGModeAtLeast) sign = @"gg.SIGN_GREATER_OR_EQUAL";
				[o appendFormat:@"step(%@)\n", LuaStr(BL(@"Change the number in the game. After OK you have WAIT seconds.", @"Измени число в игре. После OK у вас WAIT секунд."))];
				[o appendString:PromptLine(@"r", BL(@"The new number from the game", @"Новое число из игры"), text)];
				[o appendFormat:@"gg.refineNumber(r[1], %@, false, %@)\n", typeExpr, sign];
				break;
			}
		}
	}

	[o appendString:@"\n-- "];
	[o appendString:BL(@"result\n", @"итог\n")];
	[o appendFormat:@"local count = gg.getResultCount()\nif count == 0 then\n  gg.alert(%@)\n  gg.exit()\nend\n", LuaStr(BL(@"Nothing found. Run the recipe again.", @"Ничего не найдено. Запусти рецепт ещё раз."))];
	[o appendString:@"local res = gg.getResults(10)\nlocal lines = {}\nfor i, v in ipairs(res) do\n  lines[#lines + 1] = string.format(\"0x%X = %s\", v.address, tostring(v.value))\nend\n"];
	[o appendFormat:@"gg.alert(%@ .. count .. \"\\n\" .. table.concat(lines, \"\\n\"))\n", LuaStr(BL(@"Found: ", @"Найдено: "))];
	[o appendFormat:@"local q = gg.prompt({%@}, {\"\"}, {\"number\"})\nif q and q[1] then\n  gg.editAll(tostring(q[1]), gg.TYPE_AUTO)\nend\n", LuaStr(BL(@"New value for everything found (empty: do not change)", @"Новое значение для всех найденных (пусто: не менять)"))];
	return o;
}

NSString *BTBGGSaveRecipe(NSString *baseName, NSString *source) {
	NSString *name = [[baseName stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	while ([name hasPrefix:@"."]) name = [name substringFromIndex:1];
	if (name.length == 0) name = BL(@"Recipe", @"Рецепт");
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *folder = [BTBGGScriptsRoot(NO, YES) stringByAppendingPathComponent:BL(@"Recipes", @"Рецепты")];
	[fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *file = [name stringByAppendingPathExtension:@"lua"];
	NSString *path = [folder stringByAppendingPathComponent:file];
	NSInteger i = 2;
	while ([fm fileExistsAtPath:path]) path = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld.lua", name, (long)i++]];
	if (![source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) return nil;
	return [BL(@"Recipes", @"Рецепты") stringByAppendingPathComponent:path.lastPathComponent];
}

BOOL BTBGGRunRecipe(NSString *relativePath) {
	if (relativePath.length == 0) return NO;
	NSString *path = [BTBGGScriptsRoot(NO, YES) stringByAppendingPathComponent:relativePath];
	NSString *src = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	if (!src) return NO;
	if ([BTBGGScriptRunner shared].running) return NO;
	[[BTBGGScriptRunner shared] runSource:src name:relativePath.lastPathComponent plainLua:NO];
	return YES;
}
