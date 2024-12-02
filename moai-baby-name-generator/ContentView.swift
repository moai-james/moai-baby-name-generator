//
//  ContentView.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/10/9.
//
import UIKit
import SwiftUI
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

// extension Color {
//     static let customBackground = Color("CustomBackground")
//     static let customText = Color("CustomText")
//     static let customAccent = Color("CustomAccent")
//     static let customSecondary = Color("CustomSecondary")
struct BannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let bannerView = GADBannerView(adSize: GADAdSizeBanner)
        let viewController = UIViewController()
        
        // 測試用廣告單元 ID,發布時要換成真實的
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2435281174"
        // bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        bannerView.rootViewController = viewController
        
        viewController.view.addSubview(bannerView)
        viewController.view.frame = CGRect(origin: .zero, size: GADAdSizeBanner.size)
        bannerView.load(GADRequest())
        
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    @State private var showSplash = true
    @StateObject private var authViewModel = AuthViewModel()
    
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
                SplashScreenView()
                    .edgesIgnoringSafeArea(.all)
                    .zIndex(1)
            }
            
            if !authViewModel.isLoggedIn {
                LoginView(authViewModel: authViewModel)  // 只傳遞 authViewModel
                    .transition(.opacity)  // 添加過渡效果
                    .onAppear {
                        // 5秒後移除 splash screen
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            withAnimation {
                                showSplash = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            checkExistingAuth()
        }
    }
    
    private func checkExistingAuth() {
        if let user = Auth.auth().currentUser {
            user.getIDTokenResult { tokenResult, error in
                if let error = error {
                    print("Token 驗證錯誤: \(error.localizedDescription)")
                    self.authViewModel.isLoggedIn = false
                    return
                }
                
                guard let tokenResult = tokenResult else {
                    self.authViewModel.isLoggedIn = false
                    return
                }
                
                if tokenResult.expirationDate > Date() {
                    self.authViewModel.isLoggedIn = true
                } else {
                    user.getIDTokenForcingRefresh(true) { _, error in
                        if let error = error {
                            print("Token 刷新錯誤: \(error.localizedDescription)")
                            self.authViewModel.isLoggedIn = false
                        } else {
                            self.authViewModel.isLoggedIn = true
                        }
                    }
                }
            }
        } else {
            self.authViewModel.isLoggedIn = false
        }
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
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
                
                
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.custom("NotoSansTC-Regular", size: 14))
                }
                
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
            }
            .padding(.horizontal, 30)
        }
        .sheet(isPresented: $showVerificationCode) {
            if let resolver = mfaResolver {
                VerificationCodeView(resolver: resolver)
            }
        }
        .sheet(isPresented: $authViewModel.showPhoneVerification) {
            PhoneVerificationView(
                authViewModel: authViewModel,
                resolver: authViewModel.mfaResolver
            )
        }
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { 
            print("❌ 無法獲取 clientID")
            return 
        }
        
        print("✅ 開始 Google 登入流程")
        print("ClientID: \(clientID)")
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            print("❌ 無法獲取 rootViewController")
            return
        }
        
        print("✅ 準備顯示 Google 登入視窗")
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [self] result, error in
            if let error = error {
                print("❌ Google 登入錯誤: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                return
            }
            
            print("✅ Google 登入成功")
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { [self] authResult, error in
                if let error = error as NSError? {
                    if error.domain == AuthErrorDomain,
                       error.code == AuthErrorCode.secondFactorRequired.rawValue {
                        // Handle MFA
                        print(" Auth.auth().currentUser: \(Auth.auth().currentUser)")
                        authViewModel.mfaResolver = error.userInfo[AuthErrorUserInfoMultiFactorResolverKey] as? MultiFactorResolver
                        authViewModel.showPhoneVerification = true
                    } else {
                        errorMessage = error.localizedDescription
                    }
                } else {
                    print(" Auth.auth().currentUser: \(Auth.auth().currentUser)")
                    authViewModel.isLoggedIn = true  // Use authViewModel
                }
            }           
        }
    }
    
    private func signInWithApple() {
        appleSignInCoordinator = AppleSignInCoordinator()
        appleSignInCoordinator?.startSignInWithAppleFlow { result in
            switch result {
            case .success(let authResult):
                // Successfully signed in with Apple
                authViewModel.isLoggedIn = true
                
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
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
    
    @State private var isValid: Bool = true
    @State private var showError: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .onChange(of: text) { newValue in
                        validateInput(newValue)
                    }
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
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
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int
    @Binding var isLoggedIn: Bool
    @ObservedObject var authViewModel: AuthViewModel  // 新增這行
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("isDarkMode") private var isDarkMode = false
    @StateObject private var rewardedViewModel = RewardedViewModel()
    @StateObject private var usageManager = UsageManager.shared
    @State private var showAlert = false
    // Add interstitial ad property
    @StateObject private var interstitialAd = InterstitialAdViewModel()
    @State private var alertMessage = ""
    @State private var showPhoneVerification = false
    
    var body: some View {
        ZStack {
            // Main content area
            ZStack {
                if selectedTab == 0 {
                    homeView
                } else if selectedTab == 1 {
                    VStack {
                        Text("收藏")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.customText)
                            .padding(.top, 20)
                        FavoritesListView()
                    }
                } else {
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
                            interstitialAd.showAd()
                        }
                        selectedTab = 1
                    }
                    Spacer()
                    TabBarButton(imageName: "setting_icon", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.tabbar)
                .cornerRadius(25, corners: [.topLeft, .topRight])
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationDestination(for: String.self) { destination in
            if destination == "FormView" {
                FormView(navigationPath: $navigationPath)
            }
        }
        .navigationDestination(for: FormData.self) { formData in
            DialogView(navigationPath: $navigationPath, formData: formData)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    var homeView: some View {
        ZStack {
            VStack() {
                // Header
                VStack(spacing: 0) {
                    Color.black.frame(height: 0) // This creates a black area above the text
                    HStack {
                        Spacer()
                        Text("千尋取名")
                            .font(.custom("NotoSansTC-Black", size: 20))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8) // Add some vertical padding to the text
                    .background(Color.black)
                    Color.pink.frame(height: 5)
                }
                
                // Main content
                VStack() {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 380, height: 375)
                            .opacity(0.5)
                        
                        Image("main_mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                    }
                    
                    Button(action: {
                        if usageManager.remainingUses > 0 {
                            navigationPath.append("FormView")
                        } else {
                            showAlert = true
                        }
                    }) {    
                        Text("開始取名")
                            .font(.custom("NotoSansTC-Black", size: 32))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .cornerRadius(25)
                            .tracking(20)
                    }
                    .alert(isPresented: $showAlert) {
                        Alert(
                            title: Text("使用次數已用完"),
                            message: Text("很抱歉，您的免費使用次數已用完。"),
                            dismissButton: .default(Text("確定"))
                        )
                    }
                    .background(
                        Image("naming_button")
                            .resizable()
                            .scaledToFill()
                    )
                    .frame(width: UIScreen.main.bounds.width * 0.8)
                    .padding(.horizontal, 20)
                    .offset(y: -40)
                    
                    Spacer()

                    // Add semi-transparent card for remaining uses and ad button
                    VStack(spacing: 10) {
                        // Remaining uses count with larger number
                        VStack(spacing: 5) {
                            Text("\(usageManager.remainingUses)")
                                .font(.custom("NotoSansTC-Black", size: 36))
                                .foregroundColor(.customText)
                                .bold()
                            
                            Text("剩餘使用次數")
                                .font(.custom("NotoSansTC-Regular", size: 16))
                                .foregroundColor(.customText)
                        }
                        
                        // Add watch ad button 
                        // if rewardedViewModel.isAdLoaded {
                        Button(action: {
                            rewardedViewModel.showAd()
                        }) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text("觀看廣告獲得3次使用機會")
                                        .font(.custom("NotoSansTC-Regular", size: 16))
                                }
                                .foregroundColor(.customText)
                                .padding()
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(25)
                        }
                        .disabled(!rewardedViewModel.isAdLoaded) // 廣告未載入時禁用按鈕
                        .opacity(rewardedViewModel.isAdLoaded ? 1 : 0.5) // 視覺反饋
                        // }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.5))
                    )
                    .padding(.horizontal, 10)
                    .offset(y: -40)
                    
                    Spacer()
                        // .frame(height: 50) // Add fixed spacing at the bottom
                    
                    // Add banner ad
                    BannerView()
                        .frame(width: GADAdSizeBanner.size.width, height: GADAdSizeBanner.size.height)
                }
            }
        }
        .background(
            Image("background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
        )
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
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    if let user = Auth.auth().currentUser, let name = user.displayName {
                        Text(name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.customText)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            // 主要內容區域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 商城區域
                    VStack(alignment: .leading, spacing: 15) {
                        Text("商城")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.customText)
                        
                        Button(action: {
                            IAPManager.shared.purchaseProduct(.fiveUses)
                        }) {
                            SettingRow(icon: "cart.fill", title: "購買五次使用機會", price: "NT$50")
                        }
                        
                        Button(action: {
                            IAPManager.shared.purchaseProduct(.twentyUses)
                        }) {
                            SettingRow(icon: "cart.fill", title: "購買二十次使用機會", price: "NT$150")
                        }
                        
                        Button(action: {
                            IAPManager.shared.purchaseProduct(.hundredUses)
                        }) {
                            SettingRow(icon: "cart.fill", title: "購買一百次使用機會", price: "NT$490")
                        }
                    }
                    
                    // 資訊區域
                    VStack(alignment: .leading, spacing: 15) {
                        Text("資訊")
                            .font(.system(size: 20, weight: .bold))
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
                        
                        // 登出按鈕
                        Button(action: logOut) {
                            SettingRow(icon: "rectangle.portrait.and.arrow.right", 
                                     title: "登出",
                                     textColor: .red)
                        }
                    }        
                }
                .padding(.horizontal)
                // 確保內容不會被廣告橫幅遮擋
                .padding(.bottom, GADAdSizeBanner.size.height + 45)
            }
        }
    }

    // 保持 SettingRow 結構體不變
    struct SettingRow: View {
        let icon: String
        let title: String
        var price: String? = nil
        var textColor: Color = .customText
        
        var body: some View {
            HStack {
                Image(systemName: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 18))
                    .foregroundColor(textColor)
                if let price = price {
                    Spacer()
                    Text(price)
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
                if price == nil {
                    Spacer()
                }
            }
            .foregroundColor(textColor)
            .padding()
            .background(Color.customSecondary)
            .cornerRadius(10)
        }
    }

    // 新增 Terms and Privacy View
    struct TermsAndPrivacyView: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("服務條款與隱私權政策")
                        .font(.system(size: 24, weight: .bold))
                        .padding(.bottom, 10)
                    
                    Group {
                        Text("摩艾科技有限公司隱私權保護政策")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.bottom, 5)
                        
                        Text("隱私權保護政策的內容")
                            .font(.system(size: 18, weight: .bold))
                        
                        Text("本隱私權政策說明摩艾科技有限公司(以下說明將以品牌名稱-『千尋命名』、『我們』或『我們的』簡稱)通過我們的應用程式及網站收集到的資訊，以及我們將如何使用這些資訊。我們非常重視您的隱私權。請您閱讀以下有關隱私權保護政策的更多內容。")
                            .padding(.bottom, 10)
                        
                        Group {
                            Text("我們使用您個人資料的方式")
                                .font(.system(size: 18, weight: .bold))
                            Text("本政策涵蓋的內容包括：摩艾科技如何處理蒐集或收到的個人資料 (包括與您過去使用我們的產品及服務相關的資料）。個人資料是指得以識別您的身分且未公開的資料，如姓名、地址、電子郵件地址或電話號碼。\n本隱私權保護政策只適用於摩艾科技")
                        }
                        
                        Group {
                            Text("資料蒐集及使用原則")
                                .font(.system(size: 18, weight: .bold))
                            Text("在您註冊摩艾科技所屬的官網、使用App相關產品、瀏覽我們的產品官網或某些合作夥伴的網頁，以及參加宣傳活動或贈獎活動時，摩艾科技會蒐集您的個人資料。摩艾科技也可能將商業夥伴或其他企業所提供的關於您的資訊與摩艾科技所擁有的您的個人資料相結合。\n\n當您在使用摩艾科技所提供的服務進���會員註冊時，我們會詢問您的姓名、電子郵件地址、出生日期、性別及郵遞區號等資料。在您註冊摩艾科技的會員帳號並登入我們的服務後，我們就能辨別您的身分。您得自由選擇是否提供個人資料給我們，但若特定資料欄位係屬必填欄位者，您若不提供該等資料則無法使用相關的摩艾科技所提供產品及服務。")
                        }
                        
                        Group {
                            Text("其他技術收集資訊細節")
                                .font(.system(size: 18, weight: .bold))
                            Text("➤ 軟硬體相關資訊\n我們會收集裝置專屬資訊 (例如您的硬體型號、作業系統版本、裝置唯一的識別碼，以及包括電話號碼在內的行動網路資訊)。\n\n➤ 地理位置資訊\n當您使用APP服務時，我們會收集並處理您實際所在位置的相關資訊。我們會使用各種技術判斷您的所在位置，包括 IP 位址、GPS 和其他感應器。\n\n➤ 專屬應用程式編號\n某些服務所附的專屬應用程式編號；當您安裝或解除安裝這類服務，或是這類服務定期與我們的伺服器連線時，系統就會將這個編號以及安裝資訊傳送給摩艾科技。")
                        }
                        
                        Group {
                            Text("兒童線上隱私保護法案")
                                .font(.system(size: 18, weight: .bold))
                            Text("我們的所有兒童類APP及網站產品皆遵守兒童線上隱私保護條款the Children's Online Privacy Protection Act (『COPPA』)，我們不會收集任何未滿13歲兒童的個人資訊，如檢測到年齡小於13歲的相關資訊，我們將及時刪除，不會予以保留或儲存。")
                        }
                        
                        Group {
                            Text("聯繫我們")
                                .font(.system(size: 18, weight: .bold))
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
            try Auth.auth().signOut()
            // 登出後重置狀態
            authViewModel.isLoggedIn = false  // 這會觸發顯示登入介面
            selectedTab = 0     // 重置到主頁標籤
            navigationPath = NavigationPath()  // 清除導航堆疊
        } catch let signOutError as NSError {
            print("Error signing out: %@", signOutError)
        }
    }
}

