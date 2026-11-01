//  BTBRateBeGone.m — /norev: suppress "Rate this app" prompts.

#import "BTBCommon.h"

void BTBFeatureNoRate(void) {
	Class cls = NSClassFromString(@"SKStoreReviewController");
	BTBSwizzle(cls, NSSelectorFromString(@"requestReview"), YES, ^(id self) {
		BTB_LOG("blocked requestReview");
	});
	BTBSwizzle(cls, NSSelectorFromString(@"requestReviewInScene:"), YES, ^(id self, id scene) {
		BTB_LOG("blocked requestReviewInScene");
	});
	// popular third-party rating libraries
	BTBSwizzle(NSClassFromString(@"Appirater"), NSSelectorFromString(@"showPrompt"), NO, ^(id self) {});
	BTBSwizzle(NSClassFromString(@"iRate"), NSSelectorFromString(@"promptForRating"), NO, ^(id self) {});
}
