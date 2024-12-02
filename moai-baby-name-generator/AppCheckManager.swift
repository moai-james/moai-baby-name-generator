//
//  AppCheckManager.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/11/20.
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

class AppCheckManager {
    static let shared = AppCheckManager()
    
    private init() {}
    
    func configureAppCheck() {
        #if DEBUG
        // Debug configuration
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("⚠️ Using Debug App Check configuration")
        
        // Get and print the debug token for testing
        Task {
            do {
                let token = try await AppCheck.appCheck().token(forcingRefresh: true)
                print("🔐 Debug App Check Token: \(token.token)")
            } catch {
                print("❌ Error getting debug token: \(error)")
            }
        }
        
        #else
        // Production configuration
        if #available(iOS 14.0, *) {
            let provider = AppAttestProvider()
            AppCheck.setAppCheckProviderFactory(provider)
            print("✅ Using AppAttest Provider for App Check")
        } else {
            let provider = DeviceCheckProvider()
            AppCheck.setAppCheckProviderFactory(provider)
            print("✅ Using DeviceCheck Provider for App Check")
        }
        #endif
    }
    
    func getAppCheckToken() async throws -> String {
        let token = try await AppCheck.appCheck().token(forcingRefresh: false)
        return token.token
    }
}