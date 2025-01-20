import SwiftUI
import FirebaseAuth
import Combine
import FirebaseFirestore

enum AuthError: Error {
    case signInError(String)
}

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var error: AuthError?
    
    static let shared = AuthenticationManager()
    
    private init() {
        currentUser = Auth.auth().currentUser
        isAuthenticated = currentUser != nil
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
                        
            DispatchQueue.main.async {
                self.currentUser = result.user
                self.isAuthenticated = true
            }
        } catch let error as NSError {
            throw AuthError.signInError(error.localizedDescription)
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        DispatchQueue.main.async {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
    
    func verifyMFA(verificationID: String, verificationCode: String, resolver: MultiFactorResolver) async throws {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        let assertion = PhoneMultiFactorGenerator.assertion(with: credential)
        
        do {
            let result = try await resolver.resolveSignIn(with: assertion)
            DispatchQueue.main.async {
                self.currentUser = result.user
                self.isAuthenticated = true
            }
        } catch {
            throw AuthError.signInError(error.localizedDescription)
        }
    }
    
    func enrollMFA(phoneNumber: String) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw AuthError.signInError("No user logged in")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
                if let error = error {
                    continuation.resume(throwing: AuthError.signInError(error.localizedDescription))
                    return
                }
                
                if let verificationID = verificationID {
                    continuation.resume(returning: verificationID)
                } else {
                    continuation.resume(throwing: AuthError.signInError("Failed to get verification ID"))
                }
            }
        }
    }
    
    func startMFAEnrollment(phoneNumber: String) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.signInError("No user logged in")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            user.multiFactor.getSessionWithCompletion { session, error in
                if let error = error {
                    continuation.resume(throwing: AuthError.signInError(error.localizedDescription))
                    return
                }
                
                guard let session = session else {
                    continuation.resume(throwing: AuthError.signInError("Failed to get MFA session"))
                    return
                }
                
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    phoneNumber,
                    uiDelegate: nil,
                    multiFactorSession: session
                ) { verificationID, error in
                    if let error = error {
                        continuation.resume(throwing: AuthError.signInError(error.localizedDescription))
                        return
                    }
                    
                    if let verificationID = verificationID {
                        continuation.resume(returning: verificationID)
                    } else {
                        continuation.resume(throwing: AuthError.signInError("Failed to get verification ID"))
                    }
                }
            }
        }
    }
    
    func checkPhoneNumberExists(_ phoneNumber: String) async throws -> Bool {
        guard let user = Auth.auth().currentUser else {
            print("❌ [Auth] 檢查手機號碼時發現用戶未登入")
            throw AuthError.signInError("No user logged in")
        }
        
        print("📱 [Auth] 開始檢查手機號碼: \(phoneNumber)")
        
        // 獲取用戶的 MFA 信息
        let enrolledFactors = user.multiFactor.enrolledFactors
        
        // 檢查是否已經有相同的手機號碼被註冊為 MFA
        for factor in enrolledFactors {
            if let phoneMultiFactor = factor as? PhoneMultiFactorInfo,
               phoneMultiFactor.phoneNumber == phoneNumber {
                print("✅ [Auth] 手機號碼已被用於 MFA")
                return true
            }
        }
        
        print("✅ [Auth] 手機號碼未被用於 MFA")
        return false
    }
    
}
