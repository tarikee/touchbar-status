// Reports whether our item is currently registered in the Control Strip.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
typedef BOOL (*GetFn)(NSString *);
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *ident = argc > 1 ? [NSString stringWithUTF8String:argv[1]]
                                   : @"com.tarik.touchbarstatus.tray";
        void *h = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation", RTLD_NOW);
        GetFn get = (GetFn)dlsym(h, "DFRElementGetControlStripPresenceForIdentifier");
        if (!get) { NSLog(@"PRESENCE: symbol missing"); return 2; }
        BOOL present = get(ident);
        NSLog(@"PRESENCE: %@ -> %@", ident, present ? @"REGISTERED" : @"absent");
        return present ? 0 : 1;
    }
}
