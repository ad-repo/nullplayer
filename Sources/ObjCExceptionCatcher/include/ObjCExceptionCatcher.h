#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^NPObjCExceptionTryBlock)(void);

BOOL NPObjCExceptionCatch(NPObjCExceptionTryBlock tryBlock, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
