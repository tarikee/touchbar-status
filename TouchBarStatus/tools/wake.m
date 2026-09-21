// Wakes / undims the Touch Bar panel so it can be captured for QA.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void *(*CreateFn)(void);
typedef void (*ClientVoidFn)(void *);
typedef void (*ClientIntFn)(void *, int);
typedef void (*SetDimFn)(int);

int main(void) {
    @autoreleasepool {
        void *f = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation", RTLD_NOW);
        SetDimFn setDim = f ? (SetDimFn)dlsym(f, "DFRSetDimmingStep") : NULL;
        if (setDim) { setDim(0); NSLog(@"WAKE: DFRSetDimmingStep(0) called"); }
        else NSLog(@"WAKE: DFRSetDimmingStep missing");

        void *b = dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/Versions/A/DFRBrightness", RTLD_NOW);
        if (!b) { NSLog(@"WAKE: DFRBrightness dlopen failed"); return 1; }
        CreateFn create = (CreateFn)dlsym(b, "DFRBrightnessClientCreate");
        ClientVoidFn turnOn = (ClientVoidFn)dlsym(b, "DFRBrightnessClientDisplayTurnOn");
        ClientIntFn dimStep = (ClientIntFn)dlsym(b, "DFRBrightnessClientDisplaySetDimmingStep");
        NSLog(@"WAKE: create=%p turnOn=%p dimStep=%p", create, turnOn, dimStep);
        if (!create || !turnOn) return 2;

        void *client = create();
        NSLog(@"WAKE: client=%p", client);
        if (!client) return 3;
        if (dimStep) dimStep(client, 0);
        turnOn(client);
        NSLog(@"WAKE: display turned on");
        [NSThread sleepForTimeInterval:0.3];
    }
    return 0;
}
