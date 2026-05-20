#import "ObjCExceptionCatcher.h"

static NSString * const NPObjCExceptionErrorDomain = @"com.nullplayer.objc-exception";

BOOL NPObjCExceptionCatch(NPObjCExceptionTryBlock tryBlock, NSError **error) {
    @try {
        tryBlock();
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
            if (exception.name != nil) {
                userInfo[NSLocalizedDescriptionKey] = exception.name;
            }
            if (exception.reason != nil) {
                userInfo[NSLocalizedFailureReasonErrorKey] = exception.reason;
            }
            userInfo[@"NSExceptionName"] = exception.name ?: @"";
            userInfo[@"NSExceptionReason"] = exception.reason ?: @"";

            *error = [NSError errorWithDomain:NPObjCExceptionErrorDomain code:1 userInfo:userInfo];
        }
        return NO;
    }
}
