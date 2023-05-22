#import <Foundation/Foundation.h>
#import <CoreMediaIO/CMIOExtension.h>

@interface CEProviderSource:NSObject<CMIOExtensionProviderSource>
-(instancetype)initWithClientQueue:(dispatch_queue_t)clientQueue;
@property(nonatomic, readonly) CMIOExtensionProvider *provider;
@end
