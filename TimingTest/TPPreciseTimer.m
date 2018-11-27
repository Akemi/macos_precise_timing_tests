//
//  TPPreciseTimer.m
//  Loopy
//
//  Created by Michael Tyson on 06/09/2011.
//  Copyright 2011 A Tasty Pixel. All rights reserved.
//

#import "TPPreciseTimer.h"
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#import <pthread.h>

static NSString *kTimeKey = @"time";
static NSString *kBlockKey = @"block";

@interface TPPreciseTimer () {
    double _spinLockTime;
    int _spinLockSleepRatio;
}
@end

@implementation TPPreciseTimer

- (id)initWithSpinLock:(double)spinLock spinLockSleepRatio:(int)sleep highPrecision:(BOOL)pre {
    if ( !(self = [super init]) ) return nil;
    
    _spinLockTime = spinLock;
    _spinLockSleepRatio = sleep;

    struct mach_timebase_info timebase;
    mach_timebase_info(&timebase);
    timebase_ratio = ((double)timebase.numer / (double)timebase.denom) * 1.0e-9;
    
    events = [[NSMutableArray alloc] init];
    condition = [[NSCondition alloc] init];
    
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    struct sched_param param;
    param.sched_priority = sched_get_priority_max(SCHED_FIFO);
    pthread_attr_setschedparam(&attr, &param);
    pthread_attr_setschedpolicy(&attr, SCHED_FIFO);
    pthread_create(&thread, &attr, thread_entry, (__bridge void*)self);
    
    if (pre) {
        struct thread_time_constraint_policy ttcpolicy;
        thread_port_t threadport = pthread_mach_thread_np(thread);
        
        ttcpolicy.period=(1/60)*1000000000;
        ttcpolicy.computation=61*0.75*1000000;
        ttcpolicy.constraint=61*0.85*1000000;
        ttcpolicy.preemptible=1;
        
        int ret = thread_policy_set(threadport, THREAD_TIME_CONSTRAINT_POLICY,
                                    (thread_policy_t)&ttcpolicy, THREAD_TIME_CONSTRAINT_POLICY_COUNT);
        if (ret != KERN_SUCCESS) {
            printf("highPrecision failed.\n");
        } else {
            printf("highPrecision success.\n");
        }
    }
    
    return self;
}


- (void)scheduleBlock:(void (^)(void))block atTime:(UInt64)time {
    [self addSchedule:[NSDictionary dictionaryWithObjectsAndKeys:
                       [block copy], kBlockKey,
                       [NSNumber numberWithUnsignedLongLong: time], kTimeKey,
                       nil]];
}

- (void)addSchedule:(NSDictionary*)schedule {
    [condition lock];
    [events addObject:schedule];
    [events sortUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:kTimeKey ascending:YES]]];
    BOOL mustSignal = [events count] > 1 && [events objectAtIndex:0] == schedule;
    [condition signal];
    [condition unlock];
    if ( mustSignal ) {
        pthread_kill(thread, SIGALRM); // Interrupt thread if it's performing a mach_wait_until and new schedule is earlier
    }
}

void *thread_entry(void* argument) {
    [(__bridge TPPreciseTimer*)argument thread];
    return NULL;
}

void thread_signal(int signal) {
    // Ignore
}

- (void)thread {
    signal(SIGALRM, thread_signal);
    [condition lock];

    while ( 1 ) {
        while ( [events count] == 0 ) {
            [condition wait];
        }
        NSDictionary *nextEvent = [events objectAtIndex:0];
        NSTimeInterval time = [[nextEvent objectForKey:kTimeKey] unsignedLongLongValue] * timebase_ratio;
        
        [condition unlock];
        
        mach_wait_until((uint64_t)((time - _spinLockTime) / timebase_ratio));
        
        if ( (double)(mach_absolute_time() * timebase_ratio) >= time-_spinLockTime ) {
            
            // Spin lock until it's time
            uint64_t end = time / timebase_ratio;
            //printf("---\n");
            while ( _spinLockTime > 0 && mach_absolute_time() < end ) {
                if (_spinLockSleepRatio > 0)
                    [NSThread sleepForTimeInterval:_spinLockTime/_spinLockSleepRatio];
            }
            
            void (^block)(void) = [nextEvent objectForKey:kBlockKey];
            if ( block ) {
                block();
            }
            
            [condition lock];
            [events removeObject:nextEvent];
        } else {
            [condition lock];
        }
    }
}

@end
