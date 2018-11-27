//
//  TPPreciseTimer.h
//  Loopy
//
//  Created by Michael Tyson on 06/09/2011.
//  Copyright 2011 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TPPreciseTimer : NSObject {
    double timebase_ratio;
    
    NSMutableArray *events;
    NSCondition *condition;
    pthread_t thread;
}

- (id)initWithSpinLock:(double)spinLock spinLockSleepRatio:(int)sleep highPrecision:(BOOL)pre;
- (void)scheduleBlock:(void (^)(void))block atTime:(UInt64)time;

@end
