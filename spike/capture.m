#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

typedef CGDisplayStreamRef (*DFRStreamCreateFn)(int, dispatch_queue_t, CGDisplayStreamFrameAvailableHandler);

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        const char *outPath = argc > 1 ? argv[1] : "touchbar.png";
        double delay = argc > 2 ? atof(argv[2]) : 1.5;
        void *h = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation", RTLD_NOW);
        DFRStreamCreateFn fn = (DFRStreamCreateFn)dlsym(h, "DFRDisplayStreamCreate");
        if (!fn) { NSLog(@"CAP: no symbol"); return 2; }

        __block BOOL armed = YES, done = NO;
        __block int frames = 0;
        CGDisplayStreamRef stream = fn(0, dispatch_get_main_queue(),
            ^(CGDisplayStreamFrameStatus status, uint64_t t, IOSurfaceRef surface, CGDisplayStreamUpdateRef u) {
                if (status != kCGDisplayStreamFrameStatusFrameComplete || !surface) return;
                frames++;
                if (!armed) return;
                CIImage *ci = [CIImage imageWithIOSurface:surface];
                NSBitmapImageRep *bmp = [[NSBitmapImageRep alloc] initWithCIImage:ci];
                NSData *png = [bmp representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                [png writeToFile:[NSString stringWithUTF8String:outPath] atomically:YES];
                NSLog(@"CAP: frame %d written (%lu bytes)", frames, (unsigned long)png.length);
            });
        if (!stream) { NSLog(@"CAP: NULL stream"); return 3; }
        CGDisplayStreamStart(stream);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            armed = YES;
            NSLog(@"CAP: armed after %.1fs (%d frames seen so far)", delay, frames);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"CAP: done, %d frames captured", frames); exit(frames>0?0:4);
        });
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
