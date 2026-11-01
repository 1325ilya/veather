//  BTBNetwork.m — /nowifi (no network at all) and /noupd (no forced update checks).

#import "BTBURLBlock.h"

void BTBFeatureNoNetwork(void) {
	BTBInstallURLFilter(^BTBURLDecision(NSURLRequest *request) {
		NSString *host = request.URL.host.lowercaseString;
		if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"]) return BTBURLDecisionAllow;
		return BTBURLDecisionFail;
	});
}

void BTBFeatureNoUpdates(void) {
	// Apps usually ask the App Store lookup API for the latest version; answer "no results".
	BTBInstallURLFilter(^BTBURLDecision(NSURLRequest *request) {
		NSString *host = request.URL.host.lowercaseString;
		NSString *path = request.URL.path.lowercaseString;
		if (([host hasSuffix:@"itunes.apple.com"] || [host hasSuffix:@"apps.apple.com"]) && [path hasSuffix:@"/lookup"]) {
			return BTBURLDecisionEmptyLookup;
		}
		return BTBURLDecisionAllow;
	});
}
