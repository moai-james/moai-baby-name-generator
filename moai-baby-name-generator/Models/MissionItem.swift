import Foundation

struct MissionItem: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let rewardUses: Int
    var isCompleted: Bool
    var isRewardClaimed: Bool
    let type: MissionType
    
    enum MissionType: String, Codable {
        case dailyLogin = "daily_login"
        case twoFactorAuth = "two_factor_auth"
        case accountLink = "account_link"
        case appRating = "app_rating"
    }
} 