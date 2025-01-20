import SwiftUI
import UIKit

struct SerialNumberInputView: View {
    @Binding var isPresented: Bool
    @State private var serialNumber = ""
    @State private var showError = false
    @State private var errorMessage = "序號無效！請檢查您的輸入後重試。"
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Serial number input field
                TextField("請輸入序號", text: $serialNumber)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($isInputFocused)
                    .padding(.horizontal)
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Confirm button
                Button(action: validateSerialNumber) {
                    Text("確認")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(serialNumber.isEmpty ? Color.gray : Color.customAccent)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                }
                .disabled(serialNumber.isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("輸入序號")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("取消") {
                isPresented = false
            })
            .onAppear {
                // 自動顯示鍵盤
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isInputFocused = true
                }
            }
        }
    }
    
    private func validateSerialNumber() {
        // 目前所有序號都視為無效
        showError = true
        
        // 震動反饋
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

struct SerialNumberInputView_Previews: PreviewProvider {
    static var previews: some View {
        SerialNumberInputView(isPresented: .constant(true))
    }
} 