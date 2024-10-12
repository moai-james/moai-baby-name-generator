import Foundation

struct APIConfig {
    static var openAIKey: String {
        get {
            guard let filePath = Bundle.main.path(forResource: "Config", ofType: "plist") else {
                fatalError("Couldn't find file 'Config.plist'.")
            }
            
            let plist = NSDictionary(contentsOfFile: filePath)
            
            guard let value = plist?.object(forKey: "OpenAI_API_Key") as? String else {
                fatalError("Couldn't find key 'OpenAI_API_Key' in 'Config.plist'.")
            }
            
            return value
        }
    }
}
