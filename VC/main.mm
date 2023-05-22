#import <Cocoa/Cocoa.h>
#import <SystemExtensions/SystemExtensions.h>

#import "addMethod.h"

class App {
    
    private:
    
        NSWindow *win = nil;
    
        id observer = nil;
        id delegate = nil;
    
    public:
      
        App() {
            
            CGRect screen = [[[NSScreen screens] objectAtIndex:0] frame];
            
            CGSize stageSize = CGSizeMake(320,120-28);
            CGSize buttonSize = CGSizeMake(120,28);
            
            this->win = [[NSWindow alloc] initWithContentRect:CGRectMake(64,screen.size.height-24-(stageSize.height+28)-64,stageSize.width,stageSize.height) styleMask:1|1<<1|1<<2 backing:NSBackingStoreBuffered defer:NO];
                [this->win makeKeyAndOrderFront:nil];
            [this->win  setSharingType:NSWindowSharingNone];
            [this->win setReleasedWhenClosed:NO];
            
            float margin = (stageSize.width-buttonSize.width*2)/5.0;
            
            if(objc_getClass("Delegate")==nil) { objc_registerClassPair(objc_allocateClassPair(objc_getClass("NSObject"),"Delegate",0)); }
            Class Delegate = objc_getClass("Delegate");
            addMethod(Delegate,@"touchUpInside:",^(id me, NSButton *sender) {
                if([sender.title isEqualToString:@"Activate"]) {
                    [OSSystemExtensionManager.sharedManager submitRequest:[OSSystemExtensionRequest activationRequestForExtension:@"org.mizt.VC.CE" queue:dispatch_get_main_queue()]];
                }
                else if([sender.title isEqualToString:@"Deactivate"]) {
                    [OSSystemExtensionManager.sharedManager submitRequest:[OSSystemExtensionRequest deactivationRequestForExtension:@"org.mizt.VC.CE" queue:dispatch_get_main_queue()]];
                }
            },"v@:@");

            this->delegate = [Delegate new];
            
            NSButton *button[2] = {
                [[NSButton alloc] initWithFrame:CGRectMake((int)(margin*2.0),(int)((stageSize.height-buttonSize.height)*0.5),buttonSize.width,buttonSize.height)],
                [[NSButton alloc] initWithFrame:CGRectMake((int)(margin*3.0+buttonSize.width),(int)((stageSize.height-buttonSize.height)*0.5),buttonSize.width,buttonSize.height)]
            };
                        
            [button[0] setTitle:@"Activate"];
            [button[1] setTitle:@"Deactivate"];
            
            for(int n=0; n<2; n++) {
                [button[n] setBezelStyle:NSBezelStyleRegularSquare];
                [button[n] setBordered:YES];
                [button[n] setAction:NSSelectorFromString(@"touchUpInside:")];
                [button[n] setTarget:this->delegate];
                [[this->win contentView] addSubview:button[n]];
            }
            
            this->observer = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSWindowWillCloseNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *){
                    if(this->observer) {
                        [[NSNotificationCenter defaultCenter] removeObserver:(id)this->observer];
                        this->observer = nil;
                    }
                    this->win = nil;
                    [NSApp terminate:nil];
                }
            ];
        }
        
        ~App() {
            if(this->win) {
                [this->win close];
                this->win = nil;
            }
        }
};

#pragma mark AppDelegate

@interface AppDelegate:NSObject <NSApplicationDelegate> {
    App *app;
}
@end

@implementation AppDelegate
-(void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    app = new App();
}
-(void)applicationWillTerminate:(NSNotification *)aNotification {
    delete app;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        id app = [NSApplication sharedApplication];
        id delegat = [AppDelegate alloc];
        [app setDelegate:delegat];
        
        id menu = [[NSMenu alloc] init];
        id rootMenuItem = [[NSMenuItem alloc] init];
        [menu addItem:rootMenuItem];
        id appMenu = [[NSMenu alloc] init];
        id quitMenuItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenu addItem:quitMenuItem];
        [rootMenuItem setSubmenu:appMenu];
        [NSApp setMainMenu:menu];
        
        [app run];
    }
}
