//  BTBNoAds.m — /noads
//
//  Layers, from first to last line of defence:
//   1. Network: ad hosts fail like a DNS block (NSURLSession, getaddrinfo, WKWebView rules).
//   2. Loads with completion blocks (Google Mobile Ads) fail immediately with an error,
//      so apps never wait for an ad that will not come.
//   3. "Is an ad ready?" checks answer NO, so apps skip showing ads.
//   4. Banner views stay hidden and take no space.
//   5. A full-screen ad that still gets presented is dismissed right away; the SDK then
//      reports "ad closed" and the app continues (no frozen screens, no rewards).
//
//  We never no-op "show" calls: apps often wait for the "ad dismissed" callback and
//  would hang forever.

#import "BTBURLBlock.h"
#import "BTBPresentation.h"
#import "BTBWebBlock.h"
#import <UIKit/UIKit.h>

NSArray<NSString *> *BTBAdHosts(void) {
	static NSArray *hosts;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		hosts = @[
			// Google
			@"doubleclick.net", @"googlesyndication.com", @"googleadservices.com", @"admob.com",
			@"googletagservices.com", @"adservice.google.com", @"pagead2.googlesyndication.com",
			@"googleads.g.doubleclick.net", @"imasdk.googleapis.com",
			// AppLovin / MAX
			@"applovin.com", @"applvn.com", @"applovin.io", @"aplvn.com",
			// Unity
			@"unityads.unity3d.com", @"ads.unity3d.com", @"unityads.unitychina.cn",
			// ironSource / LevelPlay
			@"supersonicads.com", @"ironsrc.com", @"ironsrc.mobi", @"ironsrc.net", @"is.com",
			// Meta Audience Network
			@"an.facebook.com",
			// Others
			@"ads.mopub.com", @"mopub.com", @"vungle.com", @"vungle.io", @"chartboost.com",
			@"inmobi.com", @"inmobicdn.net", @"adcolony.com", @"startappservice.com", @"tapjoy.com",
			@"tapjoyads.com", @"pangle.io", @"pangleglobal.com", @"pglstatp-toutiao.com",
			@"mintegral.com", @"mtgglobals.com", @"rayjump.com", @"fyber.com", @"inner-active.mobi",
			@"smaato.net", @"criteo.com", @"criteo.net", @"amazon-adsystem.com", @"adnxs.com",
			@"bidmachine.io", @"appodeal.com", @"appodealx.com", @"liftoff.io", @"liftoff-creatives.io",
			@"moloco.com", @"adsmoloco.com", @"hyprmx.com", @"ogury.co", @"presage.io", @"pubnative.net",
			@"verve.com", @"adsrvr.org", @"rubiconproject.com", @"pubmatic.com", @"openx.net",
			@"casalemedia.com", @"bidswitch.net", @"smartadserver.com", @"adform.net", @"yieldmo.com",
			@"taboola.com", @"outbrain.com", @"kidoz.net", @"tappx.com", @"aarki.net", @"admost.com",
			@"sigmob.com", @"adtiming.com", @"digitalturbine.com", @"bigabid.com", @"mobilefuse.com",
			// Russian networks (Yandex, VK / myTarget)
			@"yandexadexchange.net", @"an.yandex.ru", @"ads.yandex.ru", @"mobileads.yandex.ru",
			@"adfox.ru", @"adfox.yandex.ru", @"ad.mail.ru", @"target.my.com", @"ads.vk.com",
			@"r.mradx.net"
		];
	});
	return hosts;
}

BOOL BTBIsAdHost(const char *cHost) {
	if (!cHost) return NO;
	size_t length = strlen(cHost);
	for (NSString *suffix in BTBAdHosts()) {
		const char *s = suffix.UTF8String;
		size_t sl = strlen(s);
		if (length < sl) continue;
		const char *tail = cHost + (length - sl);
		if (strcasecmp(tail, s) != 0) continue;
		if (length == sl || cHost[length - sl - 1] == '.') return YES;
	}
	return NO;
}

static NSError *BTBAdBlockedError(void) {
	return [NSError errorWithDomain:@"Veather.NoAds" code:-1
		userInfo:@{NSLocalizedDescriptionKey: @"No ad available (blocked by Veather)."}];
}

/// Class method `+load…:completionHandler:` (last argument is a block (ad, error)) → fail at once.
static void BTBFailLoad(NSString *className, NSString *selectorName) {
	Class cls = NSClassFromString(className);
	SEL sel = NSSelectorFromString(selectorName);
	if (BTBReturnType(cls, sel, YES) != 'v') return;
	int args = BTBArgumentCount(cls, sel, YES);
	void (^fail)(id) = ^(id completion) {
		if (!completion) return;
		void (^handler)(id, NSError *) = completion;
		dispatch_async(dispatch_get_main_queue(), ^{ handler(nil, BTBAdBlockedError()); });
	};
	if (args == 3) {
		BTBSwizzle(cls, sel, YES, ^(id self, id a, id b, id completion) { fail(completion); });
	} else if (args == 4) {
		BTBSwizzle(cls, sel, YES, ^(id self, id a, id b, id c, id completion) { fail(completion); });
	}
}

/// BOOL getter or BOOL method with one object argument → NO.
static void BTBAnswerNo(NSString *className, NSString *selectorName, BOOL isClass) {
	Class cls = NSClassFromString(className);
	SEL sel = NSSelectorFromString(selectorName);
	char ret = BTBReturnType(cls, sel, isClass);
	if (ret != 'B' && ret != 'c') return;
	int args = BTBArgumentCount(cls, sel, isClass);
	if (args == 0) {
		BTBSwizzle(cls, sel, isClass, ^BOOL(id self) { return NO; });
	} else if (args == 1) {
		BTBSwizzle(cls, sel, isClass, ^BOOL(id self, id a) { return NO; });
	}
}

