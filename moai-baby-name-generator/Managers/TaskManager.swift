import Foundation
import FirebaseAuth
import FirebaseFirestore

class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    @Published private(set) var missions: [MissionItem] = []
    private let db = Firestore.firestore()
    private var timer: Timer?
    
    private init() {
        setupDefaultMissions()
        setupMidnightTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // 設置午夜重置計時器
    private func setupMidnightTimer() {
        // 取消現有的計時器
        timer?.invalidate()
        
        // 計算下一個台灣午夜時間
        let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taiwanTimeZone
        
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) else {
            return
        }
        
        // 設置計時器在下一個午夜觸發
        let timer = Timer(fire: nextMidnight, interval: 86400, repeats: true) { [weak self] _ in
            self?.performMidnightReset()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    // 執行午夜重置
    private func performMidnightReset() {
        Task {
            // 確保在主線程執行 UI 更新
            await MainActor.run {
                resetDailyMissionsRewardState()
            }
            
            // 同步到 Firestore
            if let userId = Auth.auth().currentUser?.uid {
                do {
                    // 只更新獎勵領取狀態
                    let dailyLoginRef = db.collection("users").document(userId)
                    try await dailyLoginRef.setData([
                        "missions": [
                            "daily_login": [
                                "isRewardClaimed": false,
                                "rewardClaimedAt": nil
                            ]
                        ]
                    ], merge: true)
                } catch {
                    print("❌ 重置每日任務狀態失敗: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 修改：只重置獎勵領取狀態
    private func resetDailyMissionsRewardState() {
        if let index = missions.firstIndex(where: { $0.type == .dailyLogin }) {
            // 只重置獎勵領取狀態，保持完成狀態不變
            missions[index].isRewardClaimed = false
            saveMissionState(missions[index])
            sortMissions()
        }
    }
    
    // 從 Firebase 同步任務狀態
    func syncMissionsFromFirebase() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🚫 [Missions] 無法同步：用戶未登入")
            return
        }
        
        print("🔄 [Missions] 開始從 Firestore 同步任務狀態 - 用戶ID: \(userId)")
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            print("📄 [Missions] 成功獲取文檔")
            
            let data = document.data()?["missions"] as? [String: [String: Any]] ?? [:]
            print("📊 [Missions] 獲取到的原始數據: \(data)")
            
            await MainActor.run {
                print("🔄 [Missions] 開始重置本地任務狀態")
                // 重置所有任務狀態為未完成和未領取
                for i in 0..<missions.count {
                    let oldState = "完成:\(missions[i].isCompleted), 領取:\(missions[i].isRewardClaimed)"
                    missions[i].isCompleted = false
                    missions[i].isRewardClaimed = false
                    print("🔄 [Missions] 重置任務 \(missions[i].id) - 原狀態: \(oldState) -> 新狀態: 完成:false, 領取:false")
                }
                
                print("📥 [Missions] 開始更新任務狀態")
                // 從 Firebase 更新任務狀態
                for (missionId, missionData) in data {
                    if let index = missions.firstIndex(where: { $0.id == missionId }) {
                        let oldState = "完成:\(missions[index].isCompleted), 領取:\(missions[index].isRewardClaimed)"
                        
                        missions[index].isCompleted = missionData["isCompleted"] as? Bool ?? false
                        
                        // 檢查 rewardClaimedAt 時間戳記
                        if let rewardClaimedAt = missionData["rewardClaimedAt"] as? Timestamp {
                            let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
                            var calendar = Calendar(identifier: .gregorian)
                            calendar.timeZone = taiwanTimeZone
                            
                            // 如果 rewardClaimedAt 是今天，則設為已領取
                            missions[index].isRewardClaimed = calendar.isDateInToday(rewardClaimedAt.dateValue())
                            print("📅 [Missions] 檢查獎勵領取時間 - 任務:\(missionId), 領取時間:\(rewardClaimedAt.dateValue()), 是今天:\(calendar.isDateInToday(rewardClaimedAt.dateValue()))")
                        } else {
                            missions[index].isRewardClaimed = false
                            print("⚠️ [Missions] 任務 \(missionId) 無領取時間記錄")
                        }
                        
                        print("✏️ [Missions] 更新任務 \(missionId) - 原狀態: \(oldState) -> 新狀態: 完成:\(missions[index].isCompleted), 領取:\(missions[index].isRewardClaimed)")
                    }
                }
                
                print("🔄 [Missions] 開始排序任務")
                self.sortMissions()
                print("✅ [Missions] 排序完成")
                
                print("🔍 [Missions] 開始檢查所有任務狀態")
                self.checkAllMissionStates()
                print("✅ [Missions] 任務狀態檢查完成")
                
                // 打印最終狀態
                print("📊 [Missions] 最終任務狀態:")
                for mission in self.missions {
                    print("- \(mission.id): 完成:\(mission.isCompleted), 領取:\(mission.isRewardClaimed)")
                }
            }
        } catch {
            print("❌ [Missions] 從 Firebase 同步任務失敗: \(error.localizedDescription)")
        }
    }
    
    private func syncMissionToFirestore(_ mission: MissionItem) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🚫 [Missions] 無法同步到 Firestore：用戶未登入")
            return
        }
        
        print("📤 [Missions] 開始同步任務到 Firestore - 用戶ID: \(userId), 任務ID: \(mission.id)")
        print("📊 [Missions] 任務狀態 - 完成:\(mission.isCompleted), 領取:\(mission.isRewardClaimed)")
        
        let missionData: [String: Any] = [
            "isCompleted": mission.isCompleted,
            "isRewardClaimed": mission.isRewardClaimed,
            "completedAt": mission.isCompleted ? FieldValue.serverTimestamp() : nil,
            "rewardClaimedAt": mission.isRewardClaimed ? FieldValue.serverTimestamp() : nil,
            "type": mission.type.rawValue
        ]
        
        db.collection("users").document(userId).setData([
            "missions": [
                mission.id: missionData
            ]
        ], merge: true) { error in
            if let error = error {
                print("❌ [Missions] 同步任務到 Firebase 失敗: \(error.localizedDescription)")
            } else {
                print("✅ [Missions] 成功同步任務到 Firestore")
            }
        }
    }
    
    private func setupDefaultMissions() {
        print("📝 [Missions] 創建默認任務列表")
        missions = [
            MissionItem(id: "daily_login",
                     title: "每日登入",
                     description: "每日首次登入即可獲得3次使用次數",
                     rewardUses: 3,
                     isCompleted: false,
                     isRewardClaimed: false,
                     type: .dailyLogin),
            
            MissionItem(id: "two_factor_auth",
                     title: "開啟雙重驗證",
                     description: "設定雙重驗證提升帳號安全性，獲得3次使用次數",
                     rewardUses: 3,
                     isCompleted: false,
                     isRewardClaimed: false,
                     type: .twoFactorAuth),
            
            MissionItem(id: "account_link",
                     title: "綁定帳號",
                     description: "將訪客帳號升級為正式帳號，獲得3次使用次數",
                     rewardUses: 3,
                     isCompleted: false,
                     isRewardClaimed: false,
                     type: .accountLink),
            
            MissionItem(id: "app_rating",
                     title: "應用程式評分",
                     description: "在 App Store 給予五星好評，獲得10次使用次數",
                     rewardUses: 10,
                     isCompleted: false,
                     isRewardClaimed: false,
                     type: .appRating)
        ]
        
        print("✅ [Missions] 默認任務列表創建完成，共 \(missions.count) 個任務")
        
        // 如果用戶已登入，從 Firebase 同步最新狀態
        if Auth.auth().currentUser != nil {
            Task {
                await syncMissionsFromFirebase()
            }
        }
    }
    
    // 修改 saveMissionState 方法，只同步到 Firestore
    private func saveMissionState(_ mission: MissionItem) {
        syncMissionToFirestore(mission)
    }
    
    private func sortMissions() {
        missions.sort { (mission1, mission2) -> Bool in
            if mission1.isRewardClaimed != mission2.isRewardClaimed {
                return !mission1.isRewardClaimed
            }
            if mission1.isCompleted != mission2.isCompleted {
                return !mission1.isCompleted
            }
            return true
        }
    }

    private func checkDailyLogin() {
        if let user = Auth.auth().currentUser {
            let lastLoginTime = user.metadata.lastSignInDate
            if let lastLoginTime = lastLoginTime {
                print("✅ 上次登入時間: \(lastLoginTime)")
            }

            // make sure daily login mission is completed
            completeDailyLoginMission()

            // if lastLoginTime is not today, set rewardClaimed to false
            let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = taiwanTimeZone
            
            if let lastLoginTime = lastLoginTime, !calendar.isDateInToday(lastLoginTime) {
                if let index = missions.firstIndex(where: { $0.type == .dailyLogin }) {
                    missions[index].isRewardClaimed = false
                    saveMissionState(missions[index])
                }
            }
        }
    }
    
    private func checkDailyReset() {
        let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taiwanTimeZone
        
        // 使用 Firebase Auth 的 lastSignInDate 來檢查是否需要重置
        if let user = Auth.auth().currentUser,
           let lastLoginTime = user.metadata.lastSignInDate {
            let now = Date()
            
            if !calendar.isDateInToday(lastLoginTime) {
                resetDailyMissionsRewardState() // 只重置獎勵領取狀態
            }
            
            // 檢查今日是否已完成登入任務
            if calendar.isDateInToday(lastLoginTime) {
                completeDailyLoginMission()
            } else {
                // 如果沒有上次登入記錄，直接完成任務
                completeDailyLoginWithoutCheck()
            }
        } else {
            // 如果沒有用戶登入資訊，直接完成任務
            completeDailyLoginWithoutCheck()
        }
    }
    
    // 新增：無需檢查直接完成每日登入任務
    private func completeDailyLoginWithoutCheck() {
        if let index = missions.firstIndex(where: { $0.type == .dailyLogin }) {
            missions[index].isCompleted = true
            missions[index].isRewardClaimed = false // 確保獎勵狀態為未領取
            saveMissionState(missions[index])
            syncMissionToFirestore(missions[index])
            sortMissions()
        }
    }
    
    // 完成每日登入任務
    private func completeDailyLoginMission() {
        if let index = missions.firstIndex(where: { $0.type == .dailyLogin }) {
            missions[index].isCompleted = true
            saveMissionState(missions[index])
            syncMissionToFirestore(missions[index])
            sortMissions()
        }
    }
    
    // MARK: - Public Methods
    
    func completeMission(_ type: MissionItem.MissionType) {
        if let index = missions.firstIndex(where: { $0.type == type }) {
            missions[index].isCompleted = true
            saveMissionState(missions[index])
            
            syncMissionToFirestore(missions[index])
            sortMissions()
        }
    }
    
    func isMissionCompleted(_ type: MissionItem.MissionType) -> Bool {
        return missions.first(where: { $0.type == type })?.isCompleted ?? false
    }
    
    func getMission(_ type: MissionItem.MissionType) -> MissionItem? {
        return missions.first(where: { $0.type == type })
    }
    
    // 新增：領取獎勵方法
    func claimReward(_ type: MissionItem.MissionType) async {
        guard let index = missions.firstIndex(where: { $0.type == type }),
              missions[index].isCompleted,
              !missions[index].isRewardClaimed else {
            return
        }
        
        missions[index].isRewardClaimed = true
        saveMissionState(missions[index])
        syncMissionToFirestore(missions[index])
        
        // 更新使用次數
        await MainActor.run {
            UsageManager.shared.remainingUses += missions[index].rewardUses
        }
        
        // 同步到雲端
        do {
            try await UsageManager.shared.updateCloudData()
        } catch {
            print("❌ 更新使用次數失敗: \(error.localizedDescription)")
        }
        
        sortMissions()
    }
    
    // 計算未完成任務數量
    var uncompletedMissionsCount: Int {
        missions.filter { !$0.isCompleted }.count
    }
    
    // 計算已完成但未領取獎勵的任務數量
    var unclaimedRewardsCount: Int {
        missions.filter { $0.isCompleted && !$0.isRewardClaimed }.count
    }
    
    // 獲取需要在 TabBar 顯示的數字（未完成 + 未領取）
    var tabBadgeCount: Int {
        uncompletedMissionsCount + unclaimedRewardsCount
    }
    
    // 檢查所有任務狀態
    func checkAllMissionStates() {

        let user = Auth.auth().currentUser

        // 檢查每日登入任務
        checkDailyLogin()
                
        // 檢查雙重驗證任務
        if let user = user {
            let providers = user.providerData.map { $0.providerID }
            if providers.contains("phone") {
                completeMission(.twoFactorAuth)
            } else {
                uncompleteMission(.twoFactorAuth)
                unclaimReward(.twoFactorAuth)
            }
        }
        
        // 檢查帳號綁定任務
        if let user = user, !user.isAnonymous {
            completeMission(.accountLink)
        } else {
            uncompleteMission(.accountLink)
            unclaimReward(.accountLink)
        }
        
        // 檢查 App Store 評分任務
        checkAppRatingMission()


    }
    
    // 檢查 App Store 評分任務
    private func checkAppRatingMission() {
        if UserDefaults.standard.bool(forKey: "hasRatedApp") && !isMissionCompleted(.appRating) {
            completeMission(.appRating)
        } else {
            uncompleteMission(.appRating)
            unclaimReward(.appRating)
        }
    }
    
    // 修改 resetAndSetupMissions 方法
    func resetAndSetupMissions() {
        print("🔄 [Missions] 開始重置任務狀態")
        timer?.invalidate()
        missions = []
        
        // 設置默認任務
        print("📝 [Missions] 設置默認任務")
        setupDefaultMissions()
        
        // 如果用戶已登入，立即從 Firebase 同步最新狀態
        if let userId = Auth.auth().currentUser?.uid {
            print("👤 [Missions] 用戶已登入 (ID: \(userId))，開始同步 Firestore 狀態")
            Task {
                await syncMissionsFromFirebase()
            }
        } else {
            print("⚠️ [Missions] 用戶未登入，使用默認任務狀態")
        }
    }
    
    func uncompleteMission(_ type: MissionItem.MissionType) {
        if let index = missions.firstIndex(where: { $0.type == type }) {
            guard missions[index].isCompleted && !missions[index].isRewardClaimed else {
                return
            }
            
            missions[index].isCompleted = false
            saveMissionState(missions[index])
            sortMissions()
        }
    }
    
    func unclaimReward(_ type: MissionItem.MissionType) {
        if let index = missions.firstIndex(where: { $0.type == type }) {
            missions[index].isRewardClaimed = false
            saveMissionState(missions[index])
            sortMissions()
        }
    }
    
    private func saveMissionStates() {
        for mission in missions {
            saveMissionState(mission)
        }
    }
} 