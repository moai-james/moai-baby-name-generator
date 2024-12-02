import SwiftUI
import FirebaseAuth

struct VerificationCodeView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var verificationCode = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @Environment(\.presentationMode) var presentationMode
    
    let resolver: MultiFactorResolver?
    let verificationId: String?
    
    init(resolver: MultiFactorResolver? = nil, verificationId: String? = nil) {
        self.resolver = resolver
        self.verificationId = verificationId
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("輸入驗證碼")
                .font(.title)
                .fontWeight(.bold)
            
            Text("請輸入傳送至您手機的驗證碼")
                .foregroundColor(.secondary)
            
            TextField("驗證碼", text: $verificationCode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            Button(action: verifyCode) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("驗證")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .navigationTitle("驗證碼")
    }
    
    private func verifyCode() {
        if let resolver = resolver {
            // Handle MFA sign-in verification
            isLoading = true
            errorMessage = ""
            
            Task {
                do {
                    try await authManager.verifyMFA(
                        verificationID: verificationCode,
                        verificationCode: verificationCode,
                        resolver: resolver
                    )
                    isLoading = false
                    presentationMode.wrappedValue.dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        } else if let verificationId = verificationId {
            // Handle MFA enrollment
            isLoading = true
            errorMessage = ""
            
            guard let user = Auth.auth().currentUser else {
                errorMessage = "No user logged in"
                isLoading = false
                return
            }
            
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationId,
                verificationCode: verificationCode
            )
            
            let assertion = PhoneMultiFactorGenerator.assertion(with: credential)
            
            user.multiFactor.enroll(with: assertion, displayName: "Phone") { error in
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } else {
            errorMessage = "驗證資訊無效"
        }
    }
}
