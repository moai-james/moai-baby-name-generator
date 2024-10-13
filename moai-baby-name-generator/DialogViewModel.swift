//
//  DialogViewModel.swift
//  moai-baby-name-generator
//
//  Created by james hsiao on 2024/10/13.
//

import Foundation
import SwiftOpenAI

class DialogViewModel: ObservableObject {
    @Published var selectedTraits: [String] = []
    @Published var generatedName: String = ""
    @Published var generatedAnalysis: String = ""
    @Published var generatedWuxing: [String] = []
    @Published var isGenerating = false
    @Published var currentQuestionIndex = 0
    @Published var selectedChoices: [String] = []
    @Published var selectedTab = 0

    func generateName(formData: FormData, selectedChoices: [String]) {
        isGenerating = true
        
        // Prepare the prompt for the AI model
        let prompt = preparePrompt(formData: formData, selectedChoices: selectedChoices)
        
        // Call the OpenAI API to generate the name
        Task {
            do {
                let (name, analysis, wuxing) = try await callOpenAIAPI(with: prompt)
                DispatchQueue.main.async {
                    self.generatedName = name
                    self.generatedAnalysis = analysis
                    self.generatedWuxing = wuxing
                    self.isGenerating = false
                }
            } catch {
                print("Error generating name: \(error)")
                DispatchQueue.main.async {
                    self.isGenerating = false
                }
            }
        }
    }

    func loadQuestions() {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load questions.json")
            return
        }
        
        do {
            let jsonDecoder = JSONDecoder()
            let allQuestions = try jsonDecoder.decode(QuestionList.self, from: data)
            
            var combinedQuestions: [Question] = allQuestions.questions.map { question in
                Question(question: question.question, choices: question.choices.map { Choice(meaning: "", text: $0) })
            }
            
            combinedQuestions += allQuestions.scenario_questions.map { scenario in
                Question(question: scenario.scenario, choices: scenario.choices)
            }
            
            questions = Array(combinedQuestions.shuffled().prefix(5))
        } catch {
            print("Failed to decode questions: \(error)")
        }
    }

    private func preparePrompt(formData: FormData, selectedChoices: [String]) -> String {
        let formDataString = "姓氏: \(formData.surname), 指定中間字: \(formData.middleName), 單雙名: \(formData.numberOfNames == 1 ? "單名" : "雙名")"
        let answersString = selectedChoices.joined(separator: ", ")
        return """
        根據以下資訊為嬰兒生成一個中文名字：
        \(formDataString)
        問題回答：\(answersString)
        請生成一個適合的中文名字，並提供簡短的分析解釋這個名字的含義和為什麼它適合這個嬰兒。同時，請為名字中的每個字分析其對應的五行屬性（金木水火土）。
        回覆格式：
        名字：[生成的名字]
        分析：[名字分析]
        五行：[每個字的五行屬性，用逗號分隔，五行屬性的數目必須與姓名字數相同。例1：金，木，水; 例2：火，土，金]
        """
    }

    private func callOpenAIAPI(with prompt: String) async throws -> (String, String, [String]) {
        let apiKey = APIConfig.openAIKey
        let service = OpenAIServiceFactory.service(apiKey: apiKey)
        
        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text("你是一個專業的中文嬰兒命名專家。")),
            .init(role: .user, content: .text(prompt))
        ]
        
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .gpt4TurboPreview
        )
        
        let completionObject = try await service.startChat(parameters: parameters)
        
        guard let responseContent = completionObject.choices.first?.message.content else {
            throw NSError(domain: "OpenAIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No response from OpenAI"])
        }
        
        return parseGeneratedResponse(responseContent)
    }

    private func parseGeneratedResponse(_ response: String) -> (String, String, [String]) {
        let components = response.split(separator: "\n")
        guard components.count == 3 else {
            return ("", "", [])
        }

        let name = String(components[0].dropFirst(3)) // Remove "名字：" prefix
        let analysis = String(components[1].dropFirst(3)) // Remove "分析：" prefix
        let wuxingString = String(components[2].dropFirst(3)) // Remove "五行：" prefix
        let wuxing = wuxingString.split { $0 == "，" || $0 == "、" }.map(String.init)

        return (name, analysis, wuxing)
    }
}
