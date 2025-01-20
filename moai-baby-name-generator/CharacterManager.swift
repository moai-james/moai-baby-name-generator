import Foundation

class CharacterManager {
    static let shared = CharacterManager()
    
    private var characters: [String: [String: Any]] = [:]
    
    private init() {
        loadCharacters()
    }
    
    private func loadCharacters() {
        guard let url = Bundle.main.url(forResource: "characters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let chars = json["characters"] as? [String: [String: Any]] else {
            print("Failed to load characters.json")
            return
        }
        characters = chars
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
