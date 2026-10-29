import Foundation

/// Recognizes a narrow, explicit instruction in the current submission, never
/// retrieved text or a digest. This is an additional denial rule, not a general
/// intent classifier or a grant of permission when no phrase matches.
package enum RequestRestrictions {
  package static func isExplicitlyReadOnly(_ prompt: String) -> Bool {
    let phrases: Set<String> = [
      "make no changes", "do not change anything", "do not change the workbook",
      "do not make any changes", "don't make any changes", "do not make changes",
      "don't make changes",
      "do not save anything", "don't save anything", "ask before saving anything",
      "ask me before saving anything", "ask what you need before saving anything",
      "explain only", "explain without changing anything", "explain without making changes",
      "leave this workbook unchanged", "leave the workbook unchanged",
      "don't change anything", "don't change the workbook", "no changes",
      "no hagas cambios", "no cambies nada", "sin hacer cambios",
    ]
    return prompt.lowercased().replacingOccurrences(of: "’", with: "'")
      .components(separatedBy: CharacterSet(charactersIn: ".!?;\n")).contains { sentence in
        phrases.contains(sentence.split(whereSeparator: \.isWhitespace).joined(separator: " "))
      }
  }
}
