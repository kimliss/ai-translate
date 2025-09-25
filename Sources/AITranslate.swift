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
    
  static let configuration = CommandConfiguration(
      abstract: "A command line tool that performs translation of xcstrings",
      usage: """
      ai-translate /path/to/your/Localizable.xcstrings
      ai-translate /path/to/your/Localizable.xcstrings -v -f
      """,
      discussion: """
      VERSION: 1.0.0
      """
  )
    
  static let systemPrompt =
    """
    You are a translator tool that translates UI strings for a software application.
    Your inputs will be a source language, a target language, the original text, and
    optionally some context to help you understand how the original text is used within
    the application. Each piece of information will be inside some XML-like tags.
    In your response include *only* the translation, and do not include any metadata, tags, 
    periods, quotes, or new lines, unless included in the original text.
    Placeholders (like %@, %d, %1$@, etc) should be preserved exactly as they appear in the original text.
    Treat multi-letter abbreviations (such as common technical acronyms like "HTML", "URL", "API", "HTTP", "HTTPS", "JSON", "XML", "CPU", "GPU", "RAM", "ID", "UI", "UX", etc) as case-sensitive and do not translate them.
    """

  static func gatherLanguages(from input: String) -> [String] {
    input.split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespaces) }
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
    help: ArgumentHelp("Your Model, see: https://platform.openai.com/docs/models, e,g (gpt-3.5-turbo, gpt-4o-mini, gpt-4o)")
  )
  var model: String = ""

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("Max number of concurrent translation tasks (default: 5)")
  )
  var concurrency: Int = 5

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

  lazy var openAI: OpenAI = {
    let configuration = OpenAI.Configuration(
      token: openAIKey,
      organizationIdentifier: nil,
      host: openAIHost,
      timeoutInterval: 60.0
    )

    return OpenAI(configuration: configuration)
  }()

  var numberOfTranslationsProcessed = 0

  mutating func run() async throws {
    let config = try EnvUtil.loadAndValidateConfig(
      languages: languages,
      openAIKey: openAIKey,
      openAIHost: openAIHost,
      model: model
    )
    languages = config.languages
    openAIKey = config.openAIKey
    openAIHost = config.openAIHost
    model = config.model

    if verbose {
      print("[📁] Using languages: \(languages.joined(separator: ", "))")
      print("[🤖] Using model: \(model)")
      print("[🌐] Using host: \(openAIHost)")
      print("[⚙️] concurrency: \(concurrency)")
    }

    do {
      let dict = try JSONDecoder().decode(
        StringsDict.self,
        from: try Data(contentsOf: inputFile)
      )

      let entries = Array(dict.strings)
      let totalNumberOfTranslations = dict.strings.count * languages.count
      let start = Date()
      var previousPercentage: Int = -1

      let languagesLocal = languages
      let modelLocal = model
      let openAIClient = openAI
      let verboseLocal = verbose
      let forceLocal = force
      let sourceLanguageLocal = dict.sourceLanguage

      var numberProcessedLocal = numberOfTranslationsProcessed

      let batchSize = max(1, concurrency)
      var currentIndex = 0
      while currentIndex < entries.count {
        let endIndex = min(currentIndex + batchSize, entries.count)
        let batch = entries[currentIndex..<endIndex]

        await withTaskGroup(of: (String, LocalizationGroup).self) { group in
          for entry in batch {
            let key = entry.key
            let localizationGroup = entry.value

            group.addTask {
              let updated = await Self.processEntry(
                key: key,
                localizationGroup: localizationGroup,
                sourceLanguage: sourceLanguageLocal,
                languages: languagesLocal,
                model: modelLocal,
                openAI: openAIClient,
                force: forceLocal,
                verbose: verboseLocal
              )
              return (key, updated)
            }
          }

          for await (key, updatedGroup) in group {
            dict.strings[key] = updatedGroup

            numberProcessedLocal += languagesLocal.count

            let fractionProcessed = Double(numberProcessedLocal) / Double(totalNumberOfTranslations)
            let percentageProcessed = Int(fractionProcessed * 100)

            if percentageProcessed != previousPercentage, percentageProcessed % 10 == 0 {
              print("[⏳] \(percentageProcessed)%")
              previousPercentage = percentageProcessed
            }
          }
        }

        currentIndex = endIndex
      }

      numberOfTranslationsProcessed = numberProcessedLocal

      try save(dict)

      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = [.hour, .minute, .second]
      formatter.unitsStyle = .full
      let formattedString = formatter.string(from: Date().timeIntervalSince(start))!

      print("[✅] 100% \n[⏰] Translations time: \(formattedString)")
    } catch let error {
      throw error
    }
  }

  static func processEntry(
    key: String,
    localizationGroup: LocalizationGroup,
    sourceLanguage: String,
    languages: [String],
    model: String,
    openAI: OpenAI,
    force: Bool,
    verbose: Bool
  ) async -> LocalizationGroup {
    let localizationGroup = localizationGroup
    var localizationEntries = localizationGroup.localizations ?? [:]

    for lang in languages {
      let unit = localizationEntries[lang]

      if let unit, unit.hasTranslation, force == false {
        continue
      }

      if let unit, unit.isSupportedFormat == false {
        if verbose {
          print("[⚠️] Unsupported format in entry with key: \(key) for lang: \(lang)")
        }
        continue
      }

      let sourceText = localizationEntries[sourceLanguage]?.stringUnit?.value ?? key

      let result: String?
      if (localizationGroup.shouldTranslate != false) {
        result = await Self.performTranslation(
          sourceText,
          from: sourceLanguage,
          to: lang,
          context: localizationGroup.comment,
          model: model,
          openAI: openAI,
          verbose: verbose
        )
      } else {
        result = key
        if verbose {
          print("[\(lang)] " + key + " -> skip")
        }
      }

      localizationEntries[lang] = LocalizationUnit(
        stringUnit: StringUnit(
          state: result == nil ? "error" : "translated",
          value: result ?? ""
        )
      )
    }

    localizationGroup.localizations = localizationEntries
    return localizationGroup
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

      try? FileManager.default.trashItem(
        at: backupFileURL,
        resultingItemURL: nil
      )

      try FileManager.default.moveItem(
        at: inputFile,
        to: backupFileURL
      )
    }
  }

  static func performTranslation(
      _ text: String,
      from source: String,
      to target: String,
      context: String? = nil,
      model: String,
      openAI: OpenAI,
      verbose: Bool
    ) async -> String? {
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

      if let context {
        translationRequest += "<context>\(context)</context>"
      }

      let query = ChatQuery(
        messages: [
          .init(role: .system, content: Self.systemPrompt)!,
          .init(role: .user, content: translationRequest)!
        ],
        model: model
      )

      do {
        let result = try await openAI.chats(query: query)
        let translation = result.choices.first?.message.content?.string ?? text

        if verbose {
          print("[\(target)] " + text + " -> " + translation)
        }

        return translation
      } catch {
        print("[❌] Failed to translate \(text) into \(target)")
        if verbose {
          print("[💥] " + error.localizedDescription)
        }
        return nil
      }
    }
  }
