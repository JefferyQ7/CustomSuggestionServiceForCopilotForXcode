import CopilotForXcodeKit
import Foundation

public final class CodeCompletionLogger {
    struct Model {
        var type: String
        var format: String
        var modelName: String
        var baseURL: String
    }

    @TaskLocal public static var logger: CodeCompletionLogger = .init(request: SuggestionRequest(
        fileURL: .init(filePath: "/"),
        relativePath: "",
        language: .plaintext,
        content: "",
        lines: [],
        cursorPosition: .zero,
        tabSize: 0,
        indentSize: 0,
        usesTabsForIndentation: false,
        relevantCodeSnippets: []
    ))

    let request: SuggestionRequest
    var model = Model(type: "", format: "", modelName: "", baseURL: "")
    var prompt: [(message: String, role: String)] = []
    var responses: [String] = []
    let startTime = Date()
    
    var shouldLogToConsole: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.shared.value(for: \.verboseLog)
        #endif
    }

    public init(request: SuggestionRequest) {
        self.request = request
    }

    public func logModel(_ chatModel: ChatModel) {
        model = .init(
            type: "Chat Completion",
            format: chatModel.format.rawValue,
            modelName: chatModel.info.modelName,
            baseURL: chatModel.info.baseURL
        )
    }

    public func logModel(_ completionModel: CompletionModel) {
        model = .init(
            type: "Chat Completion",
            format: completionModel.format.rawValue,
            modelName: completionModel.info.modelName,
            baseURL: completionModel.info.baseURL
        )
    }
    
    public func logModel(_ tabbyModel: TabbyModel) {
        model = .init(
            type: "Tabby",
            format: "N/A",
            modelName: "N/A",
            baseURL: tabbyModel.url
        )
    }

    public func logPrompt(_ prompt: [(message: String, role: String)]) {
        self.prompt = prompt
    }

    public func logResponse(_ response: String) {
        responses.append(response)
    }

    public func error(_ error: Error) {
        guard shouldLogToConsole else { return }
        
        let now = Date()
        let duration = now.timeIntervalSince(startTime)
        let formattedDuration = String(format: "%.2f", duration)
        
        Logger.service.info("""
        [Request] 
        
        Duration: \(formattedDuration)
        Error: \(error.localizedDescription).
        """)
    }

    public func finish() {
        guard shouldLogToConsole else { return }

        let now = Date()
        let duration = now.timeIntervalSince(startTime)
        let formattedDuration = String(format: "%.2f", duration)

        Logger.service.info("""
        [Request]

        Format: \(model.format)
        Model Name: \(model.modelName)
        Base URL: \(model.baseURL)
        Duration: \(formattedDuration)
        ---
        File URL: \(request.fileURL)
        Code Snippets: \(request.relevantCodeSnippets.count) snippets
        CursorPosition: \(request.cursorPosition)

        [Prompt]

        \(prompt.map { "\($0.role): \($0.message)" }.joined(separator: "\n\n"))

        [Response]

        \(responses.enumerated().map { "\($0 + 1): \($1)" }.joined(separator: "\n\n"))
        """)
    }
}

