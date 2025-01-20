//
//  ContentView.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/10/9.
//
import UIKit
import SwiftUI
import SwiftyGif
import SwiftOpenAI
import GoogleSignIn
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import WebKit
import GoogleMobileAds
import StoreKit
import AuthenticationServices
import CryptoKit
import FirebaseAppCheck

// extension Color {
//     static let customBackground = Color("CustomBackground")
//     static let customText = Color("CustomText")
//     static let customAccent = Color("CustomAccent")
//     static let customSecondary = Color("CustomSecondary")
struct BannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        print("📱 [BannerAd] Starting to create banner view")
        let bannerView = GADBannerView(adSize: GADAdSizeBanner)
        let viewController = UIViewController()
        
        // 測試用廣告單元 ID,發布時要換成真實的
        print("🎯 [BannerAd] Setting ad unit ID")
        // bannerView.adUnitID = "ca-app-pub-3469743877050320/3645991765"
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        bannerView.rootViewController = viewController
        
        
        print("🔄 [BannerAd] Adding banner view to view controller")
        viewController.view.addSubview(bannerView)
        viewController.view.frame = CGRect(origin: .zero, size: GADAdSizeBanner.size)
        
        print("📤 [BannerAd] Loading banner ad request")
        bannerView.load(GADRequest())
        print("✅ [BannerAd] Banner view setup complete")
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    @State private var showSplash = true
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var usageManager = UsageManager.shared
    @StateObject private var appStateManager = AppStateManager()
    
    
    var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                MainView(navigationPath: $navigationPath, 
                        selectedTab: $authViewModel.selectedTab,
                        isLoggedIn: $authViewModel.isLoggedIn,
                        authViewModel: authViewModel)
            }
            .accentColor(.customAccent)

            if showSplash {
                SplashScreenView(showSplash: $showSplash)
                .zIndex(1)
            }
            
            if !showSplash && !authViewModel.isLoggedIn {
                LoginView(authViewModel: authViewModel)
            }
        }
        .onAppear {
            checkExistingAuth()
            
            // 更新提示詞模板
            Task {
                await PromptManager.shared.updatePrompts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            appStateManager.handleAppForeground()
        }
    }
    
    private func checkExistingAuth() {
        if let user = Auth.auth().currentUser {
            print("👤 Found existing user: \(user.uid)")
            user.getIDTokenResult { tokenResult, error in
                if let error = error {
                    print("❌ Token 驗證錯誤: \(error.localizedDescription)")
                    self.authViewModel.isLoggedIn = false
                    return
                }
                
                guard let tokenResult = tokenResult else {
                    print("❌ No token result")
                    self.authViewModel.isLoggedIn = false
                    return
                }
                
                if tokenResult.expirationDate > Date() {
                    print("✅ Token is valid")
                    authViewModel.handleSuccessfulLogin()
                } else {
                    print("🔄 Token expired, refreshing...")
                    user.getIDTokenForcingRefresh(true) { _, error in
                        if let error = error {
                            print("❌ Token 刷新錯誤: \(error.localizedDescription)")
                            self.authViewModel.isLoggedIn = false
                        } else {
                            print("✅ Token refreshed successfully")
                            authViewModel.handleSuccessfulLogin()
                        }
                    }
                }
            }
        } else {
            print("👤 No existing user found")
            self.authViewModel.isLoggedIn = false
        }
    }

}

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var errorMessage: String?
    @Environment(\.colorScheme) var colorScheme
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var isLoading = false
    @State private var showPhoneVerification = false
    @State private var showVerificationCode = false
    @State private var mfaResolver: MultiFactorResolver?
    @State private var lastSMSRequestTime: Date?
    @State private var cooldownRemaining: Int = 0
    let smsCooldownDuration: Int = 60 // 冷卻時間（秒）
    
    let textColor = Color(hex: "#FF798C")
    
    var body: some View {
        ZStack {
            Image("background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                HStack(alignment: .center, spacing: 0) {
                    Image("login_mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180)
                        .offset(x:-15)
                        
                    Text("歡迎加入")
                        .font(.custom("NotoSansTC-Black", size: 32))
                        .foregroundColor(textColor)
                        .offset(x:-20, y:10)
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                
                
                // if let errorMessage = errorMessage {
                //     Text(errorMessage)
                //         .foregroundColor(.red)
                //         .font(.custom("NotoSansTC-Regular", size: 14))
                // }
                
                Button(action: signInWithGoogle) {
                    HStack {
                        Image("GoogleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 17)
                        Text("使用 Google 帳號登入")
                            .font(.custom("NotoSansTC-Black", size: 16))
                            .bold()
                    }
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(textColor, lineWidth: 1)
                    )
                }
                
                Button(action: signInWithApple) {
                    HStack {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 17)
                        Text("使用 Apple 帳號登入")
                            .font(.custom("NotoSansTC-Black", size: 16))
                            .bold()
                    }
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(textColor, lineWidth: 1)
                    )
                }
                
                Button(action: signInAsGuest) {
                    HStack {
                        Image(systemName: "person.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 17)
                        Text("以訪客身份使用")
                            .font(.custom("NotoSansTC-Black", size: 16))
                            .bold()
                    }
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(textColor, lineWidth: 1)
                    )
                }
                
                // Spacer()
            
                // Version information
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.bottom, 10)
                }

            }
            .padding(.horizontal, 30)
            
            // Phone Verification Sheet
            .sheet(isPresented: $authViewModel.showPhoneVerification, onDismiss: {
                authViewModel.resetVerificationState()
            }) {
                NavigationView {
                    VStack(spacing: 20) {
                        // Phone number input
                        CustomTextField(
                            placeholder: "請輸入手機號碼",
                            text: $authViewModel.phoneNumber,
                            keyboardType: .phonePad
                        )
                        .padding(.horizontal)
                        
                        if authViewModel.canResetPhoneNumber {
                            // 顯示重設手機號碼的選項
                            HStack {
                                Text("手機號碼輸入錯誤？")
                                    .font(.custom("NotoSansTC-Regular", size: 14))
                                    .foregroundColor(.gray)
                                
                                Button("重新輸入號碼") {
                                    authViewModel.resetPhoneNumberInput()
                                }
                                .font(.custom("NotoSansTC-Regular", size: 14))
                                .foregroundColor(.customAccent)
                            }
                            .padding(.horizontal)
                        }
                        
                        if authViewModel.verificationID != nil {
                            // Verification code input
                            CustomTextField(
                                placeholder: "請輸入驗證碼",
                                text: $authViewModel.verificationCode,
                                keyboardType: .numberPad,
                                textContentType: .oneTimeCode  // 添加這行來支持自動填充簡訊驗證碼
                            )
                            .padding(.horizontal)
                            .onChange(of: authViewModel.verificationCode) { newValue in
                                // 當驗證碼改變時，檢查是否為從剪貼簿貼上的內容
                                if let pasteboardString = UIPasteboard.general.string,
                                   pasteboardString.count == 6,  // 假設驗證碼為 6 位數
                                   pasteboardString.allSatisfy({ $0.isNumber }) {
                                    authViewModel.verificationCode = pasteboardString
                                }
                            }
                            
                            // Countdown timer and resend button
                            HStack {
                                if let remainingTime = authViewModel.remainingTime {
                                    Text("驗證碼有效時間：\(remainingTime)秒")
                                        .font(.custom("NotoSansTC-Regular", size: 14))
                                        .foregroundColor(.gray)
                                    
                                    if remainingTime == 0 {
                                        Button("重新發送") {
                                            authViewModel.sendVerificationCode()
                                        }
                                        .font(.custom("NotoSansTC-Regular", size: 14))
                                        .foregroundColor(.customAccent)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            // Verify button with loading state
                            Button(action: {
                                authViewModel.verifyCode()
                            }) {
                                HStack {  // 添加 HStack 來確保內容橫向填滿
                                    if authViewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("驗證")
                                    }
                                }
                                .frame(maxWidth: .infinity)  // 將 frame 移到 HStack 上
                                .padding()
                                .background(authViewModel.isLoading ? Color.gray : Color.customAccent)
                                .foregroundColor(.white)
                                .cornerRadius(25)
                            }
                            .padding(.horizontal)
                            .disabled(authViewModel.isLoading)
                        } else {
                            // Send code button
                            Button(action: {
                                authViewModel.sendVerificationCode()
                            }) {
                                HStack {  // 添加 HStack 來確保內容橫向填滿
                                    if authViewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text(authViewModel.displayCooldownTime > 0 
                                            ? "請等待 \(authViewModel.displayCooldownTime) 秒"
                                            : "發送驗證碼")
                                    }
                                }
                                .frame(maxWidth: .infinity)  // 將 frame 移到 HStack 上
                                .padding()
                                .background(
                                    authViewModel.displayCooldownTime > 0 || authViewModel.isLoading 
                                        ? Color.gray 
                                        : Color.customAccent
                                )
                                .foregroundColor(.white)
                                .cornerRadius(25)
                            }
                            .padding(.horizontal)
                            .disabled(authViewModel.displayCooldownTime > 0 || authViewModel.isLoading)
                        }
                        
                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.custom("NotoSansTC-Regular", size: 14))
                                .foregroundColor(.red)
                                .padding()
                        }
                        
                        Spacer()
                    }
                    .padding(.top)
                    .navigationTitle("雙重驗證設定")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(trailing: Button("取消") {
                        authViewModel.showPhoneVerification = false
                    }
                    .font(.custom("NotoSansTC-Regular", size: 16))
                    )
                    .onAppear {
                        authViewModel.resetVerificationState()
                    }
                }
            }
            
            // Loading overlay
            if isLoading {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("登入中...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
            }
        }
        .sheet(isPresented: $showVerificationCode) {
            if let resolver = mfaResolver {
                VerificationCodeView(resolver: resolver)
            }
        }
    }

    private func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { 
            print("❌ 無法獲取 clientID")
            return 
        }
        
        // 設置 loading 狀態
        isLoading = true
        
        print("✅ 開始 Google 登入流程")
        print("ClientID: \(clientID)")
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            isLoading = false  // 如果失敗要關閉 loading
            print("❌ 無法獲取 rootViewController")
            return
        }
        
        print("✅ 準備顯示 Google 登入視窗")
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [self] result, error in
            if let error = error {
                print("❌ Google 登入錯誤: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                isLoading = false  // 登入失敗關閉 loading
                return
            }
            
            print("✅ Google 登入成功")
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                isLoading = false  // 資料無效關閉 loading
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { [self] authResult, error in
                // 完成時關閉 loading
                defer { isLoading = false }
                
                if let error = error as NSError? {
                    if error.domain == AuthErrorDomain,
                       error.code == AuthErrorCode.secondFactorRequired.rawValue {
                        // Handle MFA
                        print(" Auth.auth().currentUser: \(String(describing: Auth.auth().currentUser))")
                        authViewModel.mfaResolver = error.userInfo[AuthErrorUserInfoMultiFactorResolverKey] as? MultiFactorResolver
                        authViewModel.showPhoneVerification = true
                    } else {
                        errorMessage = error.localizedDescription
                    }
                } else {
                    print(" Auth.auth().currentUser: \(String(describing: Auth.auth().currentUser))")
                    print("✅ google登入成功")
                    authViewModel.handleSuccessfulLogin()
                }
            }           
        }
    }
    
    private func signInWithApple() {
        isLoading = true  // 開始載入
        appleSignInCoordinator = AppleSignInCoordinator()
        appleSignInCoordinator?.startSignInWithAppleFlow { result in
            // 完成時關閉 loading
            defer { isLoading = false }
            
            switch result {
            case .success(_):
                authViewModel.handleSuccessfulLogin()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func signInAsGuest() {
        isLoading = true  // 開始載入
        
        // 清空收藏列表
        UserDefaults.standard.removeObject(forKey: "FavoriteNames")
        
        Auth.auth().signInAnonymously { [self] authResult, error in
            // 完成時關閉 loading
            defer { isLoading = false }
            
            if let error = error {
                print("❌ 訪客登入錯誤: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                return
            }
            
            guard let user = authResult?.user else {
                print("❌ 無法獲取用戶資訊")
                return
            }
            
            print("✅ 創建新的匿名帳號")
            print("👤 用戶 ID: \(user.uid)")
            print("🔑 是否為匿名用戶: \(user.isAnonymous)")
            
            // 在 Firestore 中創建用戶文檔
            let db = Firestore.firestore()
            db.collection("users").document(user.uid).setData([
                "isAnonymous": true,
                "createdAt": FieldValue.serverTimestamp(),
                "lastLoginAt": FieldValue.serverTimestamp(),
                "favorites": [] // 確保收藏列表為空
            ], merge: true) { error in
                if let error = error {
                    print("❌ 創建用戶文檔失敗: \(error.localizedDescription)")
                } else {
                    print("✅ 創建用戶文檔成功")
                }
            }
            
            authViewModel.handleSuccessfulLogin()
        }
    }

    private func startCooldownTimer() {
        // 設置最後發送時間
        lastSMSRequestTime = Date()
        // 開始倒數計時
        cooldownRemaining = smsCooldownDuration
        
        // 創建計時器來更新剩餘時間
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if cooldownRemaining > 0 {
                cooldownRemaining -= 1
            } else {
                timer.invalidate()
            }
        }
    }
    
    private func canSendSMS() -> Bool {
        guard let lastRequest = lastSMSRequestTime else { return true }
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
        return timeSinceLastRequest >= Double(smsCooldownDuration)
    }
}

struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var isSecure: Bool = false
    var validation: ((String) -> Bool)?
    var errorMessage: String?
    var textContentType: UITextContentType? = nil
    var returnKeyType: UIReturnKeyType = .done
    var cooldownRemaining: Int? = nil
    
    @State private var isValid: Bool = true
    @State private var showError: Bool = false
    @FocusState private var isFocused: Bool  // 新增 FocusState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .textContentType(textContentType)
                    .submitLabel(.done)
                    .focused($isFocused)  // 添加 focused 修飾符
                    .onTapGesture {  // 添加點擊手勢
                        isFocused = true
                    }
                    .onChange(of: text) { newValue in
                        validateInput(newValue)
                    }
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .textContentType(textContentType)
                    .submitLabel(.done)
                    .focused($isFocused)  // 添加 focused 修飾符
                    .onTapGesture {  // 添加點擊手勢
                        isFocused = true
                    }
                    .onChange(of: text) { newValue in
                        validateInput(newValue)
                    }
            }
            
            if showError, let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 4)
            }
            
            if let cooldown = cooldownRemaining, cooldown > 0 {
                Text("\(cooldown) 秒後可重新發送")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func validateInput(_ value: String) {
        if let validation = validation {
            isValid = validation(value)
            showError = !isValid && !value.isEmpty
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white)
            .cornerRadius(25)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.customAccent, lineWidth: 1)
            )
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct MainView: View {
    // Navigation and tab state
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int
    @Binding var isLoggedIn: Bool
    
    // View models
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var rewardedViewModel = RewardedViewModel()
    @StateObject private var usageManager = UsageManager.shared
    @StateObject private var interstitialAd = InterstitialAdViewModel()
    @StateObject private var iapManager = IAPManager.shared
    // @ObservedObject private var taskManager = TaskManager.shared
    
    // Environment and storage
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("favoriteTabCount") private var favoriteTabCount = 0
    
    // Alert states
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showPhoneVerification = false
    @State private var showDeleteAccountAlert = false
    @State private var showTwoFactorAlert = false
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var upgradeErrorMessage: String? // Renamed to avoid conflict
    @State private var showUpgradeError = false
    @State private var isUpgrading = false
    
    // Add new state for showing account linking options
    @State private var showAccountLinkingOptions = false
    @State private var showSerialNumberInput = false

    var body: some View {
        ZStack {
            // Main content area
            ZStack {
                if selectedTab == 0 {
                    homeView
                } else if selectedTab == 1 {
                    VStack {
                        Text("收藏")
                            .font(.custom("NotoSansTC-Black", size: 32))
                            .foregroundColor(.customText)
                            .padding(.top, 20)
                        FavoritesListView()
                    }
                } else if selectedTab == 2 {
                    StoreView()
                } else if selectedTab == 3 {
                    settingsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            // Tab bar with banner ad
            VStack(spacing: 0) {
                Spacer()
                    
                // Add banner ad
                BannerView()
                    .frame(width: GADAdSizeBanner.size.width, height: GADAdSizeBanner.size.height)
                    
                // Tab bar
                HStack(spacing: 20) {
                    Spacer()
                    TabBarButton(imageName: "home_icon", isSelected: selectedTab == 0) { 
                        selectedTab = 0 
                    }
                    Spacer()
                    TabBarButton(imageName: "favs_icon", isSelected: selectedTab == 1) { 
                        // Show interstitial ad when switching to favorites tab
                        if selectedTab != 1 {
                            favoriteTabCount += 1
                            if favoriteTabCount >= 3 {
                                interstitialAd.showAd()
                                favoriteTabCount = 0  // Reset counter
                            }
                        }
                        selectedTab = 1
                    }
                    Spacer()
                    TabBarButton(imageName: "store_icon", isSelected: selectedTab == 2) { 
                        selectedTab = 2 
                    }
                    Spacer()
                    // TabBarButton(imageName: "setting_icon", isSelected: selectedTab == 3, badgeCount: taskManager.missions.filter { !$0.isRewardClaimed }.count) { 
                    //     selectedTab = 3 
                    // }
                    TabBarButton(imageName: "setting_icon", isSelected: selectedTab == 3, badgeCount: 0) { 
                        selectedTab = 3 
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical , 10)
                .frame(maxWidth: .infinity)
                .background(Color.tabbar)
                .cornerRadius(25, corners: [.topLeft, .topRight])
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationDestination(for: String.self) { destination in
            if destination == "FormView" {
                FormView(navigationPath: $navigationPath, 
                        selectedTab: $selectedTab,
                        isLoggedIn: $authViewModel.isLoggedIn,
                        authViewModel: authViewModel)
                .background(Color.black.opacity(0.3))
                .transition(.identity)
            }
        }
        .navigationDestination(for: FormData.self) { formData in
            DialogView(
                navigationPath: $navigationPath,
                selectedTab: $selectedTab,  // 傳遞 selectedTab
                formData: formData)
            .transition(.identity)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            // 檢查是否需要顯示雙重驗證提醒
            if UserDefaults.standard.bool(forKey: "shouldShowTwoFactorAlert") {
                showTwoFactorAlert = true
                UserDefaults.standard.set(false, forKey: "shouldShowTwoFactorAlert")
            }
        }
    }
   
    var homeView: some View {
        ZStack {
            GeometryReader { geometry in
                VStack() {
                    // Header 保持在外層
                    VStack(spacing: 0) {
                        Color.black.frame(height: 0)
                        HStack {
                            Spacer()
                            Text("千尋取名")
                                .font(.custom("NotoSansTC-Black", size: 20))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.black)
                        Color.pink.frame(height: 5)
                    }.zIndex(1)
                    
                    // Content area
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: geometry.size.height * 0.03) // 減少頂部間距，因為已經有 header
                        
                        // 主要圖示區域
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(
                                    width: min(geometry.size.width * 0.9, 380),
                                    height: min(geometry.size.width * 0.9, 375)
                                )
                                .opacity(0.5)
                            
                            Image("main_mascot")
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: min(geometry.size.width * 0.6, 260),
                                    height: min(geometry.size.width * 0.6, 260)
                                )
                        }
                        .frame(width: geometry.size.width)
                        .frame(height: geometry.size.height * 0.35)
                        
                        // 開始取名按鈕
                        Button(action: {
                            if usageManager.remainingUses > 0 {
                                // 記錄開始導航
                                // NavigationErrorTracker.shared.logNavigationError(
                                //     type: "navigation_start",
                                //     details: [
                                //         "remaining_uses": "\(usageManager.remainingUses)",
                                //         "button_action": "start_naming"
                                //     ],
                                //     navigationState: "main_to_form"
                                // )
                                
                                // 記錄當前路徑
                                let currentPath = navigationPath
                                
                                // 嘗試導航
                                DispatchQueue.main.async {
                                    navigationPath.append("FormView")
                                }
                                
                                // 設定檢查計時器
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    // 只在導航失敗時記錄錯誤
                                    if navigationPath == currentPath {
                                        // 導航失敗，記錄錯誤
                                        NavigationErrorTracker.shared.logNavigationError(
                                            type: "navigation_failed",
                                            details: [
                                                "error": "Navigation timeout",
                                                "current_path": "\(currentPath)",
                                                "new_path": "\(navigationPath)",
                                                "remaining_uses": "\(usageManager.remainingUses)",
                                                "device_orientation": UIDevice.current.orientation.rawValue.description,
                                                "background_refresh_status": UIApplication.shared.backgroundRefreshStatus.rawValue.description
                                            ],
                                            navigationState: "stuck_at_main"
                                        )
                                        
                                        print("⚠️ Navigation failed, attempting recovery...")
                                        
                                        // 嘗試重置導航
                                        // DispatchQueue.main.async {
                                        //     navigationPath = NavigationPath()
                                        //     navigationPath.append("FormView")
                                        // }
                                    }
                                }
                            } else {
                                showAlert = true
                            }
                        }) {    
                            Text("開始取名")
                                .font(.custom("NotoSansTC-Black", size: min(32, geometry.size.width * 0.08)))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, geometry.size.height * 0.02)
                                .cornerRadius(25)
                                .tracking(20)
                        }
                        .background(
                            Image("naming_button")
                                .resizable()
                                .scaledToFill()
                        )
                        .frame(width: geometry.size.width * 0.8)
                        .padding(.horizontal, 20)
                        .padding(.vertical, geometry.size.height * 0.03)
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.05) // 按鈕和使用次數卡片之間的間距
                        
                        // 使用次數和廣告按鈕卡片
                        VStack(spacing: geometry.size.height * 0.015) {
                            VStack(spacing: geometry.size.height * 0.01) {
                                Text("\(usageManager.remainingUses)")
                                    .font(.custom("NotoSansTC-Black", size: min(36, geometry.size.width * 0.09)))
                                    .foregroundColor(.customText)
                                    .bold()
                                
                                Text("剩餘使用次數")
                                    .font(.custom("NotoSansTC-Regular", size: min(16, geometry.size.width * 0.04)))
                                    .foregroundColor(.customText)
                            }
                            
                            Button(action: {
                                rewardedViewModel.showAd()
                            }) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text(rewardedViewModel.remainingCooldown > 0 
                                        ? "請等待 \(rewardedViewModel.remainingCooldown) 秒"
                                        : "觀看廣告獲得3次使用機會")
                                        .font(.custom("NotoSansTC-Regular", size: min(16, geometry.size.width * 0.04)))
                                }
                                .foregroundColor(.customText)
                                .padding(.vertical, geometry.size.height * 0.015)
                                .padding(.horizontal, geometry.size.width * 0.04)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(25)
                            }
                            .disabled(!rewardedViewModel.isAdLoaded || rewardedViewModel.remainingCooldown > 0)
                            .opacity(rewardedViewModel.isAdLoaded && rewardedViewModel.remainingCooldown == 0 ? 1 : 0.5)
                        }
                        .padding(.vertical, geometry.size.height * 0.02)
                        .padding(.horizontal, geometry.size.width * 0.04)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.5))
                        )
                        .padding(.horizontal, geometry.size.width * 0.04)
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.05) // Banner 廣告上方的間距
                    }
                }
            }
        }
        .background(
            Image("background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
        )
        .onAppear {
            // 檢查是否需要顯示雙重驗證提醒
            if UserDefaults.standard.bool(forKey: "shouldShowTwoFactorAlert") {
                showTwoFactorAlert = true
                UserDefaults.standard.set(false, forKey: "shouldShowTwoFactorAlert")
            }
        }
        .alert("提升帳號安全", isPresented: $showTwoFactorAlert) {
            Button("稍後再說") { }
            Button("前往設定") {
                selectedTab = 3  // 切換到設定頁面
                // 觸發雙重驗證按鈕
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    authViewModel.showPhoneVerification = true
                }
            }
        } message: {
            Text("建議您開啟雙重驗證以提升帳號安全性")
        }
    }

    private var settingsView: some View {
        VStack(spacing: 0) {
            // 頂部區域：頭像和招呼語
            HStack(alignment: .center, spacing: 12) {
                // 用戶頭像
                if let user = Auth.auth().currentUser, let photoURL = user.photoURL {
                    AsyncImage(url: photoURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.gray)
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.gray)
                }
                
                // 招呼語
                VStack(alignment: .leading, spacing: 4) {
                    Text("歡迎回來")
                        .font(.custom("NotoSansTC-Regular", size: 16))
                        .foregroundColor(.gray)
                    if let user = Auth.auth().currentUser {
                        Text(user.displayName ?? "使用者")
                            .font(.custom("NotoSansTC-Black", size: 20))
                            .foregroundColor(.customText)
                    }
                }
                
                Spacer()
                
                // 登出按鈕
                Button(action: logOut) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            // Main content area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Add Security section
                    if Auth.auth().currentUser?.isAnonymous == true {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("綁定帳號")
                                .font(.custom("NotoSansTC-Black", size: 20))
                                .foregroundColor(.customText)
                            
                            Button(action: {
                                showAccountLinkingOptions = true
                            }) {
                                SettingRow(
                                    icon: "person.badge.plus", 
                                    title: "綁定帳號",
                                    isLoading: isUpgrading
                                )
                            }
                            .disabled(isUpgrading)
                            .actionSheet(isPresented: $showAccountLinkingOptions) {
                                ActionSheet(
                                    title: Text("選擇綁定方式"),
                                    buttons: [
                                        .default(Text("使用 Google 帳號")) {
                                            isUpgrading = true
                                            upgradeWithGoogle()
                                        },
                                        .default(Text("使用 Apple 帳號")) {
                                            isUpgrading = true
                                            upgradeWithApple()
                                        },
                                        .cancel(Text("取消"))
                                    ]
                                )
                            }
                            .tint(.customAccent) // 使用 tint modifier 來設置整個 ActionSheet 的主題色
                        }
                        .padding(.horizontal)
                    }

                    else {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("安全")
                                .font(.custom("NotoSansTC-Black", size: 20))
                            .foregroundColor(.customText)
                        
                            Button(action: {
                                authViewModel.showPhoneVerification = true
                            }) {
                                SettingRow(icon: "lock.shield.fill", title: authViewModel.isTwoFactorAuthenticated ? "已雙重驗證" : "雙重驗證")
                            }
                                .opacity(authViewModel.isTwoFactorAuthenticated ? 0.6 : 1) // 如果已驗證則降低透明度
                                .disabled(authViewModel.isTwoFactorAuthenticated)
                        }
                        .padding(.horizontal)

                        // 新增任務中心區塊
                        // VStack(alignment: .leading, spacing: 15) {
                        //     Text("任務")
                        //         .font(.custom("NotoSansTC-Black", size: 20))
                        //         .foregroundColor(.customText)
                            
                        //     NavigationLink(destination: TaskListView()) {
                        //         SettingRow(
                        //             icon: "list.star",
                        //             title: "任務中心",
                        //             textColor: .customText,
                        //             badge: taskManager.tabBadgeCount > 0 ? "\(taskManager.tabBadgeCount)" : nil
                        //         )
                        //     }
                        // }
                        // .padding(.horizontal)
                    }
                    
                    
                    
                    // 資訊區域
                    VStack(alignment: .leading, spacing: 15) {
                        Text("資訊")
                            .font(.custom("NotoSansTC-Black", size: 20))
                            .foregroundColor(.customText)
                        
                        Button(action: {
                            if let url = URL(string: "https://moai.tw") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            SettingRow(icon: "info.circle.fill", title: "關於千尋")
                        }
                        
                        NavigationLink(destination: TermsAndPrivacyView()) {
                            SettingRow(icon: "doc.text.fill", title: "服務條款與隱私權")
                        }
                        
                        Button(action: {
                            if let url = URL(string: "https://moai.tw") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            SettingRow(icon: "envelope.fill", title: "聯絡我們")
                        }
                    }
                    .padding(.horizontal)
                    
                    // 在 settingsView 的 VStack 中，在最後一個區塊後添加：
                    VStack(alignment: .leading, spacing: 15) {
                        Text("帳號")
                            .font(.custom("NotoSansTC-Black", size: 20))
                            .foregroundColor(.customText)
                        
                        Button(action: {
                            showDeleteAccountAlert = true
                        }) {
                            SettingRow(
                                icon: "person.crop.circle.badge.minus",
                                title: "刪除帳號",
                                textColor: .red
                            )
                        }
                    }
                    .padding(.horizontal)
                    .alert("確認刪除帳號", isPresented: $showDeleteAccountAlert) {
                        Button("取消", role: .cancel) { }
                        Button("刪除", role: .destructive) {
                            deleteAccount()
                        }
                    } message: {
                        Text("此操作無法復原，您確定要永久刪除您的帳號嗎？")
                    }

                    
                }
                .padding(.horizontal)
                .padding(.bottom, GADAdSizeBanner.size.height + 45)
            }
        }
        // Add this sheet presentation after other .sheet modifiers in the settingsView
        .sheet(isPresented: $showSerialNumberInput) {
            SerialNumberInputView(isPresented: $showSerialNumberInput)
        }
        // Add sheet for phone verification
        .sheet(isPresented: $authViewModel.showPhoneVerification, onDismiss: {
            authViewModel.resetVerificationState()
        }) {
            NavigationView {
                VStack(spacing: 20) {
                    // Phone number input
                    CustomTextField(
                        placeholder: "請輸入手機號碼",
                        text: $authViewModel.phoneNumber,
                        keyboardType: .phonePad
                    )
                    .padding(.horizontal)
                    
                    if authViewModel.canResetPhoneNumber {
                        // 顯示重設手機號碼的選項
                        HStack {
                            Text("手機號碼輸入錯誤？")
                                .font(.custom("NotoSansTC-Regular", size: 14))
                                .foregroundColor(.gray)
                            
                            Button("重新輸入號碼") {
                                authViewModel.resetPhoneNumberInput()
                            }
                            .font(.custom("NotoSansTC-Regular", size: 14))
                            .foregroundColor(.customAccent)
                        }
                        .padding(.horizontal)
                    }
                    
                    if authViewModel.verificationID != nil {
                        // Verification code input
                        CustomTextField(
                            placeholder: "請輸入驗證碼",
                            text: $authViewModel.verificationCode,
                            keyboardType: .numberPad,
                            textContentType: .oneTimeCode  // 添加這行來支持自動填充簡訊驗證碼
                        )
                        .padding(.horizontal)
                        .onChange(of: authViewModel.verificationCode) { newValue in
                            // 當驗證碼改變時，檢查是否為從剪貼簿貼上的內容
                            if let pasteboardString = UIPasteboard.general.string,
                               pasteboardString.count == 6,  // 假設驗證碼為 6 位數
                               pasteboardString.allSatisfy({ $0.isNumber }) {
                                authViewModel.verificationCode = pasteboardString
                            }
                        }
                        
                        // Countdown timer and resend button
                        HStack {
                            if let remainingTime = authViewModel.remainingTime {
                                Text("驗證碼有效時間：\(remainingTime)秒")
                                    .font(.custom("NotoSansTC-Regular", size: 14))
                                    .foregroundColor(.gray)
                                
                                if remainingTime == 0 {
                                    Button("重新發送") {
                                        authViewModel.sendVerificationCode()
                                    }
                                    .font(.custom("NotoSansTC-Regular", size: 14))
                                    .foregroundColor(.customAccent)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Verify button with loading state
                        Button(action: {
                            authViewModel.verifyCode()
                        }) {
                            HStack {  // 添加 HStack 來確保內容橫向填滿
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("驗證")
                                }
                            }
                            .frame(maxWidth: .infinity)  // 將 frame 移到 HStack 上
                            .padding()
                            .background(authViewModel.isLoading ? Color.gray : Color.customAccent)
                            .foregroundColor(.white)
                            .cornerRadius(25)
                        }
                        .padding(.horizontal)
                        .disabled(authViewModel.isLoading)
                    } else {
                        // Send code button
                        Button(action: {
                            authViewModel.sendVerificationCode()
                        }) {
                            HStack {  // 添加 HStack 來確保內容橫向填滿
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(authViewModel.displayCooldownTime > 0 
                                        ? "請等待 \(authViewModel.displayCooldownTime) 秒"
                                        : "發送驗證碼")
                                }
                            }
                            .frame(maxWidth: .infinity)  // 將 frame 移到 HStack 上
                            .padding()
                            .background(
                                authViewModel.displayCooldownTime > 0 || authViewModel.isLoading 
                                    ? Color.gray 
                                    : Color.customAccent
                            )
                            .foregroundColor(.white)
                            .cornerRadius(25)
                        }
                        .padding(.horizontal)
                        .disabled(authViewModel.displayCooldownTime > 0 || authViewModel.isLoading)
                    }
                    
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.custom("NotoSansTC-Regular", size: 14))
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    Spacer()
                }
                .padding(.top)
                .navigationTitle("雙重驗證設定")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("取消") {
                    authViewModel.showPhoneVerification = false
                }
                .font(.custom("NotoSansTC-Regular", size: 16))
                )
                .onAppear {
                    authViewModel.resetVerificationState()
                }
            }
        }
        .overlay(
            Group {
                if showUpgradeError {
                    CustomAlertView(
                        title: "綁定失敗",
                        message: upgradeErrorMessage ?? "",
                        isPresented: $showUpgradeError
                    )
                }
            }
        )
        // Add this sheet presentation after other .sheet modifiers in the settingsView
        .sheet(isPresented: $showSerialNumberInput) {
            SerialNumberInputView(isPresented: $showSerialNumberInput)
        }
    }
    
    

    // 保持 SettingRow 結構體不變
    struct SettingRow: View {
        let icon: String
        let title: String
        var price: String? = nil
        var textColor: Color = .customText
        var isPurchasing: Bool = false
        var isLoading: Bool = false
        var badge: String? // 新增 badge 參數
        
        var body: some View {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.customAccent)
                }
                
                Text(isLoading ? "綁定中..." : title)
                    .font(.custom("NotoSansTC-Regular", size: 18))
                    .foregroundColor(textColor)
                
                Spacer()
                
                if isPurchasing {
                    ProgressView()
                } else if let price = price {
                    Text(price)
                        .foregroundColor(.customAccent)
                }
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.customAccent)
                        .clipShape(Capsule())
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
    }

    // 新增 Terms and Privacy View
    struct TermsAndPrivacyView: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("服務條款與隱私權政策")
                        .font(.custom("NotoSansTC-Black", size: 24))
                        .padding(.bottom, 10)
                    
                    Group {
                        Text("摩艾科技有限公司隱私權保護政策")
                            .font(.custom("NotoSansTC-Regular", size: 20))
                            .padding(.bottom, 5)
                        
                        Text("隱私權保護政策的內容")
                            .font(.custom("NotoSansTC-Regular", size: 18))
                        
                        Text("本隱私權政策說明摩艾科技有限公司(以下說明將以品牌名稱-『千尋命名』、『我們』或『我們的』簡稱)通過我們的應用程式及網站收集到的資訊，以及我們將如何使用這些資訊。我們非常重視您的隱私權。請您閱讀以下有關隱私權保護政策的更多內容。")
                            .padding(.bottom, 10)
                        
                        Group {
                            Text("我們使用您個人資料的方式")
                                .font(.custom("NotoSansTC-Regular", size: 18))
                            Text("本政策涵蓋的內容包括：摩艾科技如何處理蒐集或收到的個人資料 (包括與您過去使用我們的產品及服務相關的資料）。個人資料是指得以識別您的身分且未公開的資料，如姓名、地址、電子郵件地址或電話號碼。\n本隱私權保護政策只適用於摩艾科技")
                        }
                        
                        Group {
                            Text("資料蒐集及使用原則")
                                .font(.custom("NotoSansTC-Regular", size: 18))
                            Text("在您註冊摩艾科技所屬的官網、使用App相關產品、瀏覽我們的產品官網或某些合作夥伴的網頁，以及參加宣傳活動或贈獎活動時，摩艾科技會蒐集您的個人資料。摩艾科技也可能將商業夥伴或其他企業所提供的關於您的資訊與摩艾科技所擁有的您的個人資料相結合。\n\n當您在使用摩艾科技所提供的服務進會員註冊時，我們會詢問您的姓名、電子郵件地址、出生日期、性別及郵遞區號等資料。在您註冊摩艾科技的會員帳號並登入我們的服務後，我們就能辨別您的身分。您得自由選擇是否提供個人資料給我們，但若特定資料欄位係屬必填欄位者，您若不提供該等資料則無法使用相關的摩艾科技所提供產品及服務。")
                        }
                        
                        Group {
                            Text("其他技術收集資訊細節")
                                .font(.custom("NotoSansTC-Regular", size: 18))
                            Text("➤ 軟硬體相關資訊\n我們會收集裝置專屬資訊 (例如您的硬體型號、作業系統版本、裝置唯一的識別碼，以及包括電話號碼在內的行動網路資訊)。\n\n➤ 地理位置資訊\n當您使用APP服務時，我們會收集並處理您實際所在位置的相關資訊。我們會使用各種技術判斷您的所在位置，包括 IP 位址、GPS 和其他感應器。\n\n➤ 專屬應用程式編號\n某些服務所附的專屬應用程式編號；當您安裝或解除安裝這類服務，或是這類服務定期與我們的伺服器連線時，系統就會將這個編號以及安裝資訊傳送給摩艾科技。")
                        }
                        
                        Group {
                            Text("兒童線上隱私保護法案")
                                .font(.custom("NotoSansTC-Regular", size: 18))
                            Text("我們的所有兒童類APP及網站產品皆遵守兒童線上隱私保護條款the Children's Online Privacy Protection Act (『COPPA』)，我們不會收集任何未滿13歲兒童的個人資訊，如檢測到年齡小於13歲的相關資訊，我們將及時刪除，不會予以保留或儲存。")
                        }
                        
                        Group {
                            Text("聯繫我們")
                                .font(.custom("NotoSansTC-Regular", size: 18))
                            Text("如果您有關於本隱私權的任何問題或疑慮，請聯繫我們；我們會盡快回覆您：moai@moai.tw")
                                .padding(.bottom, 20)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitle("服務條款與隱私權", displayMode: .inline)
        }
    }

    private func logOut() {
        do {
            // Check if current user is anonymous
            if let user = Auth.auth().currentUser {
                if user.isAnonymous {
                    print("👤 Deleting anonymous user account")
                    // Delete user data from Firestore first
                    let db = Firestore.firestore()
                    db.collection("users").document(user.uid).delete { error in
                        if let error = error {
                            print("❌ Error deleting Firestore data: \(error.localizedDescription)")
                        } else {
                            print("✅ Firestore data deleted successfully")
                        }
                        
                        // Then delete the anonymous user account
                        user.delete { error in
                            if let error = error {
                                print("❌ Error deleting anonymous user: \(error.localizedDescription)")
                            } else {
                                print("✅ Anonymous user deleted successfully")
                            }
                        }
                    }
                }
            }

            try Auth.auth().signOut()
            // Reset UI state after logout
            authViewModel.isLoggedIn = false
            authViewModel.isTwoFactorAuthenticated = false
            selectedTab = 0
            navigationPath = NavigationPath()
            
        } catch let signOutError as NSError {
            print("❌ Error signing out: \(signOutError)")
        }
    }

    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        
        // 刪除 Firestore 中的用戶資料
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).delete { error in
            if let error = error {
                print("❌ 刪除 Firestore 資料失敗: \(error.localizedDescription)")
            }
        }
        
        // 刪除 Authentication 中的用戶
        user.delete { error in
            if let error = error as NSError? {
                // 處理需要重新驗證的情況
                if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                    print("⚠️ 需要重新驗證後才能刪除帳號")
                    // 可以在這裡添加重新驗證的邏輯
                    // 刪除成功，更新 UI
                    authViewModel.isLoggedIn = false
                    selectedTab = 0
                    navigationPath = NavigationPath()
                    return
                }
                print("❌ 刪除帳號失敗: \(error.localizedDescription)")
                return
            }
            
            // 刪除成功，更新 UI
            authViewModel.isLoggedIn = false
            selectedTab = 0
            navigationPath = NavigationPath()
        }
    }
    
    private func upgradeWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { 
            isUpgrading = false
            return 
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                print("❌ Google 綁定錯誤: \(error.localizedDescription)")
                isUpgrading = false
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            
            Auth.auth().currentUser?.link(with: credential) { [self] authResult, error in
                if let error = error as NSError? {
                    // 處理特定錯誤類型
                    let errorMessage: String
                    switch error.code {
                    case AuthErrorCode.emailAlreadyInUse.rawValue:
                        errorMessage = "此 Google 帳號已被使用，請使用其他帳號"
                    case AuthErrorCode.credentialAlreadyInUse.rawValue:
                        errorMessage = "此 Google 帳號已綁定其他帳號"
                    case AuthErrorCode.providerAlreadyLinked.rawValue:
                        errorMessage = "您已綁定 Google 帳號"
                    default:
                        errorMessage = error.localizedDescription
                    }
                    DispatchQueue.main.async {
                        isUpgrading = false
                        upgradeErrorMessage = errorMessage
                        showUpgradeError = true
                    }
                    return
                }
                
                // 更新用戶資料
                let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                changeRequest?.displayName = user.profile?.name
                changeRequest?.photoURL = user.profile?.imageURL(withDimension: 200)
                
                changeRequest?.commitChanges { error in
                    if let error = error {
                        print("❌ 更新用戶資料失敗: \(error.localizedDescription)")
                    } else {
                        print("✅ 用戶資料更新成功")
                    }
                    
                    print("✅ 帳號升級成功")
                    isUpgrading = false
                    // 觸發 UI 更新
                    authViewModel.handleSuccessfulLogin()
                }
            }
        }
    }
    
    private func upgradeWithApple() {
        isUpgrading = true
        appleSignInCoordinator = AppleSignInCoordinator()
        
        appleSignInCoordinator?.startSignInWithAppleFlow { result in
            defer {
                DispatchQueue.main.async {
                    isUpgrading = false
                }
            }
            
            switch result {
            case .success(_):
                self.handleSuccessfulUpgrade()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    if let authError = error as? NSError {
                        // Firebase Auth errors
                        switch authError.code {
                        case AuthErrorCode.emailAlreadyInUse.rawValue:
                            upgradeErrorMessage = "此 Apple 帳號已被使用，請使用其他帳號"
                        case AuthErrorCode.credentialAlreadyInUse.rawValue:
                            upgradeErrorMessage = "此 Apple 帳號已綁定其他帳號"
                        case AuthErrorCode.providerAlreadyLinked.rawValue:
                            upgradeErrorMessage = "您已綁定 Apple 帳號"
                        case AuthErrorCode.invalidCredential.rawValue:
                            upgradeErrorMessage = "無效的憑證"
                        case AuthErrorCode.operationNotAllowed.rawValue:
                            upgradeErrorMessage = "此操作不被允許"
                        case AuthErrorCode.tooManyRequests.rawValue:
                            upgradeErrorMessage = "請求次數過多，請稍後再試"
                        case AuthErrorCode.networkError.rawValue:
                            upgradeErrorMessage = "網路連線錯誤，請檢查網路狀態"
                        case AuthErrorCode.userDisabled.rawValue:
                            upgradeErrorMessage = "此帳號已被停用"
                        case AuthErrorCode.requiresRecentLogin.rawValue:
                            upgradeErrorMessage = "需要重新登入才能執行此操作"
                        default:
                            // 如果是 Apple Sign In 的錯誤
                            if let asError = error as? ASAuthorizationError {
                                switch asError.code {
                                case .canceled:
                                    upgradeErrorMessage = "使用者取消綁定"
                                case .invalidResponse:
                                    upgradeErrorMessage = "伺服器回應無效"
                                case .notHandled:
                                    upgradeErrorMessage = "無法處理此請求"
                                case .failed:
                                    upgradeErrorMessage = "綁定失敗"
                                default:
                                    upgradeErrorMessage = error.localizedDescription
                                }
                            } else {
                                upgradeErrorMessage = error.localizedDescription
                            }
                        }
                        self.showUpgradeError = true
                    }
                }
            }
        }
    }
    
    // 如果需要連結帳號的話，可以添加這個輔助方法
    private func linkAccount(with credential: AuthCredential) {
        guard let user = Auth.auth().currentUser else {
            print("❌ 無法連結帳號：未找到當前用戶")
            return
        }
        
        user.link(with: credential) { authResult, error in
            if let error = error {
                print("❌ 帳號連結失敗: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.upgradeErrorMessage = error.localizedDescription
                }
                return
            }
            
            print("✅ 帳號連結成功")
            // 可以在這裡添加其他成功后的處理邏輯
        }
    }

    // 在 upgradeWithGoogle 和 upgradeWithApple 方法成功后添加
    private func handleSuccessfulUpgrade() {
        isUpgrading = false
        
        // 轉移匿名用戶的使用次數
        UsageManager.shared.transferAnonymousUses()
        
        // 更新雲端資料
        Task {
            try? await UsageManager.shared.updateCloudData()
        }
        
        // 触发 UI 更新
        authViewModel.handleSuccessfulLogin()
        
        // 保存新的认证状态
        UserDefaults.standard.set(false, forKey: "isAnonymousUser")
    }
}

