import SevraCore
import SevraPreviewUI

func checkStructuredPresentation() throws {
  let excerpt = StructuredPresentation.searchExcerpt(
    #"{"code":9007199254740993,"enabled":false,"quantity":0,"tax":null}"#, title: "quote.json")
  try require(
    excerpt.contains("Code: 9007199254740993") && excerpt.contains("Enabled: No")
      && excerpt.contains("Quantity: 0") && excerpt.contains("Tax: Not provided")
      && !excerpt.contains("{") && !excerpt.contains("\""),
    "presentation_check", "Search exposed raw JSON or changed exact values")
  try require(
    StructuredPresentation.searchExcerpt(#"{"code":90"#, title: "quote.json")
      == "Structured data. Open the file to inspect its contents."
      && StructuredPresentation.searchExcerpt("[Draft] Compare quotes.", title: "Notes.txt")
        == "[Draft] Compare quotes."
      && StructuredPresentation.searchExcerpt("[]", title: "data.json") == "Empty list"
      && StructuredPresentation.searchExcerpt("[1,2]", title: "data.json").contains("2 entries"),
    "presentation_check", "Partial data became a complete claim or ordinary prose was hidden")
  try require(
    StructuredPresentation.scalar(.string("0014")) == "0014"
      && StructuredPresentation.scalar(.number(1.23456789)) == "1.23456789",
    "presentation_check", "Readable values changed a code or rounded precision")
  try require(
    StructuredPresentation.scalar(.bool(false)) == "No"
      && StructuredPresentation.scalar(.null) == "Not provided"
      && StructuredPresentation.scalar(.string("")) == "Empty text",
    "presentation_check", "False, missing and empty became indistinguishable")
  let original: Value = .object(["sku": .string("0014"), "received": .number(0)])
  try require(
    StructuredPresentation.embedded(.string(try original.json()))["sku"] == .string("0014")
      && StructuredPresentation.embedded(.string(try original.json()))["received"] == .string("0")
      && StructuredPresentation.embedded(.string("{invalid")) == .string("{invalid"),
    "presentation_check", "Nested data lost structure or invalid text was reinterpreted")
  let exact = StructuredPresentation.parseJSON(
    #"{"large":9007199254740993,"decimal":1.2300,"small":1e-20,"negativeZero":-0,"quoted":"1.2 \"3\"","enabled":false,"missing":null}"#
  )
  try require(
    exact?["large"] == .string("9007199254740993")
      && exact?["decimal"] == .string("1.2300") && exact?["small"] == .string("1e-20")
      && exact?["negativeZero"] == .string("-0") && exact?["enabled"] == .bool(false)
      && exact?["missing"] == .null && exact?["quoted"] == .string("1.2 \"3\"")
      && StructuredPresentation.parseJSON("{1:2}") == nil
      && StructuredPresentation.parseJSON(
        String(repeating: "[", count: 300) + String(repeating: "]", count: 300)) == nil,
    "presentation_check",
    "Structured file preview changed number spelling, escaped text or invalid syntax")
  try require(
    StructuredPresentation.label("unit_price") == "Unit price"
      && StructuredPresentation.label("currentVersion") == "Current Version"
      && StructuredPresentation.isIdentifier("datasetID")
      && !StructuredPresentation.isIdentifier("paid"),
    "presentation_check", "Field labels lost meaning or hid a business field")
  print(
    "PASS native structured presentation: exact codes and precision, false/empty/missing, nested data and identity fields"
  )
}
