//
//  MemoryDiagnostics.swift
//  DynastyStatDrop
//
//  Provides a lightweight resident memory (RSS) helper used by diagnostic logs.
//  Only active where referenced under #if DEBUG.
//
//  NOTE: This uses mach task_info; safe for iOS/macOS simulator & device.
//

import Foundation
import Darwin

extension ProcessInfo {
    /// Approximate resident memory (physical) usage of current process in MB.
    /// Returns -1 if the kernel call fails.
    var residentMemoryMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Int(info.resident_size) / (1024 * 1024)
        } else {
            return -1
        }
    }
}