// authViewModel.isLoggedIn = false
// selectedTab = 0
// navigationPath = NavigationPath()

// Updated TabBarButton view
struct TabBarButton: View {
    let imageName: String
    let isSelected: Bool
    let action: () -> Void
    var badgeCount: Int? // 新增 badge 數量參數
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(isSelected ? .customAccent : .gray)
                
                // Badge View
                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.customAccent)
                        .clipShape(Capsule())
                        .offset(x: 12, y: -12)
                }
            }
        }
        .frame(width: 40, height: 40)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct FormView: View {
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int
    @Binding var isLoggedIn: Bool
    @ObservedObject var authViewModel: AuthViewModel
    @State private var surname = ""
    @State private var middleName = ""
    @State private var numberOfNames = 2
    @State private var isBorn = false
    @State private var birthDate = Date()
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var gender = "未知"
    @Environment(\.colorScheme) var colorScheme
    
    // 2. 修改初始化方法以匹配調用
    init(navigationPath: Binding<NavigationPath>,
         selectedTab: Binding<Int>,
         isLoggedIn: Binding<Bool>,
         authViewModel: AuthViewModel) {
        self._navigationPath = navigationPath
        self._selectedTab = selectedTab
        self._isLoggedIn = isLoggedIn
        self.authViewModel = authViewModel
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Add tap gesture to the background
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                    }
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: -10) {
                            FormHeaderView()
                            FormFieldsView(
                                surname: $surname,
                                middleName: $middleName,
                                numberOfNames: $numberOfNames,
                                gender: $gender,
                                isBorn: $isBorn,
                                birthDate: $birthDate
                            )
                        }
                    }
                    
                    BottomButtonView(action: validateAndProceed)
                }
            }
            .background(
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)
            )
            .navigationBarSetup(navigationPath: $navigationPath)
            .alert("提示", isPresented: $showAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                      to: nil, from: nil, for: nil)
    }
    
    private func validateAndProceed() {
        // Validate all required fields
        if surname.isEmpty {
            alertMessage = "請輸入姓氏"
            showAlert = true
        } else if surname.count > 2 {
            alertMessage = "姓氏不能超過兩個字"
            showAlert = true
        } else if middleName.count > 1 {
            alertMessage = "中間字不能超過一個字"
            showAlert = true
        } else {
            let formData = FormData(surname: surname, middleName: middleName, numberOfNames: numberOfNames, isBorn: isBorn, birthDate: birthDate, gender: gender)
            withAnimation(nil) {
                navigationPath.append(formData)
            }
        }
    }
}

