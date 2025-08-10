import Foundation
import FirebaseFirestore

class PromptManager {
    static let shared = PromptManager()
    
    private let promptsCacheKey = "cachedPrompts"
    private let systemPromptCacheKey = "cachedSystemPrompt"
    private var isTestMode: Bool = false
    
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
    
    private var systemPrompt: String = """
    您是一位專精於中華文化的命名顧問，具備以下專業知識：
    1. 精通《說文解字》、《康熙字典》等字書，能準確解析漢字字義與內涵
    2. 熟稔《詩經》、《左傳》、《楚辭》、《史記》、《論語》等經典文獻，善於運用典故為名字增添文化深度
    3. 深諳五行八字、音律諧和之道，確保名字音韻優美
    4. 擅長結合現代命名美學，打造既傳統又時尚的名字

    您的任務是：
    1. 確保名字的音韻、字義皆相輔相成
    2. 選用富有正面寓意的典故，並詳細解釋其文化內涵
    3. 分析名字如何呼應家長的期望與願景
    4. 確保名字有創意，不落俗套
    """ // 預設系統提示詞
    
    private init() {
        if let testMode = Bundle.main.object(forInfoDictionaryKey: "IS_TEST_MODE") as? Bool {
            isTestMode = testMode
        }
        loadCachedPrompts()
    }
    
    private func loadCachedPrompts() {
        if let prompt = UserDefaults.standard.string(forKey: promptsCacheKey) {
            self.nameGenerationPrompt = prompt
        }
        if let systemPrompt = UserDefaults.standard.string(forKey: systemPromptCacheKey) {
            self.systemPrompt = systemPrompt
        }
    }
    
    func getNameGenerationPrompt() -> String {
        if nameGenerationPrompt.isEmpty {
            print("⚠️ [Prompts] 警告：提示詞模板為空，使用預設模板")
        }
        return nameGenerationPrompt
    }
    
    func getSystemPrompt() -> String {
        if systemPrompt.isEmpty {
            print("⚠️ [Prompts] 警告：系統提示詞為空，使用預設模板")
        }
        print("🔧 [Prompts] 系統提示詞: \(systemPrompt)")
        return systemPrompt
    }
    
    func updatePrompts() async {
        print("🔄 [Prompts] 開始更新提示詞模板")
        print("🔧 [Prompts] 當前模式: \(isTestMode ? "測試版" : "正式版")")
        
        do {
            let db = Firestore.firestore()
            let querySnapshot = try await db.collection("prompts")
                .document("nameGeneration")
                .collection("versions")
                .whereField(isTestMode ? "isActiveInTest" : "isActive", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()
            
            guard let activeVersion = querySnapshot.documents.first,
                  let template = activeVersion.data()["template"] as? String,
                  let systemTemplate = activeVersion.data()["systemPrompt"] as? String else {
                print("⚠️ [Prompts] 無法從 Firestore 獲取活躍模板，使用預設模板")
                return
            }
            
            self.nameGenerationPrompt = template
            self.systemPrompt = systemTemplate
            
            // 更新快取
            UserDefaults.standard.set(template, forKey: promptsCacheKey)
            UserDefaults.standard.set(systemTemplate, forKey: systemPromptCacheKey)
            
            print("✅ [Prompts] 成功更新提示詞模板")
        } catch let error {
            print("❌ [Prompts] 更新提示詞模板失敗：\(error.localizedDescription)")
        }
    }
} 