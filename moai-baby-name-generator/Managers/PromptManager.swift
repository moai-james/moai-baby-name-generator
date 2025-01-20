import Foundation
import FirebaseFirestore

class PromptManager {
    static let shared = PromptManager()
    
    private let promptsCacheKey = "cachedPrompts"
    
    private var nameGenerationPrompt: String = """
    請根據以下表單資料和父母期許為嬰兒生成中文名字：

    命名要求：
    1. 名字為單名或雙名，務必確保與基本資料中的單雙名一致。
    2. 如有指定中間字，須包含於名中。
    3. 名字符合嬰兒性別。
    4. 典故來源於具體內容不可僅引用篇名。
    5. 典故與名字有明確聯繫，並詳述其關係。
    6. 針對每個期許提供簡短的分析，說明名字如何呼應父母的期待。
    
    注意事項：
    1. 請確保輸出格式符合JSON規範並與範例一致。
    2. 情境分析只需提供分析結果，無需重複問題和答案。
    3. 所有字串值使用雙引號，並適當使用轉義字符。
    4. 請使用繁體中文，禁止使用簡體中文。

    基本資料：{{formData}}

    父母期許：{{meaningString}}
    """  // 預設模板
    
    private init() {
        loadCachedPrompts()
    }
    
    private func loadCachedPrompts() {
        if let prompt = UserDefaults.standard.string(forKey: promptsCacheKey) {
            self.nameGenerationPrompt = prompt
        }
    }
    
    func getNameGenerationPrompt() -> String {
        if nameGenerationPrompt.isEmpty {
            print("⚠️ [Prompts] 警告：提示詞模板為空，使用預設模板")
        }
        return nameGenerationPrompt
    }
    
    func updatePrompts() async {
        print("🔄 [Prompts] 開始更新提示詞模板")
        
        do {
            let db = Firestore.firestore()
            let querySnapshot = try await db.collection("prompts")
                .document("nameGeneration")
                .collection("versions")
                .whereField("isActive", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()
            
            guard let activeVersion = querySnapshot.documents.first,
                  let template = activeVersion.data()["template"] as? String else {
                print("⚠️ [Prompts] 無法從 Firestore 獲取活躍模板，使用預設模板")
                return
            }
            
            self.nameGenerationPrompt = template
            
            // 更新快取
            UserDefaults.standard.set(template, forKey: promptsCacheKey)
            
            print("✅ [Prompts] 成功更新提示詞模板")
        } catch let error {
            print("❌ [Prompts] 更新提示詞模板失敗：\(error.localizedDescription)")
        }
    }
} 