// Header View
private struct FormHeaderView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("login_mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
            
            VStack(alignment: .leading) {
                Text("送給孩子的第一份禮物\n就是為孩子取名字！")
                    .font(.custom("NotoSansTC-Regular", size: 18))
                    .foregroundColor(.black)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(15)
                    .overlay(
                        Triangle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .rotationEffect(.degrees(-90))
                            .offset(x: -15, y: 10)
                        , alignment: .topLeading
                    )
            }
        }
        .padding()
    }
}

// Form Fields View
private struct FormFieldsView: View {
    @Binding var surname: String
    @Binding var middleName: String
    @Binding var numberOfNames: Int
    @Binding var gender: String
    @Binding var isBorn: Bool
    @Binding var birthDate: Date
    @State private var showMiddleNameAlert = false
    
    var body: some View {
        VStack(spacing: 15) {
            // Add required field indicator for surname
            VStack(alignment: .leading, spacing: 5) {
                CustomTextField(
                    placeholder: "姓氏（必填）", 
                    text: $surname
                )
            }
            
            // Add optional field indicator for middle name
            CustomTextField(
                placeholder: numberOfNames == 1 ? "單名不得設定中間字" : "指定中間字（選填）", 
                text: $middleName
            )
            .disabled(numberOfNames == 1)
            .onChange(of: numberOfNames) { newValue in
                if newValue == 1 && !middleName.isEmpty {
                    showMiddleNameAlert = true
                    middleName = ""  // 清空中間字
                }
            }
            .alert(isPresented: $showMiddleNameAlert) {
                Alert(
                    title: Text("提示"),
                    message: Text("單名不得設定中間字"),
                    dismissButton: .default(Text("確定"))
                )
            }
            
            NameCountSelector(numberOfNames: $numberOfNames)
            GenderSelector(gender: $gender)
            BirthInfoView(isBorn: $isBorn, birthDate: $birthDate)
        }
        .padding()
    }
}

