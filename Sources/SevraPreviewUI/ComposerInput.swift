import Foundation
import SevraCore

/// What the composer does with a message that has not reached a conversation yet.
public enum ComposerInput {
  /// Asked before the composer clears, so a refused message is still there to shorten.
  public static func admit(_ input: String) throws {
    try require(
      input.utf8.count <= AgentRequest.maximumPromptBytes, "prompt_limit",
      "Please shorten this message to 16,000 bytes or less. It is still in the composer.")
  }

  /// The returned message comes first, then whatever was typed while it was being prepared.
  public static func restored(_ input: String, over typed: String) -> String {
    typed.isEmpty || typed == input ? input : input + "\n\n" + typed
  }

  /// For a composer that shows another conversation or has closed: the message becomes the
  /// saved draft of the conversation it was typed in.
  public static func keep(_ input: String, conversation: String, in book: Workbook) throws {
    let saved = try book.conversationViewState(conversation)
    try book.saveConversationViewState(
      conversation, draft: restored(input, over: saved.draft), reading: saved.reading,
      expectedDraft: saved.draft)
  }
}