/// Google banner / native loaders: tell the delegate the load failed instead of loading.
static void BTBFailDelegateLoad(NSString *className, NSString *delegateSelectorName) {
	Class cls = NSClassFromString(className);
	SEL sel = @selector(loadRequest:);
	if (BTBReturnType(cls, sel, NO) != 'v') return;
	SEL delegateSel = NSSelectorFromString(delegateSelectorName);
	BTBSwizzle(cls, sel, NO, ^(id self, id request) {
		id delegate = [self respondsToSelector:@selector(delegate)] ? [self valueForKey:@"delegate"] : nil;
		if ([delegate respondsToSelector:delegateSel]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				((void (*)(id, SEL, id, id))objc_msgSend)(delegate, delegateSel, self, BTBAdBlockedError());
			});
		}
	});
}

static void BTBHideAdViews(void) {
	NSArray *bannerClasses = @[
		@"GADBannerView", @"GAMBannerView", @"GADNativeAdView", @"MAAdView", @"MANativeAdView",
		@"ALAdView", @"FBAdView", @"FBNativeAdView", @"ISBannerView", @"LPMBannerAdView",
		@"UADSBannerView", @"MPAdView", @"YMAAdView", @"YMABannerAdView", @"MTRGAdView",
		@"PAGBannerAdView", @"BUNativeExpressBannerView", @"MTGBannerAdView", @"IMBanner",
		@"CHBBanner", @"APDBannerView", @"BDMBannerView", @"VungleBannerView", @"IASAdView"
	];
	for (NSString *name in bannerClasses) {
		Class c = NSClassFromString(name);
		if (!c) continue;

		SEL move = @selector(didMoveToWindow);
		__block IMP origMove = NULL;
		origMove = BTBSwizzle(c, move, NO, ^(UIView *self) {
			if (origMove) ((void (*)(id, SEL))origMove)(self, move);
			self.hidden = YES;
		});

		SEL setHidden = @selector(setHidden:);
		__block IMP origHidden = NULL;
		origHidden = BTBSwizzle(c, setHidden, NO, ^(UIView *self, BOOL hidden) {
			if (origHidden) ((void (*)(id, SEL, BOOL))origHidden)(self, setHidden, YES);
		});

		BTBSwizzle(c, @selector(intrinsicContentSize), NO, ^CGSize(UIView *self) {
			return CGSizeZero;
		});
	}
}

void BTBFeatureNoAds(void) {
	// 1. network
	BTBInstallURLFilter(^BTBURLDecision(NSURLRequest *request) {
		return BTBIsAdHost(request.URL.host.UTF8String) ? BTBURLDecisionBlockHost : BTBURLDecisionAllow;
	});
	BTBInstallWebContentBlock(@"noads", BTBWebRulesBlockingDomains(BTBAdHosts()));

	// 2. Google Mobile Ads: loads fail immediately
	for (NSString *cls in @[@"GADInterstitialAd", @"GADRewardedAd", @"GADRewardedInterstitialAd", @"GADAppOpenAd"]) {
		BTBFailLoad(cls, @"loadWithAdUnitID:request:completionHandler:");
	}
	BTBFailLoad(@"GADAppOpenAd", @"loadWithAdUnitID:request:orientation:completionHandler:");
	BTBFailLoad(@"GAMInterstitialAd", @"loadWithAdManagerAdUnitID:request:completionHandler:");
	BTBFailDelegateLoad(@"GADBannerView", @"bannerView:didFailToReceiveAdWithError:");
	BTBFailDelegateLoad(@"GAMBannerView", @"bannerView:didFailToReceiveAdWithError:");
	BTBFailDelegateLoad(@"GADAdLoader", @"adLoader:didFailToReceiveAdWithError:");

	// 3. readiness checks
	BTBAnswerNo(@"MAInterstitialAd", @"isReady", NO);
	BTBAnswerNo(@"MARewardedAd", @"isReady", NO);
	BTBAnswerNo(@"MAAppOpenAd", @"isReady", NO);
	BTBAnswerNo(@"IronSource", @"hasInterstitial", YES);
	BTBAnswerNo(@"IronSource", @"hasRewardedVideo", YES);
	BTBAnswerNo(@"LPMInterstitialAd", @"isAdReady", NO);
	BTBAnswerNo(@"LPMRewardedAd", @"isAdReady", NO);
	BTBAnswerNo(@"UnityAds", @"isReady", YES);
	BTBAnswerNo(@"UnityAds", @"isReady:", YES);
	BTBAnswerNo(@"FBInterstitialAd", @"isAdValid", NO);
	BTBAnswerNo(@"FBRewardedVideoAd", @"isAdValid", NO);
	BTBAnswerNo(@"VungleSDK", @"isAdCachedForPlacementID:", NO);
	BTBAnswerNo(@"CHBInterstitial", @"isCached", NO);
	BTBAnswerNo(@"CHBRewarded", @"isCached", NO);
	BTBAnswerNo(@"IMInterstitial", @"isReady", NO);
	BTBAnswerNo(@"YMAInterstitialAd", @"isLoaded", NO);
	BTBAnswerNo(@"MTRGInterstitialAd", @"isLoaded", NO);

	// 4. banners
	BTBHideAdViews();

	// 5. full-screen ads that slip through: close at once so the app continues
	BTBAddPresentationFilter(^BTBPresentDecision(UIViewController *presenter, UIViewController *controller) {
		return BTBIsAdControllerClass([controller class]) ? BTBPresentAutoDismiss : BTBPresentAllow;
	});
}
