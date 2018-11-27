//
//  main.swift
//  TimingTest
//
//  Created by Akemi on 27/11/2018.
//  Copyright © 2018 Akemi. All rights reserved.
//

import Cocoa
import Accelerate

class TimerObject: NSObject {
    @objc func exec(_ timer: Timer?) {
        let block: (() -> Void)? = timer?.userInfo as? (() -> Void)
        block?()
    }
}

func shell(_ command: String) -> Process {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]
    task.launch()
    return task
}

let methods: [[String:Any]] = [
    ["type": "dispatch", "name": "Dispatch (default)",                "queue": DispatchQueue(label: "dedicated.default", qos: .default)],
    ["type": "dispatch", "name": "Dispatch (userInitiated)",          "queue": DispatchQueue(label: "dedicated.userInitiated", qos: .userInitiated)],
    ["type": "dispatch", "name": "Dispatch (main)",                   "queue": DispatchQueue.main],
    ["type": "dispatch", "name": "Dispatch global (default)",         "queue": DispatchQueue.global(qos: .default)],
    ["type": "dispatch", "name": "Dispatch global (userInitiated)",   "queue": DispatchQueue.global(qos: .userInitiated)],
    ["type": "timer",    "name": "Timer",                             "queue": TimerObject()],
    ["type": "tpp",      "name": "TPP",                               "queue": TPPreciseTimer(spinLock: 0.0, spinLockSleepRatio: 0, highPrecision: false)],
    ["type": "tpp",      "name": "TPP (spin 0.1)",                    "queue": TPPreciseTimer(spinLock: 0.1, spinLockSleepRatio: 0, highPrecision: false)],
    ["type": "tpp",      "name": "TPP (spin 0.01)",                   "queue": TPPreciseTimer(spinLock: 0.01, spinLockSleepRatio: 0, highPrecision: false)],
    ["type": "tpp",      "name": "TPP (spin 0.001)",                  "queue": TPPreciseTimer(spinLock: 0.001, spinLockSleepRatio: 0, highPrecision: false)],
    ["type": "tpp",      "name": "Test (spin 0.01, ratio 10)",        "queue": TPPreciseTimer(spinLock: 0.01, spinLockSleepRatio: 10, highPrecision: false)],
    ["type": "tpp",      "name": "Test (spin 0.001, ratio 10)",       "queue": TPPreciseTimer(spinLock: 0.001, spinLockSleepRatio: 10, highPrecision: false)],
    ["type": "tpp",      "name": "Test (high)",                       "queue": TPPreciseTimer(spinLock: 0.0, spinLockSleepRatio: 0, highPrecision: true)],
    ["type": "tpp",      "name": "Test (high, spin 0.001, ratio 10)", "queue": TPPreciseTimer(spinLock: 0.001, spinLockSleepRatio: 10, highPrecision: true)],
    ["type": "precise",  "name": "Precise Timer",                     "queue": PreciseTimer()],
    ["type": "precise",  "name": "Precise Timer (prio 1.0)",          "queue": PreciseTimer(priority: 1.0)],
    ["type": "precise2", "name": "Precise Timer2",                    "queue": PreciseTimer2()],
    ["type": "precise2", "name": "Precise Timer2 (high)",             "queue": PreciseTimer2(highPrecision: true)],
]

var stats: [String:[Double]] = [:]

var timebase: mach_timebase_info = mach_timebase_info()
mach_timebase_info(&timebase)
let timebaseRatio = (Double(timebase.numer) / Double(timebase.denom)) / CVGetHostClockFrequency()
let period: Double = 1/60
let numSamples: Int = 1000
let stdOffset: Double = 2.0
let start = mach_absolute_time()
let workaroundTimer = PreciseTimer2(highPrecision: true)

func logStats(name: String, startTime: UInt64) {
    let end = mach_absolute_time()
    stats[name]?.append( (Double(end-startTime) * timebaseRatio) * 1000 )
}

for (index, method) in methods.enumerated() {
    let type = method["type"] as! String
    let name = method["name"] as! String
    stats[name] = []
    
    for n in (numSamples*index)...numSamples*(index+1)-1 {
        let offset = stdOffset*Double(index+1) + period*Double(n)
        let startTime = start + UInt64(offset/timebaseRatio)
        
        switch type {
        case "dispatch":
            let queue = method["queue"] as! DispatchQueue
            // if only one dispatch queue is doing work and several timely close events
            // are being queued, those events are being grouped depending on the idle time
            workaroundTimer.scheduleAt(time: startTime, closure: {
                let start2 = mach_absolute_time() + UInt64(period/timebaseRatio)
                queue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds:start2)) {
                    logStats(name: name, startTime: start2)
                }
            })
            // broken
            /*print(startTime)
            queue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds:startTime)) {
                logStats(name: name, startTime: startTime)
            }*/
        case "timer":
            // takes a delay not an absolute time
            let start2 = mach_absolute_time()
            let timer = method["queue"] as! TimerObject
            Timer.scheduledTimer(timeInterval: offset, target: timer, selector: #selector(timer.exec), userInfo: {
                logStats(name: name, startTime: start2 + UInt64(offset/timebaseRatio))
            }, repeats: false)
        case "tpp":
            let tpp = method["queue"] as! TPPreciseTimer
            tpp.scheduleBlock({
                logStats(name: name, startTime: startTime)
            }, atTime: startTime)
        case "precise":
            let precise = method["queue"] as! PreciseTimer
            precise.scheduleAt(time: startTime) {
                logStats(name: name, startTime: startTime)
            }
        case "precise2": fallthrough
        default:
            let precise = method["queue"] as! PreciseTimer2
            precise.scheduleAt(time: startTime) {
                logStats(name: name, startTime: startTime)
            }
        }
    }
}

// log cpu usage
//let task = shell("while sleep \(period/2.0); do  ps -p \(getpid()) -o pcpu= ; done;")

let completeDur = Double(methods.count+1)*stdOffset + Double(methods.count*numSamples)*period
print("Processing will take around \(completeDur.rounded()) seconds")

DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds:start) + completeDur) {
    print("\t\t\t\t\t\tMean,\t\tMeanSq,\t\t\tStdDev\t\t\tMin,\t\tMax")
    for (index, stat) in stats {
        let min = stat.min() ?? 0
        let max = stat.max() ?? 0
        let length = vDSP_Length(stat.count)
        var mean: Double = 0.0
        var meanSquare: Double = 0.0
        var stdDev: Double = 0.0
        vDSP_measqvD(stat, 1, &meanSquare, length)
        vDSP_normalizeD(stat, 1, nil, 1, &mean, &stdDev, length)

        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 10
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = ""
         
        print("\(index): \(numberFormatter.string(for: mean) ?? "")ms, " +
                       "\(numberFormatter.string(for: meanSquare) ?? "")ms, " +
                       "\(numberFormatter.string(for: stdDev) ?? "")ms, " +
                       "\(numberFormatter.string(for: min) ?? "")ms, " +
                       "\(numberFormatter.string(for: max) ?? "")ms")
    }

    // comma separated list
    /*for (index, stat) in stats {
        print("\(index)," + stat.map({"\($0)"}).joined(separator: ","))
    }*/
    
    //task.terminate()
    exit(1)
}

RunLoop.main.run()
