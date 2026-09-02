#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitKeys.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDDeviceKeys.h>

#include <dispatch/dispatch.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

static const char *kHidutilPath = "/usr/bin/hidutil";
static const char *kMapping =
    "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000006F,"
    "\"HIDKeyboardModifierMappingDst\":0xFF00000003}]}";

static dispatch_source_t pendingTimer;
static dispatch_queue_t applyQueue;
static IONotificationPortRef notificationPort;
static io_iterator_t keyboardIterator;
static id wakeObserver;
static BOOL initialKeyboardScan = YES;

static void Log(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    fputs(line.UTF8String, stderr);
    fflush(stderr);
}

static void ApplyMapping(NSString *reason) {
    dispatch_async(applyQueue, ^{
        char *const arguments[] = {
            (char *)kHidutilPath,
            "property",
            "--set",
            (char *)kMapping,
            NULL,
        };

        pid_t pid = 0;
        int spawnResult = posix_spawn(&pid, kHidutilPath, NULL, NULL, arguments, environ);
        if (spawnResult != 0) {
            Log([NSString stringWithFormat:@"Failed to start hidutil (%d), reason: %@",
                                           spawnResult, reason]);
            return;
        }

        int status = 0;
        if (waitpid(pid, &status, 0) == -1) {
            Log([NSString stringWithFormat:@"Failed waiting for hidutil, reason: %@", reason]);
            return;
        }

        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            Log([NSString stringWithFormat:@"Applied F20 -> Fn, reason: %@", reason]);
        } else {
            Log([NSString stringWithFormat:@"hidutil failed with status %d, reason: %@",
                                           status, reason]);
        }
    });
}

static void ScheduleMapping(NSTimeInterval delay, NSString *reason) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pendingTimer != nil) {
            dispatch_source_cancel(pendingTimer);
            pendingTimer = nil;
        }

        pendingTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                              dispatch_get_main_queue());
        uint64_t nanoseconds = (uint64_t)(delay * (double)NSEC_PER_SEC);
        dispatch_source_set_timer(pendingTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)nanoseconds),
                                  DISPATCH_TIME_FOREVER,
                                  100 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(pendingTimer, ^{
            dispatch_source_t firedTimer = pendingTimer;
            pendingTimer = nil;
            ApplyMapping(reason);
            dispatch_source_cancel(firedTimer);
        });
        dispatch_resume(pendingTimer);

        Log([NSString stringWithFormat:@"Scheduled mapping in %.0f seconds, reason: %@",
                                       delay, reason]);
    });
}

static void KeyboardMatched(void *context, io_iterator_t iterator) {
    (void)context;

    NSUInteger matchedCount = 0;
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        matchedCount += 1;
        IOObjectRelease(service);
    }

    if (matchedCount == 0) {
        return;
    }

    if (initialKeyboardScan) {
        Log([NSString stringWithFormat:@"Found %lu existing keyboard HID service(s)",
                                       (unsigned long)matchedCount]);
        return;
    }

    ScheduleMapping(2.0, @"keyboard HID service appeared");
}

static CFMutableDictionaryRef CreateKeyboardMatchingDictionary(void) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOHIDInterface");
    if (matching == NULL) {
        return NULL;
    }

    int usagePageValue = 1;
    int usageValue = 6;
    CFNumberRef usagePage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType,
                                           &usagePageValue);
    CFNumberRef usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType,
                                       &usageValue);
    CFMutableDictionaryRef properties =
        CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                  &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);

    CFDictionarySetValue(properties, CFSTR(kIOHIDPrimaryUsagePageKey), usagePage);
    CFDictionarySetValue(properties, CFSTR(kIOHIDPrimaryUsageKey), usage);
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), properties);

    CFRelease(properties);
    CFRelease(usage);
    CFRelease(usagePage);
    return matching;
}

static BOOL StartKeyboardNotifications(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
#pragma clang diagnostic pop
    if (notificationPort == NULL) {
        Log(@"Failed to create IOKit notification port");
        return NO;
    }

    IONotificationPortSetDispatchQueue(notificationPort, dispatch_get_main_queue());

    CFMutableDictionaryRef matching = CreateKeyboardMatchingDictionary();
    if (matching == NULL) {
        Log(@"Failed to create keyboard matching dictionary");
        return NO;
    }

    kern_return_t result = IOServiceAddMatchingNotification(
        notificationPort,
        kIOMatchedNotification,
        matching,
        KeyboardMatched,
        NULL,
        &keyboardIterator);

    if (result != KERN_SUCCESS) {
        Log([NSString stringWithFormat:@"Failed to register keyboard notifications: 0x%x",
                                       result]);
        return NO;
    }

    KeyboardMatched(NULL, keyboardIterator);
    initialKeyboardScan = NO;
    Log(@"Listening for keyboard HID services (UsagePage 1, Usage 6)");
    return YES;
}

int main(void) {
    @autoreleasepool {
        applyQueue = dispatch_queue_create("com.local.KeyRemapping.apply", DISPATCH_QUEUE_SERIAL);

        if (!StartKeyboardNotifications()) {
            return 1;
        }

        wakeObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserverForName:NSWorkspaceDidWakeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *notification) {
                        (void)notification;
                        ScheduleMapping(5.0, @"Mac woke from sleep");
                    }];

        ScheduleMapping(10.0, @"watcher started");
        Log(@"KeyRemappingWatcher started");
        [[NSRunLoop mainRunLoop] run];

        (void)wakeObserver;
    }
    return 0;
}
