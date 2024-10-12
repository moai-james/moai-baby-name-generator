//
//  ContentView.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/10/9.
//

import SwiftUI
import SwiftOpenAI
import GoogleSignIn
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// extension Color {
//     static let customBackground = Color("CustomBackground")
//     static let customText = Color("CustomText")
//     static let customAccent = Color("CustomAccent")
//     static let customSecondary = Color("CustomSecondary")


struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    @State private var isLoggedIn = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            if !isLoggedIn {
                LoginView(isLoggedIn: $isLoggedIn)
            } else {
                MainView(navigationPath: $navigationPath, isLoggedIn: $isLoggedIn)
            }
        }
        .accentColor(.customAccent)
    }
}

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isForgotPassword = false
    @State private var errorMessage: String?
    @State private var fullName = ""
    @State private var companyName = ""
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Image("LoginImage") // Add a login image to your assets
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                
                Text(isCreatingAccount ? "註冊" : (isForgotPassword ? "忘記密碼？" : "登入"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.customText)
                
                if isCreatingAccount {
                    createAccountView
                } else if isForgotPassword {
                    forgotPasswordView
                } else {
                    loginView
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
        }
    }
    
    var loginView: some View {
        VStack(spacing: 20) {
            TextField("電子郵件", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("密碼", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: signInWithEmailPassword) {
                Text("登入")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.customAccent)
                    .cornerRadius(10)
            }
            
            Text("或")
                .foregroundColor(.customText)
            
            Button(action: signInWithGoogle) {
                HStack {
                    Image("GoogleLogo") // Add Google logo to your assets
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text("使用 Google 帳號登入")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.customText)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.customAccent, lineWidth: 1)
                )
            }
            
            Button(action: guestLogin) {
                Text("訪客模式")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.customAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.customAccent, lineWidth: 1)
                    )
            }
            
            HStack {
                Text("還沒有帳號？")
                    .foregroundColor(.customText)
                Button("註冊") {
                    isCreatingAccount = true
                }
                .foregroundColor(.customAccent)
            }
            
            Button("忘記密碼？") {
                isForgotPassword = true
            }
            .foregroundColor(.customAccent)
        }
    }
    
    var createAccountView: some View {
        VStack(spacing: 20) {
            TextField("電子郵件", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("密碼", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("全名", text: $fullName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("公司名稱", text: $companyName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: createAccount) {
                Text("註冊")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            
            Button("返回登入") {
                isCreatingAccount = false
            }
            .foregroundColor(.blue)
        }
    }
    
    var forgotPasswordView: some View {
        VStack(spacing: 20) {
            Text("別擔心！這種情況時有發生。請輸入與您的帳戶關聯的電子郵件地址。")
                .multilineTextAlignment(.center)
                .foregroundColor(.customText)
            
            TextField("電子郵件", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: { /* Implement password reset logic */ }) {
                Text("提交")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.customAccent)
                    .cornerRadius(10)
            }
            
            Button("返回入") {
                isForgotPassword = false
            }
            .foregroundColor(.customAccent)
        }
    }
    
    private func signInWithEmailPassword() {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                isLoggedIn = true
            }
        }
    }
    
    private func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    isLoggedIn = true
                }
            }
        }
    }
    
    private func createAccount() {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                // User created successfully
                if let user = authResult?.user {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = fullName
                    changeRequest.commitChanges { error in
                        if let error = error {
                            print("Error updating user profile: \(error.localizedDescription)")
                        }
                    }
                    
                    // Save additional user data to Firestore
                    let db = Firestore.firestore()
                    db.collection("users").document(user.uid).setData([
                        "fullName": fullName,
                        "companyName": companyName,
                        "email": email
                    ]) { error in
                        if let error = error {
                            print("Error saving user data: \(error.localizedDescription)")
                        } else {
                            // Account created and data saved successfully
                            isLoggedIn = true
                        }
                    }
                }
            }
        }
    }

    private func guestLogin() {
        // Implement guest login logic here
        // For now, we'll just set isLoggedIn to true
        isLoggedIn = true
    }
}