// Name Count Selector
private struct NameCountSelector: View {
    @Binding var numberOfNames: Int
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: { 
                hideKeyboard()
                numberOfNames = 1 
            }) {
                Text("單名")
                    .foregroundColor(numberOfNames == 1 ? .white : Color(hex: "#FF798C"))
                    .frame(width: 100)
                    .padding(.vertical, 10)
                    .background(numberOfNames == 1 ? Color(hex: "#FF798C") : Color(hex: "#FFE5E9"))
            }
            Button(action: { 
                hideKeyboard()
                numberOfNames = 2 
            }) {
                Text("雙名")
                    .foregroundColor(numberOfNames == 2 ? .white : Color(hex: "#FF798C"))
                    .frame(width: 100)
                    .padding(.vertical, 10)
                    .background(numberOfNames == 2 ? Color(hex: "#FF798C") : Color(hex: "#FFE5E9"))
            }
        }
        .background(Color(hex: "#FFE5E9"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "#FF798C"), lineWidth: 1)
        )
    }
}

// Gender Selector
private struct GenderSelector: View {
    @Binding var gender: String
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["男", "女", "未知"], id: \.self) { option in
                Button(action: { 
                    hideKeyboard()
                    gender = option 
                }) {
                    Text(option)
                        .foregroundColor(gender == option ? .white : Color(hex: "#FF798C"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(gender == option ? Color(hex: "#FF798C") : Color(hex: "#FFE5E9"))
                }
            }
        }
        .background(Color(hex: "#FFE5E9"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "#FF798C"), lineWidth: 1)
        )
    }
}

// Birth Info View
private struct BirthInfoView: View {
    @Binding var isBorn: Bool
    @Binding var birthDate: Date
    
    var body: some View {
        VStack(spacing: 15) {
            Toggle("未/已出生", isOn: $isBorn)
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(25)
                .toggleStyle(CustomToggleStyle(onColor: Color(hex: "#FF798C")))
                .onTapGesture {
                    hideKeyboard()
                }
            
            if isBorn {
                DatePicker(
                    "出生日期",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .padding()
                .background(Color.white)
                .cornerRadius(25)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color(hex: "#FF798C"), lineWidth: 1)
                )
                .onTapGesture {
                    hideKeyboard()
                }
            }
        }
    }
}

// Bottom Button View
private struct BottomButtonView: View {
    let action: () -> Void
    
    var body: some View {
        VStack {
            Button(action: {
                hideKeyboard()
                action()
            }) {
                Text("下一步")
                    .font(.custom("NotoSansTC-Black", size: 18))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#FF798C"))
                    .cornerRadius(25)
            }
            .padding()
        }
        .background(Color.clear) // 改為透明背景
        .ignoresSafeArea(.keyboard)
    }
}

// Navigation Bar Setup
extension View {
    func navigationBarSetup(navigationPath: Binding<NavigationPath>) -> some View {
        self
            .navigationBarTitle("資料填寫", displayMode: .inline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        navigationPath.wrappedValue.removeLast()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("資料填寫")
                        .font(.custom("NotoSansTC-Black", size: 20))
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(
                Color.pink.frame(height: 5)
                    .edgesIgnoringSafeArea(.horizontal)
                    .offset(y: 0)
                , alignment: .top
            )
    }
}

struct FormData: Hashable {
    let surname: String
    let middleName: String
    let numberOfNames: Int
    let isBorn: Bool
    let birthDate: Date
    let gender: String
}

struct DialogView: View {
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int  // 新增這行
    let formData: FormData
    @State private var questions: [Question] = []
    @State private var currentQuestionIndex = 0
    @State private var answers: [String] = []
    @State private var isGeneratingName = false
    @State private var generatedName: String?
    @State private var nameAnalysis: [String: String]?
    @State private var wuxing: [String]?
    @Environment(\.colorScheme) var colorScheme
    @State private var errorMessage: String?
    // Add state variable
    @State private var shouldDismissOnTap = false
    
    private let usageManager = UsageManager.shared
    
    // Add a state to track if generation is in progress
    @State private var isGenerating = false
    
    // 修改初始化方法
    init(navigationPath: Binding<NavigationPath>,
         selectedTab: Binding<Int>,  // 新增這行
         formData: FormData) {
        self._navigationPath = navigationPath
        self._selectedTab = selectedTab  // 新增這行
        self.formData = formData
    }
    
