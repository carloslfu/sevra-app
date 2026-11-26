import CQuickJS
import Darwin
import Foundation
import SevraCore

@_silgen_name("sandbox_init")
private func enterSandbox(
  _ profile: UnsafePointer<CChar>, _ flags: UInt64,
  _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32
@_silgen_name("sandbox_free_error")
private func freeSandboxError(_ error: UnsafeMutablePointer<CChar>)

/// Runs one script of the `run` chat tool. The script can reach nothing by itself: no file,
/// no network, no clock.
///
/// It reaches the workbook only by asking the host. This process answers no call. It lists
/// the calls the script made, the host answers them, and the script runs again from the top
/// with those answers until it returns. A script is therefore run several times, and must do
/// the same thing each time, which is why the clock is fixed and randomness is refused.
enum ChatScriptRuntime {
  static func evaluate(_ url: URL) throws -> Value {
    let file = try FileHandle(forReadingFrom: url)
    let bytes = try file.read(upToCount: 4_000_001) ?? Data()
    try file.close()
    try require(bytes.count <= 4_000_000, "run_limit", "The script's input exceeds 4 MB.")
    let request = try Value.parse(String(decoding: bytes, as: UTF8.self))
    let source = request["source"].text
    try require(
      !source.isEmpty && source.utf8.count <= 32_000 && !source.contains("\0"), "run",
      "Send JavaScript under 32,000 bytes.")
    // Read the one input first, then give up all OS access before any script runs.
    // There is no unsandboxed fallback.
    var error: UnsafeMutablePointer<CChar>?
    let profile = "(version 1)(deny default)(allow sysctl-read)(allow process-info*)"
    let status = profile.withCString { enterSandbox($0, 0, &error) }
    if let error { freeSandboxError(error) }
    try require(status == 0, "run_sandbox", "The script sandbox could not start.")
    if let probe = request["sandboxProbe"].string {
      let descriptor = Darwin.open(probe, O_RDONLY)
      let deniedRead = descriptor < 0 && errno == EPERM
      if descriptor >= 0 { Darwin.close(descriptor) }
      let write = Darwin.open(probe + ".probe", O_WRONLY | O_CREAT | O_EXCL, 0o600)
      let deniedWrite = write < 0 && errno == EPERM
      if write >= 0 { Darwin.close(write) }
      return .object(["deniedRead": .bool(deniedRead), "deniedWrite": .bool(deniedWrite)])
    }
    guard let engine = sevra_js_create() else {
      throw SevraError("run", "The script runtime could not start.")
    }
    defer { sevra_js_destroy(engine) }
    // Check the script alone first, so a stray brace reads as the script's mistake.
    let body = "(async()=>{\n" + source + "\n})"
    guard let syntax = body.withCString({ sevra_js_check_syntax(engine, $0, body.utf8.count, 500) })
    else { throw SevraError("run", "The script could not be checked.") }
    let diagnostic = String(cString: syntax)
    sevra_js_free(syntax)
    if diagnostic.hasPrefix("!") {
      throw SevraError(
        "run",
        "The script has a syntax error: "
          + String(diagnostic.dropFirst().split(separator: "\n").first ?? "").prefix(400)
          + ". Line numbers start one line above your code. Write the body of an async function: statements that end with return.")
    }
    // A saved tool's body is checked when it is saved, without running it.
    if request["checkOnly"] == .bool(true) { return .object(["syntax": .string("ok")]) }
    let now = request["now"].int ?? 0
    let script = """
      const __answers=\(try Value.array(request["answers"].array).json()),__calls=[],__requests=[],__log=[];
      const __now=\(now),__today=\(try Value.string(request["today"].text).json());
      {const Native=Date;
       globalThis.Date=class extends Native{constructor(...a){if(a.length===0)super(__now);else super(...a);}static now(){return __now;}};}
      globalThis.Atomics=undefined;globalThis.SharedArrayBuffer=undefined;
      Math.random=()=>{throw Error('run has no randomness.');};
      const __text=x=>typeof x==='string'?x:JSON.stringify(x);
      const __print=(...a)=>{if(__log.length<40)__log.push(a.map(__text).join(' ').slice(0,400));};
      globalThis.console=Object.freeze({log:__print,info:__print,warn:__print,error:__print});
      const __host=(method,args)=>{
        const index=__calls.length;
        __calls.push({method,args:JSON.parse(JSON.stringify(args))});
        if(index<__answers.length){
          const answer=__answers[index];
          return 'error' in answer?Promise.reject(Error(answer.error)):Promise.resolve(answer.value);
        }
        return new Promise(()=>{});
      };
      const sql=(statement,values)=>__host('sql',{statement:String(statement),values:values??null});
      const tool=(name,values)=>__host('tool',{name:String(name),values:JSON.parse(JSON.stringify(values??{}))});
      const search=query=>__host('search',{query:String(query)});
      const read=id=>__host('read',{id:String(id)});
      const action=(name,args)=>{__requests.push({action:String(name),arguments:JSON.parse(JSON.stringify(args??{}))});return {queued:__requests.length};};
      const today=__today;
      const inputs=Object.freeze(\(try Value.object(request["inputs"].object).json()));
      let __state={done:false};
      (async()=>{
      \(source)
      })().then(
        value=>{__state={done:true,value:value===undefined?null:value};},
        error=>{__state={done:true,error:String((error&&error.message)||error),errorName:String((error&&error.name)||'')};});
      globalThis.Sevra=Object.freeze({__flush:()=>({...__state,calls:__calls,requests:__requests,log:__log})});
      """
    guard let output = script.withCString({ sevra_js_eval(engine, $0, script.utf8.count, 1_000) })
    else { throw SevraError("run", "The script runtime failed.") }
    defer { sevra_js_free(output) }
    let text = String(cString: output)
    if text.hasPrefix("!") {
      var message = String(text.dropFirst().split(separator: "\n", maxSplits: 1).first ?? "")
      if message.hasPrefix("Error: ") { message.removeFirst(7) }
      throw SevraError(
        "run", message.isEmpty ? "The script failed." : String(message.prefix(1_000)))
    }
    try require(text.utf8.count <= 2_000_000, "run_limit", "The script's result exceeds 2 MB.")
    return try Value.parse(text)
  }
}
