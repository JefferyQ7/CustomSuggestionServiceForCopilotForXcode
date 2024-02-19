import CopilotForXcodeKit
import Foundation

public actor OpenAIService {
    let url: URL
    let endpoint: Endpoint
    let modelName: String
    let maxToken: Int
    let temperature: Double
    let apiKey: String
    let stopWords: [String]
    
    public enum Endpoint {
        case completion
        case chatCompletion
    }

    public init(
        url: String? = nil,
        endpoint: Endpoint,
        modelName: String,
        maxToken: Int? = nil,
        temperature: Double = 0.2,
        stopWords: [String] = [],
        apiKey: String
    ) {
        self.url = url.flatMap(URL.init(string:)) ?? {
            switch endpoint {
            case .chatCompletion:
                URL(string: "https://api.openai.com/v1/chat/completions")!
            case .completion:
                URL(string: "https://api.openai.com/v1/completions")!
            }
        }()
            
        self.endpoint = endpoint
        self.modelName = modelName
        self.maxToken = maxToken ?? ChatCompletionModels(rawValue: modelName)?.maxToken ?? 4096
        self.temperature = temperature
        self.apiKey = apiKey
        self.stopWords = stopWords
    }
}

extension OpenAIService: CodeCompletionServiceType {
    func getCompletion(_ request: PromptStrategy) async throws -> String {
        let messages = createMessages(from: request)
        CodeCompletionLogger.logger.logPrompt(messages.map {
            ($0.content, $0.role.rawValue)
        })
        return try await sendMessages(messages)
    }
}

extension OpenAIService {
    public struct Message: Codable, Equatable {
        public enum Role: String, Codable {
            case user
            case assistant
            case system
        }

        /// The role of the message.
        public var role: Role
        /// The content of the message.
        public var content: String
    }

    public struct APIError: Decodable {
        var message: String
        var type: String
        var param: String
        var code: String
    }

    public enum Error: Swift.Error, LocalizedError {
        case decodeError(Swift.Error)
        case apiError(APIError)
        case otherError(String)

        public var errorDescription: String? {
            switch self {
            case let .decodeError(error):
                return error.localizedDescription
            case let .apiError(error):
                return error.message
            case let .otherError(message):
                return message
            }
        }
    }

    func createMessages(from request: PromptStrategy) -> [Message] {
        let prompts = request.createPrompt(
            truncatedPrefix: request.prefix,
            truncatedSuffix: request.suffix,
            includedSnippets: request.relevantCodeSnippets
        )
        return [
            // The result is more correct when there is only one message.
            .init(
                role: .user,
                content: ([request.systemPrompt] + prompts).joined(separator: "\n\n")
            ),
        ]
    }

    func sendMessages(_ messages: [Message]) async throws -> String {
        let requestBody = ChatCompletionRequestBody(
            model: modelName,
            messages: messages,
            temperature: temperature,
            stop: stopWords
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (result, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw CancellationError()
        }

        guard response.statusCode == 200 else {
            if let error = try? JSONDecoder().decode(APIError.self, from: result) {
                throw Error.apiError(error)
            }
            throw Error.otherError(String(data: result, encoding: .utf8) ?? "Unknown Error")
        }

        do {
            let body = try JSONDecoder().decode(CompletionResponseBody.self, from: result)
            return body.choices.first?.message.content ?? ""
        } catch {
            dump(error)
            throw Error.decodeError(error)
        }
    }
    
    func sendCompletionRequest(_ prompt: String) async throws -> String {
        fatalError()
    }

    func countToken(_ message: Message) -> Int {
        message.content.count
    }
}

extension OpenAIService {
    public enum ChatCompletionModels: String, CaseIterable {
        case gpt35Turbo = "gpt-3.5-turbo"
        case gpt35Turbo16k = "gpt-3.5-turbo-16k"
        case gpt4 = "gpt-4"
        case gpt432k = "gpt-4-32k"
        case gpt4TurboPreview = "gpt-4-turbo-preview"
        case gpt40314 = "gpt-4-0314"
        case gpt40613 = "gpt-4-0613"
        case gpt41106Preview = "gpt-4-1106-preview"
        case gpt4VisionPreview = "gpt-4-vision-preview"
        case gpt35Turbo0301 = "gpt-3.5-turbo-0301"
        case gpt35Turbo0613 = "gpt-3.5-turbo-0613"
        case gpt35Turbo1106 = "gpt-3.5-turbo-1106"
        case gpt35Turbo0125 = "gpt-3.5-turbo-0125"
        case gpt35Turbo16k0613 = "gpt-3.5-turbo-16k-0613"
        case gpt432k0314 = "gpt-4-32k-0314"
        case gpt432k0613 = "gpt-4-32k-0613"
        case gpt40125 = "gpt-4-0125-preview"
    }

