// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Qualification builds use an isolated product directory. This is a build-time
// migration switch, never a user-selectable runtime backend.
let nativeCandidate = ProcessInfo.processInfo.environment["SEVRA_NATIVE_CANDIDATE"] == "1"

let package = Package(
  name: "Sevra", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "sevra-automation-ui-checks", targets: ["SevraAutomationUIChecks"]),
    .library(name: "SevraCore", targets: ["SevraCore"]),
    .executable(name: "SevraDesktop", targets: ["SevraApp"]),
    .executable(name: "sevra", targets: ["SevraCLI"]),
    .executable(name: "sevra-extract", targets: ["SevraExtractionWorker"]),
    .executable(name: "sevra-extraction-checks", targets: ["SevraExtractionChecks"]),
    .executable(name: "sevra-checks", targets: ["SevraChecks"]),
    .executable(name: "sevra-table-ui-checks", targets: ["SevraTableUIChecks"]),
    .executable(name: "sevra-search-ui-checks", targets: ["SevraSearchUIChecks"]),
    .executable(name: "sevra-product-checks", targets: ["SevraProductChecks"]),
    .executable(name: "sevra-voice-checks", targets: ["SevraVoiceChecks"]),
    .executable(name: "sevra-context-durability", targets: ["SevraContextDurability"]),
    .executable(name: "sevra-workflow-durability", targets: ["SevraWorkflowDurability"]),
    .executable(name: "sevra-automation-durability", targets: ["SevraAutomationDurability"]),
    .executable(name: "sevra-document-checks", targets: ["SevraDocumentChecks"]),
    .executable(name: "sevra-preview-checks", targets: ["SevraPreviewChecks"]),
    .executable(name: "sevra-benchmark", targets: ["SevraBenchmark"]),
    .executable(name: "sevra-splash-checks", targets: ["SevraSplashChecks"]),
    .executable(name: "sevra-splash-text-checks", targets: ["SevraSplashTextChecks"]),
    .executable(name: "sevra-splash-grammar-checks", targets: ["SevraSplashGrammarChecks"]),
    .executable(name: "sevra-agent-checks", targets: ["SevraAgentChecks"]),
    .executable(name: "sevra-native-setup", targets: ["SevraNativeSetup"]),
    .executable(name: "sevra-inference-performance", targets: ["SevraInferencePerformance"]),
    .executable(name: "sevra-workflow-performance", targets: ["SevraWorkflowPerformance"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/carloslfu/slotstream.git",
      revision: "7578fb21e57ec362d19f5050922e0f583914935d"),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.3.5"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
  ],
  targets: [
    .target(
      name: "SevraAutomationUI", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraAutomationUIChecks", dependencies: ["SevraCore", "SevraAutomationUI"],
      path: "IntegrationTests/AutomationUI", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraPreviewUI",
      dependencies: [
        "SevraCore", "SevraTableUI",
        .product(name: "Markdown", package: "swift-markdown"),
      ], swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraPreviewChecks", dependencies: ["SevraCore", "SevraPreviewUI", "SevraTableUI"],
      path: "IntegrationTests/Preview", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraDocumentUI", dependencies: ["SevraCore"], swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(
      name: "SevraDocumentChecks", dependencies: ["SevraCore", "SevraDocumentUI"],
      path: "IntegrationTests/Documents", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraContextDurability", dependencies: ["SevraCore"],
      path: "IntegrationTests/ContextDurability", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraWorkflowDurability", dependencies: ["SevraCore"],
      path: "IntegrationTests/WorkflowDurability", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraAutomationDurability", dependencies: ["SevraCore"],
      path: "IntegrationTests/AutomationDurability", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "SevraVoice", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraVoiceChecks", dependencies: ["SevraVoice"],
      path: "IntegrationTests/Voice", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraWorkflowPerformance",
      dependencies: [
        "SevraCore", "SevraAI", "SevraNativeAI", "SevraSplash", "SevraSplashText",
        "SevraSplashGrammar",
      ],
      path: "IntegrationTests/WorkflowPerformance", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraInferencePerformance",
      dependencies: ["SevraSplash", "SevraSplashText", "SevraSplashGrammar"],
      path: "IntegrationTests/Performance", swiftSettings: [.swiftLanguageMode(.v5)]),
    .systemLibrary(name: "CSQLite"),
    .systemLibrary(name: "CLLGuidance"),
    .target(
      name: "SevraSplashGrammar", dependencies: ["SevraSplash", "SevraSplashText", "CLLGuidance"],
      resources: [.copy("Resources/json-slices.json")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraSplashGrammarChecks",
      dependencies: ["SevraSplashGrammar", "SevraSplashText", "SevraSplash"],
      path: "IntegrationTests/Grammar", resources: [.copy("fixtures.json")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraSplash", resources: [.copy("Resources/selected-model.json")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraNativeSetup", dependencies: ["SevraSplash"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraSplashChecks", dependencies: ["SevraSplash"], path: "IntegrationTests/Splash",
      resources: [.copy("protocol_golden.txt")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraSplashText",
      dependencies: [
        "SevraSplash",
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "Hub", package: "swift-transformers"),
      ],
      resources: [.copy("Resources/template-patch.json")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraSplashTextChecks", dependencies: ["SevraSplashText", "SevraSplash"],
      path: "IntegrationTests/Text",
      resources: [.copy("fixtures.json"), .copy("output-fixtures.json")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraCore",
      dependencies: [
        "CSQLite", "ZIPFoundation", .product(name: "Markdown", package: "swift-markdown"),
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraExtractionWorker", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraExtractionChecks", dependencies: ["SevraCore"],
      path: "IntegrationTests/Extraction", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraAI", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraBaseline",
      dependencies: ["SevraAI", "SevraCore", .product(name: "Slotstream", package: "slotstream")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraNativeAI",
      dependencies: [
        "SevraAI", "SevraCore", "SevraSplash", "SevraSplashText", "SevraSplashGrammar",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraProduct",
      dependencies: nativeCandidate
        ? [
          "SevraCore", "SevraAI", "SevraNativeAI", "SevraSplash", "SevraSplashText",
          "SevraSplashGrammar",
        ]
        : ["SevraCore", "SevraAI", "SevraBaseline"],
      swiftSettings: [.swiftLanguageMode(.v5)]
        + (nativeCandidate ? [.define("SEVRA_NATIVE_CANDIDATE")] : [])),
    .target(
      name: "SevraTableUI", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraSearchUI", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraSearchUIChecks", dependencies: ["SevraSearchUI", "SevraCore"],
      path: "IntegrationTests/SearchUI", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraTableUIChecks", dependencies: ["SevraTableUI", "SevraCore"],
      path: "IntegrationTests/TableUI", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraProductChecks",
      dependencies: [
        "SevraProduct", "SevraCore", "SevraAI", "SevraNativeAI", "SevraSplash", "SevraSplashText",
      ] + (nativeCandidate ? [] : ["SevraBaseline"]),
      path: "IntegrationTests/Product",
      swiftSettings: [.swiftLanguageMode(.v5)]
        + (nativeCandidate ? [.define("SEVRA_NATIVE_CANDIDATE")] : [])),
    .executableTarget(
      name: "SevraApp",
      dependencies: [
        "SevraCore", "SevraAI", "SevraProduct", "SevraTableUI", "SevraSearchUI", "SevraVoice",
        "SevraDocumentUI", "SevraPreviewUI", "SevraAutomationUI",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraCLI", dependencies: ["SevraCore", "SevraAI", "SevraProduct"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraBenchmark", dependencies: ["SevraCore"], path: "Benchmarks",
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraChecks", dependencies: ["SevraCore"], path: "Tests",
      resources: [.copy("Fixtures")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraAgentChecks",
      dependencies: [
        "SevraNativeAI", "SevraAI", "SevraBaseline", "SevraCore", "SevraSplashGrammar",
        "SevraSplashText",
        "SevraSplash",
      ],
      path: "IntegrationTests/Agent",
      resources: [.copy("workbook-tools.json"), .copy("tool-grammar-fixtures.json")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
  ])