// Updated TabBarButton view
struct TabBarButton: View {
    let imageName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(imageName)
                            .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            }
            .foregroundColor(isSelected ? .tabbar : .gray)
        }
        .frame(width: 40, height: 40)
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct FormView: View {
    @Binding var navigationPath: NavigationPath
    @State private var surname = ""
    @State private var middleName = ""
    @State private var numberOfNames = 1
    @State private var isBorn = false
    @State private var birthDate = Date()
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var gender = "未知"
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            VStack(spacing: -10) {
                // Mascot and message
                HStack(alignment: .top, spacing: 10) {
                    Image("login_mascot") // Replace with your actual mascot image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                    
                    // Dialogue bubble
                    VStack(alignment: .leading) {
                        Text("送給孩子的第一份禮物\n就是為孩子取名字！")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.black)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(15)
                            .overlay(
                                Triangle()
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                                , alignment: .topLeading
                            )
                    }
                }
                .padding()
                
                // Form fields
                VStack(spacing: 15) {
                    CustomTextField(placeholder: "姓氏", text: $surname)
                    CustomTextField(placeholder: "指定中間字", text: $middleName)
                    
                    // Single/Double name picker
                    HStack(spacing: 0) {
                        Button(action: { numberOfNames = 1 }) {
                            Text("單名")
                                .foregroundColor(numberOfNames == 1 ? .white : Color(hex: "#FF798C"))
                                .frame(width: 100)
                                .padding(.vertical, 10)
                                .background(numberOfNames == 1 ? Color(hex: "#FF798C") : Color(hex: "#FFE5E9"))
                        }
                        Button(action: { numberOfNames = 2 }) {
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
                    .frame(maxWidth: .infinity)
                    
                    // Gender picker
                    HStack(spacing: 0) {
                        ForEach(["男", "女", "未知"], id: \.self) { option in
                            Button(action: { gender = option }) {
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
                    
                    // Born toggle and date picker
                    VStack(spacing: 15) {
                        Toggle("未/已出生", isOn: $isBorn)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(25)
                            .toggleStyle(CustomToggleStyle(onColor: Color(hex: "#FF798C")))
                        
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
                        }
                    }
                }

                        Spacer()

                // Next button
                Button(action: validateAndProceed) {
                    Text("下一步")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#FF798C"))
                        .cornerRadius(25)
                }

                
            }
            .padding()
        }
        .navigationBarTitle("資料填寫", displayMode: .inline)
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
                .offset(y: 0) // Adjust this value if needed to position the line correctly
            , alignment: .top
        )
        .background(
            Image("background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
        )
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func validateAndProceed() {
        if surname.isEmpty {
            alertMessage = "姓氏不能為空"
            showAlert = true
        } else if surname.count > 2 {
            alertMessage = "姓氏不能超過兩個字"
            showAlert = true
        } else if middleName.count > 1 {
            alertMessage = "中間字不能超過一個字"
            showAlert = true
        } else {
            let formData = FormData(surname: surname, middleName: middleName, numberOfNames: numberOfNames, isBorn: isBorn, birthDate: birthDate, gender: gender)
            navigationPath.append(formData)
        }
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
    private let usageManager = UsageManager.shared
    
    // Add a state to track if generation is in progress
    @State private var isGenerating = false
    
    var body: some View {
        ZStack {
            // Color(hex: "#FFF0F5") // Light pink background
            //     .edgesIgnoringSafeArea(.all)

            if isGeneratingName {
                VStack {
                    // GIFImageView("loading_animation", frame: CGRect(x: 0, y: 0, width: 200, height: 200))
                    //     .frame(width: 200, height: 200)

                    // add an image of a mascot
                    Image("main_mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                    

                    ProgressView("生成名字中...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .foregroundColor(.black)
                        .scaleEffect(1.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("生成名字失敗")
                        .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.red)
                    .padding()
                
                    Text(errorMessage)
                        .font(.system(size: 18))
                        .foregroundColor(.customText)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    // Only show retry button if user has remaining uses
                    if usageManager.remainingUses > 0 {
                        Button("重試") {
                            self.errorMessage = nil
                            generateName()  // This will deduct another point
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding()
                        .background(.customAccent)
                    .cornerRadius(10)
                    } else {
                        Text("您的使用次數已用完，請觀看廣告獲取更多次數。")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .padding()
            } else if let generatedName = generatedName, let nameAnalysis = nameAnalysis, let wuxing = wuxing {
                NameAnalysisView(
                    name: generatedName,
                    analysis: nameAnalysis,
                    wuxing: wuxing,
                    navigationPath: $navigationPath,
                    regenerateAction: generateName
                )
            } else {
                VStack(spacing: -10) {
                    if !questions.isEmpty {

                        // add spacer with height 10

                        VStack(spacing: 10) {
                            HStack(alignment: .center, spacing: 10) {
                                Image("main_mascot")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    
                                Text("問題 #\(currentQuestionIndex + 1)")
                                    .font(.custom("NotoSansTC-Black", size: 16))
                                    .foregroundColor(.customAccent)
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


                        VStack(spacing: 15) {
                            ForEach(questions[currentQuestionIndex].choices, id: \.self) { choice in
                                Button(action: {
                                    answers.append(choice.text)
                                    if currentQuestionIndex < questions.count - 1 {
                                        currentQuestionIndex += 1
                                    } else {
                                        generateName()
                                    }
                                }) {
                                    HStack {
                                        Text(choice.text)
                                            .font(.custom("NotoSansTC-Black", size: 16))
                                            .foregroundColor(.customText)
                                        Spacer()
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                } 
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.customAccent, lineWidth: 1)
                                )
                            }
                        }
                        .padding()

                        Spacer()
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
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func loadQuestions() {
        // Clear previous answers
        answers.removeAll()
        
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load questions.json")
            return
        }
        
        do {
            let jsonDecoder = JSONDecoder()
            let allQuestions = try jsonDecoder.decode(QuestionList.self, from: data)
            
            var combinedQuestions: [Question] = []
            // var combinedQuestions: [Question] = allQuestions.questions.map { question in
            //     Question(question: question.question, choices: question.choices.map { Choice(meaning: "", text: $0) })
            // }
            
            combinedQuestions += allQuestions.scenario_questions.map { scenario in
                Question(question: scenario.scenario, choices: scenario.choices)
            }
            
            questions = Array(combinedQuestions.shuffled().prefix(5))
        } catch {
            print("Failed to decode questions: \(error)")
        }
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
                    
                    print("✅ [Generate] ��字生成流程完成")
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
        單雙名: \(formData.numberOfNames == 1 ? "單名" : "雙名")
        性別: \(formData.gender)
        """
        
        let answersString: String
        do {
            answersString = try answers.enumerated().map { index, answer in
                guard index < questions.count else {
                    throw NSError(domain: "AnswerMapping", code: 1, userInfo: [NSLocalizedDescriptionKey: "Index out of bounds: \(index) >= \(questions.count)"])
                }
                return """
                問題\(index + 1): \(questions[index].question)
                回答: \(answer)
                """
            }.joined(separator: "\n\n")
        } catch {
            print("Error mapping answers: \(error)")
            answersString = "Error processing answers"
        }

        return """
        請根據以下表單資料和問答為嬰兒生成中文名字：

        基本資料：\(formData)

        問答內容：\(answersString)

        命名要求：
        1. 名字為單名或雙名。
        2. 如有指定中間字，須包含於名中。
        3. 名字符合嬰兒性別。
        4. 典故來源於《左傳》或《詩經》的具體內容不可僅引用篇名。
        5. 典故與名字有明確聯繫，並詳述其關係。
        注意事項：
        1. 請確保輸出格式符合JSON規範並與範例一致，包括所有必要字段和嵌套結構。
        2. 所有字串值使用雙引號，並適當使用轉義字符（如\n表示換行）。
        """
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
            required: ["question", "answer", "analysis"]
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
            required: ["source", "original_text", "interpretation", "connection"]
        )

        // 分析的 Schema
        let analysisSchema = JSONSchema(
            type: .object,
            properties: [
                "character_meaning": JSONSchema(type: .string),
                "literary_allusion": literaryAllusionSchema,
                "situational_analysis": JSONSchema(
                    type: .array,
                    items: situationalAnalysisSchema
                )
            ],
            required: ["character_meaning", "literary_allusion", "situational_analysis"]
        )

        // 完整的回應 Schema
        return JSONSchema(
            type: .object,
            properties: [
                "name": JSONSchema(type: .string),
                "analysis": analysisSchema
            ],
            required: ["name", "analysis"]
        )
    }

    // 2. 修改 API 調用函數
    private func callOpenAIAPI(with prompt: String) async throws -> (String, [String: String], [String]) {
        let monitor = PerformanceMonitor.shared
        
        monitor.start("API Setup")
        let apiKey = APIConfig.openAIKey
        let service = OpenAIServiceFactory.service(apiKey: apiKey)
        monitor.end("API Setup")
        
        // 創建 tool 定義
        let tool = ChatCompletionParameters.Tool(
            function: .init(
                name: "generate_name",
                strict: true, description: "Generate a Chinese name with analysis",
                parameters: createNameGenerationSchema()
            )
        )

        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text("""
                您是一位專精於中華文化的命名顧問，具備以下專業知識：
                1. 精通《說文解字》、《康熙字典》等字書，能準確解析漢字字義與內涵
                2. 熟稔《詩經》、《左傳》等經典文獻，善於運用典故為名字增添文化深度
                3. 深諳五行八字、音律諧和之道，確保名字音韻優美
                4. 擅長結合現代命名美學，打造既傳統又時尚的名字

                您的任務是：
                1. 確保名字的音韻、字義皆相輔相成
                2. 選用富有正面寓意的典故，並詳細解釋其文化內涵
                3. 分析名字如何呼應家長的期望與願景

                回應須包含：
                1. 完整的名字建議
                2. 詳細的字義解析
                3. 相關典故出處與詮釋
                4. 與家長期望的連結分析
                """)),
            .init(role: .user, content: .text(prompt))
        ]

        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .gpt4omini,
            tools: [tool]
        )

        monitor.start("API Request Preparation")
        let completionObject = try await service.startChat(parameters: parameters)
        monitor.end("API Request Preparation")
        
        monitor.start("Response Processing")
        guard let toolCall = completionObject.choices.first?.message.toolCalls?.first,
              let jsonData = toolCall.function.arguments.data(using: .utf8) else {
            throw NSError(domain: "OpenAIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

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
            "情境分析": jsonResult.analysis.situational_analysis.enumerated().map { index, item in
                "Q\(index + 1)：\(item.question)\nA：\(item.answer)\n→ \(item.analysis)"
            }.joined(separator: "\n\n")
        ]

        monitor.end("Response Processing")
        
        return (jsonResult.name, analysisDict, elements)
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
    let situational_analysis: [SituationalAnalysis]
}

struct LiteraryAllusion: Codable {
    let source: String
    let original_text: String
    let interpretation: String
    let connection: String
}

struct SituationalAnalysis: Codable {
    let question: String
    let answer: String
    let analysis: String
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
    @State private var isFavorite: Bool = false
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) var colorScheme
    @State private var isRegenerating = false
    let regenerateAction: () -> Void
    @AppStorage("remainingUses") private var remainingUses = 3
    @State private var showInsufficientUsesAlert = false
    @StateObject private var interstitialAd = InterstitialAdViewModel()
    @State private var hasShownReviewRequest = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                nameCard
                    .padding(.horizontal)
                
                // Analysis sections
                VStack(spacing: 20) {
                    // Character Analysis
                    AnalysisCard(title: "字義") {
                        if let analysisContent = analysis["字義分析"] {
                            let lines = analysisContent.split(separator: "\n")
                            ForEach(lines, id: \.self) { line in
                                Text(line)
                                    .font(.custom("NotoSansTC-Regular", size: 16))
                                    .foregroundColor(.customText)
                            }
                        }
                    }
                    
                    // Literary Allusion
                    AnalysisCard(title: "典故") {
                        if let analysisContent = analysis["典故分析"] {
                            let lines = analysisContent.split(separator: "\n")
                            ForEach(lines, id: \.self) { line in
                                Text(line)
                                    .font(.custom("NotoSansTC-Regular", size: 16))
                                    .foregroundColor(.customText)
                            }
                        }
                    }
                    
                    // Situational Analysis
                    AnalysisCard(title: "情境契合度") {
                        if let situationalContent = analysis["情境分析"] {
                            let questions = situationalContent.split(separator: "Q")
                            ForEach(questions.indices, id: \.self) { index in
                                if index > 0 {
                                    Divider()
                                        .padding(.vertical, 10)
                                }
                                SituationalQuestionView(question: "Q" + questions[index])
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                actionButtons
                    .padding(.horizontal)
                    .padding(.bottom, GADAdSizeBanner.size.height + 20)
            }
        }
        .background(Color.customBackground)
        .navigationBarTitle("名字分析", displayMode: .inline)
        .onAppear(perform: checkFavoriteStatus)
        .overlay(
            Group {
                if isRegenerating {
                    VStack {
                        GIFImageView("loading_animation", frame: CGRect(x: 0, y: 0, width: 200, height: 200))
                            .frame(width: 200, height: 200)
                        
                        ProgressView("生成名字中...")
                            .scaleEffect(1.5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                }
            }
        )
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
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
                            .font(.custom("NotoSansTC-Black", size: 48))
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
                toggleFavorite()
                // Show review request when adding to favorites
                if !hasShownReviewRequest && isFavorite {
                    requestReview()
                    hasShownReviewRequest = true
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
                .background(.customAccent)
                .cornerRadius(10)
            }
            
            Button(action: {
                if remainingUses > 0 {
                    interstitialAd.showAd()
                    regenerateName()
                } else {
                    showInsufficientUsesAlert = true
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
                interstitialAd.showAd()
                navigationPath.removeLast(navigationPath.count)
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
                    .font(.system(size: 18))
                    .foregroundColor(.customText)
            } else {
                List {
                    ForEach(favorites, id: \.name) { favorite in
                        NavigationLink(destination: FavoriteDetailView(favorite: favorite)) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(favorite.name)
                                        .font(.system(size: 24, weight: .bold))
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
                                    .font(.system(size: 14))
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
        .enableInjection()
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

struct FavoriteDetailView: View {
    let favorite: FavoriteNameData
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 30) {
                    nameCard
                    characterAnalysisCard
                    literaryAllusionCard
                    situationalAnalysisCard
                }
                .padding()
            }
        }
        .navigationBarTitle("名字分析", displayMode: .inline)
        .onAppear {
            // Add this onAppear modifier to print the favorite values
            print("Favorite dictionary contents:")
            print("Name: \(favorite.name)")
            print("Wuxing: \(favorite.wuxing.joined(separator: ", "))")
        }
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private var nameCard: some View {
        VStack(spacing: 10) {
            Text("收藏的名字")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.customText)
            
            HStack(spacing: 20) {
                let name = favorite.name
                let wuxing = favorite.wuxing
                let nameCharacters = name.map { String($0) }
                let surnameCharCount = nameCharacters.count - wuxing.count + 1

                // Display surname
                VStack {
                    Text(nameCharacters[0..<surnameCharCount].joined())
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.customText)
                    
                    Image(systemName: wuxingIcon(for: wuxing[0]))
                        .font(.system(size: 24))
                        .foregroundColor(wuxingColor(for: wuxing[0]))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.customSecondary)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                )

                // Display given name characters
                ForEach(Array(zip(nameCharacters[surnameCharCount...], wuxing[1...])), id: \.0) { character, element in
                    VStack {
                        Text(character)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.customText)
                        
                        Image(systemName: wuxingIcon(for: element))
                            .font(.system(size: 24))
                            .foregroundColor(wuxingColor(for: element))
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
    
    private var characterAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("字義")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.customText)
            
            if let analysisContent = favorite.analysis["字義分析"] {
                let lines = analysisContent.split(separator: "\n")
                ForEach(lines, id: \.self) { line in
                    if line.starts(with: "整體含義：") {
                        Text(line)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.customText)
                            .padding(.top, 5)
                    } else {
                        Text(line)
                            .font(.system(size: 16))
                            .foregroundColor(.customText)
                    }
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

    private var literaryAllusionCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("典故")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.customText)
            
            if let analysisContent = favorite.analysis["典故分析"] {
                let lines = analysisContent.split(separator: "\n")
                ForEach(lines, id: \.self) { line in
                    if line.starts(with: "出處：") || line.starts(with: "原文：") || line.starts(with: "釋義：") || line.starts(with: "連結：") {
                        Text(line)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.customText)
                    } else {
                        Text(line)
                            .font(.system(size: 16))
                            .foregroundColor(.customText)
                    }
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

    private var situationalAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("情境契合度")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.customText)
            
            if let situationalContent = favorite.analysis["情境分析"] {
                let questions = situationalContent.split(separator: "Q")
                ForEach(questions.indices, id: \.self) { index in
                    SituationalQuestionView(question: "Q" + questions[index])
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
                    .font(.custom("NotoSansTC-Regular", size: 16))
                    .foregroundColor(.customAccent)
                
                Text(String(parts[1].trimmingCharacters(in: .whitespaces))) // Answer
                    .font(.custom("NotoSansTC-Regular", size: 16))
                    .foregroundColor(.customText)
                
                Text(String(parts[2].trimmingCharacters(in: .whitespaces))) // Analysis
                    .font(.custom("NotoSansTC-Regular", size: 16))
                    .foregroundColor(.customText)
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 10)
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
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

struct GIFImageView: UIViewRepresentable {
    private let name: String
    private let frame: CGRect

    init(_ name: String, frame: CGRect = .zero) {
        self.name = name
        self.frame = frame
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: frame)
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        
        if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
            let request = URLRequest(url: url)
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.frame = frame
    }
}

struct SplashScreenView: View {
    @State private var isAnimationComplete = false
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            GeometryReader { geometry in
                GIFImageView("splash_animation", frame: geometry.frame(in: .local))
                    .opacity(isAnimationComplete ? 0 : 1)
                    .onAppear {
                        size = geometry.size
                    }
            }
        }
        .onAppear {
            // Adjust this delay to match your GIF duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation {
                    isAnimationComplete = true
                }
            }
        }
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
}

// 将Character扩展移到文件的全局范围内
extension Character {
    var isChineseCharacter: Bool {
        return String(self).range(of: "\\p{Han}", options: .regularExpression) != nil
    }
}

// 新增 ViewModel
class RewardedViewModel: NSObject, ObservableObject, GADFullScreenContentDelegate {
    private let usageManager = UsageManager.shared
    private var rewardedAd: GADRewardedAd?
    @Published var isAdLoaded = false
    private var isLoading = false
    
    override init() {
        super.init()
        // 初始化時就開始載入廣告
        preloadNextAd()
    }
    
    private func preloadNextAd() {
        guard !isLoading else { return }
        isLoading = true
        
        print("📱 [AdLoad] 開始載入廣告")
        Task {
            do {
                rewardedAd = try await GADRewardedAd.load(
                    withAdUnitID: "ca-app-pub-3940256099942544/1712485313",
                    request: GADRequest())
                rewardedAd?.fullScreenContentDelegate = self
                
                await MainActor.run {
                    isAdLoaded = true
                    isLoading = false
                    print("✅ [AdLoad] 廣告載入成功")
                }
            } catch {
                await MainActor.run {
                    isAdLoaded = false
                    isLoading = false
                    print("❌ [AdLoad] 廣告載入失敗: \(error.localizedDescription)")
                }
                
                // 如果載入失敗，等待一段時間後重試
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000) // 3秒後重試
                preloadNextAd()
            }
        }
    }
    
    func showAd() {
        guard let rewardedAd = rewardedAd else {
            print("❌ [AdShow] 廣告未準備好")
            // 如果廣告不可用，嘗試重新載入
            preloadNextAd()
            return
        }
        
        print("📱 [AdShow] 開始展示廣告")
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rewardedAd.present(fromRootViewController: rootViewController) { [weak self] in
                print("✅ [AdShow] 廣告播放完成，獎勵發放")
                self?.usageManager.remainingUses += 3
                // 顯示廣告後立即預載下一個
                self?.preloadNextAd()
            }
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 [AdDismiss] 廣告關閉，開始預載下一個")
        preloadNextAd()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ [AdShow] 廣告展示失敗: \(error.localizedDescription)")
        // 展示失敗時重新載入
        preloadNextAd()
    }
}

class UsageManager: ObservableObject {
    @AppStorage("remainingUses") var remainingUses = 3 {
        didSet {
            print("📊 [UsageManager] remainingUses 更新: \(remainingUses)")
        }
    }
    
    static let shared: UsageManager = UsageManager()
    private init() {}
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
        .enableInjection()
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
            if let error = error {
                print("錯誤")
                return
            }
            
            if let user = result?.user {
                // 更新用戶資
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = fullName
                changeRequest.commitChanges { error in
                    if let error = error {
                        print("錯誤")
                    }
                }
                
                // 儲存額外的用戶資訊到 Firestore
                let db = Firestore.firestore()
                db.collection("users").document(user.uid).setData([
                    "fullName": fullName,
                    "email": email,
                    "createdAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        print("錯誤")
                    }
                }
                
                isLoggedIn = true
                dismiss()
            }
        }
    }
}

class AuthViewModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var selectedTab = 0
    @Published var phoneNumber = ""
    @Published var verificationCode = ""
    @Published var showPhoneVerification = false
    @Published var verificationID: String?
    @Published var mfaResolver: MultiFactorResolver? // 新增這行
    
    func signIn() {
        isLoggedIn = true
        selectedTab = 0
    }
    
    func verifyPhoneNumber(completion: @escaping (Bool) -> Void) {
        guard let number = phoneNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        // 直接使用 verifyPhoneNumber 方法
        PhoneAuthProvider.provider().verifyPhoneNumber(
            number,
            uiDelegate: nil,
            multiFactorSession: mfaResolver?.session
        ) { [weak self] verificationID, error in
            if let error = error {
                print("Phone verification error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            self?.verificationID = verificationID
            completion(true)
        }
    }
    
    func verifyCode(completion: @escaping (Bool) -> Void) {
        guard let verificationID = verificationID else { return }
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        if let user = Auth.auth().currentUser {
            user.link(with: credential) { [weak self] result, error in
                if let error = error {
                    print("Phone linking error: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                // Store user data in Firestore
                self?.saveUserData(user: user)
                completion(true)
            }
        }
    }
    
    private func saveUserData(user: User) {
        let db = Firestore.firestore()
        let userData: [String: Any] = [
            "email": user.email ?? "",
            "phoneNumber": user.phoneNumber ?? "",
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(user.uid).setData(userData, merge: true)
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
        
        // Sign in with Firebase
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            if let error = error {
                self?.completion?(.failure(error))
                return
            }
            
            guard let authResult = authResult else {
                self?.completion?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing auth result"])))
                return
            }
            
            // Save user info if it's a new user
            if let fullName = appleIDCredential.fullName {
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = "\(fullName.givenName ?? "") \(fullName.familyName ?? "")"
                changeRequest.commitChanges { error in
                    if let error = error {
                        print("Error updating user profile: \(error.localizedDescription)")
                    }
                }
            }
            
            self?.completion?(.success(authResult))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
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
                .font(.system(size: 16, weight: .medium))
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
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
}

struct PhoneVerificationView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var authViewModel: AuthViewModel
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var showVerificationCode = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showSkipAlert = false
    let resolver: MultiFactorResolver? // 確保這個屬性存在
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("增加帳戶安全性")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("新增手機號碼作為第二道驗證程序")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                CustomTextField(
                    placeholder: "手機號碼 (+886912345678)",
                    text: $phoneNumber,
                    keyboardType: .phonePad
                )
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                
                Button(action: sendVerificationCode) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("傳送驗證碼")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                
                Button("稍後再說") {
                    showSkipAlert = true
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .navigationBarTitle("多重驗證", displayMode: .inline)
            .navigationBarItems(leading: Button("取消") {
                dismiss()
            })
            .alert("確定要跳過？", isPresented: $showSkipAlert) {
                Button("確定", role: .destructive) {
                    authViewModel.isLoggedIn = true  // 使用 authViewModel
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("您可以稍後在設定中啟用多重驗證")
            }
            .sheet(isPresented: $showVerificationCode) {
                VerificationCodeView(verificationId: verificationCode)
            }
        }
    }
    
    private func sendVerificationCode() {
        isLoading = true
        errorMessage = ""
        
        var formattedPhoneNumber = phoneNumber
        if !phoneNumber.hasPrefix("+") {
            formattedPhoneNumber = "+886" + phoneNumber.trimmingCharacters(in: .whitespaces)
        }
        print("📱 嘗試發送驗證碼到: \(formattedPhoneNumber)")
        
        if let resolver = resolver {
            print("🔄 使用 MFA 驗證流程")
            PhoneAuthProvider.provider().verifyPhoneNumber(
                formattedPhoneNumber,
                uiDelegate: nil,
                multiFactorSession: resolver.session
            ) { verificationID, error in
                isLoading = false
                print("📬 收到驗證回應")
                print("verificationID: \(String(describing: verificationID))")
                if let error = error {
                    print("❌ 錯誤: \(error.localizedDescription)")
                }
                handleVerificationResponse(verificationID: verificationID, error: error)
            }
        } else {
            print("🔄 使用 MFA 註冊流程")
            guard let user = Auth.auth().currentUser else {
                errorMessage = "未登入"
                isLoading = false
                return
            }
            
            user.multiFactor.getSessionWithCompletion { session, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    print("❌ 獲取 MFA session 失敗: \(error.localizedDescription)")
                    return
                }
                
                guard let session = session else {
                    self.errorMessage = "無法獲取 MFA session"
                    self.isLoading = false
                    print("❌ MFA session 為空")
                    return
                }
                
                print("✅ 成功獲取 MFA session")
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    formattedPhoneNumber,
                    uiDelegate: nil,
                    multiFactorSession: session
                ) { verificationID, error in
                    self.isLoading = false
                    print("📬 收到驗證回應")
                    print("verificationID: \(String(describing: verificationID))")
                    if let error = error {
                        print("❌ 錯誤: \(error.localizedDescription)")
                    }
                    self.handleVerificationResponse(verificationID: verificationID, error: error)
                }
            }
        }
    }

    private func handleVerificationResponse(verificationID: String?, error: Error?) {
        if let error = error {
            errorMessage = error.localizedDescription
            return
        }
        
        if let verificationID = verificationID {
            verificationCode = verificationID
            showVerificationCode = true
        } else {
            errorMessage = "無法獲取驗證碼"
        }
    }
}
