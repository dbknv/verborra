#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside @try. Returns nil on success, or an NSError (domain "VBRObjCException",
/// userInfo "name" / "reason") when the block raised an NSException (spec 015, research R10).
/// AVAudioEngine raises NSExceptions for format mismatches; Swift can't catch those itself.
NSError * _Nullable VBRTryCatch(NS_NOESCAPE void (^ _Nonnull block)(void));

NS_ASSUME_NONNULL_END
