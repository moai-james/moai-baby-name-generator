import SwiftUI
import FirebaseAuth

struct ForgotPasswordView: View {
    @Binding var isPresented: Bool
    @State private var email = ""
    @State private var message: String?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("重設密碼")
                    .font(.custom("NotoSansTC-Black", size: 24))
                    .foregroundColor(.customText)
                
                Text("請輸入您的電子郵件地址，我們將寄送重設密碼連結給您。")
                    .font(.custom("NotoSansTC-Regular", size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                CustomTextField(
                    placeholder: "電子郵件",
                    text: $email,
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
                .padding(.horizontal)
                
                if let message = message {
                    Text(message)
                        .foregroundColor(message.contains("已寄出") ? .green : .red)
                        .font(.custom("NotoSansTC-Regular", size: 14))
                }
                
                Button(action: resetPassword) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("送出")
                            .font(.custom("NotoSansTC-Regular", size: 18))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.customAccent)
                .cornerRadius(25)
                .padding(.horizontal)
                .disabled(email.isEmpty || isLoading)
            }
            .navigationBarItems(trailing: Button("關閉") {
                isPresented = false
            })
        }
    }
    
    private func resetPassword() {
        isLoading = true
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            isLoading = false
            if let error = error {
                message = error.localizedDescription
            } else {
                message = "重設密碼連結已寄出，請查收電子郵件"
            }
        }
    }
}
