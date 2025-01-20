import Foundation
import FirebaseAuth
import FirebaseFirestore

class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    @Published private(set) var missions: [MissionItem] = []
    private let defaults = UserDefaults.standard
    private let lastLoginDateKey = "lastLoginDate"
    private let lastResetDateKey = "lastResetDate"
    private let db = Firestore.firestore()
    private var timer: Timer?
    
    private init() {
        setupDefaultMissions()
        checkDailyReset()
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
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            guard let data = document.data()?["missions"] as? [String: [String: Any]] else {
                print("⚠️ 未找到任務資料")
                return
            }
            
            var updatedMissions = missions
            
            // 從 Firebase 更新任務狀態
            for (missionId, missionData) in data {
                if let index = updatedMissions.firstIndex(where: { $0.id == missionId }) {
                    updatedMissions[index].isCompleted = missionData["isCompleted"] as? Bool ?? false
                    
                    // 檢查 rewardClaimedAt 時間戳記
                    if let rewardClaimedAt = missionData["rewardClaimedAt"] as? Timestamp {
                        let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = taiwanTimeZone
                        
                        // 如果 rewardClaimedAt 是今天，則設為已領取
                        // 如果是昨天或更早，則設為未領取
                        updatedMissions[index].isRewardClaimed = calendar.isDateInToday(rewardClaimedAt.dateValue())
                    } else {
                        updatedMissions[index].isRewardClaimed = false
                    }
                    
                    print("✅ 已同步任務: \(missionId)")
                    print("完成狀態: \(updatedMissions[index].isCompleted)")
                    print("獎勵領取狀態: \(updatedMissions[index].isRewardClaimed)")
                    
                    // 更新本地緩存
                    defaults.set(updatedMissions[index].isCompleted, 
                               forKey: "mission_\(missionId)_completed")
                    defaults.set(updatedMissions[index].isRewardClaimed, 
                               forKey: "mission_\(missionId)_claimed")
                }
            }
            
            await MainActor.run {
                self.missions = updatedMissions
                sortMissions()
                print("✅ 任務排序完成")
                
                // 在同步完成後檢查所有任務狀態
                checkAllMissionStates()
                print("✅ 已檢查所有任務狀態")
            }
            
        } catch {
            print("❌ 從 Firebase 同步任務失敗: \(error.localizedDescription)")
        }
    }
    private func syncMissionToFirestore(_ mission: MissionItem) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let missionData: [String: Any] = [
            "isCompleted": mission.isCompleted,
            "isRewardClaimed": mission.isRewardClaimed,
            "completedAt": mission.isCompleted ? FieldValue.serverTimestamp() : nil,
            "rewardClaimedAt": mission.isRewardClaimed ? FieldValue.serverTimestamp() : nil,
            "type": mission.type.rawValue
        ]
        
        // 使用 FieldValue.arrayUnion 來更新 missions 欄位
        db.collection("users").document(userId).setData([
            "missions": [
                mission.id: missionData
            ]
        ], merge: true) { error in
            if let error = error {
                print("❌ 同步任務到 Firebase 失敗: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupDefaultMissions() {
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
        
        // 先從本地加載緩存的狀態
        loadMissionStates()
        
        // 如果用戶已登入，從 Firebase 同步最新狀態
        if Auth.auth().currentUser != nil {
            Task {
                print("✅ syncMissionsFromFirebase")
                await syncMissionsFromFirebase()
            }
        }
    }
    
    private func loadMissionStates() {
        // 檢查是否是首次加載（是否有任何任務狀態記錄）
        let isFirstLoad = !defaults.bool(forKey: "hasInitializedMissions")
        print("🔄 Loading mission states - First load: \(isFirstLoad)")
        
        if isFirstLoad {
            // 首次加載，設置初始狀態
            print("📝 First time loading - Initializing default mission states")
            for mission in missions {
                defaults.set(false, forKey: "mission_\(mission.id)_completed")
                defaults.set(false, forKey: "mission_\(mission.id)_claimed")
                print("✨ Setting initial state for mission: \(mission.id)")
            }
            defaults.set(true, forKey: "hasInitializedMissions")
        } else {
            // 從 UserDefaults 加載已保存的狀態
            print("📖 Loading saved mission states from UserDefaults")
            for i in 0..<missions.count {
                let isCompleted = defaults.bool(forKey: "mission_\(missions[i].id)_completed")
                let isRewardClaimed = defaults.bool(forKey: "mission_\(missions[i].id)_claimed")
                missions[i].isCompleted = isCompleted
                missions[i].isRewardClaimed = isRewardClaimed
                print("📊 Mission \(missions[i].id) - Completed: \(isCompleted), Claimed: \(isRewardClaimed)")
            }
        }
        
        // 將已完成且已領取獎勵的任務排到最後
        print("🔀 Sorting missions based on completion and claim status")
        sortMissions()
    }
    
    private func saveMissionState(_ mission: MissionItem) {
        defaults.set(mission.isCompleted, forKey: "mission_\(mission.id)_completed")
        defaults.set(mission.isRewardClaimed, forKey: "mission_\(mission.id)_claimed")
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

            // make sure dialy login mission is completed
            completeDailyLoginMission()

            // if lastLoginTime is not today, set rewardClaimed to false
            let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = taiwanTimeZone
            
            if let lastLoginTime = lastLoginTime, !calendar.isDateInToday(lastLoginTime) {
                missions[0].isRewardClaimed = false
                saveMissionState(missions[0])
            }
        }
    }
    
    private func checkDailyReset() {
        let taiwanTimeZone = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taiwanTimeZone
        
        let now = Date()
        
        // 檢查上次重置時間
        if let lastResetDate = defaults.object(forKey: lastResetDateKey) as? Date {
            if !calendar.isDate(lastResetDate, inSameDayAs: now) {
                resetDailyMissionsRewardState() // 只重置獎勵領取狀態
            }
        }
        
        // 更新重置時間
        defaults.set(now, forKey: lastResetDateKey)
        
        // 檢查今日是否已完成登入任務
        if let lastLoginDate = defaults.object(forKey: lastLoginDateKey) as? Date {
            if calendar.isDate(lastLoginDate, inSameDayAs: now) {
                completeDailyLoginMission()
            }
        } else {
            // 如果沒有上次登入記錄，直接完成任務
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
            
            if type == .dailyLogin {
                defaults.set(Date(), forKey: lastLoginDateKey)
            }
            
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
        // 從 UserDefaults 檢查是否已經評分
        if UserDefaults.standard.bool(forKey: "hasRatedApp") && !isMissionCompleted(.appRating) {
            completeMission(.appRating)
        } else {
            uncompleteMission(.appRating)
            unclaimReward(.appRating)
        }
    }
    
    // 新增：重置並重新初始化任務
    func resetAndSetupMissions() {
        // 停止現有的計時器
        timer?.invalidate()
        
        // 清空現有任務
        missions = []
        
        // 重新設置任務
        print("✅ resetAndSetupMissions")
        setupDefaultMissions()

        print("✅ 任務已重置並重新初始化")
        print(missions)
    }
    
    func uncompleteMission(_ type: MissionItem.MissionType) {
        if let index = missions.firstIndex(where: { $0.type == type }) {
            // 只有在任務已完成但尚未領取獎勵時才能取消完成
            guard missions[index].isCompleted && !missions[index].isRewardClaimed else {
                return
            }
            
            missions[index].isCompleted = false
            saveMissionState(missions[index])
            syncMissionToFirestore(missions[index])
            sortMissions()
            
            print("✅ 已取消完成任務: \(type.rawValue)")
        }
    }
    
    func unclaimReward(_ type: MissionItem.MissionType) {
        if let index = missions.firstIndex(where: { $0.type == type }) {
            missions[index].isRewardClaimed = false
        }
        sortMissions()
    }
} 