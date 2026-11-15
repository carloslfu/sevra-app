import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText
let frontend = try SplashTextFrontend(modelFolder: URL(fileURLWithPath: CommandLine.arguments[1]))
let row="INV-000173,2031-06-14,SKU-008922,271,45.63,19.57,12365.73\n"
for count in [320,360,400] {
 let text=String(repeating:row,count:count)
 let messages:[[String:any Sendable]]=[["role":"system","content":"Selected workbook data:\n"+text],["role":"user","content":"Compare these invoice totals without changing any records."]]
 try ContextBudget.validateEnvelope([.init(role:"system",content:"Selected workbook data:\n"+text),.init(role:"user",content:"Compare these invoice totals without changing any records.")])
 for scope:InferenceToolScope in [.all,.answer,.finish] {
  let tools=try NativeCitationPolicy.make([],toolScope:scope,thinking:true,nativeAppAuthoring:false).promptTools()
  let p=try frontend.prepare(messages:messages,tools:tools,thinking:true,contextLimit:1048576)
  let data=try JSONSerialization.data(withJSONObject:["rows":count,"scope":scope.rawValue,"promptTokens":p.tokens.count,"under32KMaintenanceThreshold":p.tokens.count<24576,"sourceBytes":text.utf8.count],options:[.sortedKeys]);print(String(decoding:data,as:UTF8.self))
 }
}
