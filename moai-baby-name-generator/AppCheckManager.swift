//
//  AppCheckManager.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/11/20.
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

class DeviceCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        return DeviceCheckProvider(app: app)
    }
}

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
        let provider = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(provider)
        print("✅ Using Production App Check Provider")
        #endif
    }
    
    func getAppCheckToken() async throws -> String {
        let token = try await AppCheck.appCheck().token(forcingRefresh: false)
        return token.token
    }
}