    var body: some View {
        ZStack {
            // Color(hex: "#FFF0F5") // Light pink background
            //     .edgesIgnoringSafeArea(.all)

            if isGeneratingName {
                // LoadingView()
                VStack {
                    ProgressView("生成時間約三十秒")
                        .scaleEffect(1.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("生成名字失敗")
                        .font(.custom("NotoSansTC-Black", size: 24))
                        .foregroundColor(.red)
                        .padding()
                
                    Text(errorMessage)
                        .font(.custom("NotoSansTC-Regular", size: 18))
                        .foregroundColor(.customText)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    // Only show retry button if user has remaining uses
                    if usageManager.remainingUses > 0 {
                        Button("重試") {
                            self.errorMessage = nil
                            generateName()  // This will deduct another point
                        }
                        .font(.custom("NotoSansTC-Regular", size: 18))
                        .foregroundColor(.white)
                        .padding()
                        .background(.customAccent)
                        .cornerRadius(10)
                        .onAppear { shouldDismissOnTap = false }
                    } else {
                        Text("您的使用次數已用完，請觀看廣告獲取更多次數。")
                            .font(.custom("NotoSansTC-Regular", size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Button(action: {
                            navigationPath.removeLast(navigationPath.count)
                        }) {
                            Text("回到首頁")
                                .font(.custom("NotoSansTC-Regular", size: 16))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .background(.customAccent)
                        .cornerRadius(10)
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if shouldDismissOnTap {
                        navigationPath.removeLast(navigationPath.count)
                    }
                }
            } else if let generatedName = generatedName, let nameAnalysis = nameAnalysis, let wuxing = wuxing {
                NameAnalysisView(
                    name: generatedName,
                    analysis: nameAnalysis,
                    wuxing: wuxing,
                    navigationPath: $navigationPath,
                    selectedTab: $selectedTab,  // 使用傳入的 selectedTab
                    regenerateAction: generateName,
                    showButtons: true
                )
            } else {
                VStack(spacing: -10) {
                    if !questions.isEmpty {
                        VStack(spacing: 10) {
                            HStack(alignment: .center, spacing: 10) {
                                Image("main_mascot")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    
                                // Question progress indicators
                                HStack(spacing: 8) {
                                    ForEach(0..<questions.count, id: \.self) { index in
                                        Button(action: {
                                            currentQuestionIndex = index
                                        }) {
                                            Text("\(index + 1)")
                                                .font(.custom("NotoSansTC-Black", size: 16))
                                                .foregroundColor(index == currentQuestionIndex ? .white : .customAccent)
                                                .frame(width: 30, height: 30)
                                                .background(
                                                    Circle()
                                                        .fill(index == currentQuestionIndex ? Color.customAccent : Color.white)
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.customAccent, lineWidth: 1)
                                                )
                                        }
                                        .disabled(index > answers.count) // 只能選擇已回答過的題目或下一題
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.7))
                                .cornerRadius(10)

                                Spacer()
                            }

                            Text(questions[currentQuestionIndex].question)
                                .font(.custom("NotoSansTC-Regular", size: 16))
                                .foregroundColor(.customText)
                                .multilineTextAlignment(.leading)
                                .padding()
                                .background(Color.white.opacity(0.7))
                                .cornerRadius(10)
                        }
                        .padding()

                        Spacer()

                        // Choices
                        VStack(spacing: 15) {
                            ForEach(questions[currentQuestionIndex].choices, id: \.self) { choice in
                                Button(action: {
                                    handleAnswer(choice.text)
                                }) {
                                    Text(choice.text)
                                        .font(.custom("NotoSansTC-Black", size: 16))
                                        .foregroundColor(.customText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                        .padding()
                                        .background(
                                            answers.count > currentQuestionIndex && 
                                            answers[currentQuestionIndex] == choice.text ? 
                                                Color.customAccent.opacity(0.2) : Color.white
                                        )
                                        .cornerRadius(20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.customAccent, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding()

                        Spacer()
                        
                        // Navigation buttons
                        HStack {
                            if currentQuestionIndex > 0 {
                                Button("上一題") {
                                    currentQuestionIndex -= 1
                                }
                                .buttonStyle(NavigationButtonStyle())
                            }
                            
                            Spacer()
                            
                            if answers.count == questions.count {
                                Button("完成") {
                                    generateName()
                                }
                                .buttonStyle(NavigationButtonStyle(isPrimary: true))
                            } else if currentQuestionIndex < questions.count - 1 {
                                Button("下一題") {
                                    currentQuestionIndex += 1
                                }
                                .buttonStyle(NavigationButtonStyle())
                                .disabled(answers.count <= currentQuestionIndex)
                            }
                        }
                        .padding()
                    }
                    else {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            
                            Text("無法載入問題")
                                .font(.custom("NotoSansTC-Black", size: 20))
                                .foregroundColor(.customText)
                            
                            Text("請檢查網路連線後重試")
                                .font(.custom("NotoSansTC-Regular", size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitle("心靈對話", displayMode: .inline)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    navigationPath.removeLast()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
            }
            ToolbarItem(placement: .principal) {
                Text(isGeneratingName ? "生成名字中" : (generatedName != nil ? "名字分析" : "心靈對話"))
                    .font(.custom("NotoSansTC-Black", size: 20))
                    .foregroundColor(.white)
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(
            Color.pink.frame(height: 5)
                .edgesIgnoringSafeArea(.horizontal)
                .offset(y: 0) // Adjust this value if needed to position the line correctly
            , alignment: .top
        )
        .onAppear(perform: loadQuestions)
        .background(
            Image("background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
        )
    }

    
    private func loadQuestions() {
        // Clear previous answers
        answers.removeAll()
        
        // Get questions from local cache
        questions = QuestionManager.shared.getRandomQuestions(5)
    }
    
    private func generateName() {
        // Add a guard to prevent multiple generations
        let monitor = PerformanceMonitor.shared
        monitor.reset()
        monitor.start("Total Generation Time")
        
        guard !isGenerating else { return }
        
        print("\n=== 開始生成名字流程 ===")
        monitor.start("Usage Check")
        print("📱 [Generate] 開始生成名字請求")
        print("📊 [Uses] 生成前剩餘次數: \(usageManager.remainingUses)")
        
        // Check remaining uses before generating
        if usageManager.remainingUses <= 0 {
            monitor.end("Usage Check")
            print("❌ [Generate] 使用次數不足，無法生成")
            errorMessage = "很抱歉，您的免費使用次數已用完。"
            return
        }
        monitor.end("Usage Check")
        
        // Set generating flag
        isGenerating = true
        
        // Deduct one use
        usageManager.remainingUses -= 1
        print("📊 [Uses] 扣除一次使用機會")
        print("📊 [Uses] 當前剩餘次數: \(usageManager.remainingUses)")

        // 更新雲端資料
        Task {
            try? await usageManager.updateCloudData()
        }
        
        monitor.start("UI Update - Loading")
        isGeneratingName = true
        errorMessage = nil
        monitor.end("UI Update - Loading")

        // Prepare the prompt for the AI model
        monitor.start("Prompt Preparation")
        let prompt = preparePrompt()
        monitor.end("Prompt Preparation")

        // Call the OpenAI API to generate the name
        Task {
            do {
                print("🤖 [API] 開始調用 OpenAI API")
                monitor.start("API Call")
                print("📝 [Prompt] 調用 OpenAI API 的 prompt: \(prompt)")
                let (name, analysis, wuxing) = try await callOpenAIAPI(with: prompt)
                monitor.end("API Call")
                print("✅ [API] API 調用成功")
                print("📝 [Result] 生成的名字: \(name)")
                
                await MainActor.run {
                    monitor.start("UI Update - Results")
                    self.generatedName = name
                    self.nameAnalysis = analysis
                    self.wuxing = wuxing
                    self.isGeneratingName = false
                    self.isGenerating = false
                    monitor.end("UI Update - Results")
                    
                    print("✅ [Generate] 字生成流程完成")
                    monitor.end("Total Generation Time")
                    monitor.printSummary()
                    print("=== 生成名字流程結束 ===\n")
                }
            } catch {
                await MainActor.run {
                    monitor.start("Error Handling")
                    self.isGeneratingName = false
                    self.isGenerating = false
                    if let nsError = error as NSError? {
                        self.errorMessage = "生成名字時發生錯誤：\(nsError.localizedDescription)"
                    } else {
                        self.errorMessage = "生成名字時發生未知錯誤。請稍後再試。"
                    }
                    monitor.end("Error Handling")
                    
                    print("❌ [Generate] 名字生成流程失敗")
                    monitor.end("Total Generation Time")
                    monitor.printSummary()
                    print("=== 生成名字流程結束 ===\n")
                }
            }
        }
    }
    
    private func preparePrompt() -> String {
        let formData = """
        姓氏: \(formData.surname)
        指定中間字: \(formData.middleName)
        單/雙名: \(formData.numberOfNames == 1 ? "單名" : "雙名")
        性別: \(formData.gender)
        """
        
        let meaningString: String
        do {
            print("📝 [Meanings] 開始處理回答意義")
            meaningString = try answers.enumerated().map { index, answer in
                guard index < questions.count,
                      let selectedChoice = questions[index].choices.first(where: { $0.text == answer }) else {
                    throw NSError(domain: "MeaningMapping", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法找到對應的意義"])
                }
                return """
                期許\(index + 1): \(selectedChoice.meaning)
                """
            }.joined(separator: "\n\n")
        } catch {
            print("Error mapping meanings: \(error)")
            meaningString = "Error processing meanings"
        }

        // 使用 PromptManager 獲取模板
        let template = PromptManager.shared.getNameGenerationPrompt()

        print("🔄 [Prompts] 使用 PromptManager 獲取模板: \(template)")
        
        // 將資料填入模板
        return template
            .replacingOccurrences(of: "{{formData}}", with: formData)
            .replacingOccurrences(of: "{{meaningString}}", with: meaningString)
    }

    // 1. 首先定義所需的 JSON Schema
    private func createNameGenerationSchema() -> JSONSchema {
        // 情境分析的 Schema
        let situationalAnalysisSchema = JSONSchema(
            type: .object,
            properties: [
                "question": JSONSchema(type: .string),
                "answer": JSONSchema(type: .string),
                "analysis": JSONSchema(type: .string)
            ],
            required: ["question", "answer", "analysis"],
            additionalProperties: false
        )

        // 典故分析的 Schema
        let literaryAllusionSchema = JSONSchema(
            type: .object,
            properties: [
                "source": JSONSchema(type: .string),
                "original_text": JSONSchema(type: .string),
                "interpretation": JSONSchema(type: .string),
                "connection": JSONSchema(type: .string)
            ],
            required: ["source", "original_text", "interpretation", "connection"],
            additionalProperties: false
        )

        // 分析的 Schema
        let analysisSchema = JSONSchema(
            type: .object,
            properties: [
                "character_meaning": JSONSchema(type: .string),
                "literary_allusion": literaryAllusionSchema,
                "situational_analysis": JSONSchema(
                    type: .object,
                    properties: [
                        "1": situationalAnalysisSchema,
                        "2": situationalAnalysisSchema,
                        "3": situationalAnalysisSchema,
                        "4": situationalAnalysisSchema,
                        "5": situationalAnalysisSchema
                    ],
                    required: ["1", "2", "3", "4", "5"],
                    additionalProperties: false
                )
            ],
            required: ["character_meaning", "literary_allusion", "situational_analysis"],
            additionalProperties: false
        )

        // 完整的回應 Schema
        return JSONSchema(
            type: .object,
            properties: [
                "name": JSONSchema(type: .string),
                "analysis": analysisSchema
            ],
            required: ["name", "analysis"],
            additionalProperties: false
        )
    }

    // 2. 修改 API 調用函數
    private func callOpenAIAPI(with prompt: String) async throws -> (String, [String: String], [String]) {
        let monitor = PerformanceMonitor.shared
        
        monitor.start("API Setup")
        let apiKey = APIConfig.openAIKey
        let service = OpenAIServiceFactory.service(apiKey: apiKey)
        monitor.end("API Setup")

        // 1. 定義情境分析的 Schema
        let situationalAnalysisSchema = JSONSchema(
            type: .object,
            properties: [
                "question": JSONSchema(type: .string),
                "answer": JSONSchema(type: .string),
                "analysis": JSONSchema(type: .string)
            ],
            required: ["question", "answer", "analysis"],
            additionalProperties: false
        )

        // 2. 定義典故分析的 Schema
        let literaryAllusionSchema = JSONSchema(
            type: .object,
            properties: [
                "source": JSONSchema(type: .string),
                "original_text": JSONSchema(type: .string),
                "interpretation": JSONSchema(type: .string),
                "connection": JSONSchema(type: .string)
            ],
            required: ["source", "original_text", "interpretation", "connection"],
            additionalProperties: false
        )

        // 3. 定義分析的 Schema
        let analysisSchema = JSONSchema(
            type: .object,
            properties: [
                "character_meaning": JSONSchema(type: .string),
                "literary_allusion": literaryAllusionSchema,
                "situational_analysis": JSONSchema(
                    type: .object,
                    properties: [
                        "1": situationalAnalysisSchema,
                        "2": situationalAnalysisSchema,
                        "3": situationalAnalysisSchema,
                        "4": situationalAnalysisSchema,
                        "5": situationalAnalysisSchema
                    ],
                    required: ["1", "2", "3", "4", "5"],
                    additionalProperties: false
                )
            ],
            required: ["character_meaning", "literary_allusion", "situational_analysis"],
            additionalProperties: false
        )

        // 4. 定義回應格式的 Schema
        let responseFormatSchema = JSONSchemaResponseFormat(
            name: "name_generation",
            strict: true,
            schema: JSONSchema(
                type: .object,
                properties: [
                    "name": JSONSchema(type: .string),
                    "analysis": analysisSchema
                ],
                required: ["name", "analysis"],
                additionalProperties: false
            )
        )

        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text("""
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
                """)),
            .init(role: .user, content: .text(prompt))
        ]

        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .gpt4omini,
            responseFormat: .jsonSchema(responseFormatSchema)
        )

        monitor.start("API Request Preparation")
        let completionObject = try await service.startChat(parameters: parameters)
        monitor.end("API Request Preparation")
        
        monitor.start("Response Processing")
        guard let jsonString = completionObject.choices.first?.message.content,
              let jsonData = jsonString.data(using: .utf8) else {
            ErrorManager.shared.logError(
                category: .aiResponseMalformedJSON,
                message: "Invalid AI response format",
                details: [
                    "prompt": prompt,
                    "response": completionObject.choices.first?.message.content ?? "No content"
                ]
            )
            throw NSError(domain: "OpenAIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        do {
            let jsonResult = try JSONDecoder().decode(NameGenerationResult.self, from: jsonData)
            
            // 獲取五行屬性
            let elements = jsonResult.name.map { char in
                CharacterManager.shared.getElement(for: String(char))
            }
            
            // 構建分析字典
            let analysisDict: [String: String] = [
                "字義分析": jsonResult.analysis.character_meaning,
                "典故分析": """
                    出處：\(jsonResult.analysis.literary_allusion.source)
                    原文：\(jsonResult.analysis.literary_allusion.original_text)
                    釋義：\(jsonResult.analysis.literary_allusion.interpretation)
                    連結：\(jsonResult.analysis.literary_allusion.connection)
                    """,
                "情境分析": zip(questions, answers).enumerated().map { index, qa in
                    let analysis = switch index {
                        case 0: jsonResult.analysis.situational_analysis.one.analysis
                        case 1: jsonResult.analysis.situational_analysis.two.analysis
                        case 2: jsonResult.analysis.situational_analysis.three.analysis
                        case 3: jsonResult.analysis.situational_analysis.four.analysis
                        case 4: jsonResult.analysis.situational_analysis.five.analysis
                        default: "分析資料缺失"
                    }
                    return "Q\(index + 1)：\(qa.0.question)\nA：\(qa.1)\n→ \(analysis)"
                }.joined(separator: "\n\n")
            ]


            monitor.end("Response Processing")
            
            // Add character count validation
            let expectedCharCount = formData.numberOfNames
            let actualCharCount = jsonResult.name.count - formData.surname.count
            if actualCharCount != expectedCharCount {
                ErrorManager.shared.logError(
                    category: .aiResponseWrongCharacterCount,
                    message: "生成名字字數錯誤",
                    details: [
                        "expected_count": "\(expectedCharCount)",
                        "actual_count": "\(actualCharCount)",
                        "generated_name": jsonResult.name,
                        "surname": formData.surname
                    ]
                )
                // throw NSError(
                //     domain: "NameGeneration",
                //     code: 1001,
                //     userInfo: [NSLocalizedDescriptionKey: "生成的名字字數不符合要求，請重試"]
                // )
            }
            
            return (jsonResult.name, analysisDict, elements)
        } catch let decodingError as DecodingError {
            // JSON 解析錯誤
            ErrorManager.shared.logError(
                category: .aiResponseMalformedJSON,
                message: "Failed to decode AI response",
                details: [
                    "error": decodingError.localizedDescription,
                    "json": String(data: jsonData, encoding: .utf8) ?? "Invalid JSON"
                ]
            )
            throw decodingError
            
        } catch let networkError as URLError {
            // 網路相關錯誤
            let category: ErrorCategory = {
                switch networkError.code {
                case .timedOut:
                    return .apiCallTimeout
                case .notConnectedToInternet:
                    return .apiCallNetworkError
                default:
                    return .apiCallNetworkError
                }
            }()
            
            ErrorManager.shared.logError(
                category: category,
                message: "API network error",
                details: [
                    "error_code": "\(networkError.code.rawValue)",
                    "error_description": networkError.localizedDescription
                ]
            )
            throw networkError
            
        } catch {
            // 其他未預期的錯誤
            ErrorManager.shared.logError(
                category: .unknown,
                message: "Unexpected error in AI response handling",
                details: [
                    "error": error.localizedDescription,
                    "prompt": prompt
                ]
            )
            throw error
        }
    }
    
    private func handleAnswer(_ answer: String) {
        if answers.count > currentQuestionIndex {
            // 更新現有答案
            answers[currentQuestionIndex] = answer
        } else {
            // 添加新答案
            answers.append(answer)
        }
        
        // 如果不是最後一題，自動前進到下一題
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
        }
    }
}

// 更新 NameGenerationResult 結構體
struct NameGenerationResult: Codable {
    let name: String
    let analysis: Analysis
}

struct Analysis: Codable {
    let character_meaning: String
    let literary_allusion: LiteraryAllusion
    let situational_analysis: SituationalAnalysisMap
}

struct LiteraryAllusion: Codable {
    let source: String
    let original_text: String
    let interpretation: String
    let connection: String
}

struct SituationalAnalysis: Codable {
    let analysis: String  // 只需要分析部分
}

// New type to represent the object structure
struct SituationalAnalysisMap: Codable {
    let one: SituationalAnalysis
    let two: SituationalAnalysis
    let three: SituationalAnalysis
    let four: SituationalAnalysis
    let five: SituationalAnalysis
    
    private enum CodingKeys: String, CodingKey {
        case one = "1"
        case two = "2"
        case three = "3"
        case four = "4"
        case five = "5"
    }
}

// Add this struct at the end of the file
struct Config {
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

struct FavoriteNameData: Codable {
    let name: String
    let analysis: [String: String]
    let wuxing: [String]
}

struct NameAnalysisView: View {
    let name: String
    let analysis: [String: String]
    let wuxing: [String]
    let regenerateAction: () -> Void
    @Binding var selectedTab: Int  // 新增這行
    let showButtons: Bool
    @State private var isFavorite: Bool = false
    @Binding var navigationPath: NavigationPath
    @State private var showSaveFavoriteAlert = false
    @State private var showRegenerateAlert  = false
    @State private var showAccountLinkingOptions = false
    @Environment(\.colorScheme) var colorScheme
    @State private var isRegenerating = false
    @AppStorage("remainingUses") private var remainingUses = 3
    @State private var showInsufficientUsesAlert = false
    @StateObject private var interstitialAd = InterstitialAdViewModel()
    @State private var hasShownReviewRequest = false
    private let usageManager = UsageManager.shared
    @AppStorage("returnHomeCount") private var returnHomeCount = 0
    @State private var showTwoFactorAlert = false
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var showAccountLinkingSheet = false
    @State private var isUpgrading = false
    @State private var upgradeErrorMessage: String?
    @State private var showUpgradeError = false
    // add a boolean if the buttons below is shown
     
    // 在 NameAnalysisView 結構體內添加
    private enum SelectedButton {
        case favorite
        case regenerate
    }

    @State private var selectedButton: SelectedButton = .favorite
    
    // 修改初始化方法
    init(name: String, 
         analysis: [String: String], 
         wuxing: [String], 
         navigationPath: Binding<NavigationPath>,
         selectedTab: Binding<Int>,  // 新增這行
         regenerateAction: @escaping () -> Void,
         showButtons: Bool) {
        self.name = name
        self.analysis = analysis
        self.wuxing = wuxing
        self._navigationPath = navigationPath
        self._selectedTab = selectedTab  // 新增這行
        self.regenerateAction = regenerateAction
        self.showButtons = showButtons
    }
    
    var body: some View {
        mainScrollView
            .background(Color.customBackground)
            .navigationBarTitle("名字分析", displayMode: .inline)
            .onAppear(perform: checkFavoriteStatus)
            .overlay(loadingOverlay)
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    // Break down into smaller components
    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 20) {
                nameCard
                    .padding(.horizontal)
                
                analysisSection
                    .padding(.horizontal)
                
                if showButtons {  // Changed from _showButtons to showButtons
                    actionButtons
                        .padding(.horizontal)
                        .padding(.bottom, GADAdSizeBanner.size.height + 20)
                }
            }
        }
        .overlay(
            Group {
                if showUpgradeError {
                    CustomAlertView(
                        title: "綁定失敗",
                        message: upgradeErrorMessage ?? "",
                        isPresented: $showUpgradeError
                    )
                }
            }
        )
    }



    private var analysisSection: some View {
        VStack(spacing: 20) {
            characterAnalysisCard
                .frame(maxWidth: .infinity)
            literaryAllusionCard
                .frame(maxWidth: .infinity)
            situationalAnalysisCard
                .frame(maxWidth: .infinity)
        }
    }

    private var characterAnalysisCard: some View {
        AnalysisCard(title: "字義") {
            analysisContent(for: "字義分析")
                .frame(maxWidth: .infinity)
        }
    }

    private var literaryAllusionCard: some View {
        AnalysisCard(title: "典故") {
            analysisContent(for: "典故分析")
                .frame(maxWidth: .infinity)
        }
    }

    private var situationalAnalysisCard: some View {
        AnalysisCard(title: "情境契合度") {
            if let situationalContent = analysis["情境分析"] {
                situationalAnalysisContent(content: situationalContent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func analysisContent(for key: String) -> some View {
        Group {
            if let analysisContent = analysis[key] {
                let lines = analysisContent.split(separator: "\n")
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.custom("NotoSansTC-Regular", size: 20))
                        .foregroundColor(.customText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func situationalAnalysisContent(content: String) -> some View {
        let questionsArray = content.split(separator: "Q")
        return ForEach(questionsArray.indices, id: \.self) { index in
            if index >= 0 {
                VStack {
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 10)
                    }
                    SituationalQuestionView(question: "Q" + questionsArray[index])
                }
            }
        }
    }

    private var loadingOverlay: some View {
        Group {
            if isRegenerating {
                VStack(spacing: 15) {
                    ProgressView("生成名字中（約30秒）...")
                        .scaleEffect(1.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
            }
        }
    }

    private var nameCard: some View {
        VStack(spacing: 10) {
            Text("為您生成的名字")
                .font(.custom("NotoSansTC-Black", size: 18))
                .foregroundColor(.customText)
            
            HStack(spacing: 20) {
                let nameCharacters = name.map { String($0) }
                
                // Display each character with its wuxing element
                ForEach(0..<nameCharacters.count, id: \.self) { index in
                    VStack {
                        Text(nameCharacters[index])
                            .font(.custom("NotoSansTC-Black", size: calculateFontSize(for: nameCharacters.count)))
                            .foregroundColor(.customText)
                        
                        // Add wuxing element icon and text
                        if index < wuxing.count {
                            HStack(spacing: 5) {
                                Image(systemName: wuxingIcon(for: wuxing[index]))
                                    .foregroundColor(wuxingColor(for: wuxing[index]))
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.customSecondary)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    )
                }
            }
        }
    }
    
    private func AnalysisCard<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.custom("NotoSansTC-Black", size: 22))
                .foregroundColor(.customText)
            
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.customSecondary)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    private var actionButtons: some View {
        VStack(spacing: 15) {
            Button(action: {
                if Auth.auth().currentUser?.isAnonymous == true {
                    selectedButton = .favorite
                    showAccountLinkingSheet = true
                } else {
                    toggleFavorite()
                }
            }) {
                HStack {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                    Text(isFavorite ? "已收藏" : "收藏")
                }
                .font(.custom("NotoSansTC-Black", size: 18))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isFavorite ? Color.gray : Color.customAccent)
                .cornerRadius(10)
            }

            
            Button(action: {
                if Auth.auth().currentUser?.isAnonymous == true {
                    selectedButton = .regenerate
                    showAccountLinkingSheet = true
                } else {
                    if remainingUses > 0 {
                        regenerateName()
                    } else {
                        showInsufficientUsesAlert = true
                    }
                }
            }) {
                Text("重新生成")
                    .font(.custom("NotoSansTC-Black", size: 18))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.customAccent)
                    .cornerRadius(10)
            }
            .alert(isPresented: $showInsufficientUsesAlert) {
                Alert(
                    title: Text("使用次數不足"),
                    message: Text("很抱歉，您的免費使用次數已用完。請觀看廣告獲取更多次數。"),
                    dismissButton: .default(Text("確定"))
                )
            }
            
            Button(action: {
                returnHomeCount += 1
                if returnHomeCount >= 3 {
                    interstitialAd.showAd()
                    returnHomeCount = 0  // 重置計數
                }
                
                // 檢查是否已經完成雙重驗證
                 if let user = Auth.auth().currentUser {
                    if user.isAnonymous {
                        // 匿名用戶：設置標記並切換到設定頁
                        UserDefaults.standard.set(true, forKey: "shouldShowAccountLinkingAlert")
                        navigationPath.removeLast(navigationPath.count)
                        selectedTab = 2  // 切換到設定頁
                    } else if !user.providerData.contains(where: { $0.providerID == "phone" }) {
                        // 已登入但未綁定手機：設置雙重驗證提示
                        UserDefaults.standard.set(true, forKey: "shouldShowTwoFactorAlert")
                        navigationPath.removeLast(navigationPath.count)
                    } else {
                        // 正常用戶：直接返回首頁
                        navigationPath.removeLast(navigationPath.count)
                    }
                }
            }) {
                Text("返回首頁")
                    .font(.custom("NotoSansTC-Black", size: 18))
                    .foregroundColor(.customAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.customSecondary)
                    .cornerRadius(10)
            }
           
        }
        .sheet(isPresented: $showAccountLinkingSheet) {
            AccountLinkingSheet(
                isPresented: $showAccountLinkingSheet,
                isUpgrading: $isUpgrading,
                onGoogleLink: upgradeWithGoogle,
                onAppleLink: upgradeWithApple,
                message: selectedButton == .favorite ? "綁定帳號以保存您喜歡的名字" : "綁定帳號以快速用相同條件生成更多名字"
            )
        }
    }
    
    private func toggleFavorite() {
        isFavorite.toggle()
        if isFavorite {
            saveFavorite()
        } else {
            removeFavorite()
        }
    }
    
    private func saveFavorite() {
        let favoriteData = FavoriteNameData(
            name: name,
            analysis: analysis,
            wuxing: wuxing
        )
        
        var favorites = (UserDefaults.standard.data(forKey: "FavoriteNames")
            .flatMap { try? JSONDecoder().decode([FavoriteNameData].self, from: $0) }) ?? []
        favorites.append(favoriteData)
        
        if let encodedData = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encodedData, forKey: "FavoriteNames")
        }

        // 更新雲端資料
        Task {
            try? await usageManager.updateCloudData()
        }
    }
    
    private func removeFavorite() {
        guard var favorites = UserDefaults.standard.data(forKey: "FavoriteNames")
            .flatMap({ try? JSONDecoder().decode([FavoriteNameData].self, from: $0) }) else {
            return
        }
        
        favorites.removeAll { $0.name == name }
        
        if let encodedData = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encodedData, forKey: "FavoriteNames")
        }

        // 更新雲端資料
    Task {
            try? await usageManager.updateCloudData()
        }
    }
    
    private func checkFavoriteStatus() {
        guard let favorites = UserDefaults.standard.data(forKey: "FavoriteNames")
            .flatMap({ try? JSONDecoder().decode([FavoriteNameData].self, from: $0) }) else {
            return
        }
        
        isFavorite = favorites.contains { $0.name == name }
    }

    private func wuxingIcon(for element: String) -> String {
        switch element {
        case "金": return "circle.fill"
        case "木": return "leaf.fill"
        case "水": return "drop.fill"
        case "火": return "flame.fill"
        case "土": return "square.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private func wuxingColor(for element: String) -> Color {
        switch element {
        case "金": return .yellow
        case "木": return .green
        case "水": return .blue
        case "火": return .red
        case "土": return .orange
        default: return .gray
        }
    }

    private func regenerateName() {
        isRegenerating = true
        regenerateAction()
    }

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    // 添加綁定方法
    private func upgradeWithGoogle() {
        self.isUpgrading = true
        
        guard let clientID = FirebaseApp.app()?.options.clientID else { 
            self.isUpgrading = false
            self.upgradeErrorMessage = "無法獲取 Google 登入設定"
            self.showAccountLinkingSheet = false
            self.showUpgradeError = true
            return 
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            self.isUpgrading = false
            self.upgradeErrorMessage = "無法初始化 Google 登入"
            self.showAccountLinkingSheet = false
            self.showUpgradeError = true
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in                
            if let error = error {
                self.upgradeErrorMessage = "Google 登入失敗：\(error.localizedDescription)"
                self.showUpgradeError = true
                self.showAccountLinkingSheet = false
                self.isUpgrading = false
                return
            }
            
            guard let user = result?.user,
                    let idToken = user.idToken?.tokenString else {
                self.upgradeErrorMessage = "無法獲取 Google 帳號資訊"
                self.showUpgradeError = true
                self.showAccountLinkingSheet = false
                self.isUpgrading = false
                return
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            // 連結帳號
            Auth.auth().currentUser?.link(with: credential) { [self] authResult, error in
                if let error = error as NSError? {
                    // 處理特定錯誤類型
                    let errorMessage: String
                    switch error.code {
                    case AuthErrorCode.emailAlreadyInUse.rawValue:
                        errorMessage = "此 Google 帳號已被使用，請使用其他帳號"
                    case AuthErrorCode.credentialAlreadyInUse.rawValue:
                        errorMessage = "此 Google 帳號已綁定其他帳號"
                    case AuthErrorCode.providerAlreadyLinked.rawValue:
                        errorMessage = "您已綁定 Google 帳號"
                    default:
                        errorMessage = error.localizedDescription
                    }
                    print("❌ 綁定失敗: \(errorMessage)")
                    DispatchQueue.main.async {
                        self.isUpgrading = false
                        self.upgradeErrorMessage = errorMessage
                        self.showAccountLinkingSheet = false
                        self.showUpgradeError = true
                    }
                    return
                } else {
                    // 成功連結
                    self.showAccountLinkingSheet = false
                    
                    // 更新用戶資料
                    let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                    changeRequest?.displayName = user.profile?.name
                    changeRequest?.photoURL = user.profile?.imageURL(withDimension: 200)
                    
                    changeRequest?.commitChanges { error in
                        if let error = error {
                            print("❌ 更新用戶資料失敗: \(error.localizedDescription)")
                        } else {
                            print("✅ 用戶資料更新成功")
                        }
                        
                        print("✅ 帳號升級成功")
                        self.isUpgrading = false
                        // 觸發 UI 更新
                        self.handleSuccessfulUpgrade()
                    }
                }
            }
        }
    }
    
    private func upgradeWithApple() {
        self.isUpgrading = true
        appleSignInCoordinator = AppleSignInCoordinator()
        
        appleSignInCoordinator?.startSignInWithAppleFlow { [self] result in
            defer {
                DispatchQueue.main.async {
                    self.isUpgrading = false
                    self.showAccountLinkingSheet = false
                }
            }
                
            switch result {
            case .success(_):
                self.handleSuccessfulUpgrade()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    if let authError = error as? NSError {
                        // Firebase Auth errors
                        switch authError.code {
                        case AuthErrorCode.emailAlreadyInUse.rawValue:
                            upgradeErrorMessage = "此 Apple 帳號已被使用，請使用其他帳號"
                        case AuthErrorCode.credentialAlreadyInUse.rawValue:
                            upgradeErrorMessage = "此 Apple 帳號已綁定其他帳號"
                        case AuthErrorCode.providerAlreadyLinked.rawValue:
                            upgradeErrorMessage = "您已綁定 Apple 帳號"
                        case AuthErrorCode.invalidCredential.rawValue:
                            upgradeErrorMessage = "無效的憑證"
                        case AuthErrorCode.operationNotAllowed.rawValue:
                            upgradeErrorMessage = "此操作不被允許"
                        case AuthErrorCode.tooManyRequests.rawValue:
                            upgradeErrorMessage = "請求次數過多，請稍後再試"
                        case AuthErrorCode.networkError.rawValue:
                            upgradeErrorMessage = "網路連線錯誤，請檢查網路狀態"
                        case AuthErrorCode.userDisabled.rawValue:
                            upgradeErrorMessage = "此帳號已被停用"
                        case AuthErrorCode.requiresRecentLogin.rawValue:
                            upgradeErrorMessage = "需要重新登入才能執行此操作"
                        default:
                            // 如果是 Apple Sign In 的錯誤
                            if let asError = error as? ASAuthorizationError {
                                switch asError.code {
                                case .canceled:
                                    upgradeErrorMessage = "使用者取消綁定"
                                case .invalidResponse:
                                    upgradeErrorMessage = "伺服器回應無效"
                                case .notHandled:
                                    upgradeErrorMessage = "無法處理此請求"
                                case .failed:
                                    upgradeErrorMessage = "綁定失敗"
                                default:
                                    upgradeErrorMessage = error.localizedDescription
                                }
                            } else {
                                upgradeErrorMessage = error.localizedDescription
                            }
                        }
                        self.showUpgradeError = true
                    }
                }
            }
        }
    }
    
    private func linkAccount(with credential: AuthCredential) {
        guard let user = Auth.auth().currentUser else {
            print("❌ 無法連結帳號：未找到當前用戶")
            return
        }
        
        user.link(with: credential) { authResult, error in
            DispatchQueue.main.async {
                self.isUpgrading = false
                
                if let error = error {
                    self.upgradeErrorMessage = error.localizedDescription
                    self.showUpgradeError = true
                    return
                }
                
                self.showAccountLinkingOptions = false
            }
        }
    }

    private func handleSuccessfulUpgrade() {
        showAccountLinkingSheet = false
        
        // 轉移匿名用戶的使用次數
        UsageManager.shared.transferAnonymousUses()
        
        // 更新雲端資料
        Task {
            try? await UsageManager.shared.updateCloudData()
        }
    }
}

struct CustomAlertView: View {
    let title: String
    let message: String
    @Binding var isPresented: Bool
     
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 20) {
                Text(title)
                    .font(.custom("NotoSansTC-Black", size: 18))
                    .foregroundColor(.customText)
                
                Text(message)
                    .font(.custom("NotoSansTC-Regular", size: 14))
                    .foregroundColor(.customText)
                    .multilineTextAlignment(.center)
                
                Button("確定") {
                    withAnimation {
                        isPresented = false
                    }
                }
                .buttonStyle(AlertButtonStyle(isPrimary: true))
            }
            .padding()
            .background(Color.customBackground)
            .cornerRadius(15)
            .shadow(radius: 10)
            .padding(30)
        }
    }
}

struct AlertButtonStyle: ButtonStyle {
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("NotoSansTC-Regular", size: 16))
            .foregroundColor(isPrimary ? .white : .customAccent)
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
            .background(isPrimary ? Color.customAccent : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.customAccent, lineWidth: isPrimary ? 0 : 1)
            )
    }
}

// 新增 AccountLinkingSheet 視圖
struct AccountLinkingSheet: View {
    @Binding var isPresented: Bool
    @Binding var isUpgrading: Bool
    let onGoogleLink: () -> Void
    let onAppleLink: () -> Void
    let message: String  // 新增這行
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("綁定帳號")
                    .font(.custom("NotoSansTC-Black", size: 24))
                    .foregroundColor(.customText)
                    .padding(.top)
                
                Text(message)  // 使用傳入的訊息
                    .font(.custom("NotoSansTC-Regular", size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: onGoogleLink) {
                    HStack {
                        Image("GoogleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("使用 Google 帳號綁定")
                            .font(.custom("NotoSansTC-Regular", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.customAccent, lineWidth: 1)
                    )
                }
                .foregroundColor(.customText)
                .disabled(isUpgrading)
                
                Button(action: onAppleLink) {
                    HStack {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("使用 Apple 帳號綁定")
                            .font(.custom("NotoSansTC-Regular", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.customAccent, lineWidth: 1)
                    )
                }
                .foregroundColor(.customText)
                .disabled(isUpgrading)
                
                if isUpgrading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("取消") {
                isPresented = false
            })
            .background(Color.customBackground)
        }
    }
}

struct FavoritesListView: View {
    @State private var favorites: [FavoriteNameData] = []
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            if favorites.isEmpty {
                Text("目前沒有收藏的名字")
                    .font(.custom("NotoSansTC-Regular", size: 18))
                    .foregroundColor(.customText)
            } else {
                List {
                    ForEach(favorites, id: \.name) { favorite in
                        NavigationLink(destination: NameAnalysisView(
                            name: favorite.name,
                            analysis: favorite.analysis,
                            wuxing: favorite.wuxing,
                            navigationPath: .constant(NavigationPath()),
                            selectedTab: .constant(0),
                            regenerateAction: {},
                            showButtons: false  // Changed from State<Bool> to Bool
                        )) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(favorite.name)
                                        .font(.custom("NotoSansTC-Black", size: 24))
                                        .foregroundColor(.customText)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 5) {
                                        ForEach(favorite.wuxing, id: \.self) { element in
                                            Image(systemName: wuxingIcon(for: element))
                                                .foregroundColor(wuxingColor(for: element))
                                        }
                                    }
                                }
                                Text(favorite.analysis.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                                    .font(.custom("NotoSansTC-Regular", size: 14))
                                    .foregroundColor(.customText)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .onDelete(perform: removeFavorite)
                }
                .listStyle(PlainListStyle())
                // 添加底部間距，使其不被廣告遮擋
                .padding(.bottom, GADAdSizeBanner.size.height + 45)
            }
        }
        .onAppear(perform: loadFavorites)
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "FavoriteNames"),
           let decodedFavorites = try? JSONDecoder().decode([FavoriteNameData].self, from: data) {
            favorites = decodedFavorites
        }
    }
    
    private func removeFavorite(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        if let encodedData = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encodedData, forKey: "FavoriteNames")
        }
    }

    private func wuxingIcon(for element: String) -> String {
        switch element {
        case "金": return "circle.fill"
        case "木": return "leaf.fill"
        case "水": return "drop.fill"
        case "火": return "flame.fill"
        case "土": return "square.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private func wuxingColor(for element: String) -> Color {
        switch element {
        case "金": return .yellow
        case "木": return .green
        case "水": return .blue
        case "火": return .red
        case "土": return .orange
        default: return .gray
        }
    }
}


struct SituationalQuestionView: View {
    let question: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let parts = question.split(separator: "\n", omittingEmptySubsequences: false)
            if parts.count >= 3 {
                Text(String(parts[0].trimmingCharacters(in: .whitespaces))) // Q1, Q2, etc.
                    .font(.custom("NotoSansTC-Black", size: 22))
                    .foregroundColor(.customAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(parts[1].trimmingCharacters(in: .whitespaces))) // Answer
                    .font(.custom("NotoSansTC-Regular", size: 20))
                    .foregroundColor(.customText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(parts[2].trimmingCharacters(in: .whitespaces))) // Analysis
                    .font(.custom("NotoSansTC-Regular", size: 20))
                    .foregroundColor(.customText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 10)
    }
}

// Add this extension for custom corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// Add this struct for the triangle shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Add this custom toggle style
struct CustomToggleStyle: ToggleStyle {
    var onColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Rectangle()
                .foregroundColor(configuration.isOn ? onColor : Color.gray.opacity(0.3))
                .frame(width: 51, height: 31, alignment: .center)
                .overlay(
                    Circle()
                        .foregroundColor(.white)
                        .padding(.all, 3)
                        .offset(x: configuration.isOn ? 11 : -11, y: 0)
                        .animation(.linear(duration: 0.1), value: configuration.isOn)
                )
                .cornerRadius(20)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
// 将Character扩展移到文件的全局范围内
extension Character {
    var isChineseCharacter: Bool {
        return String(self).range(of: "\\p{Han}", options: .regularExpression) != nil
    }
}

@MainActor
class RewardedViewModel: NSObject, ObservableObject, GADFullScreenContentDelegate {
    private let usageManager = UsageManager.shared
    private var rewardedAd: GADRewardedAd?
    @Published var isAdLoaded = false
    @Published var remainingCooldown: Int = 0
    private var isLoading = false
    private var lastLoadTime: Date?
    private let minimumLoadInterval: TimeInterval = 300
    private var cooldownTimer: Timer?
    private let lastAdTimestampKey = "LastRewardedAdTimestamp"
    private let cooldownDuration: TimeInterval = 300 // 5分鐘冷卻時間
    
    override init() {
        super.init()
        Task { @MainActor in
            preloadNextAd()
            updateCooldownStatus() // 初始化時更新狀態
        }
    }
    
    private func canLoadAd() -> Bool {
        let lastTimestamp = UserDefaults.standard.double(forKey: lastAdTimestampKey)
        let timeSinceLastAd = Date().timeIntervalSince1970 - lastTimestamp
        return timeSinceLastAd >= cooldownDuration
    }
    
    private func updateCooldownStatus() {
        let lastTimestamp = UserDefaults.standard.double(forKey: lastAdTimestampKey)
        let timeSinceLastAd = Date().timeIntervalSince1970 - lastTimestamp
        
        if timeSinceLastAd < cooldownDuration {
            remainingCooldown = Int(cooldownDuration - timeSinceLastAd)
            startCooldownTimer()
        } else {
            remainingCooldown = 0
            preloadNextAd()
        }
    }
    
    private func startCooldownTimer() {
        cooldownTimer?.invalidate()
        
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                let lastTimestamp = UserDefaults.standard.double(forKey: self.lastAdTimestampKey)
                let timeSinceLastAd = Date().timeIntervalSince1970 - lastTimestamp
                
                if timeSinceLastAd < self.cooldownDuration {
                    self.remainingCooldown = Int(self.cooldownDuration - timeSinceLastAd)
                } else {
                    self.remainingCooldown = 0
                    self.cooldownTimer?.invalidate()
                    self.cooldownTimer = nil
                    self.preloadNextAd()
                }
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
        cooldownTimer = timer
    }
    
    private func preloadNextAd() {
        guard !isLoading else {
            print("⏳ [AdLoad] 正在載入中，跳過")
            return 
        }
        guard canLoadAd() else {
            print("⏳ [AdLoad] 未達載入間隔，開始計時")
            startCooldownTimer()
            return
        }
        
        isLoading = true
        
        print("📱 [AdLoad] 開始載入廣告")
        Task {
            do {
                rewardedAd = try await GADRewardedAd.load(
                    withAdUnitID: "ca-app-pub-3940256099942544/1712485313",
                    // withAdUnitID: "ca-app-pub-3469743877050320/4233450598",
                    request: GADRequest())
                rewardedAd?.fullScreenContentDelegate = self
                
                await MainActor.run {
                    isAdLoaded = true
                    isLoading = false
                    lastLoadTime = Date()
                    print("✅ [AdLoad] 廣告載入成功")
                }
            } catch {
                await MainActor.run {
                    isAdLoaded = false
                    isLoading = false
                    print("❌ [AdLoad] 廣告載入失敗: \(error.localizedDescription)")
                }
                
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                if canLoadAd() {
                    await MainActor.run {
                        self.preloadNextAd()
                    }
                }
            }
        }
    }
    
    func showAd() {
        guard let rewardedAd = rewardedAd else {
            if canLoadAd() {
                preloadNextAd()
            }
            return
        }
        
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rewardedAd.present(fromRootViewController: rootViewController) { [weak self] in
                self?.usageManager.remainingUses += 3
                
                // 更新最後觀看廣告的時間戳記
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self?.lastAdTimestampKey ?? "")
                
                Task {
                    try? await self?.usageManager.updateCloudData()
                }
            }
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isAdLoaded = false
        updateCooldownStatus() // 廣告關閉時更新狀態
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ [AdShow] 廣告展示失敗: \(error.localizedDescription)")
        isAdLoaded = false
        if canLoadAd() {
            preloadNextAd()
        }
    }
    
    deinit {
        cooldownTimer?.invalidate()
    }
}

class UsageManager: ObservableObject {
    static let shared = UsageManager()
    @Published var remainingUses: Int = 0
    private let db = Firestore.firestore()
    
    // 新增 UserDefaults key
    private let anonymousUsesKey = "anonymousRemainingUses"
    
    // 初始化時設定匿名用戶的初始使用次數
    private func initializeAnonymousUses() {
        if UserDefaults.standard.object(forKey: anonymousUsesKey) == nil {
            UserDefaults.standard.set(3, forKey: anonymousUsesKey)
        }
    }
    
    // 修改同步資料方法
    func syncUserData() async throws {
        guard let user = Auth.auth().currentUser else {
            print("❌ 未登入，無法同步資料")
            return
        }
        
        // 如果是匿名用戶，使用本地儲存的次數
        if user.isAnonymous {
            initializeAnonymousUses()
            await MainActor.run {
                self.remainingUses = UserDefaults.standard.integer(forKey: anonymousUsesKey)
            }
            return
        }
        
        // 非匿名用戶，從 Firestore 讀取資料
        print("🔄 開始同步用戶資料")
        let userRef = db.collection("users").document(user.uid)
        
        do {
            let document = try await userRef.getDocument()
            
            if document.exists {
                print("✅ 找到現有用戶資料")
                if let userData = try? document.data(as: UserData.self) {
                    await MainActor.run {
                        self.remainingUses = userData.remainingUses
                        if let encodedData = try? JSONEncoder().encode(userData.favorites) {
                            UserDefaults.standard.set(encodedData, forKey: "FavoriteNames")
                        }
                    }
                }
            } else {
                print("📝 創建新用戶資料")
                let newUserData = UserData.createDefault()
                try await userRef.setData(from: newUserData)
                
                await MainActor.run {
                    self.remainingUses = newUserData.remainingUses
                }
            }
        } catch {
            print("❌ 同步資料失敗: \(error.localizedDescription)")
            throw error
        }
    }
    
    // 修改更新雲端資料方法
    func updateCloudData() async throws {
        guard let user = Auth.auth().currentUser else {
            print("❌ 未登入，無法更新資料")
            return
        }
        
        // 如果是匿名用戶，只更新本地儲存
        if user.isAnonymous {
            UserDefaults.standard.set(remainingUses, forKey: anonymousUsesKey)
            return
        }
        
        print("🔄 開始更新雲端資料")
        
        let favorites = (UserDefaults.standard.data(forKey: "FavoriteNames")
            .flatMap { try? JSONDecoder().decode([FavoriteNameData].self, from: $0) }) ?? []
        
        let userData = UserData(
            remainingUses: remainingUses,
            favorites: favorites,
            lastSyncTime: Date()
        )
        
        do {
            try await db.collection("users").document(user.uid).setData(from: userData, merge: true)
            print("✅ 雲端資料更新成功")
        } catch {
            print("❌ 更新雲端資料失敗: \(error.localizedDescription)")
            throw error
        }
    }
    
    // 新增方法：處理帳號綁定時的使用次數轉移
    func transferAnonymousUses() {
        let anonymousUses = UserDefaults.standard.integer(forKey: anonymousUsesKey)
        remainingUses = anonymousUses
        // 清除匿名用戶的使用次數
        UserDefaults.standard.removeObject(forKey: anonymousUsesKey)
    }
}

// Add this new TabButton view
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
        var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("NotoSansTC-Black", size: 16))
                .foregroundColor(isSelected ? .white : .customText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.customAccent : Color.clear)
        }
        .cornerRadius(25)
    }
}

// Add new InterstitialAdViewModel class
class InterstitialAdViewModel: NSObject, ObservableObject, GADFullScreenContentDelegate {
    private var interstitialAd: GADInterstitialAd?
    private var isLoading = false
    
