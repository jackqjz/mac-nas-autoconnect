// All state belongs to the main queue. The timer only fires after an event.
#import <AppKit/AppKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

static dispatch_source_t timer;
static NSString *checkPath;
static NSTask *activeCheck;
static BOOL pending;
static NSUInteger readinessRetries;

static void schedule(double seconds) {
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC));
    dispatch_source_set_timer(timer, when, DISPATCH_TIME_FOREVER, NSEC_PER_SEC / 4);
}

static void networkChanged(void) {
    readinessRetries = 2;
    pending = YES;
    schedule(2);
}

static void check(void) {
    if (activeCheck) return;
    pending = NO;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[checkPath];
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            activeCheck = nil;
            if (pending) schedule(2);
            else if (finished.terminationStatus == 75 && readinessRetries > 0) {
                readinessRetries--;
                schedule(8);
            }
        });
    };
    NSError *error = nil;
    activeCheck = task;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Cannot launch network check: %@", error.localizedDescription);
        exit(EXIT_FAILURE);
    }
}

static void changed(SCDynamicStoreRef store, CFArrayRef keys, void *context) {
    (void)store; (void)keys; (void)context;
    networkChanged();
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return EXIT_FAILURE;
        checkPath = [NSString stringWithUTF8String:argv[1]];
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(timer, ^{ check(); });
        dispatch_resume(timer);

        SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("NAS network listener"), changed, NULL);
        NSArray *keys = @[@"State:/Network/Global/IPv4"];
        NSArray *patterns = @[@"State:/Network/Interface/en[0-9]+/(IPv4|Link|AirPort)$",
                              @"State:/Network/Service/[^/]+/IPv4$"];
        if (!store || !SCDynamicStoreSetNotificationKeys(store, (__bridge CFArrayRef)keys, (__bridge CFArrayRef)patterns)
            || !SCDynamicStoreSetDispatchQueue(store, dispatch_get_main_queue())) return EXIT_FAILURE;
        [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidWakeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note;
                networkChanged();
            }];
        networkChanged();
        [[NSRunLoop mainRunLoop] run];
        CFRelease(store);
    }
    return EXIT_SUCCESS;
}
