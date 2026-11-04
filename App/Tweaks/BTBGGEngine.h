//  BTBGGEngine.h — the memory engine behind the GameGuardian tweak (no UI).
//  It reads and writes only the memory of the app it is injected into.
//
//  Threading: every method that scans or edits must be called with the operation lock held
//  (`lock` / `tryLock`, then `unlock`). The UI uses tryLock, scripts use lock.

#import <Foundation/Foundation.h>

NSString *BTBGGL(NSString *en, NSString *ru); // picks the system language

typedef NS_ENUM(uint8_t, BTBGGType) {
	BTBGGTypeByte = 0, BTBGGTypeWord, BTBGGTypeDword, BTBGGTypeQword,
	BTBGGTypeFloat, BTBGGTypeDouble,
	BTBGGTypeXor,   // two neighbouring dwords whose XOR is the value (a common way to hide numbers)
	BTBGGTypeAuto,  // search only: tries Dword, Qword, Float and Double
};

typedef NS_ENUM(NSInteger, BTBGGMode) {
	BTBGGModeExact, BTBGGModeRange, BTBGGModeChanged, BTBGGModeUnchanged,
	BTBGGModeGreater, BTBGGModeSmaller, BTBGGModeIncreasedBy, BTBGGModeDecreasedBy,
	BTBGGModeNotEqual, BTBGGModeAtMost, BTBGGModeAtLeast,
};

typedef NS_OPTIONS(NSUInteger, BTBGGRegion) {
	BTBGGRegionHeap       = 1 << 0, // malloc memory
	BTBGGRegionAnonymous  = 1 << 1, // other private memory (game engines keep their data here)
	BTBGGRegionStack      = 1 << 2,
	BTBGGRegionAppData    = 1 << 3, // data segments of the app's own code
	BTBGGRegionSystemData = 1 << 4, // data segments of iOS libraries
	BTBGGRegionOther      = 1 << 5, // mapped files, graphics memory, the rest
	BTBGGRegionDefault    = BTBGGRegionHeap | BTBGGRegionAnonymous | BTBGGRegionAppData,
	BTBGGRegionAll        = 0x3F,
};

typedef NS_ENUM(NSInteger, BTBGGFreezeMode) {
	BTBGGFreezeExact,   // always write the value back
	BTBGGFreezeAtLeast, // only raise it when the game lowers it (keeps it from going below)
	BTBGGFreezeAtMost,  // only lower it when the game raises it
};

/// One result: the address (low 56 bits) and the type (top 8 bits) share a word.
typedef struct { uint64_t addrType; uint64_t raw; } BTBGGHit;
static inline uint64_t BTBGGHitAddress(BTBGGHit h) { return h.addrType & 0x00FFFFFFFFFFFFFFull; }
static inline BTBGGType BTBGGHitType(BTBGGHit h) { return (BTBGGType)(h.addrType >> 56); }

@interface BTBGGItem : NSObject // a line of the saved list
@property (nonatomic) uint64_t address;
@property (nonatomic) BTBGGType type;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *module;   // set when the address is inside a code image (survives restarts)
@property (nonatomic) uint64_t offset;          // offset from the image header
@end

@interface BTBGGEngine : NSObject
+ (instancetype)shared;

// MARK: locking / state
- (void)lock;
- (BOOL)tryLock;
- (void)unlock;
@property (atomic) BOOL cancel;                  // asks the running scan to stop early
@property (nonatomic, readonly) size_t count;    // number of results
@property (nonatomic, readonly) BOOL stoppedEarly; // the last scan ran out of memory or was cancelled

// MARK: search settings
@property (nonatomic) NSUInteger regions;        // BTBGGRegion mask
@property (nonatomic) uint64_t addressFrom, addressTo; // limits (0 / UINT64_MAX = everywhere)

// MARK: results
- (BOOL)search:(NSString *)text type:(BTBGGType)type unknown:(BOOL)unknown error:(NSString **)error;
- (BOOL)refine:(NSString *)text mode:(BTBGGMode)mode error:(NSString **)error;
- (void)clearResults;
- (BTBGGHit)hitAtIndex:(size_t)index;
- (void)loadHits:(const BTBGGHit *)hits count:(size_t)count;           // replaces the results
- (void)removeHitsWithAddresses:(NSSet<NSNumber *> *)addresses;
/// Sets every result to `text` (each in its own type). Returns how many were written.
- (NSUInteger)editAll:(NSString *)text freeze:(BOOL)freeze mode:(BTBGGFreezeMode)mode typeFilter:(int)typeFilter;

// MARK: values
+ (size_t)sizeOfType:(BTBGGType)type;
+ (NSString *)nameOfType:(BTBGGType)type;
+ (BOOL)parse:(NSString *)text type:(BTBGGType)type raw:(uint64_t *)raw; // one number: 12, -5, 2.5, 0x1F, h1F
+ (NSString *)format:(uint64_t)raw type:(BTBGGType)type;
+ (BOOL)isFloatType:(BTBGGType)type;
+ (double)doubleValue:(uint64_t)raw type:(BTBGGType)type;
+ (int64_t)integerValue:(uint64_t)raw type:(BTBGGType)type;
+ (uint64_t)rawFromDouble:(double)value type:(BTBGGType)type;
+ (uint64_t)rawFromInteger:(int64_t)value type:(BTBGGType)type;
- (BOOL)readValue:(uint64_t)address type:(BTBGGType)type raw:(uint64_t *)raw;
- (BOOL)writeValue:(uint64_t)address type:(BTBGGType)type raw:(uint64_t)raw;
- (BOOL)readBytes:(uint64_t)address into:(void *)buffer length:(size_t)length;
- (BOOL)writeBytes:(uint64_t)address from:(const void *)buffer length:(size_t)length;

// MARK: freezing (keeps writing the value back while the game runs)
- (void)freezeAddress:(uint64_t)address type:(BTBGGType)type raw:(uint64_t)raw mode:(BTBGGFreezeMode)mode;
- (void)unfreezeAddress:(uint64_t)address;
- (void)unfreezeAll;
- (BOOL)isFrozen:(uint64_t)address;
- (NSUInteger)frozenCount;

// MARK: memory map and modules
/// Each entry: start, end (NSNumber), mask (BTBGGRegion), name (image or ""), writable (BOOL), tag.
- (NSArray<NSDictionary *> *)regionList;
- (BOOL)moduleForAddress:(uint64_t)address name:(NSString **)name offset:(uint64_t *)offset;
- (NSString *)describeAddress:(uint64_t)address;

// MARK: saved list
@property (nonatomic, readonly) NSMutableArray<BTBGGItem *> *list;
- (BTBGGItem *)addToListAddress:(uint64_t)address type:(BTBGGType)type label:(NSString *)label;
- (void)removeListItems:(NSArray<BTBGGItem *> *)items;
- (void)clearList;
- (void)persistList;
- (NSString *)listJSON;
- (NSInteger)importListJSON:(NSString *)json; // returns the number of items added, -1 if the text is not valid
@end
