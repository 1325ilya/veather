//  BTBWebBlock.m

#import "BTBWebBlock.h"
#import <WebKit/WebKit.h>

static NSMutableDictionary<NSString *, WKContentRuleList *> *BTBRuleLists;
static NSHashTable<WKUserContentController *> *BTBControllers;
static const void *BTBAttachedKey = &BTBAttachedKey;

static void BTBAttach(WKUserContentController *controller) {
	if (!controller) return;
	[BTBControllers addObject:controller];
	NSMutableSet *attached = objc_getAssociatedObject(controller, BTBAttachedKey);
	if (!attached) {
		attached = [NSMutableSet set];
		objc_setAssociatedObject(controller, BTBAttachedKey, attached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	[BTBRuleLists enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, WKContentRuleList *list, BOOL *stop) {
		if ([attached containsObject:identifier]) return;
		[attached addObject:identifier];
		[controller addContentRuleList:list];
	}];
}

static void BTBHookWebViews(void) {
	Class cls = NSClassFromString(@"WKWebView");
	if (!cls) return;
	
	SEL initFrame = @selector(initWithFrame:configuration:);
	__block IMP origFrame = NULL;
	origFrame = BTBSwizzle(cls, initFrame, NO, ^id(WKWebView *self, CGRect frame, WKWebViewConfiguration *configuration) {
		WKWebView *view = ((id (*)(id, SEL, CGRect, id))origFrame)(self, initFrame, frame, configuration);
		BTBAttach(view.configuration.userContentController);
		return view;
	});
	
	SEL initCoder = @selector(initWithCoder:);
	__block IMP origCoder = NULL;
	origCoder = BTBSwizzle(cls, initCoder, NO, ^id(WKWebView *self, NSCoder *coder) {
		WKWebView *view = ((id (*)(id, SEL, id))origCoder)(self, initCoder, coder);
		BTBAttach(view.configuration.userContentController);
		return view;
	});
}

void BTBInstallWebContentBlock(NSString *identifier, NSString *json) {
	if (!NSClassFromString(@"WKContentRuleListStore")) return;
	
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		BTBRuleLists = [NSMutableDictionary dictionary];
		BTBControllers = [NSHashTable weakObjectsHashTable];
		BTBHookWebViews();
	});
	
	// WebKit objects must be used on the main thread
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *fullIdentifier = [@"BetterThanBox." stringByAppendingString:identifier];
		[[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:fullIdentifier
			encodedContentRuleList:json
			completionHandler:^(WKContentRuleList *list, NSError *error) {
				if (!list) {
					BTB_LOG("web rules %{public}@ failed: %{public}@", identifier, error.localizedDescription);
					return;
				}
				dispatch_async(dispatch_get_main_queue(), ^{
					BTBRuleLists[identifier] = list;
					for (WKUserContentController *controller in BTBControllers.allObjects) {
						BTBAttach(controller);
					}
				});
			}];
	});
}

NSString *BTBWebRulesBlockingDomains(NSArray<NSString *> *domains) {
	NSMutableArray *rules = [NSMutableArray array];
	for (NSString *domain in domains) {
		NSString *escaped = [domain stringByReplacingOccurrencesOfString:@"." withString:@"\\\\."];
		NSString *filter = [NSString stringWithFormat:@"^https?://([^/:]+\\\\.)?%@[/:]", escaped];
		[rules addObject:[NSString stringWithFormat:@"{\"trigger\":{\"url-filter\":\"%@\"},\"action\":{\"type\":\"block\"}}", filter]];
	}
	return [NSString stringWithFormat:@"[%@]", [rules componentsJoinedByString:@","]];
}
