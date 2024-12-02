import SwiftUI
import FirebaseAuth
import Combine

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
        guard let user = Auth.auth().currentUser else {
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
    
}
