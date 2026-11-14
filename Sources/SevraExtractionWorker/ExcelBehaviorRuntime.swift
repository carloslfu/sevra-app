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

enum ExcelBehaviorRuntime {
  // Keep native Date private. Only a primitive ISO date leaves this closure; generated
  // code cannot obtain a Date instance/constructor or read the clock or local timezone.
  private static let calendarPrelude = #"""
    globalThis.calendar=(()=>{
      const NativeDate=Date;
      return Object.freeze({addDays(iso,days){
        if(typeof iso!=='string'||iso.length!==10||!/^\d{4}-\d{2}-\d{2}$/.test(iso)
          ||typeof days!=='number'||!Number.isFinite(days)||Math.abs(days)>3660000)
          throw Error('calendar.addDays needs an ISO date and a finite day offset within 3660000 days');
        const [year,month,day]=iso.split('-').map(Number);
        const value=new NativeDate(0);
        value.setUTCFullYear(year,month-1,day);
        if(year<1||year>9999||value.getUTCFullYear()!==year
          ||value.getUTCMonth()!==month-1||value.getUTCDate()!==day)
          throw Error('calendar.addDays needs a valid Gregorian date from 0001-01-01 through 9999-12-31');
        value.setTime(value.getTime()+days*86400000);
        if(!Number.isFinite(value.getTime())||value.getUTCFullYear()<1||value.getUTCFullYear()>9999)
          throw Error('calendar.addDays result is outside 0001-01-01 through 9999-12-31');
        return value.toISOString().slice(0,10);
      }});
    })();
    """#
  private static func syntaxContext(_ diagnostic: String, source: String) -> String {
    guard let location = diagnostic.range(of: "excel-behavior.js:") else { return "" }
    let parts = diagnostic[location.upperBound...].split(separator: ":", maxSplits: 2)
    guard parts.count >= 2, let line = Int(parts[0]),
      let column = Int(parts[1].prefix(while: { $0.isNumber })), line > 0, column > 0
    else { return "" }
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    guard line <= lines.count else { return "" }
    // QuickJS counts Unicode scalars, not UTF-16 units or Swift grapheme clusters.
    let scalars = Array(lines[line - 1].unicodeScalars)
    guard column <= scalars.count + 1 else { return "" }
    let offset = column - 1
    let before = String(String.UnicodeScalarView(scalars[max(0, offset - 100)..<offset]))
    let after = String(String.UnicodeScalarView(scalars[offset..<min(scalars.count, offset + 100)]))
    var result =
      "\nParser stopped at ⟦HERE⟧ on source line \(line), column \(column):\n"
      + before + "⟦HERE⟧" + after
      + "\nAn expecting-token error can indicate an unexpected token here, not a missing delimiter."
    if offset < scalars.count, scalars[offset] == ";", diagnostic.contains("expecting '}'") {
      result +=
        " An object literal uses commas between entries; a statement semicolon belongs after its closing brace."
    }
    return result
  }

  static func evaluate(_ url: URL) throws -> Value {
    let file = try FileHandle(forReadingFrom: url)
    let bytes = try file.read(upToCount: 4_000_001) ?? Data()
    try file.close()
    try require(bytes.count <= 4_000_000, "excel_behavior_limit", "Calculation input exceeds 4 MB.")
    let request = try Value.parse(String(decoding: bytes, as: UTF8.self))
    let source = request["source"].text
    try require(
      !source.isEmpty && source.utf8.count <= 131_072 && !source.contains("\0"),
      "excel_behavior", "Use a bounded behavior function.")
    // Read the sole input first, then irrevocably remove OS access before evaluating code.
    // No unsandboxed fallback: an unavailable platform sandbox refuses the calculation.
    var error: UnsafeMutablePointer<CChar>?
    let profile = "(version 1)(deny default)(allow sysctl-read)(allow process-info*)"
    let status = profile.withCString { enterSandbox($0, 0, &error) }
    if let error { freeSandboxError(error) }
    try require(status == 0, "excel_sandbox", "The isolated calculation sandbox could not start.")
    // A bounded host-side audit uses the same production profile. No file is read or created.
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
      throw SevraError("excel_behavior", "Cannot allocate calculation runtime.")
    }
    defer { sevra_js_destroy(engine) }
    // Parse the candidate on its own, without executing it. Otherwise a stray closing
    // brace can escape the wrapper syntactically and produce a misleading wrapper error.
    guard
      let syntax = source.withCString({
        sevra_js_check_syntax(engine, $0, source.utf8.count, 500)
      })
    else { throw SevraError("excel_behavior", "Cannot check calculation syntax.") }
    let diagnostic = String(cString: syntax)
    sevra_js_free(syntax)
    if diagnostic.hasPrefix("!") {
      throw SevraError(
        "excel_behavior",
        "Invalid excelBehavior.source: " + String(diagnostic.dropFirst().prefix(1800))
          + syntaxContext(diagnostic, source: source)
          + "\nThe location refers to your source, not a wrapper. Reformat the function into clear blocks and correct the unexpected token or delimiter before resubmitting. Do not repeat unchanged source. Source ending:\n"
          + String(source.suffix(700)))
    }
    let script = """
      \(calendarPrelude)
      globalThis.Date=undefined;globalThis.Atomics=undefined;globalThis.SharedArrayBuffer=undefined;
      Math.random=()=>{throw Error('Randomness needs an explicit input');};Object.freeze(Math);
      const __rawInput=\(try request["input"].json()),__hidden=new Set(\(try Value.array(request["hiddenOutputs"].array).json()));
      const __address=/^sheet[1-9][0-9]*![A-Z]+[1-9][0-9]*$/;
      __rawInput.cells=new Proxy(__rawInput.cells,{get(target,key){if(Object.prototype.hasOwnProperty.call(target,key))return target[key];if(__hidden.has(key))throw Error('Compute derived cell '+key+' from input cells; its saved answer is hidden');if(typeof key==='string'&&__address.test(key))return '';if(typeof key==='string'&&key!=='toJSON'&&!Reflect.has(target,key))throw Error('Invalid Excel cell key '+JSON.stringify(key.slice(0,80))+'. Read input.cells["sheet1!B2"], never input.cells.c2 or input.cells["c2"]. Available input addresses: '+Object.keys(target).slice(0,16).join(', '));return Reflect.get(target,key);}});
      const __input=new Proxy(__rawInput,{get(target,key){if(typeof key==='string'&&key!=='toJSON'&&!Reflect.has(target,key))throw Error('Invalid recreate input property '+JSON.stringify(key.slice(0,80))+'. Input has event, cells and arguments. Read Excel values from input.cells["sheet1!B2"], not input.c2 or input["sheet1!B2"].');return Reflect.get(target,key);}});
      const __result=(()=>{'use strict';\n\(source)\nreturn recreate(__input);})();
      if(!__result||typeof __result!=='object'||Array.isArray(__result)||typeof __result.then==='function'){const e=Error('Return a cell-value object synchronously');e.name='SevraResultError';throw e;}
      globalThis.Sevra=Object.freeze({__flush:()=>__result});
      """
    guard let output = script.withCString({ sevra_js_eval(engine, $0, script.utf8.count, 500) })
    else {
      throw SevraError("excel_behavior", "Calculation runtime failed.")
    }
    defer { sevra_js_free(output) }
    let text = String(cString: output)
    if text.hasPrefix("!") {
      // A user validation error is also shown in the native form. Keep the message,
      // not QuickJS's internal stack frames, which are not useful recovery guidance.
      var message = String(text.dropFirst().split(separator: "\n", maxSplits: 1).first ?? "")
      if message.hasPrefix("SevraResultError: ") {
        throw SevraError("excel_behavior_result", String(message.dropFirst(18).prefix(2000)))
      }
      if message.hasPrefix("Error: ") { message.removeFirst(7) }
      if message.hasPrefix("SyntaxError:") {
        throw SevraError(
          "excel_behavior",
          "Invalid excelBehavior.source: " + String(message.prefix(500))
            + ". Check for extra or missing delimiters and reserved host-name conflicts. Do not repeat unchanged source. Source ending:\n"
            + String(source.suffix(700)))
      }
      throw SevraError(
        "excel_behavior", message.isEmpty ? "Calculation failed." : String(message.prefix(2000)))
    }
    try require(
      text.utf8.count <= 1_000_000, "excel_behavior_limit", "Calculation output exceeds 1 MB.")
    return try Value.parse(text)
  }
}
