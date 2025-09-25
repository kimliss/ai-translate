import ArgumentParser
import Foundation

struct EnvUtil {

    struct Config {
        let languages: [String]
        let openAIKey: String
        let openAIHost: String
        let model: String
    }

    static func loadEnvFile() -> [String: String] {
        let envPath = FileManager.default.currentDirectoryPath + "/.env"
        let envURL = URL(fileURLWithPath: envPath)

        guard let envContent = try? String(contentsOf: envURL) else {
            return [:]
        }

        var envVars: [String: String] = [:]
        let lines = envContent.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            // 跳过空行和注释行
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            // 分割键值对
            let components = trimmedLine.components(separatedBy: "=")
            if components.count >= 2 {
                let key = components[0].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let value = components.dropFirst().joined(separator: "=")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))  // 移除引号

                envVars[key] = value
            }
        }

        return envVars
    }

    static func loadAndValidateConfig(
        languages: [String],
        openAIKey: String,
        openAIHost: String,
        model: String
    ) throws -> Config {
        let envVars = loadEnvFile()

        // 从环境变量填充缺失的参数
        let resolvedLanguages =
            languages.isEmpty
            ? gatherLanguages(from: envVars["LANGUAGES"] ?? "") : languages
        let resolvedOpenAIKey =
            openAIKey.isEmpty ? (envVars["OPENAI_API_KEY"] ?? "") : openAIKey
        let resolvedOpenAIHost =
            openAIHost.isEmpty
            ? (envVars["OPENAI_HOST"] ?? "api.openai.com") : openAIHost
        let resolvedModel =
            model.isEmpty ? (envVars["MODEL"] ?? "gpt-4o-mini") : model

        // 验证必要参数
        try validateRequiredParameters(
            languages: resolvedLanguages,
            openAIKey: resolvedOpenAIKey
        )

        return Config(
            languages: resolvedLanguages,
            openAIKey: resolvedOpenAIKey,
            openAIHost: resolvedOpenAIHost,
            model: resolvedModel
        )
    }

    private static func validateRequiredParameters(
        languages: [String],
        openAIKey: String
    ) throws {
        guard !languages.isEmpty else {
            throw ValidationError(
                "Languages must be specified either via command line (-l) or .env file (LANGUAGES)"
            )
        }

        guard !openAIKey.isEmpty else {
            throw ValidationError(
                "OpenAI API key must be specified either via command line (-k) or .env file (OPENAI_API_KEY)"
            )
        }
    }

    static func gatherLanguages(from input: String) -> [String] {
        input.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

}
