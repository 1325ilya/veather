//  BTBURLBlock.m

#import "BTBURLBlock.h"

static NSMutableArray<BTBURLFilter> *BTBFilters;
static NSString *const BTBHandledKey = @"BTBURLHandled";

static BTBURLDecision BTBDecide(NSURLRequest *request) {
	@synchronized (BTBFilters) {
		for (BTBURLFilter filter in BTBFilters) {
			BTBURLDecision d = filter(request);
			if (d != BTBURLDecisionAllow) return d;
		}
	}
	return BTBURLDecisionAllow;
}

@interface BTBURLProtocol : NSURLProtocol
@end

@implementation BTBURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
	if ([NSURLProtocol propertyForKey:BTBHandledKey inRequest:request]) return NO;
	NSString *scheme = request.URL.scheme.lowercaseString;
	if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
	return BTBDecide(request) != BTBURLDecisionAllow;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
	BTBURLDecision d = BTBDecide(self.request);
	if (d == BTBURLDecisionEmptyLookup) {
		NSData *body = [@"{\"resultCount\":0,\"results\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
		NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
		[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
		[self.client URLProtocol:self didLoadData:body];
		[self.client URLProtocolDidFinishLoading:self];
		return;
	}
	NSInteger code = d == BTBURLDecisionBlockHost ? NSURLErrorCannotFindHost : NSURLErrorNotConnectedToInternet;
	NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:@{
		NSURLErrorFailingURLErrorKey: self.request.URL ?: [NSNull null],
		NSLocalizedDescriptionKey: @"Blocked by Veather"
	}];
	[self.client URLProtocol:self didFailWithError:error];
}
- (void)stopLoading {}
@end

void BTBInstallURLFilter(BTBURLFilter filter) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		BTBFilters = [NSMutableArray array];
		[NSURLProtocol registerClass:[BTBURLProtocol class]];
		// sessions created with custom configurations ignore registerClass:, so prepend our protocol
		SEL sel = @selector(protocolClasses);
		Class cfg = [NSURLSessionConfiguration class];
		__block IMP orig = NULL;
		orig = BTBSwizzle(cfg, sel, NO, ^NSArray *(NSURLSessionConfiguration *self) {
			NSArray *classes = orig ? ((NSArray *(*)(id, SEL))orig)(self, sel) : @[];
			if ([classes containsObject:[BTBURLProtocol class]]) return classes;
			return [@[[BTBURLProtocol class]] arrayByAddingObjectsFromArray:classes ?: @[]];
		});
	});
	@synchronized (BTBFilters) {
		[BTBFilters addObject:[filter copy]];
	}
}