    override init() {
        super.init()
        loadAd()
    }
    
    private func loadAd() {
        guard !isLoading else { return }
        isLoading = true
        
        print("📱 [InterstitialAd] 開始載入廣告")
        Task {
            do {
                interstitialAd = try await GADInterstitialAd.load(
                    withAdUnitID: "ca-app-pub-3940256099942544/4411468910",
                    // withAdUnitID: "ca-app-pub-3469743877050320/9105399676",
                    request: GADRequest())
                interstitialAd?.fullScreenContentDelegate = self
                
                await MainActor.run {
                    isLoading = false
                    print("✅ [InterstitialAd] 廣告載入成功")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    print("❌ [InterstitialAd] 廣告載入失敗: \(error.localizedDescription)")
                }
                
                // 如果載入失敗，等待後重試
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                loadAd()
            }
        }
    }
    
    func showAd() {
        guard let interstitialAd = interstitialAd else {
            print("❌ [InterstitialAd] 廣告未準備好")
            loadAd()
            return
        }
        
        print("📱 [InterstitialAd] 開始展示廣告")
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            interstitialAd.present(fromRootViewController: rootViewController)
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 [InterstitialAd] 廣告關閉，開始預載下一個")
        loadAd()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ [InterstitialAd] 廣告展示失敗: \(error.localizedDescription)")
        loadAd()
    }
}

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private var startTimes: [String: CFAbsoluteTime] = [:]
    private var measurements: [(String, TimeInterval)] = []
    