struct MainView: View {
    @Binding var navigationPath: NavigationPath
    @State private var selectedTab = 0
    @Binding var isLoggedIn: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            VStack {
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
                    VStack {
                        Text("設定")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.customText)
                            .padding(.top, 20)
                        
                        Spacer()
                        
                        Button(action: logOut) {
                            Text("登出")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Bottom navigation bar
                HStack {
                    Spacer()
                    TabBarButton(imageName: "house.fill", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    Spacer()
                    TabBarButton(imageName: "heart.fill", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    Spacer()
                    TabBarButton(imageName: "gearshape.fill", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(Color.customSecondary)
                .cornerRadius(15)
                .shadow(radius: 5)
                .padding(.horizontal)
            }
        }
        .navigationDestination(for: String.self) { destination in
            if destination == "FormView" {
                FormView(navigationPath: $navigationPath)
            }
        }
        .navigationDestination(for: FormData.self) { formData in
            DialogView(navigationPath: $navigationPath, formData: formData)
        }
    }
    
    var homeView: some View {
        VStack {
            Spacer()
            Text("千尋")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.customText)
            
            Button(action: {
                navigationPath.append("FormView")
            }) {
                Text("開始取名")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(.customAccent)
                    .cornerRadius(15)
            }
            Spacer()
        }
    }

    private func logOut() {
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
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
                Image(systemName: imageName)
                    .font(.system(size: 24))
            }
            .foregroundColor(isSelected ? .customAccent : .gray)
            .padding(8)

        }
    }
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            Form {
                Section(header: Text("資料填寫")
                    .foregroundColor(.customText)) {
                    HStack {
                        Text("姓氏")
                        Text("*")
                            .foregroundColor(.red)
                        TextField("", text: $surname)
                    }
                    TextField("指定中間字", text: $middleName)
                    Picker("單雙名", selection: $numberOfNames) {
                        Text("單名").tag(1)
                        Text("雙名").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Toggle("未/已出生", isOn: $isBorn)
                    
                    if isBorn {
                        DatePicker("出生年月日時", selection: $birthDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Button(action: {
                    if surname.isEmpty {
                        showAlert = true
                    } else {
                        let formData = FormData(surname: surname, middleName: middleName, numberOfNames: numberOfNames, isBorn: isBorn, birthDate: birthDate)
                        navigationPath.append(formData)
                    }
                }) {
                    Text("下一步")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(.customAccent)
                        .cornerRadius(15)
                }
            }
            .scrollContentBackground(.hidden)
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("警告"),
                    message: Text("姓氏不能為空"),
                    dismissButton: .default(Text("確定"))
                )
            }
        }
        .navigationBarTitle("資料填寫", displayMode: .inline)
    }
}

struct FormData: Hashable {
    let surname: String
    let middleName: String
    let numberOfNames: Int
    let isBorn: Bool
    let birthDate: Date
}

