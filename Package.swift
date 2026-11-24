// swift-tools-version: 6.2
import Foundation
import PackageDescription

let uiCatalog = ProcessInfo.processInfo.environment["SEVRA_UI_CATALOG"] == "1"

let sparkleDirectory = ProcessInfo.processInfo.environment["SEVRA_SPARKLE_FRAMEWORK_DIR"]
precondition(sparkleDirectory == nil || !uiCatalog,
             "Sparkle is only linked into the distribution build")

let package = Package(
  name: "Sevra", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "sevra-app-worker", targets: ["SevraAppWorker"]),
    .executable(name: "sevra-native-app-checks", targets: ["SevraNativeAppChecks"]),
    .executable(
      name: "sevra-accessibility-headless-checks", targets: ["SevraAccessibilityHeadlessChecks"]),
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
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.3.5"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    // Already resolved through swift-transformers; the text frontend renders prompts with it.
    .package(url: "https://github.com/huggingface/swift-jinja.git", exact: "2.5.2"),
  ],
  targets: [
    .executableTarget(
      name: "SevraAccessibilityHeadlessChecks",
      dependencies: ["SevraCore", "SevraPreviewUI", "SevraTableUI", "SevraDocumentUI"],
      path: "IntegrationTests/AccessibilityHeadless", exclude: ["NoUI.sb"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraAutomationUI", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraAutomationUIChecks", dependencies: ["SevraCore", "SevraAutomationUI"],
      path: "IntegrationTests/AutomationUI", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "SevraMedia", dependencies: ["SevraCore"]),
    .target(name: "SevraVisualUI", dependencies: ["SevraCore", "SevraMedia"]),
    .target(
      name: "SevraPreviewUI",
      dependencies: [
        "SevraCore", "SevraTableUI", "SevraMedia", "SevraVisualUI",
        .product(name: "Markdown", package: "swift-markdown"),
      ], swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraPreviewChecks",
      dependencies: ["SevraCore", "SevraMedia", "SevraPreviewUI", "SevraTableUI", "SevraVisualUI"],
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
    .target(
      name: "CQuickJS", exclude: ["LICENSE"],
      sources: ["quickjs.c", "cutils.c", "libregexp.c", "libunicode.c", "dtoa.c", "SevraJS.c"],
      publicHeadersPath: "include",
      cSettings: [.define("CONFIG_VERSION", to: "\"2026-06-04\""), .define("_GNU_SOURCE")]),
    .target(
      name: "SevraAppProtocol", dependencies: ["SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraAppRuntime", dependencies: ["SevraCore", "SevraAppProtocol", "CQuickJS"],
      resources: [.copy("Resources/sdk.js"), .copy("Resources/Signals-LICENSE.txt")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraAppUI",
      dependencies: [
        "SevraCore", "SevraAppProtocol", "SevraPreviewUI", "SevraMedia", "SevraVisualUI",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraAppWorker", dependencies: ["SevraAppRuntime", "SevraAppProtocol", "SevraCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraNativeAppChecks",
      dependencies: ["SevraAppRuntime", "SevraAppProtocol", "SevraCore", "SevraAppUI"],
      path: "IntegrationTests/NativeApps", swiftSettings: [.swiftLanguageMode(.v5)]),
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
        .product(name: "Jinja", package: "swift-jinja"),
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
      name: "SevraExtractionWorker", dependencies: ["SevraCore", "CQuickJS"],
      resources: [
        .copy("Resources/elk.bundled.js"), .copy("Resources/ELK-LICENSE.md"),
        .copy("Resources/ELK-NOTICE.txt"),
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraExtractionChecks", dependencies: ["SevraCore"],
      path: "IntegrationTests/Extraction", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraAI", dependencies: ["SevraCore", "SevraAppProtocol"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraNativeAI",
      dependencies: [
        "SevraAI", "SevraCore", "SevraSplash", "SevraSplashText", "SevraSplashGrammar",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraProduct",
      dependencies: [
        "SevraCore", "SevraAI", "SevraNativeAI", "SevraSplash", "SevraSplashText",
        "SevraSplashGrammar",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]),
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
      ],
      path: "IntegrationTests/Product",
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraApp",
      dependencies: [
        "SevraVisualUI",
        "SevraCore", "SevraAI", "SevraProduct", "SevraTableUI", "SevraSearchUI", "SevraVoice",
        "SevraDocumentUI", "SevraPreviewUI", "SevraAutomationUI", "SevraAppUI", "SevraAppProtocol",
      ],
      exclude: uiCatalog ? [] : ["Catalog"],
      swiftSettings: [.swiftLanguageMode(.v5)] + (uiCatalog ? [.define("SEVRA_UI_CATALOG")] : [])
        + (sparkleDirectory.map { [.define("SEVRA_DISTRIBUTION"), .unsafeFlags(["-F", $0])] } ?? []),
      linkerSettings: sparkleDirectory.map {
        [.unsafeFlags(["-F", $0, "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
         .linkedFramework("Sparkle")]
      }),
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
        "SevraAppUI",
        "SevraNativeAI", "SevraAI", "SevraCore", "SevraSplashGrammar",
        "SevraSplashText",
        "SevraSplash",
      ],
      path: "IntegrationTests/Agent",
      resources: [.copy("workbook-tools.json"), .copy("tool-grammar-fixtures.json")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
  ])