    func start(_ name: String) {
        startTimes[name] = CFAbsoluteTimeGetCurrent()
    }
    
    func end(_ name: String) {
        guard let startTime = startTimes[name] else { return }
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        measurements.append((name, timeElapsed))
        print("⏱️ [Performance] \(name): \(String(format: "%.3f", timeElapsed))s")
    }
    
    func reset() {
        startTimes.removeAll()
        measurements.removeAll()
    }
    
    func printSummary() {
        print("\n📊 Performance Summary:")
        print("------------------------")
        for (name, time) in measurements {
            print("\(name.padding(toLength: 25, withPad: " ", startingAt: 0)): \(String(format: "%.3f", time))s")
        }
        print("------------------------\n")
    }
}

#Preview {
    ContentView()
}

struct CreateAccountView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var isLoggedIn: Bool
    @ObservedObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var companyName = ""
    @State private var isSignUp = false
    @State private var showError = false
    @State private var errorMessage: String?
    @Environment(\.colorScheme) var colorScheme
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var isLoading: Bool = false
    
    let textColor = Color(hex: "#FF798C")
    
    var body: some View {
        ZStack {
            Image("background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Pull Indicator
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.vertical, 10)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Move top padding into spacer for better layout
                        Spacer()
                            .frame(height: 30) // Reduced top spacing due to pull indicator
                        
                        Text("建立新帳號")
                            .font(.custom("NotoSansTC-Black", size: 32))
                            .foregroundColor(textColor)
                        
                        VStack(spacing: 15) {
                            CustomTextField(placeholder: "姓名", text: $fullName)
                            CustomTextField(
                                placeholder: "電子郵件", 
                                text: $email,
                                keyboardType: .emailAddress,
                                autocapitalization: .never,
                                validation: { email in
                                    let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
                                    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
                                    return emailPredicate.evaluate(with: email)
                                },
                                errorMessage: "請輸入有效的電子郵件地址"
                            )
                            CustomTextField(placeholder: "密碼", text: $password, isSecure: true)
                            CustomTextField(placeholder: "確認密碼", text: $confirmPassword, isSecure: true)
                        }
                        .padding(.horizontal)
                        
                        Button(action: createAccount) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("註冊")
                                    .font(.custom("NotoSansTC-Black", size: 18))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(textColor)
                        .cornerRadius(25)
                        .disabled(email.isEmpty || password.isEmpty || confirmPassword.isEmpty || isLoading)
                        
                        // Add bottom spacer for keyboard
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding()
                }
                // Disable scroll view's automatic keyboard avoidance
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") {
                        dismiss()
                    }
                }
            }
            .alert("錯誤", isPresented: $showError) {  // 新增 @State private var showError = false
                Button("確定", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "發生未知錯誤")  // 修改為使用可選型別
            }
        }
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func createAccount() {
        // 驗證輸入
        guard !email.isEmpty, !password.isEmpty, !fullName.isEmpty else {
            print("錯誤")
            return
        }
        
        guard password == confirmPassword else {
            print("錯誤")
            return
        }
        
        // 建立帳號
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if error != nil {
                print("錯誤")
                return
            }
            
            if let user = result?.user {
                // 更新用戶資
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = fullName
                changeRequest.commitChanges { error in
                    if error != nil {
                        print("錯誤")
                    }
                }
                
                // 儲存額外的用戶資訊到 Firestore
                let db = Firestore.firestore()
                db.collection("users").document(user.uid).setData([
                    "fullName": fullName,
                    "email": email,
                    "createdAt": Date()
                ]) { error in
                    if error != nil {
                        print("錯誤")
                    }
                }
                
                isLoggedIn = true
                dismiss()
            }
        }
    }
}



