import Foundation

class CharacterManager {
    static let shared = CharacterManager()
    
    private var characters: [String: [String: Any]] = [:]
    
    private init() {
        loadCharacters()
    }
    
    private func loadCharacters() {
        do {
            guard let url = Bundle.main.url(forResource: "characters", withExtension: "json") else {
                print("❌ [CharacterManager] characters.json 檔案不存在")
                ErrorManager.shared.logError(
                    category: .unknown,
                    message: "characters.json 檔案不存在",
                    details: [:]
                )
                return
            }
            
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let json = json,
                  let chars = json["characters"] as? [String: [String: Any]] else {
                print("❌ [CharacterManager] characters.json 格式錯誤")
                ErrorManager.shared.logError(
                    category: .aiResponseInvalidSchema,
                    message: "characters.json 格式錯誤",
                    details: [:]
                )
                return
            }
            
            characters = chars
            print("✅ [CharacterManager] 成功載入 \(chars.count) 個字符資料")
            
        } catch {
            print("❌ [CharacterManager] 載入 characters.json 失敗: \(error.localizedDescription)")
            ErrorManager.shared.logError(
                category: .unknown,
                message: "載入 characters.json 失敗",
                details: ["error": error.localizedDescription]
            )
        }
    }
    
    func getElement(for character: String) -> String {
        guard let charInfo = characters[character],
              let element = charInfo["element"] as? String else {
            // Log the unknown element error
            ErrorManager.shared.logError(
                category: .unknownElement,
                message: "Unknown element for character",
                details: ["character": character]
            )
            return "未知"
        }
        return element
    }
}
