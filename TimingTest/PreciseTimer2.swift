//
//  PreciseTimer.swift
//  TimingTest
//
//  Created by Akemi on 27/11/2018.
//  Copyright © 2018 Akemi. All rights reserved.
//

import Cocoa

class PreciseTimer2 {
    
    var thread: pthread_t?
    let condition = NSCondition()
    var events: [[String:Any]] = []
    var timebaseRatio: Double = 1.0
    var isRunning: Bool = true
    
    init(highPrecision: Bool = false) {
        var timebase: mach_timebase_info = mach_timebase_info()
        var attr: pthread_attr_t = pthread_attr_t()
        var param: sched_param = sched_param()
        mach_timebase_info(&timebase)
        pthread_attr_init(&attr)
        
        timebaseRatio = (Double(timebase.numer) / Double(timebase.denom)) / CVGetHostClockFrequency()
        param.sched_priority = sched_get_priority_max(SCHED_FIFO)
        pthread_attr_setschedparam(&attr, &param)
        pthread_attr_setschedpolicy(&attr, SCHED_FIFO)
        pthread_create(&thread, &attr, entryC, PreciseTimer2.bridge(obj: self))

        if highPrecision {
            let threadport: thread_port_t = pthread_mach_thread_np(thread!)
            let policyCount = MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size
            var policy = thread_time_constraint_policy(
                period: UInt32(1.0 / 60.0 / timebaseRatio),          //period of reoccuring event
                computation: UInt32(100000),                         //min computation time, range 50000-50000000
                constraint:  UInt32((1.0 / 60.0) / timebaseRatio/2), //max computation time, range 50000-UINT32_MAX
                preemptible: 1                                       //computation can be preemptible
            )
            
            let ret = withUnsafeMutablePointer(to: &policy) {
                $0.withMemoryRebound(to: integer_t.self, capacity: policyCount) {
                    thread_policy_set(threadport,
                                      thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                                      $0,
                                      mach_msg_type_number_t(policyCount))
                }
            }

            if ret != KERN_SUCCESS {
                print("highPrecision failed.")
            } else {
                print("highPrecision success.")
            }
        }
    }
    
    func stop() {
        isRunning = false
        pthread_cancel(thread!)
        pthread_join(thread!, nil)
    }
    
    func scheduleAt(time: UInt64, closure: @escaping () -> () ) {
        condition.lock()
        let firstEventTime = events.first?["time"] as? UInt64 ?? 0
        let lastEventTime = events.last?["time"] as? UInt64 ?? 0
        events.append(["time": time, "closure": closure])
        
        if lastEventTime > time {
            events.sort{ ($0["time"] as! UInt64) < ($1["time"] as! UInt64) }
        }

        condition.signal()
        condition.unlock()
        
        if firstEventTime > time {
            pthread_cancel(thread!)
        }
    }
    
    let entryC: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? = { (ptr: UnsafeMutableRawPointer) in
        let ptimer: PreciseTimer2 = PreciseTimer2.bridge(ptr: ptr)
        ptimer.entry()
        return nil
    }
    
    func entry() {
        while isRunning {
            condition.lock()
            while events.count == 0 {
                condition.wait()
            }
            let event = events.first
            condition.unlock()
            
            let time = event?["time"] as! UInt64
            let closure = event?["closure"] as! () -> ()
            
            mach_wait_until(time)
            
            condition.lock()
            if (events.first?["time"] as! UInt64) == time {
                closure()
                events.removeFirst()
            }
            condition.unlock()
        }
    }
    
    // (__bridge void*)
    class func bridge<T: AnyObject>(obj: T) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
    }
    
    // (__bridge T*)
    class func bridge<T: AnyObject>(ptr: UnsafeRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }
}
