import Foundation
import FirebaseFirestore
import UIKit
import FirebaseAuth

// 將 NavigationError 結構體移到這裡，避免模組引用問題
struct NavigationError {
    let timestamp: Date
    let userID: String
    let deviceInfo: String
    let errorType: String
    let errorDetails: [String: String]
    let navigationState: String
    let memoryUsage: Double
    let cpuUsage: Double
    
    func toDictionary() -> [String: Any] {
        return [
            "timestamp": timestamp,
            "userID": userID,
            "deviceInfo": deviceInfo,
            "errorType": errorType,
            "errorDetails": errorDetails,
            "navigationState": navigationState,
            "memoryUsage": memoryUsage,
            "cpuUsage": cpuUsage
        ]
    }
}

class NavigationErrorTracker {
    static let shared = NavigationErrorTracker()
    private let db = Firestore.firestore()
    
    private init() {}
    
    func logNavigationError(type: String, details: [String: String], navigationState: String) {
        // 獲取當前用戶 ID
        let userID = Auth.auth().currentUser?.uid ?? "anonymous"
        
        let error = NavigationError(
            timestamp: Date(),
            userID: userID,
            deviceInfo: getDeviceInfo(),
            errorType: type,
            errorDetails: details,
            navigationState: navigationState,
            memoryUsage: getMemoryUsage(),
            cpuUsage: getCPUUsage()
        )
        
        db.collection("navigationErrors").addDocument(data: error.toDictionary()) { err in
            if let err = err {
                print("❌ Error logging navigation error: \(err)")
            } else {
                print("✅ Navigation error logged successfully")
            }
        }
    }
    
    private func getDeviceInfo() -> String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion), \(device.model)"
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        }
        return 0
    }
    
    private func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if threadResult == KERN_SUCCESS, let threadList = threadList {
            for index in 0..<threadCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let threadInfoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[Int(index)],
                                  thread_flavor_t(THREAD_BASIC_INFO),
                                  $0,
                                  &threadInfoCount)
                    }
                }
                
                if threadInfoResult == KERN_SUCCESS {
                    totalUsageOfCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
                }
            }
            
            vm_deallocate(mach_task_self_,
                         vm_address_t(UInt(bitPattern: threadList)),
                         vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        
        return totalUsageOfCPU * 100
    }
} 