struct DialogView: View {
    @Binding var navigationPath: NavigationPath
    let formData: FormData
    @State private var questions: [Question] = []
    @State private var currentQuestionIndex = 0
    @State private var answers: [String] = []
    @State private var isGeneratingName = false
    @State private var generatedName: String?
    @State private var nameAnalysis: String?
    @State private var wuxing: [String]?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            if isGeneratingName {
                ProgressView("生成名字中...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .customText))
                    .scaleEffect(1.5)
            } else if let generatedName = generatedName, let nameAnalysis = nameAnalysis, let wuxing = wuxing {
                NameAnalysisView(name: generatedName, analysis: nameAnalysis, wuxing: wuxing, navigationPath: $navigationPath)
            } else {
                VStack(spacing: 20) {
                    // Image("CuteCreature")
                    //     .resizable()
                    //     .scaledToFit()
                    //     .frame(height: 200)
                    
                    Text("千尋")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.customText)
                    
                    if !questions.isEmpty {
                        Text(questions[currentQuestionIndex].question)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.customText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        VStack(spacing: 15) {
                            ForEach(questions[currentQuestionIndex].choices, id: \.self) { choice in
                                TraitButton(title: choice.text) {
                                    answers.append(choice.text)
                                    if currentQuestionIndex < questions.count - 1 {
                                        currentQuestionIndex += 1
                                    } else {
                                        generateName()
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationBarTitle("心靈對話", displayMode: .inline)
        .onAppear(perform: loadQuestions)
    }
    
    private func loadQuestions() {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load questions.json")
            return
        }
        
        do {
            let jsonDecoder = JSONDecoder()
            let allQuestions = try jsonDecoder.decode(QuestionList.self, from: data)
            
            var combinedQuestions: [Question] = allQuestions.questions.map { question in
                Question(question: question.question, choices: question.choices.map { Choice(meaning: "", text: $0) })
            }
            
            combinedQuestions += allQuestions.scenario_questions.map { scenario in
                Question(question: scenario.scenario, choices: scenario.choices)
            }
            
            questions = Array(combinedQuestions.shuffled().prefix(5))
        } catch {
            print("Failed to decode questions: \(error)")
        }
    }
    
    private func generateName() {
        isGeneratingName = true
        
        // Prepare the prompt for the AI model
        let prompt = preparePrompt()
        
        // Call the OpenAI API to generate the name
        Task {
            do {
                let (name, analysis, wuxing) = try await callOpenAIAPI(with: prompt)
                DispatchQueue.main.async {
                    self.generatedName = name
                    self.nameAnalysis = analysis
                    self.wuxing = wuxing
                    self.isGeneratingName = false
                }
            } catch {
                print("Error generating name: \(error)")
                DispatchQueue.main.async {
                    self.isGeneratingName = false
                }
            }
        }
    }
    
    private func preparePrompt() -> String {
        // Combine form data and question answers into a prompt
        let formData = "姓氏: \(formData.surname), 指定中間字: \(formData.middleName), 單雙名: \(formData.numberOfNames == 1 ? "單名" : "雙名")"
        let answersString = answers.joined(separator: ", ")
        return """
        根據以下資訊為嬰兒生成一個中文名字：
        \(formData)
        問題回答：\(answersString)
        請生成一個適合的中文名字，並提供簡短的分析解釋這個名字的含義和為什麼它適合這個嬰兒。同時，請為名字中的每個字分析其對應的五行屬性（金木水火土）。
        回覆格式：
        名字：[生成的名字]
        分析：[名字分析]
        五行：[每個字的五行屬性，用逗號分隔，五行屬性的數目必須與姓名字數相同。例1：金，木，水; 例2：火，土，金]
        回覆範例：
        名字：蕭勇
        分析：這個名字包含了「蕭」姓氏，表達了勇往直前的精神。個中字義，「蕭」通「逍」，意味着英俊不凡、心靈自在。而「勇」代表勇敢、堅強，象徵著對知識好奇心和對藝術文化的熱愛。這個選擇的名字也象徵着能成為朋友中的有力支持者，值得信賴。整體名字給人一種積極向上、充滿活力與樂觀的感覺。
        五行：木，金

        名字：蕭藝璇
        分析：這個名字選用了「蕭」作為姓氏，而「藝」代表藝術、文化，「璇」則象徵著璀璨、閃耀。整個名字暗示著這位嬰兒將擁有堅持不懈的毅力，對知識的好奇心，成為受人信賴的朋友，並展現勇往直前的精神，同時有對藝術與文化的熱愛。這個名字給人一種具有多方面才華和個性的印象。
        五行：木、金、水
        """
    }
    
    private func callOpenAIAPI(with prompt: String) async throws -> (String, String, [String]) {
        // Use the Config struct to get the API key
        let apiKey = APIConfig.openAIKey
        
        let service = OpenAIServiceFactory.service(apiKey: apiKey)
        
        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text("你是一個專業的中文嬰兒命名專家。")),
            .init(role: .user, content: .text(prompt))
        ]
        
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .gpt4TurboPreview
        )
        
        let completionObject = try await service.startChat(parameters: parameters)
        
        guard let responseContent = completionObject.choices.first?.message.content else {
            throw NSError(domain: "OpenAIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No response from OpenAI"])
        }
        
        // Print the full response for debugging
        print("OpenAI API Response:")
        print(responseContent)
        
        let components = responseContent.split(separator: "\n")
        guard components.count == 3 else {
            throw NSError(domain: "OpenAIError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        }

        let name = String(components[0].dropFirst(3)) // Remove "名字：" prefix
        print("name:", name)
        let analysis = String(components[1].dropFirst(3)) // Remove "分析：" prefix
        print("analysis:", analysis)
        
        // Updated wuxing parsing
        let wuxingString = String(components[2].dropFirst(3)) // Remove "五行：" prefix
        let wuxing = wuxingString.split { $0 == "，" || $0 == "、" }.map(String.init)
        print("wuxing:", wuxing)

        return (name, analysis, wuxing)
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

struct NameAnalysisView: View {
    let name: String
    let analysis: String
    let wuxing: [String]
    @State private var isFavorite: Bool = false
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 30) {
                    nameCard
                    analysisCard
                    actionButtons
                }
                .padding()
            }
        }
        .navigationBarTitle("名字分析", displayMode: .inline)
        .onAppear {
            print("Name: \(name)")
            print("Wuxing count: \(wuxing.count)")
            print("Wuxing elements: \(wuxing)")
        }
        .onAppear(perform: checkFavoriteStatus)
    }
    
    private var nameCard: some View {
        VStack(spacing: 10) {
            Text("為您生成的名字")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.customText)
            
            HStack(spacing: 20) {
                ForEach(Array(name.enumerated()), id: \.offset) { index, character in
                    VStack {
                        Text(String(character))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.customText)
                        
                        if index < wuxing.count {
                            Image(systemName: wuxingIcon(for: wuxing[index]))
                                .font(.system(size: 24))
                                .foregroundColor(wuxingColor(for: wuxing[index]))
                        } else {
                            Text("No wuxing")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    )
                }
            }
        }
    }
    
    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("名字分析")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.customText)
            
            Text(analysis)
                .font(.system(size: 16))
                .foregroundColor(.customText)
                .lineSpacing(5)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    private var actionButtons: some View {
        VStack(spacing: 15) {
            Button(action: toggleFavorite) {
                HStack {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                    Text(isFavorite ? "已收藏" : "收藏")
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.customAccent)
                .cornerRadius(10)
            }
            
            Button(action: {
                navigationPath.removeLast(navigationPath.count)
            }) {
                Text("返回首頁")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.customAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.customAccent, lineWidth: 2)
                    )
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
        var favorites = UserDefaults.standard.array(forKey: "FavoriteNames") as? [[String: String]] ?? []
        favorites.append(["name": name, "analysis": analysis, "wuxing": wuxing.joined(separator: ",")])
        UserDefaults.standard.set(favorites, forKey: "FavoriteNames")
    }
    
    private func removeFavorite() {
        var favorites = UserDefaults.standard.array(forKey: "FavoriteNames") as? [[String: String]] ?? []
        favorites.removeAll { $0["name"] == name }
        UserDefaults.standard.set(favorites, forKey: "FavoriteNames")
    }
    
    private func checkFavoriteStatus() {
        let favorites = UserDefaults.standard.array(forKey: "FavoriteNames") as? [[String: String]] ?? []
        isFavorite = favorites.contains { $0["name"] == name }
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
        case "土": return .brown
        default: return .gray
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
    }
}

struct FavoritesListView: View {
    @State private var favorites: [[String: String]] = []
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
                    ForEach(favorites, id: \.self) { favorite in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(favorite["name"] ?? "")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.customText)
                                
                                Spacer()
                                
                                HStack(spacing: 5) {
                                    ForEach(favorite["wuxing"]?.split(separator: ",") ?? [], id: \.self) { element in
                                        Image(systemName: wuxingIcon(for: String(element)))
                                            .foregroundColor(wuxingColor(for: String(element)))
                                    }
                                }
                            }
                            Text(favorite["analysis"] ?? "")
                                .font(.system(size: 14))
                                .foregroundColor(.customText)
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete(perform: removeFavorite)
                }
                .listStyle(PlainListStyle())
            }
        }
        .onAppear(perform: loadFavorites)
    }
    
    private func loadFavorites() {
        favorites = UserDefaults.standard.array(forKey: "FavoriteNames") as? [[String: String]] ?? []
    }
    
    private func removeFavorite(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        UserDefaults.standard.set(favorites, forKey: "FavoriteNames")
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
        case "土": return .brown
        default: return .gray
        }
    }
}

#Preview {
    ContentView()
}
