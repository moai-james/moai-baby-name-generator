//
//  IAPManager.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/11/7.
//

import StoreKit
import FirebaseFirestore
import FirebaseAuth

enum IAPProduct {
    case fiveUses
    case twentyUses
    case hundredUses
    
    var id: String {
        switch self {
        case .fiveUses:
            return "com.moai.babynamer.uses"
        case .twentyUses:
            return "com.moai.babynamer.20uses"
        case .hundredUses:
            return "com.moai.babynamer.100uses"
        }
    }
    
    var uses: Int {
        switch self {
        case .fiveUses:
            return 5
        case .twentyUses:
            return 20
        case .hundredUses:
            return 100
        }
    }
}

class IAPManager: NSObject, ObservableObject {
    static let shared = IAPManager()
    
    @Published var products: [SKProduct] = []
    @Published var isLoading = false
    @Published var isPurchasing = false
    @Published var purchaseError: String?
    @Published var showPurchaseSuccess = false
    @Published var purchasedUses: Int = 0
    
    private override init() {
        super.init()
        print("🛍️ [IAP] 初始化 IAPManager")
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }
    
    private func fetchProducts() {
        print("🛍️ [IAP] 開始獲取產品信息")
        let productIDs = Set([
            IAPProduct.fiveUses.id,
            IAPProduct.twentyUses.id,
            IAPProduct.hundredUses.id
        ])
        print("🛍️ [IAP] 請求產品 IDs: \(productIDs)")
        isLoading = true
        let request = SKProductsRequest(productIdentifiers: productIDs)
        request.delegate = self
        request.start()
    }
    
    func purchaseProduct(_ product: IAPProduct) {
        guard let skProduct = products.first(where: { $0.productIdentifier == product.id }) else {
            print("❌ [IAP] 找不到產品: \(product.id)")
            return
        }
        
        if SKPaymentQueue.canMakePayments() {
            isPurchasing = true
            purchaseError = nil
            print("✅ [IAP] 開始購買產品: \(skProduct.productIdentifier)")
            let payment = SKPayment(product: skProduct)
            SKPaymentQueue.default().add(payment)
        } else {
            print("❌ [IAP] 用戶無法進行付款")
            purchaseError = "設備無法進行付款"
        }
    }
    
    private func handlePurchase(_ transaction: SKPaymentTransaction) {
        let productID = transaction.payment.productIdentifier
        
        Task {
            if let product = IAPProduct.allCases.first(where: { $0.id == productID }) {
                do {
                    // 1. 先在外部宣告變數
                    var previousUses: Int = 0
                    
                    // 2. 在主線程更新本地使用次數
                    await MainActor.run {
                        previousUses = UsageManager.shared.remainingUses
                        UsageManager.shared.remainingUses += product.uses
                    }
                    
                    // 3. 嘗試更新雲端資料，最多重試 3 次
                    var retryCount = 0
                    while retryCount < 3 {
                        do {
                            try await UsageManager.shared.updateCloudData()
                            break
                        } catch {
                            retryCount += 1
                            if retryCount == 3 {
                                throw error
                            }
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                    
                    if let userId = Auth.auth().currentUser?.uid {
                        try await Firestore.firestore().collection("purchases").addDocument(data: [
                            "userId": userId,
                            "productId": productID,
                            "uses": product.uses,
                            "timestamp": Date()
                        ])
                    }
                    
                    await MainActor.run {
                        SKPaymentQueue.default().finishTransaction(transaction)
                        self.isPurchasing = false
                        self.purchaseError = nil
                        self.purchasedUses = product.uses
                        self.showPurchaseSuccess = true
                    }
                } catch {
                    await MainActor.run {
                        self.purchaseError = "購買處理失敗：\(error.localizedDescription)"
                        self.isPurchasing = false
                    }
                    print("❌ [IAP] 處理購買時發生錯誤: \(error)")
                }
            }
        }
    }
}

extension IAPManager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.products = response.products
            self.isLoading = false
            
            print("🛍️ [IAP] 收到產品響應")
            print("🛍️ [IAP] 有效產品數量: \(response.products.count)")
            print("🛍️ [IAP] 無效產品 ID: \(response.invalidProductIdentifiers)")
            
            if response.products.isEmpty {
                print("No products found")
            }
        }
    }
}

extension IAPManager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        DispatchQueue.main.async {
            for transaction in transactions {
                print("🛍️ [IAP] 交易狀態更新: \(transaction.transactionState.rawValue)")
                
                switch transaction.transactionState {
                case .purchased:
                    print("✅ [IAP] 購買成功")
                    self.isPurchasing = false
                    self.handlePurchase(transaction)
                    
                case .failed:
                    print("❌ [IAP] 購買失敗")
                    if let error = transaction.error as? SKError {
                        switch error.code {
                        case .paymentCancelled:
                            self.purchaseError = "購買已取消"
                            print("❌ [IAP] 用戶取消購買")
                        case .paymentInvalid:
                            self.purchaseError = "付款無效"
                            print("❌ [IAP] 付款無效")
                        case .paymentNotAllowed:
                            self.purchaseError = "此設備不允許付款"
                            print("❌ [IAP] 設備不允許付款")
                        default:
                            self.purchaseError = "購買失敗：\(error.localizedDescription)"
                            print("❌ [IAP] 其他錯誤：\(error.localizedDescription)")
                        }
                    } else if let error = transaction.error {
                        self.purchaseError = "購買失敗：\(error.localizedDescription)"
                        print("❌ [IAP] 錯誤：\(error.localizedDescription)")
                    }
                    self.isPurchasing = false
                    SKPaymentQueue.default().finishTransaction(transaction)
                    
                case .restored:
                    print("✅ [IAP] 恢復購買")
                    self.isPurchasing = false
                    self.handlePurchase(transaction)
                    
                case .deferred:
                    print("⏳ [IAP] 交易延遲")
                    
                case .purchasing:
                    print("⏳ [IAP] 購買中...")
                    
                @unknown default:
                    print("❓ [IAP] 未知狀態")
                }
            }
        }
    }
}

extension IAPProduct: CaseIterable {}