// Add Apple Sign In Coordinator
class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
    private var completion: ((Result<AuthDataResult, Error>) -> Void)?
    private var currentNonce: String? // 添加 nonce 屬性
    
    // 生成隨機 nonce 的方法
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    // SHA256 雜湊函數
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
    
    func startSignInWithAppleFlow(completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        self.completion = completion
        
        // 生成 nonce
        let nonce = randomNonceString()
        currentNonce = nonce
        let hashedNonce = sha256(nonce)
        
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = hashedNonce
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8),
              let nonce = currentNonce else {
            completion?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple Sign In failed"])))
            return
        }
        
        // Create Firebase credential with nonce
        let credential = OAuthProvider.credential(
            withProviderID: "apple.com",
            idToken: idTokenString,
            rawNonce: nonce // 使用生成的 nonce
        )

        handleAppleSignIn(credential: credential, appleIDCredential: appleIDCredential)

        // 保存用戶全名
        if let fullName = appleIDCredential.fullName {
            let displayName = [
                fullName.givenName,
                fullName.familyName
            ].compactMap { $0 }.joined(separator: " ")
            
            print("👤 Constructed display name: \(displayName)")
            
            if !displayName.isEmpty {
                print("🔄 Starting profile update...")
                // 使用 Auth.auth().currentUser 而不是 authResult
                if let currentUser = Auth.auth().currentUser {
                    let changeRequest = currentUser.createProfileChangeRequest()
                    changeRequest.displayName = displayName
                    changeRequest.commitChanges { error in
                        if let error = error {
                            print("❌ Error updating user profile: \(error.localizedDescription)")
                            print("🔍 Error details: \(error)")
                        } else {
                            print("✅ Successfully updated user display name to: \(displayName)")
                            print("🎉 Profile update completed successfully")
                        }
                    }
                } else {
                    print("⚠️ No current user found")
                }
            } else {
                print("⚠️ Display name was empty, skipping profile update")
            }
        } else {
            print("ℹ️ No full name provided in Apple credential")
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        print("Sign in with Apple errored: \(error.localizedDescription)")
    }
}

extension AppleSignInCoordinator {
    func handleAppleSignIn(credential: AuthCredential, appleIDCredential: ASAuthorizationAppleIDCredential?) {
        if let user = Auth.auth().currentUser {
            if user.isAnonymous {
                // Case B：匿名 → 與 Apple 連結
                print("匿名用戶，開始連結 Apple 帳號")
                linkAnonymousUserToApple(credential: credential, fullName: appleIDCredential?.fullName)
            } else {
                // Case C：一般登入使用者
                print("Current user is not anonymous, consider linking or show a message.")
            }
        } else {
            // Case A：尚未登入 → 以 Apple 帳號登入
            print("尚未登入，開始以 Apple 帳號登入")
            signInWithApple(credential: credential, fullName: appleIDCredential?.fullName)
        }
    }

    private func linkAnonymousUserToApple(credential: AuthCredential, fullName: PersonNameComponents?) {
        guard let user = Auth.auth().currentUser else {
            print("找不到當前用戶")
            self.completion?(.failure(NSError(
                domain: "AppleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "找不到當前用戶"]
            )))
            return
        }
        
        user.link(with: credential) { [weak self] authResult, error in
            if let error = error as NSError? {
                print("連結 Apple 帳號失敗：\(error.localizedDescription)")
                self?.completion?(.failure(error))
                return
            }
            
            // 成功連結後更新用戶資料
            if let fullName = fullName {
                let displayName = [
                    fullName.givenName,
                    fullName.familyName
                ].compactMap { $0 }.joined(separator: " ")
                
                if !displayName.isEmpty {
                    let changeRequest = authResult?.user.createProfileChangeRequest()
                    changeRequest?.displayName = displayName
                    changeRequest?.commitChanges { error in
                        if let error = error {
                            print("❌ 更新用戶資料失敗：\(error.localizedDescription)")
                        } else {
                            print("✅ 成功更新用戶顯示名稱為：\(displayName)")
                        }
                    }
                }
            }
            
            // 完成回調
            if let authResult = authResult {
                self?.completion?(.success(authResult))
            }
        }
    }

    private func signInWithApple(credential: AuthCredential, fullName: PersonNameComponents?) {
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            if let error = error {
                self?.completion?(.failure(error))
                return
            }
            
            // 成功登入後更新用戶資料
            if let fullName = fullName {
                let displayName = [
                    fullName.givenName,
                    fullName.familyName
                ].compactMap { $0 }.joined(separator: " ")
                
                if !displayName.isEmpty {
                    let changeRequest = authResult?.user.createProfileChangeRequest()
                    changeRequest?.displayName = displayName
                    changeRequest?.commitChanges { error in
                        if let error = error {
                            print("❌ Error updating user profile: \(error.localizedDescription)")
                        } else {
                            print("✅ Successfully updated user display name to: \(displayName)")
                        }
                    }
                }
            }
            
            if let authResult = authResult {
                self?.completion?(.success(authResult))
            }
        }
    }
}

struct Choice: Codable, Hashable {
    let meaning: String
    let text: String
}

struct Question: Codable {
    let question: String
    let choices: [Choice]
}

struct QuestionList: Codable {
    let questions: [SimpleQuestion]
    let scenario_questions: [ScenarioQuestion]
}

struct SimpleQuestion: Codable {
    let question: String
    let choices: [String]
}

struct ScenarioQuestion: Codable {
    let scenario: String
    let choices: [Choice]
}

struct TraitButton: View {
    let title: String
    let action: () -> Void
    
        var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("NotoSansTC-Regular", size: 16))
                .foregroundColor(.customText)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.customSecondary)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.customAccent, lineWidth: 1)
                )
        }
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
}

struct GIFImageView: UIViewRepresentable {
    private let gifName: String
    private let frame: CGRect
    private let onAnimationComplete: () -> Void
    private let isTransparent: Bool
    private let loopCount: Int
    
    init(_ name: String, 
         frame: CGRect, 
         isTransparent: Bool = false,
         loopCount: Int = 1,
         onAnimationComplete: @escaping () -> Void) {
        self.gifName = name
        self.frame = frame
        self.isTransparent = isTransparent
        self.loopCount = loopCount
        self.onAnimationComplete = onAnimationComplete
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: frame)
        view.backgroundColor = isTransparent ? .clear : .black
        
        // Load GIF
        if let path = Bundle.main.path(forResource: gifName, ofType: "gif") {
            let url = URL(fileURLWithPath: path)
            let gifImageView = UIImageView(gifURL: url, loopCount: loopCount)
            gifImageView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height) // 設定為與view相同大小以完全填滿
            gifImageView.contentMode = .scaleAspectFill
            gifImageView.backgroundColor = isTransparent ? .clear : .black

            gifImageView.delegate = context.coordinator
            view.addSubview(gifImageView)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onAnimationComplete: onAnimationComplete)
    }
    
    class Coordinator: NSObject, SwiftyGifDelegate {
        private let onAnimationComplete: () -> Void
        
        init(onAnimationComplete: @escaping () -> Void) {
            self.onAnimationComplete = onAnimationComplete
            super.init()
        }
        
        func gifDidStop(sender: UIImageView) {
            onAnimationComplete()
        }
    }
}

struct SplashScreenView: View {
    @Binding var showSplash: Bool
    
    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            GIFImageView("splash_animation", 
                        frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height),
                        isTransparent: false,
                        onAnimationComplete: {
                            // GIF 播放完成後的回調
                            showSplash = false
                        })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
        }
        .ignoresSafeArea()
    }
}

struct UserData: Codable {
    var remainingUses: Int
    var favorites: [FavoriteNameData]
    var lastSyncTime: Date
    
    static let defaultUses = 3
    
    static func createDefault() -> UserData {
        return UserData(
            remainingUses: defaultUses,
            favorites: [],
            lastSyncTime: Date()
        )
    }
}

// 新增一個通用的可點擊效果修飾器
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0) // 保留透明度變化但移除動畫
            .animation(nil, value: configuration.isPressed) // 禁用動畫
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                GIFImageView("loading_animation", 
                    frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height),
                    isTransparent: true,
                    loopCount: -1) {
                }
                .frame(maxWidth: .infinity) // 讓容器佔據全寬，實現水平置中
                
                Text("生成名字中（約30秒）...")
                    .font(.custom("NotoSansTC-Black", size: 18))
                    .foregroundColor(.black)
            }
        }
    }
}

struct SuccessPopupView: View {
    let uses: Int
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onDismiss()
                }
            
            // 彈出視窗
            VStack(spacing: 24) { // 增加整體垂直間距
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.green)
                    .padding(.top, 32) // 頂部增加間距
                
                VStack(spacing: 12) { // 文字區塊的垂直間距
                    Text("購買成功！")
                        .font(.custom("NotoSansTC-Black", size: 24))
                        .foregroundColor(.customText)
                    
                    Text("已新增 \(uses) 次使用機會")
                        .font(.custom("NotoSansTC-Regular", size: 18))
                        .foregroundColor(.customText)
                }
                
                Button(action: onDismiss) {
                    Text("確定")
                        .font(.custom("NotoSansTC-Regular", size: 16))
                        .foregroundColor(.white)
                        .frame(width: 120) // 增加按鈕寬度
                        .padding(.vertical, 14) // 增加按鈕高度
                        .background(Color.customAccent)
                        .cornerRadius(25)
                }
                .padding(.top, 8) // 按鈕上方間距
                .padding(.bottom, 32) // 底部增加間距
            }
            .frame(width: 280) // 設定固定寬度
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 10)
            .padding(.horizontal, 40)
        }
        .transition(.opacity)
    }
}

// 新增一個自定義按鈕樣式
struct NavigationButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("NotoSansTC-Black", size: 16))
            .foregroundColor(isPrimary ? .white : .customAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                isPrimary ? Color.customAccent : Color.white
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.customAccent, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// Add hideKeyboard() as a global function
private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                  to: nil, from: nil, for: nil)
}

// 新增 AppOpenAdManager 類別
class AppOpenAdManager: NSObject, GADFullScreenContentDelegate {
    static let shared = AppOpenAdManager()
    
    private var appOpenAd: GADAppOpenAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?
    
    private let fourHoursInSeconds = TimeInterval(3600 * 4)
    
    override init() {
        super.init()
        loadAd()
    }
    
    private func loadAd() {
        // 如果正在載入廣告或已有可用廣告，則不載入
        if isLoadingAd || isAdAvailable() {
            return
        }
        isLoadingAd = true
        
        print("📱 [AppOpenAd] 開始載入廣告")
        // Task {
        //     do {
        //         appOpenAd = try await GADAppOpenAd.load(
        //             withAdUnitID: "ca-app-pub-3469743877050320/7027134890",
        //             request: GADRequest())
        //         appOpenAd?.fullScreenContentDelegate = self
        //         loadTime = Date()
                
        //         await MainActor.run {
        //             isLoadingAd = false
        //             print("✅ [AppOpenAd] 廣告載入成功")
        //         }
        //     } catch {
        //         await MainActor.run {
        //             isLoadingAd = false
        //             print("❌ [AppOpenAd] 廣告載入失敗: \(error.localizedDescription)")
        //         }
        //     }
        // }
    }
    
    func showAdIfAvailable() {
        // 如果廣告正在顯示中，則不顯示
        guard !isShowingAd else { return }
        
        // 如果沒有可用廣告，則載入新廣告
        if !isAdAvailable() {
            loadAd()
            return
        }
        
        if let ad = appOpenAd {
            isShowingAd = true
            print("📱 [AppOpenAd] 開始展示廣告")
            if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
                ad.present(fromRootViewController: rootViewController)
            }
        }
    }
    
    private func wasLoadTimeLessThanFourHoursAgo() -> Bool {
        guard let loadTime = loadTime else { return false }
        return Date().timeIntervalSince(loadTime) < fourHoursInSeconds
    }
    
    private func isAdAvailable() -> Bool {
        return appOpenAd != nil && wasLoadTimeLessThanFourHoursAgo()
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        appOpenAd = nil
        isShowingAd = false
        print("📱 [AppOpenAd] 廣告關閉，開始預載下一個")
        loadAd()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        appOpenAd = nil
        isShowingAd = false
        print("❌ [AppOpenAd] 廣告展示失敗: \(error.localizedDescription)")
        loadAd()
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 [AppOpenAd] 廣告將要展示")
    }
}

// 修改 AppStateManager
class AppStateManager: ObservableObject {
    private let appOpenAdManager = AppOpenAdManager.shared
    private var lastBackgroundTime: Date?
    private let minimumBackgroundDuration: TimeInterval = 30
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppBackground() {
        lastBackgroundTime = Date()
    }
    
    func handleAppForeground() {
        guard let lastBackground = lastBackgroundTime else { return }
        
        let timeInBackground = Date().timeIntervalSince(lastBackground)
        
        if timeInBackground >= minimumBackgroundDuration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.appOpenAdManager.showAdIfAvailable()
            }
        }
        
        lastBackgroundTime = nil
    }
}

// Add these extensions at the bottom of the file
extension String {
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
}

extension String {
    var sha256: String {
        let inputData = Data(self.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// 在檔案開頭新增 QuestionManager 類別
class QuestionManager: ObservableObject {
    static let shared = QuestionManager()
    @Published private(set) var questions: [Question] = []
    private let questionsCacheKey = "cachedQuestions"
    private let lastUpdateTimeKey = "questionsLastUpdateTime"
    private let updateInterval: TimeInterval = 24 * 60 * 60 // 24小時更新一次
    
    private init() {
        loadCachedQuestions()
    }
    
    private func loadCachedQuestions() {
        if let data = UserDefaults.standard.data(forKey: questionsCacheKey),
           let cachedQuestions = try? JSONDecoder().decode([Question].self, from: data) {
            self.questions = cachedQuestions
        }
    }
    
    func updateQuestionsIfNeeded() async {
        // 檢查是否需要更新
        let lastUpdate = UserDefaults.standard.double(forKey: lastUpdateTimeKey)
        let now = Date().timeIntervalSince1970
        
        guard now - lastUpdate > updateInterval else {
            print("✅ [Questions] 問題庫仍在有效期內，無需更新")
            return
        }
        
        print("🔄 [Questions] 開始更新問題庫")
        
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("questions").getDocuments()
            
            var newQuestions: [Question] = []
            
            for document in snapshot.documents {
                if let questionsData = document.get("questions") as? [[String: Any]] {
                    for questionData in questionsData {
                        if let scenario = questionData["question"] as? String,
                           let choicesData = questionData["choices"] as? [String: [String: String]] {
                            
                            let choices = choicesData.values.compactMap { choiceDict -> Choice? in
                                guard let text = choiceDict["text"],
                                      let meaning = choiceDict["meaning"] else {
                                    return nil
                                }
                                return Choice(meaning: meaning, text: text)
                            }
                            
                            let question = Question(question: scenario, choices: choices)
                            newQuestions.append(question)
                        }
                    }
                }
            }
            
            // 更新快取
            if !newQuestions.isEmpty {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newQuestions) {
                    UserDefaults.standard.set(encoded, forKey: questionsCacheKey)
                    UserDefaults.standard.set(now, forKey: lastUpdateTimeKey)
                }
                
                await MainActor.run {
                    self.questions = newQuestions
                }
                print("✅ [Questions] 問題庫更新成功")
            }
            
        } catch {
            print("❌ [Questions] 更新問題庫失敗: \(error.localizedDescription)")
        }
    }
    
    func getRandomQuestions(_ count: Int) -> [Question] {
        return Array(questions.shuffled().prefix(count))
    }
}

// Add this helper function
private func calculateFontSize(for characterCount: Int) -> CGFloat {
    switch characterCount {
        case 2: return 48 // 兩個字維持原始大小
        case 3: return 42 // 三個字稍微縮小
        case 4: return 36 // 四個字再縮小
        default: return 32 // 其他情況使用最小字體
    }
}
