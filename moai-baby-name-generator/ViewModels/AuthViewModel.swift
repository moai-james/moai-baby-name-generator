import SwiftUI
import GoogleSignIn
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore


class AuthViewModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var selectedTab = 0
    @Published var phoneNumber = ""
    @Published var verificationCode = ""
    @Published var showPhoneVerification = false
    @Published var verificationID: String?
    @Published var mfaResolver: MultiFactorResolver?
    @Published var errorMessage: String?
    @Published var isTwoFactorAuthenticated = false
    @Published var isLoading = false
    @Published var remainingTime: Int?
    private let usageManager = UsageManager.shared  // 添加 UsageManager 引用
    private var timer: Timer?
    @Published var showAccountLinkingOptions = false
    @Published var lastSMSRequestTime: Date?
    private let smsCooldownDuration: TimeInterval = 60 // 60秒冷卻時間
    @Published var canResetPhoneNumber = false // 控制是否可以重設手機號碼
    @Published var cooldownTimer: Timer?
    @Published var displayCooldownTime: Int = 0 // 用於顯示的倒數時間
    
    init() {
    }

    func handleSuccessfulLogin() {
        Task {
            print("✅ handleSuccessfulLogin")
            do {
                // 同步用戶使用次數資料
                try await self.usageManager.syncUserData()
                                
                // 更新最後登入時間
                guard let userId = Auth.auth().currentUser?.uid else { return }
                let db = Firestore.firestore()
                try await db.collection("users").document(userId).setData([
                    "lastLoginTime": Date()
                ], merge: true)

                // 檢查是否已完成雙重驗證
                if let currentUser = Auth.auth().currentUser {
                    let hasPhoneAuth = currentUser.providerData.contains { provider in
                        provider.providerID == PhoneAuthProviderID
                    }
                    await MainActor.run {
                        self.isTwoFactorAuthenticated = hasPhoneAuth
                    }
                }

                // 更新 UI 狀態
                await MainActor.run {
                    self.isLoggedIn = true
                    
                    // 重置任務狀態並從 Firestore 同步
                    print("🔄 [Auth] 開始重置並同步任務狀態")
                    TaskManager.shared.resetAndSetupMissions()
                }
            } catch {
                print("❌ 登入後同步資料失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 計算剩餘冷卻時間
    var remainingCooldownTime: Int {
        guard let lastRequest = lastSMSRequestTime else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRequest)
        let remaining = smsCooldownDuration - elapsed
        return max(0, Int(remaining))
    }
    
    // 檢查是否可以發送簡訊
    private func canSendSMS() -> Bool {
        guard let lastRequest = lastSMSRequestTime else { return true }
        return Date().timeIntervalSince(lastRequest) >= smsCooldownDuration
    }
    
    // 發送驗證碼
    func sendVerificationCode() {
        guard canSendSMS() else {
            errorMessage = "請等待 \(displayCooldownTime) 秒後再試"
            return
        }
        
        isLoading = true
        // Configure auth settings to use App Check instead of reCAPTCHA
        let auth = Auth.auth()
        auth.settings?.isAppVerificationDisabledForTesting = false // 確保在生產環境中啟用驗證
        
        var formattedNumber = phoneNumber
        if !phoneNumber.hasPrefix("+886") {
            if phoneNumber.hasPrefix("0") {
                formattedNumber = "+886" + phoneNumber.dropFirst()
            } else {
                formattedNumber = "+886" + phoneNumber
            }
        }
        
        print("Attempting to send verification code to: \(formattedNumber)")
        
        Task {
            do {
                // 先檢查手機號碼是否已驗證過
                let exists = try await AuthenticationManager.shared.checkPhoneNumberExists(formattedNumber)
                if exists {
                    await MainActor.run {
                        self.errorMessage = "該手機號碼已綁定其他帳號"
                        isLoading = false
                    }
                    return
                }
                
                // Send verification code
                let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(
                    formattedNumber,
                    uiDelegate: nil
                )
                
                await MainActor.run {
                    self.verificationID = verificationID
                    UserDefaults.standard.set(verificationID, forKey: "authVerificationID")
                    self.showPhoneVerification = true
                    print("✅ 驗證碼發送成功")
                }
            } catch {
                await MainActor.run {
                    let nsError = error as NSError
                    let errorCode = AuthErrorCode(_bridgedNSError: nsError)
                    switch errorCode?.code {
                    case .invalidPhoneNumber:
                        self.errorMessage = "無效的電話號碼格式"
                    case .quotaExceeded:
                        self.errorMessage = "驗證碼請求次數過多，請稍後再試"
                    case .invalidAppCredential:
                        self.errorMessage = "應用程式驗證失敗，請確認設置"
                    default:
                        self.errorMessage = "發送失敗：\(error.localizedDescription)"
                    }
                    print("❌ Phone auth error: \(error.localizedDescription)")
                    print("Error details: \(error)")
                }
            }
            isLoading = false
        }
        
        // Start countdown timer (120 seconds)
        remainingTime = 120
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let time = self.remainingTime {
                if time > 0 {
                    self.remainingTime = time - 1
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.verificationID = nil
                }
            }
        }
        
        // 更新最後發送時間
        lastSMSRequestTime = Date()
        // 允許重設手機號碼
        canResetPhoneNumber = true
        startCooldownTimer()
    }
    
    private func startCooldownTimer() {
        // 先停止現有的計時器
        cooldownTimer?.invalidate()
        
        // 設置初始倒數時間
        displayCooldownTime = Int(smsCooldownDuration)
        
        // 創建新的計時器
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.displayCooldownTime > 0 {
                DispatchQueue.main.async {
                    self.displayCooldownTime -= 1
                }
            } else {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
            }
        }
    }
    
    // 驗證碼登入
    func verifyCode() {
        isLoading = true
        guard let verificationID = verificationID else {
            errorMessage = "Missing verification ID"
            return
        }
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        // Check if user is already logged in
        if let currentUser = Auth.auth().currentUser {
            // Link the credential with current user
            print("currentUser: \(currentUser)")
            currentUser.link(with: credential) { [weak self] authResult, error in
                if let error = error as NSError? {
                    print("error: \(error)")
                    if error.domain == AuthErrorDomain && error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                        DispatchQueue.main.async {
                            self?.errorMessage = "此電話號碼已與其他帳號綁定"
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.errorMessage = error.localizedDescription
                        }
                    }
                    return
                }
                // Linking successful
                DispatchQueue.main.async {
                    self?.isTwoFactorAuthenticated = true
                    self?.showPhoneVerification = false
                    
                    // 完成雙重驗證任務
                    // TaskManager.shared.completeMission(.twoFactorAuth)
                }
            }
        } else {
            // No user is logged in, proceed with normal sign in
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                if let error = error {
                    // Handle multi-factor authentication
                    let authError = error as NSError
                    if AuthErrorCode.secondFactorRequired.rawValue == authError.code {
                        let resolver = authError.userInfo[AuthErrorUserInfoMultiFactorResolverKey] as! MultiFactorResolver
                        self?.mfaResolver = resolver
                        // Handle multi-factor authentication UI logic...
                    } else {
                        self?.errorMessage = error.localizedDescription
                    }
                    return
                }
                
                // Sign in successful
                DispatchQueue.main.async {
                    self?.isLoggedIn = true
                    self?.selectedTab = 0
                    self?.showPhoneVerification = false
                    print("✅ 驗證碼登入成功")
                }
            }
        }
        isLoading = false
    }
    
    // 登出
    func signOut() {
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
        } catch let signOutError as NSError {
            errorMessage = signOutError.localizedDescription
        }
    }
    
    // 檢查登入狀態
    func checkAuthState() {
        if Auth.auth().currentUser != nil {
            isLoggedIn = true
        }
    }

    func resetVerificationState() {
        errorMessage = nil
        mfaResolver = nil
        timer?.invalidate()
        timer = nil
        isLoading = false
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        
        // 如果還在冷卻時間內，重新啟動計時器
        if let lastRequest = lastSMSRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < smsCooldownDuration {
                displayCooldownTime = Int(smsCooldownDuration - elapsed)
                startCooldownTimer()
                // 如果驗證碼已發送且在有效期內，保持驗證碼輸入框
                if let storedVerificationID = UserDefaults.standard.string(forKey: "authVerificationID") {
                    verificationID = storedVerificationID
                    // 重新啟動驗證碼有效期計時器
                    remainingTime = max(0, 120 - Int(elapsed))  // 假設驗證碼有效期為 120 秒
                    if remainingTime! > 0 {
                        startVerificationTimer()
                    }
                }
            } else {
                // 如果已超過冷卻時間，重置所有狀態
                phoneNumber = ""
                verificationCode = ""
                verificationID = nil
                remainingTime = nil
                lastSMSRequestTime = nil
            }
        } else {
            // 如果沒有發送過驗證碼，重置所有狀態
            phoneNumber = ""
            verificationCode = ""
            verificationID = nil
            remainingTime = nil
        }
    }
    
    // 新增方法：啟動驗證碼有效期計時器
    private func startVerificationTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let time = self.remainingTime {
                if time > 0 {
                    self.remainingTime = time - 1
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.verificationID = nil
                }
            }
        }
    }
    
    // 重設手機號碼的方法
    func resetPhoneNumberInput() {
        phoneNumber = ""
        verificationID = nil
        errorMessage = nil
        canResetPhoneNumber = false
        // 保持 lastSMSRequestTime 不變，確保 rate limiting 持續有效
    }
    
    deinit {
        timer?.invalidate()
        cooldownTimer?.invalidate()
    }
    
    private func handleSuccessfulAccountLink() {
        if !TaskManager.shared.isMissionCompleted(.accountLink) {
            TaskManager.shared.completeMission(.accountLink)
        }
    }
    
    // 在其他登入相關方法中也需要添加重置邏輯
    func signInAnonymously() {
        Task {
            do {
                let result = try await Auth.auth().signInAnonymously()
                print("✅ 匿名登入成功: \(result.user.uid)")
                                
                // 處理登入成功
                await handleSuccessfulLogin()
            } catch {
                print("❌ 匿名登入失敗: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }
}
