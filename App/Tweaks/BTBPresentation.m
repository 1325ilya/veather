//  BTBPresentation.m

#import "BTBPresentation.h"

static NSMutableArray<BTBPresentFilter> *BTBPresentFilters;

BOOL BTBIsAdControllerClass(Class cls) {
	static NSArray<NSString *> *prefixes, *keywords;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		prefixes = @[
			@"GAD", @"GAM", @"MA", @"AL", @"FB", @"UADS", @"USRV", @"UnityAds", @"Vungle", @"VNG",
			@"IS", @"LPM", @"MTG", @"PAG", @"BU", @"CHB", @"Chartboost", @"IM", @"InMobi", @"YMA",
			@"MTRG", @"APD", @"Appodeal", @"BM", @"BidMachine", @"IA", @"Fyber", @"SMA", @"TJ", @"Tapjoy",
			@"ADC", @"AdColony", @"MOL", @"Moloco", @"Liftoff", @"Mintegral", @"Pangle", @"HyprMX", @"OGA"
		];
		keywords = @[
			@"Interstitial", @"Rewarded", @"FullScreenAd", @"FullscreenAd", @"FullScreenView",
			@"FullscreenView", @"AppOpen", @"VideoAd", @"AdViewController", @"AdController", @"Splash"
		];
	});
	for (Class c = cls; c && c != [UIViewController class]; c = class_getSuperclass(c)) {
		NSString *name = NSStringFromClass(c);
		NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
		if (dot.location != NSNotFound) name = [name substringFromIndex:dot.location + 1]; // Swift "Module.Class"
		BOOL hasPrefix = NO;
		for (NSString *p in prefixes) {
			if ([name hasPrefix:p]) { hasPrefix = YES; break; }
		}
		if (!hasPrefix) continue;
		for (NSString *k in keywords) {
			if ([name rangeOfString:k].location != NSNotFound) return YES;
		}
	}
	return NO;
}

void BTBAddPresentationFilter(BTBPresentFilter filter) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		BTBPresentFilters = [NSMutableArray array];
		SEL sel = @selector(presentViewController:animated:completion:);
		__block IMP orig = NULL;
		orig = BTBSwizzle([UIViewController class], sel, NO, ^(UIViewController *self, UIViewController *controller, BOOL animated, void (^completion)(void)) {
			BTBPresentDecision decision = BTBPresentAllow;
			if (controller) {
				NSArray *filters;
				@synchronized (BTBPresentFilters) { filters = [BTBPresentFilters copy]; }
				for (BTBPresentFilter f in filters) {
					decision = f(self, controller);
					if (decision != BTBPresentAllow) break;
				}
			}
			void (*present)(id, SEL, id, BOOL, id) = (void (*)(id, SEL, id, BOOL, id))orig;
			switch (decision) {
				case BTBPresentBlock:
					BTB_LOG("blocked presentation of %{public}@", NSStringFromClass([controller class]));
					if (completion) completion();
					return;
				case BTBPresentAutoDismiss: {
					BTB_LOG("auto-dismissed %{public}@", NSStringFromClass([controller class]));
					__weak UIViewController *weakController = controller;
					present(self, sel, controller, NO, ^{
						if (completion) completion();
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
							[weakController dismissViewControllerAnimated:NO completion:nil];
						});
					});
					return;
				}
				default:
					present(self, sel, controller, animated, completion);
			}
		});
	});
	@synchronized (BTBPresentFilters) {
		[BTBPresentFilters addObject:[filter copy]];
	}
}
