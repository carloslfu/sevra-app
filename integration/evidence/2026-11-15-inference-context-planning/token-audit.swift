import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText

func emit(_ object: [String: Any]) throws {
 print(String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),as:UTF8.self))
}
let frontend = try SplashTextFrontend(modelFolder: URL(fileURLWithPath: CommandLine.arguments[1]))
for context in [8192,16384,32768,65536,131072,262144,1010000] {
 try emit(["test":"capacity","capacity":context,"profileExists":ContextBudget.Profile(rawValue:context) != nil,"threshold":ContextBudget.maintenanceThreshold(capacity:context)])
}
for profile: ContextBudget.Profile in [.development8K,.evaluation32K,.evaluation64K] {
 let b=ContextBudget(profile:profile);let p=b.maintenanceThreshold-1
 for authoring in [false,true] {
  let a=try b.allowance(promptTokens:p,nativeAppAuthoring:authoring)
  try emit(["test":"reserve","capacity":b.contextTokens,"authoring":authoring,"promptTokens":p,"outputBudget":a.outputTokens,"remainingAfterOutput":b.contextTokens-p-a.outputTokens,"promisedToolAndRecoveryReserve":b.nextToolResultReserve+b.recoveryReserve])
 }
}
for authoring in [false,true] {
 for scope: InferenceToolScope in [.all,.inspection,.finish,.nativeAppReview,.excelCalculation,.excelInterface] {
  let tools=try NativeCitationPolicy.make([],toolScope:scope,thinking:true,nativeAppAuthoring:authoring).promptTools()
  let prompt=try frontend.prepare(messages:[["role":"user","content":"Compare the supplier quotes and show the costs."]],tools:tools,thinking:true,contextLimit:1048576)
  try emit(["test":"schemaOverhead","authoring":authoring,"scope":scope.rawValue,"tools":tools.count,"renderedTokens":prompt.tokens.count])
 }
}
let large=String(repeating:"a",count:1048576)
do {try ContextBudget.validateEnvelope([.init(role:"user",content:large)]);try emit(["test":"byteLimit","refused":false])}
catch {try emit(["test":"byteLimit","refused":true,"error":String(describing:error)])}
for label in ["supplier-text","spanish-text","csv-numbers","application-code"] {
 let row: String
 switch label {
 case "supplier-text":row="Supplier North quotes 250 brass bolts at 0.25 kilograms per package. Delivery is Tuesday; verify the accepted receipt before changing stock.\n"
 case "spanish-text":row="El proveedor ofrece 250 tornillos de latón a 0,25 kilogramos por paquete. La entrega es el martes; verifica el recibo antes de cambiar existencias.\n"
 case "csv-numbers":row="INV-000173,2031-06-14,SKU-008922,271,45.63,19.57,12365.73\n"
 default:row="const total = rows.reduce((sum, row) => sum + Number(row.quantity) * Number(row.price), 0);\n"
 }
 let count=1000000/row.utf8.count;let content=String(repeating:row,count:count)
 let prompt=try frontend.prepare(messages:[["role":"user","content":content]],thinking:true,contextLimit:1048576)
 try emit(["test":"oneMegabyteTokenDensity","fixture":label,"bytes":content.utf8.count,"tokens":prompt.tokens.count])
}
