#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the block and catches any Objective-C exception (e.g. an unsupported PhotoKit sort key).
/// Returns nil on success, or "name: reason" of the caught exception.
NSString * _Nullable SPTryObjC(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
