//  BTBURLBlock.h — NSURLProtocol-based request filter shared by several tweaks.

#import "BTBCommon.h"

typedef NS_ENUM(NSInteger, BTBURLDecision) {
	BTBURLDecisionAllow = 0,
	BTBURLDecisionFail,          // fail with "not connected to internet"
	BTBURLDecisionEmptyLookup    // answer an App Store lookup with zero results
};

typedef BTBURLDecision (^BTBURLFilter)(NSURLRequest *request);

/// Installs a global filter (NSURLSession + NSURLConnection). Can be called by several tweaks.
void BTBInstallURLFilter(BTBURLFilter filter);
