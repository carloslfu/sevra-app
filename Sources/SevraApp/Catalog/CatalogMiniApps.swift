import Foundation

/// Small recipes use the shipped SDK, rather than drawing a second set of controls.
enum CatalogMiniApps {
  static func source(
    type: String, variant: String, label: String, spacing: Int = 16, columns: Int = 2,
    vertical: Bool = false
  ) -> String {
    let title = String(
      data: try! JSONEncoder().encode(
        label.isEmpty
          ? (variant == "Long labels"
            ? "A deliberately long workshop input label that wraps across narrow native layouts"
            : "Workshop input") : label), encoding: .utf8)!
    let disabled = variant == "Disabled" ? "false" : "true"
    var props = "{label:\(title),enabled:\(disabled),gap:\(spacing)}"
    var children = "Sevra.h('text',{text:'First section'}),Sevra.h('text',{text:'Second section'})"
    switch type {
    case "text":
      props = "{text:\(title),size:24,selectable:true}"
      children = ""
    case "textField", "textEditor":
      props =
        "{label:\(title),value:draft,enabled:\(disabled)\(type == "textField" ? ",placeholder:'Enter a value'" : "")}"
      children = ""
    case "toggle":
      props = "{title:\(title),value:Sevra.signal(false),enabled:\(disabled)}"
      children = ""
    case "picker":
      props =
        "{label:\(title),value:Sevra.signal('Oak'),options:['Oak','Cedar','Birch'],enabled:\(disabled)}"
      children = ""
    case "slider":
      props = "{label:\(title),value:Sevra.signal(35),min:0,max:100,enabled:\(disabled)}"
      children = ""
    case "date":
      props = "{label:'Delivery date',value:Sevra.signal('2026-11-17'),enabled:\(disabled)}"
      children = ""
    case "button":
      props = "{title:\(title),enabled:\(disabled),onClick:()=>status.value='Action invoked'}"
      children = ""
    case "progress":
      props = "{label:'Reading evidence',value:0.6,indeterminate:false}"
      children = ""
    case "table":
      props = "{table:'stock',label:'Stock records',height:300}"
      children = ""
    case "tabs": props = "{label:'Workspace',titles:['Inputs','Results'],value:Sevra.signal(0)}"
    case "disclosure": props = "{title:'Source details',value:Sevra.signal(true)}"
    case "grid": props = "{columns:\(columns),gap:\(spacing)}"
    case "section": props = "{label:'Evidence',padding:12}"
    case "split": props = "{vertical:\(vertical),height:240}"
    case "image":
      props = "{asset:'photo',caption:'Included synthetic image',width:240,height:140}"
      children = ""
    case "view":
      props = "{viewID:'stockView'}"
      children = ""
    case "canvas":
      props =
        "{width:480,height:280,shapes:[{type:'rect',x:24,y:24,width:160,height:70,color:'accent'},{type:'circle',x:240,y:60,width:60,height:60,color:'green'},{type:'line',x:190,y:60,x2:240,y2:90,color:'secondary'},{type:'text',x:38,y:45,text:'Order 1042',color:'primary'}],regions:[{id:'order',label:'Order 1042',x:24,y:24,width:160,height:70}],onClick:e=>status.value='Selected '+e.value,onDrop:e=>status.value='Moved order'}"
      children = ""
    case "spacer":
      props = "{height:80}"
      children = ""
    default: break
    }
    if variant == "Empty",
      ["column", "row", "grid", "split", "scroll", "section", "tabs", "disclosure"].contains(type)
    {
      children = ""
    }
    if variant == "Dense", ["column", "row", "grid", "scroll", "section"].contains(type) {
      children = (0..<18).map { "Sevra.h('text',{text:'Section \($0+1)'})" }.joined(separator: ",")
    }
    let node =
      "Sevra.h(" + String(data: try! JSONEncoder().encode(type), encoding: .utf8)! + "," + props
      + (children.isEmpty ? "" : "," + children) + ")"
    let primitive = [
      "column", "row", "grid", "split", "scroll", "section", "text", "button", "textField",
      "textEditor", "toggle", "picker", "slider", "date", "progress", "table", "tabs", "disclosure",
      "canvas", "image", "view", "spacer",
    ].contains(type)
    let helper: String
    switch type {
    case "Fragment":
      helper =
        "Sevra.h(Sevra.Fragment,{},Sevra.h('text',{text:'Fragment first child'}),Sevra.h('text',{text:'Fragment second child'}))"
    case "ActionForm", "action": helper = "Sevra.h(Sevra.ActionForm,{action:'saveItem'})"
    case "For":
      helper =
        "Sevra.h('column',{},Sevra.h(Sevra.For,{each:list,by:item=>item.id},item=>Sevra.h('text',{text:()=>item.value.name})),Sevra.h('button',{title:'Reverse keyed rows',onClick:()=>list.value=[...list.value].reverse()}))"
    case "signal", "computed", "batch", "effect":
      helper =
        "Sevra.h('column',{},Sevra.h('text',{text:()=> 'Count '+counter.value+' · Double '+double.value}),Sevra.h('button',{title:'Increment',onClick:()=>Sevra.batch(()=>{counter.value++;status.value='Batched update';})}))"
    case "draftSignal":
      helper =
        "Sevra.h('column',{},Sevra.h('textField',{label:'Saved draft',value:draft}),Sevra.h('text',{text:'Restart the app to restore the draft.'}))"
    case "liveQuery":
      helper =
        "Sevra.h('column',{},Sevra.h('text',{text:()=> 'Live records: '+(live.value?.rows?.length||0)}),Sevra.h(Sevra.ActionForm,{action:'saveItem'}),Sevra.h('table',{table:'stock',label:'Live stock'}))"
    case "calculate": helper = "Sevra.h(Sevra.ActionForm,{action:'calculate'})"
    default:
      helper =
        "Sevra.h(Sevra.Workspace,{sections:[{title:'Stock',table:'stock',actions:['saveItem']},{title:'Calculate',actions:['calculate']}]})"
    }
    let fieldType = type.hasPrefix("ActionInput.") ? String(type.dropFirst(12)) : "text"
    let actualHelper =
      type.hasPrefix("ActionInput.") ? "Sevra.h(Sevra.ActionForm,{action:'typedInput'})" : helper
    return """
      const draft=Sevra.draftSignal('name','Brass bolts'),status=Sevra.signal(''),counter=Sevra.signal(2),double=Sevra.computed(()=>counter.value*2),list=Sevra.signal([{id:'a',name:'Oak'},{id:'b',name:'Cedar'}]);
      Sevra.action('typedInput',{title:'Submit typed input',enabled:\(disabled),inputs:{answer:{type:'\(fieldType)',title:'Typed answer',...(\(fieldType == "record" ? "true":"false") ? {choices:['Oak','Cedar']}: {})}}},async a=>{status.value='Accepted '+JSON.stringify(a);return a;});
      const live=Sevra.liveQuery({table:'stock'});
      Sevra.effect(()=>{const value=counter.value; if(value>2) status.value='Effect observed '+value;});
      const saveItem=Sevra.action('saveItem',{title:'Save stock',enabled:\(disabled),inputs:{name:{type:'text',title:'Item'},quantity:{type:'decimal',title:'Quantity'}}},async a=>{if(!a.name.trim())throw Error('Enter an item name');if(Number(a.quantity)<0)throw Error('Quantity must be positive');const r=await Sevra.data.transaction([{op:'insert',table:'stock',values:a}]);status.value='Saved';return r;});
      Sevra.action('calculate',{title:'Calculate cost',inputs:{amount:{type:'decimal'}}},async a=>{status.value=await Sevra.calculate('amount*12',{amount:a.amount});});
      Sevra.mount(\(primitive ? "Sevra.h('column',{gap:16,padding:16},"+node+",Sevra.h('text',{text:status,label:'Action result'}))" : "Sevra.h('column',{gap:16,padding:16},Sevra.h('text',{text:'Workshop stock',size:26,weight:'bold'}),"+actualHelper+",Sevra.h('text',{text:status}))"));
      """
  }
}
