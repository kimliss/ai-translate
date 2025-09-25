//
//  AITranslate.swift
//
//
//  Created by Paul MacRory on 3/7/24.
//

import ArgumentParser
import OpenAI
import Foundation

@main
struct AITranslate: AsyncParsableCommand {
  static let systemPrompt =
    """
    You are a translator tool that translates UI strings for a software application.
    Your inputs will be a source language, a target language, the original text, and
    optionally some context to help you understand how the original text is used within
    the application. Each piece of information will be inside some XML-like tags.
    In your response include *only* the translation, and do not include any metadata, tags, 
    periods, quotes, or new lines, unless included in the original text.
    """

  static func gatherLanguages(from input: String) -> [String] {
    input.split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespaces) }
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
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
        continue
      }
      let components = trimmedLine.components(separatedBy: "=")
      if components.count >= 2 {
        let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = components.dropFirst().joined(separator: "=")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        envVars[key] = value
      }
    }
    return envVars
  }

  @Argument(transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("A comma separated list of language codes (must match the language codes used by xcstrings)"),
    transform: AITranslate.gatherLanguages(from:)
  )
  var languages: [String] = []

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("Your OpenAI API key, see: https://platform.openai.com/api-keys")
  )
  var openAIKey: String = ""
    
  @Option(
    name: .customLong("host"),
    help: ArgumentHelp("Your OpenAI Proxy Host")
  )
  var openAIHost: String = ""

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("Your Model, see: https://platform.openai.com/docs/models")
  )
  var model: String = ""

  @Flag(name: .shortAndLong)
  var verbose: Bool = false

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp("By default a backup of the input will be created. When this flag is provided, the backup is skipped.")
  )
  var skipBackup: Bool = false

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp("Forces all strings to be translated, even if an existing translation is present.")
  )
  var force: Bool = false

  private var resolvedLanguages: [String] = []
  private var resolvedOpenAIKey: String = ""
  private var resolvedOpenAIHost: String = ""
  private var resolvedModel: String = ""

  lazy var openAI: OpenAI = {
    let configuration = OpenAI.Configuration(
      token: resolvedOpenAIKey,
      organizationIdentifier: nil,
      host: resolvedOpenAIHost,
      timeoutInterval: 60.0
    )
    return OpenAI(configuration: configuration)
  }()

  mutating func run() async throws {
    let envVars = Self.loadEnvFile()
    
    resolvedLanguages = languages.isEmpty ?
      Self.gatherLanguages(from: envVars["LANGUAGES"] ?? "") : languages
    
    resolvedOpenAIKey = openAIKey.isEmpty ?
      (envVars["OPENAI_API_KEY"] ?? "") : openAIKey
    
    resolvedOpenAIHost = openAIHost.isEmpty ?
      (envVars["OPENAI_HOST"] ?? "api.openai.com") : openAIHost
    
    resolvedModel = model.isEmpty ?
      (envVars["MODEL"] ?? "gpt-4o-mini") : model
    
    guard !resolvedLanguages.isEmpty else {
      throw ValidationError("Languages must be specified either via command line (-l) or .env file (LANGUAGES)")
    }
    
    guard !resolvedOpenAIKey.isEmpty else {
      throw ValidationError("OpenAI API key must be specified either via command line (-k) or .env file (OPENAI_API_KEY)")
    }
    
    if verbose {
      print("[📁] Using languages: \(resolvedLanguages.joined(separator: ", "))")
      print("[🤖] Using model: \(resolvedModel)")
      print("[🌐] Using host: \(resolvedOpenAIHost)")
    }

    let dict = try JSONDecoder().decode(
      StringsDict.self,
      from: try Data(contentsOf: inputFile)
    )

    let totalLanguages = resolvedLanguages.count
    var processedLanguages = 0
    let start = Date()

    for lang in resolvedLanguages {
      try await processLanguage(lang, dict: dict, sourceLanguage: dict.sourceLanguage)

      processedLanguages += 1
      try save(dict) // 保存当前语言的翻译结果

      let percentage = Int((Double(processedLanguages) / Double(totalLanguages)) * 100)
      print("[⏳] 已完成 \(processedLanguages)/\(totalLanguages) 个语言 (\(percentage)%)")
    }

    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .full
    let formattedString = formatter.string(from: Date().timeIntervalSince(start))!
    print("[✅] 所有语言翻译完成 \n[⏰] 总耗时: \(formattedString)")
  }

  mutating func processLanguage(_ lang: String, dict: StringsDict, sourceLanguage: String) async throws {
    let semaphore = DispatchSemaphore(value: 5)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for entry in dict.strings {
        group.addTask {
          semaphore.wait()
          defer { semaphore.signal() }
          try await self.processEntry(
            key: entry.key,
            localizationGroup: entry.value,
            sourceLanguage: sourceLanguage,
            targetLanguage: lang
          )
        }
      }
      try await group.waitForAll()
    }
  }

  mutating func processEntry(
    key: String,
    localizationGroup: LocalizationGroup,
    sourceLanguage: String,
    targetLanguage: String
  ) async throws {
    let localizationEntries = localizationGroup.localizations ?? [:]
    let unit = localizationEntries[targetLanguage]

    if let unit, unit.hasTranslation, force == false { return }
    if let unit, unit.isSupportedFormat == false {
      print("[⚠️] Unsupported format in entry with key: \(key)")
      return
    }

    let sourceText = localizationEntries[sourceLanguage]?.stringUnit?.value ?? key
    let result: String?
    if localizationGroup.shouldTranslate != false {
      result = try await performTranslation(
        sourceText,
        from: sourceLanguage,
        to: targetLanguage,
        context: localizationGroup.comment,
        openAI: openAI
      )
    } else {
      result = key
      if verbose { print("[\(targetLanguage)] \(key) -> skip") }
    }

    var newEntries = localizationEntries
    newEntries[targetLanguage] = LocalizationUnit(
      stringUnit: StringUnit(
        state: result == nil ? "error" : "translated",
        value: result ?? ""
      )
    )
    localizationGroup.localizations = newEntries
  }

  func save(_ dict: StringsDict) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    let data = try encoder.encode(dict)
    try backupInputFileIfNecessary()
    try data.write(to: inputFile)
  }

  func backupInputFileIfNecessary() throws {
    if skipBackup == false {
      let backupFileURL = inputFile.appendingPathExtension("original")
      try? FileManager.default.trashItem(at: backupFileURL, resultingItemURL: nil)
      try FileManager.default.moveItem(at: inputFile, to: backupFileURL)
    }
  }

  func performTranslation(
    _ text: String,
    from source: String,
    to target: String,
    context: String? = nil,
    openAI: OpenAI
  ) async throws -> String? {
    if text.isEmpty ||
        text.trimmingCharacters(
          in: .whitespacesAndNewlines
            .union(.symbols)
            .union(.controlCharacters)
        ).isEmpty {
      return text
    }

    var translationRequest = "<source>\(source)</source>"
    translationRequest += "<target>\(target)</target>"
    translationRequest += "<original>\(text)</original>"
    if let context { translationRequest += "<context>\(context)</context>" }

    let query = ChatQuery(
      messages: [
        .init(role: .system, content: Self.systemPrompt)!,
        .init(role: .user, content: translationRequest)!
      ],
      model: resolvedModel
    )

    do {
      let result = try await openAI.chats(query: query)
      let translation = result.choices.first?.message.content?.string ?? text
      if verbose {
        print("[\(target)] \(text) -> \(translation)")
      }
      return translation
    } catch {
      print("[❌] Failed to translate \(text) into \(target)")
      if verbose { print("[💥] " + error.localizedDescription) }
      return nil
    }
  }
}
