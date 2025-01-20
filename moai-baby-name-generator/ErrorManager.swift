import Foundation
import FirebaseFirestore

enum ErrorCategory: String {
    case unknownElement = "unknown_element"
    
    // AI Response Related
    case aiResponseMalformedJSON = "ai_response_malformed_json"     // JSON 格式錯誤
    case aiResponseInvalidSchema = "ai_response_invalid_schema"      // 不符合預期的資料結構
    case aiResponseIncompleteData = "ai_response_incomplete_data"    // 資料不完整
    case aiResponseWrongQuestionCount = "ai_response_wrong_question_count"  // 情境題數量錯誤
    case aiResponseWrongCharacterCount = "ai_response_wrong_character_count"  // Add this new case
    
    // API Related
    case apiCallTimeout = "api_call_timeout"           // API 呼叫超時
    case apiCallRateLimit = "api_call_rate_limit"      // 達到 API 限制
    case apiCallNetworkError = "api_call_network_error" // 網路連線問題
    case apiCallAuthError = "api_call_auth_error"      // API 認證錯誤
        
    // Other
    case unknown = "unknown_error"                      // 未知錯誤
}

struct ErrorEvent: Codable {
    let timestamp: Date
    let message: String
    let details: [String: String]
    let userId: String?
    
    func toDictionary() -> [String: Any] {
        return [
            "timestamp": Date(),
            "message": message,
            "details": details,
            "userId": userId ?? "anonymous"
        ]
    }
}

class ErrorManager {
    static let shared = ErrorManager()
    private let db = Firestore.firestore()
    
    private init() {}
    
    func logError(category: ErrorCategory, 
                 message: String, 
                 details: [String: String] = [:],
                 userId: String? = nil) {
        let errorEvent = ErrorEvent(
            timestamp: Date(),
            message: message,
            details: details,
            userId: userId
        )
        
        let errorRef = db.collection("errors").document(category.rawValue)
        
        errorRef.updateData([
            "events": FieldValue.arrayUnion([errorEvent.toDictionary()])
        ]) { [weak self] error in
            if let error = error {
                // If document doesn't exist, create it
                if (error as NSError).domain == FirestoreErrorDomain &&
                   (error as NSError).code == FirestoreErrorCode.notFound.rawValue {
                    self?.createNewErrorDocument(category: category, errorEvent: errorEvent)
                } else {
                    print("❌ Error logging error event: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func createNewErrorDocument(category: ErrorCategory, errorEvent: ErrorEvent) {
        let errorRef = db.collection("errors").document(category.rawValue)
        
        errorRef.setData([
            "category": category.rawValue,
            "events": [errorEvent.toDictionary()]
        ]) { error in
            if let error = error {
                print("❌ Error creating error document: \(error.localizedDescription)")
            }
        }
    }
} 