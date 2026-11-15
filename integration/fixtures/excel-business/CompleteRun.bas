Attribute VB_Name = "Business"
Option Explicit
' Synthetic source evidence. Sevra must NEVER execute this original macro.
Sub CompleteRun()
  Dim reference As String, row As Long, material As Long, batches As Double
  Dim runs As Worksheet, materials As Worksheet, capacity As Worksheet
  Set runs = ThisWorkbook.Worksheets("Runs")
  Set materials = ThisWorkbook.Worksheets("Materials")
  Set capacity = ThisWorkbook.Worksheets("Capacity")
  reference = InputBox("Run reference")
  If reference = "" Then Exit Sub
  For row = 2 To runs.Cells(runs.Rows.Count, 1).End(xlUp).Row
    If runs.Cells(row, 1).Value = reference Then
      If runs.Cells(row, 3).Value <> "Planned" Then
        MsgBox "Only planned runs can be completed"
        Exit Sub
      End If
      batches = runs.Cells(row, 2).Value
      If batches <= 0 Or batches <> Int(batches) Then
        MsgBox "Enter positive whole batches"
        Exit Sub
      End If
      Application.Calculate
      For material = 2 To 4
        If capacity.Cells(material, 3).Value < batches * materials.Cells(material, 3).Value Then
          MsgBox "Insufficient material"
          Exit Sub
        End If
      Next material
      runs.Cells(row, 3).Value = "Completed"
      Application.Calculate
      Exit Sub
    End If
  Next row
  MsgBox "Unknown run reference"
End Sub
