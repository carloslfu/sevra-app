import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText
actor AuditModel: WorkbookInference {
 let identity="CPU tokenizer/controller audit; no inference"
 let supportsCompaction=true
 let lastMetrics:Value = .null
 let frontend:SplashTextFrontend
 let scope:InferenceToolScope
 var measurements:[[String:Int]]=[]
 var dispatched=false
 init(_ frontend:SplashTextFrontend,_ scope:InferenceToolScope){self.frontend=frontend;self.scope=scope}
 func beginRun(){}
 func endRun(){}
 func measureContext(messages:[InferenceMessage],directory:URL,cancellation:Cancellation,summary:Bool,citationIDs:[String],progress:@escaping @Sendable(String)->Void)throws->ContextMeasurement {
  let tools=summary ? nil : try NativeCitationPolicy.make(citationIDs,toolScope:scope,thinking:true,itemReferenceIDs:ItemReferenceCandidates.ids(in:messages),conversationActions:messages.first?.conversationActions,documentCopyIDs:DocumentCopyCandidates.ids(in:messages),historyReferenceIDs:ItemReferenceCandidates.historyIDs(in:messages),nativeAppAuthoring:messages.first?.nativeAppAuthoring == true).promptTools()
  let prompt=try frontend.prepare(messages:messages.map(nativeTemplateMessage),tools:tools,thinking: !summary,contextLimit:SplashWire.maxTokens)
  measurements.append(["promptTokens":prompt.tokens.count,"threshold":24576])
  return .init(promptTokens:prompt.tokens.count,capacity:32768,templateIdentity:frontend.templateIdentity)
 }
 func summarize(messages:[InferenceMessage],allowedMessageIDs:[String],directory:URL,cancellation:Cancellation,progress:@escaping @Sendable(String)->Void)throws->String {throw SevraError("audit_unexpected_summary","No closed history to compact")}
 func respond(messages:[InferenceMessage],directory:URL,cancellation:Cancellation,progress:@escaping @Sendable(String)->Void,toolScope:InferenceToolScope,citationIDs:[String])throws->NativeReply {dispatched=true;throw SevraError("audit_dispatch_reached","CPU audit stopped before model generation")}
}
@main struct Audit {
 static func main() async throws {
  let frontend=try SplashTextFrontend(modelFolder:URL(fileURLWithPath:CommandLine.arguments[1]))
  let row="INV-000173,2031-06-14,SKU-008922,271,45.63,19.57,12365.73\n"
  for count in [280,320,400] {
   for scope:InferenceToolScope in [.all,.answer] {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("sevra-context-cpu-"+identifier()+".sevra")
    let book=try Workbook.create(at:root,title:"Context audit")
    let model=AuditModel(frontend,scope);var errorCode="none"
    do {_ = try await WorkbookAgent.run("Compare these invoice totals. Do not change anything.",workbook:book,context:String(repeating:row,count:count),model:model)}catch {errorCode=(error as? SevraError)?.code ?? String(describing:error)}
    let row:[String:Any] = ["rows":count,"measurementScope":scope.rawValue,"dispatched":await model.dispatched,"error":errorCode,"measurements":await model.measurements,"workbookIntegrity":try book.verify()["ok"] == .bool(true)]
    print(String(decoding:try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]),as:UTF8.self))
    try FileManager.default.removeItem(at:root)
   }
  }
 }
}
