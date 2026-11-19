import SevraCore

@main struct Worker {
  static func main() {
    ExtractionWorker.runMain(
      behavior: ExcelBehaviorRuntime.evaluate, layout: DiagramLayout.evaluate,
      script: ChatScriptRuntime.evaluate)
  }
}
