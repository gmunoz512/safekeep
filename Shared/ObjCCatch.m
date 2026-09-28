#import "ObjCCatch.h"

NSString * _Nullable SPTryObjC(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @"(no reason)"];
    }
}
