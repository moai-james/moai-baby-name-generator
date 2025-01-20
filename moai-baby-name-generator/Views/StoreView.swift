import SwiftUI

struct StoreView: View {
    @StateObject private var iapManager = IAPManager.shared
    @State private var showSerialNumberInput = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 使用次數商品
                    VStack(alignment: .leading, spacing: 15) {
                        Text("購買使用次數")
                            .font(.custom("NotoSansTC-Black", size: 20))
                            .foregroundColor(.customText)
                        
                        Button(action: {
                            IAPManager.shared.purchaseProduct(.fiveUses)
                        }) {
                            StoreItemRow(
                                icon: "cart.fill",
                                title: "五次使用機會",
                                price: "NT$50",
                                isPurchasing: iapManager.isPurchasing
                            )
                        }
                        .disabled(iapManager.isPurchasing)
                        
                        Button(action: {
                            IAPManager.shared.purchaseProduct(.twentyUses)
                        }) {
                            StoreItemRow(
                                icon: "cart.fill",
                                title: "二十次使用機會",
                                price: "NT$150",
                                isPurchasing: iapManager.isPurchasing
                            )
                        }
                        .disabled(iapManager.isPurchasing)
                        
                        Button(action: {
                            IAPManager.shared.purchaseProduct(.hundredUses)
                        }) {
                            StoreItemRow(
                                icon: "cart.fill",
                                title: "一百次使用機會",
                                price: "NT$490",
                                isPurchasing: iapManager.isPurchasing
                            )
                        }
                        .disabled(iapManager.isPurchasing)
                    }
                    .padding(.horizontal)
                    
                    // 序號兌換
                    // VStack(alignment: .leading, spacing: 15) {
                    //     Text("序號兌換")
                    //         .font(.custom("NotoSansTC-Black", size: 20))
                    //         .foregroundColor(.customText)
                        
                    //     Button(action: {
                    //         showSerialNumberInput = true
                    //     }) {
                    //         StoreItemRow(
                    //             icon: "key.fill",
                    //             title: "輸入序號",
                    //             description: "使用優惠序號兌換使用次數"
                    //         )
                    //     }
                    // }
                    // .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("商城")
            .sheet(isPresented: $showSerialNumberInput) {
                SerialNumberInputView(isPresented: $showSerialNumberInput)
            }
            .overlay(
                Group {
                    if iapManager.showPurchaseSuccess {
                        SuccessPopupView(
                            uses: iapManager.purchasedUses
                        ) {
                            withAnimation {
                                iapManager.showPurchaseSuccess = false
                            }
                        }
                    }
                }
            )
        }
    }
}

struct StoreItemRow: View {
    let icon: String
    let title: String
    var price: String? = nil
    var description: String? = nil
    var isPurchasing: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.customAccent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("NotoSansTC-Regular", size: 18))
                    .foregroundColor(.customText)
                if let description = description {
                    Text(description)
                        .font(.custom("NotoSansTC-Regular", size: 14))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            if isPurchasing {
                ProgressView()
            } else if let price = price {
                Text(price)
                    .foregroundColor(.customAccent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
} 