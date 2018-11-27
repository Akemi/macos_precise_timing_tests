//
//  PreciseTimer.swift
//  TimingTest
//
//  Created by Akemi on 27/11/2018.
//  Copyright © 2018 Akemi. All rights reserved.
//

import Foundation

extension Thread {
    
    func moveToRealTimeSchedulingClass() {
        
        let threadTimeConstraintPolicyCount = MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size
        var policy = thread_time_constraint_policy(
            period: (1 / 60) * 1000000000,
            computation: UInt32(60 * 0.75 * 1000000),
            constraint: UInt32(60 * 0.85 * 1000000),
            preemptible: 0
        )
        
        let ret = withUnsafeMutablePointer(to: &policy) {
            $0.withMemoryRebound(to: integer_t.self, capacity: threadTimeConstraintPolicyCount) {
                thread_policy_set(pthread_mach_thread_np(pthread_self()), thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, mach_msg_type_number_t(threadTimeConstraintPolicyCount))
            }
        }
        
        if ret != KERN_SUCCESS {
            print("PreciseTimer set_realtime() failed.")
        } else {
            print("PreciseTimer set_realtime() success.")
        }
    }
    
}

class PreciseTimer: NSObject {
    
    var thread: Thread!
    var pthread: pthread_t!
    let lock = NSLock()
    var events: [[String:Any]] = []
    
    init(priority: Double = 0.5) {
        super.init()
        thread = Thread(target:self, selector:#selector(loop), object:nil)
        thread.threadPriority = priority
        thread.name = "PreciseTimer Thread"
        thread.start()
    }
    
    func scheduleAt(time: UInt64, closure: @escaping () -> () ) {
        lock.lock()
        events.append(["time": time, "closure": closure])
        lock.unlock()
        perform(#selector(self.workerLoop), on:thread, with:["time": time, "closure": closure], waitUntilDone: false)
    }
    
    func stop() {
        pthread_kill(pthread, SIGALRM)
    }
    
    @objc private func loop(_ data: Any?) {
        let loop = RunLoop.current
        pthread = pthread_self()
        loop.add(NSMachPort(), forMode: .default)
        while !thread.isCancelled {
            //thread.moveToRealTimeSchedulingClass()
            loop.run()
        }
    }
    
    @objc private func workerLoop(_ data: Any?) {
        let d = data as! [String:Any]
        let time = d["time"] as! UInt64
        let closure = d["closure"] as! () -> ()
        
        mach_wait_until(time)
        closure()
    }
}
