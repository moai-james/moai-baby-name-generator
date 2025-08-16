import Foundation

struct Question: Codable, Identifiable {
    let id = UUID()
    let question: String
    let choices: [Choice]
    
    private enum CodingKeys: String, CodingKey {
        case question = "scenario"
        case choices
    }
}

struct Choice: Codable, Hashable {
    let text: String
    let meaning: String
}

struct QuestionResponse: Codable {
    let scenario_questions: [Question]
}