    public enum CompletionModels: String, CaseIterable {
        case gpt35TurboInstruct = "gpt-3.5-turbo-instruct"
    }

    /// https://platform.openai.com/docs/api-reference/chat/create
    struct ChatCompletionRequestBody: Codable, Equatable {
        struct MessageFunctionCall: Codable, Equatable {
            /// The name of the
            var name: String
            /// A JSON string.
            var arguments: String?
        }

        struct Function: Codable {
            var name: String
            var description: String
            /// JSON schema.
            var arguments: String
        }

        var model: String
        var messages: [Message]
        var temperature: Double?
        var top_p: Double?
        var n: Double?
        var stream: Bool?
        var stop: [String]?
        var max_tokens: Int?
        var presence_penalty: Double?
        var frequency_penalty: Double?
        var logit_bias: [String: Double]?

        init(
            model: String,
            messages: [Message],
            temperature: Double? = nil,
            top_p: Double? = nil,
            n: Double? = nil,
            stream: Bool? = nil,
            stop: [String]? = nil,
            max_tokens: Int? = nil,
            presence_penalty: Double? = nil,
            frequency_penalty: Double? = nil,
            logit_bias: [String: Double]? = nil
        ) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.top_p = top_p
            self.n = n
            self.stream = stream
            self.stop = stop
            self.max_tokens = max_tokens
            self.presence_penalty = presence_penalty
            self.frequency_penalty = frequency_penalty
            self.logit_bias = logit_bias
        }
    }

    struct CompletionResponseBody: Codable, Equatable {
        struct Choice: Codable, Equatable {
            var message: Message
            var index: Int
            var finish_reason: String
        }

        struct Usage: Codable, Equatable {
            var prompt_tokens: Int
            var completion_tokens: Int
            var total_tokens: Int
        }

        var id: String?
        var object: String
        var model: String
        var usage: Usage
        var choices: [Choice]
    }
}

public extension OpenAIService.ChatCompletionModels {
    var maxToken: Int {
        switch self {
        case .gpt4:
            return 8192
        case .gpt40314:
            return 8192
        case .gpt432k:
            return 32768
        case .gpt432k0314:
            return 32768
        case .gpt35Turbo:
            return 4096
        case .gpt35Turbo0301:
            return 4096
        case .gpt35Turbo0613:
            return 4096
        case .gpt35Turbo1106:
            return 16385
        case .gpt35Turbo0125:
            return 16385
        case .gpt35Turbo16k:
            return 16385
        case .gpt35Turbo16k0613:
            return 16385
        case .gpt40613:
            return 8192
        case .gpt432k0613:
            return 32768
        case .gpt41106Preview:
            return 128_000
        case .gpt4VisionPreview:
            return 128_000
        case .gpt4TurboPreview:
            return 128_000
        case .gpt40125:
            return 128_000
        }
    }
}

public extension OpenAIService.CompletionModels {
    var maxToken: Int {
        switch self {
        case .gpt35TurboInstruct:
            return 4096
        }
    }
}

