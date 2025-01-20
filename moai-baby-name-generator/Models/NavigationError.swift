import Foundation
import FirebaseFirestore

struct NavigationError: Codable {
    let timestamp: Date
    let deviceInfo: String
    let errorType: String
    let errorDetails: [String: String]
    let navigationState: String
    let memoryUsage: Double
    let cpuUsage: Double
    
    func toDictionary() -> [String: Any] {
        return [
            "timestamp": timestamp,
            "deviceInfo": deviceInfo,
            "errorType": errorType,
            "errorDetails": errorDetails,
            "navigationState": navigationState,
            "memoryUsage": memoryUsage,
            "cpuUsage": cpuUsage
        ]
    }
} 