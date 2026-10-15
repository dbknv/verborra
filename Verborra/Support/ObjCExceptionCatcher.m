#import "ObjCExceptionCatcher.h"

NSError * _Nullable VBRTryCatch(NS_NOESCAPE void (^ _Nonnull block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return [NSError errorWithDomain:@"VBRObjCException"
                                   code:1
                               userInfo:@{
                                   @"name": exception.name,
                                   @"reason": exception.reason ?: @"",
                               }];
    }
}
