#import <Foundation/Foundation.h>
#import "CEProvider.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        CEProviderSource *providerSource = [[CEProviderSource alloc] initWithClientQueue:nil];
        [CMIOExtensionProvider startServiceWithProvider:providerSource.provider];
        CFRunLoopRun();
    }
    return 0;
}
