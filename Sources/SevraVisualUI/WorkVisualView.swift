import Charts
import SevraCore
import SevraMedia
import SwiftUI

public struct WorkVisualView: View {
  let definition: WorkVisual
  let data: WorkVisualData
  let openRecord: ((String) -> Void)?
  let thumbnail: (@MainActor (String) async throws -> PreviewImage)?
  let change: ((WorkVisualData.Record, String, String?) -> Void)?
  @State private var day: String?
  @State private var displayedMonth: Date?
  @State private var weekOnly = false
  @State private var reschedule: WorkVisualData.Record?
  @State private var startText = ""
  @State private var endText = ""

  public init(
    definition: WorkVisual, data: WorkVisualData, openRecord: ((String) -> Void)? = nil,
    thumbnail: (@MainActor (String) async throws -> PreviewImage)? = nil,
    change: ((WorkVisualData.Record, String, String?) -> Void)? = nil
  ) {
    self.definition = definition
    self.data = data
    self.openRecord = openRecord
    self.thumbnail = thumbnail
    self.change = change
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(definition.title).font(.headline).accessibilityAddTraits(.isHeader)
      if data.records.isEmpty {
        Label("No records match this view.", systemImage: "rectangle.on.rectangle")
          .foregroundStyle(.secondary)
      } else {
        switch definition.style {
        case .board: board
        case .timeline:
          timeline
          DisclosureGroup("Events and records") { agenda }
        case .calendar:
          if let date = displayedMonth ?? definition.month.flatMap(Self.date) {
            calendarControls(date)
            if weekOnly {
              selectedWeek(date)
            } else {
              ViewThatFits(in: .horizontal) {
                monthGrid(date).frame(minWidth: 395)
                agenda
              }
            }
          }
        case .agenda: agenda
        }
      }
    }.onChange(of: definition.month) { _, _ in
      displayedMonth = nil
      day = nil
    }
    .sheet(item: $reschedule) { record in
      VStack(alignment: .leading, spacing: 12) {
        Text("Reschedule " + record.title).font(.headline)
        TextField("Start date · YYYY-MM-DD", text: $startText)
        if definition.end != nil { TextField("End date · YYYY-MM-DD", text: $endText) }
        HStack {
          Button("Cancel") { reschedule = nil }.keyboardShortcut(.cancelAction)
          Spacer()
          Button("Save dates") {
            change?(record, startText, endText.isEmpty ? nil : endText)
            reschedule = nil
          }.buttonStyle(.borderedProminent)
            .disabled(
              Self.date(startText) == nil || (!endText.isEmpty && Self.date(endText) == nil))
        }
      }.padding(18).frame(width: 360)
    }
  }

  private var board: some View {
    let lanes = definition.lanes ?? []
    return ScrollView(.horizontal) {
      LazyHStack(alignment: .top, spacing: 10) {
        ForEach(lanes, id: \.self) { lane in
          column(lane, records: data.records.filter { $0.value == lane })
        }
        let other = data.records.filter { record in !lanes.contains(record.value ?? "") }
        if !other.isEmpty { column("Other or unassigned", records: other) }
      }
    }.defaultScrollAnchor(.leading)
  }

  private func column(_ title: String, records: [WorkVisualData.Record]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title + " · " + records.count.formatted()).font(.subheadline.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      if records.isEmpty {
        Text("No records").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(records) { card($0, showsDate: false) }
      }
    }
    .padding(10).frame(width: 174, alignment: .leading)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  private var agenda: some View {
    LazyVStack(alignment: .leading, spacing: 6) {
      ForEach(data.records.sorted { ($0.value ?? "9999", $0.id) < ($1.value ?? "9999", $1.id) }) {
        card($0, showsDate: true)
      }
    }
  }

  private var timeline: some View {
    let dates = data.records.compactMap { record -> (WorkVisualData.Record, Date, Date)? in
      guard let day = record.value.flatMap(Self.date) else { return nil }
      let end = record.end.flatMap(Self.date) ?? day
      return (record, day, end.addingTimeInterval(86_400))
    }
    return Chart(Array(dates.enumerated()), id: \.element.0.id) { index, entry in
      BarMark(
        xStart: .value("Start", entry.1), xEnd: .value("End", entry.2),
        y: .value("Record", String(index + 1) + ". " + entry.0.title)
      )
      .accessibilityLabel(entry.0.title).accessibilityValue(dateDescription(entry.0))
    }
    .chartYAxis(dates.count <= 8 ? .visible : .hidden)
    .frame(height: max(155, min(350, CGFloat(dates.count) * 27)))
    .accessibilityLabel(definition.title)
  }

  private func calendarControls(_ date: Date) -> some View {
    HStack {
      Button {
        navigateCalendar(date, offset: -1)
      } label: {
        Image(systemName: "chevron.left")
      }
      .accessibilityLabel(weekOnly ? "Previous week" : "Previous month")
      Text(Self.monthLabel(date)).font(.subheadline.weight(.semibold)).lineLimit(1)
      Button {
        navigateCalendar(date, offset: 1)
      } label: {
        Image(systemName: "chevron.right")
      }
      .accessibilityLabel(weekOnly ? "Next week" : "Next month")
      Spacer(minLength: 0)
      Toggle("Week", isOn: $weekOnly).toggleStyle(.switch).controlSize(.small)
    }
  }

  private func navigateCalendar(_ date: Date, offset: Int) {
    displayedMonth = Self.calendar.date(
      byAdding: weekOnly ? .day : .month,
      value: weekOnly ? offset * 7 : offset, to: date)
    day = nil
  }

  private func selectedWeek(_ date: Date) -> some View {
    let start = Self.calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    return LazyVStack(alignment: .leading, spacing: 7) {
      ForEach(0..<7) { offset in
        if let date = Self.calendar.date(byAdding: .day, value: offset, to: start) {
          selectedDay(date.formatted(Self.iso))
        }
      }
    }
  }

  private func monthGrid(_ month: Date) -> some View {
    let calendar = Self.calendar
    let weekday = calendar.component(.weekday, from: month)
    let offset = (weekday + 5) % 7
    let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    return VStack(alignment: .leading, spacing: 8) {
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { label in
          Text(label).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 42) }
        ForEach(0..<days, id: \.self) { index in
          if let date = calendar.date(byAdding: .day, value: index, to: month) {
            calendarDay(date, number: index + 1)
          }
        }
      }
      if let day { selectedDay(day) }
      let unscheduled = data.records.filter { $0.value == nil }
      if !unscheduled.isEmpty {
        DisclosureGroup("Unscheduled records") {
          ForEach(unscheduled) { card($0, showsDate: true) }
        }
      }
    }
  }

  private func calendarDay(_ date: Date, number: Int) -> some View {
    let value = date.formatted(Self.iso)
    let count = records(on: value).count
    let background = day == value ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06)
    return Button {
      day = value
    } label: {
      VStack(spacing: 3) {
        Text(number.formatted()).monospacedDigit()
        if count > 0 { Text(count.formatted()).font(.caption2).foregroundStyle(.secondary) }
      }.frame(maxWidth: .infinity, minHeight: 42)
    }
    .buttonStyle(.plain).background(background, in: RoundedRectangle(cornerRadius: 4))
    .accessibilityLabel(value + ", " + count.formatted() + " records")
  }

  @ViewBuilder private func selectedDay(_ value: String) -> some View {
    Text(value).font(.subheadline.weight(.semibold))
    let entries = records(on: value)
    if entries.isEmpty {
      Text("No records on this day.").font(.caption).foregroundStyle(.secondary)
    }
    ForEach(entries) { card($0, showsDate: true) }
  }

  private func records(on day: String) -> [WorkVisualData.Record] {
    data.records.filter { record in
      guard let start = record.value else { return false }
      return start <= day && day <= (record.end ?? start)
    }
  }

  private func card(_ record: WorkVisualData.Record, showsDate: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if let key = record.imageKey, let thumbnail {
        RecordThumbnail(key: key, load: thumbnail)
      }
      VStack(alignment: .leading, spacing: 3) {
        if let openRecord {
          Button(record.title) { openRecord(record.id) }.buttonStyle(.link)
        } else {
          Text(record.title)
        }
        if showsDate { Text(dateDescription(record)).font(.caption).foregroundStyle(.secondary) }
      }
      Spacer(minLength: 0)
      if let change {
        if let lanes = definition.lanes {
          Menu {
            ForEach(lanes.filter { $0 != record.value }, id: \.self) { lane in
              Button(lane) { change(record, lane, nil) }
            }
          } label: {
            Image(systemName: "arrow.right.circle")
          }
          .menuStyle(.borderlessButton).fixedSize()
          .accessibilityLabel("Move " + record.title)
        } else {
          Button {
            startText = record.value ?? ""
            endText = record.end ?? ""
            reschedule = record
          } label: {
            Image(systemName: "calendar")
          }
          .buttonStyle(.plain).accessibilityLabel("Reschedule " + record.title)
        }
      }
    }.font(.callout).padding(6)
      .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
  }

  private func dateDescription(_ record: WorkVisualData.Record) -> String {
    guard let start = record.value else { return "Unscheduled" }
    if let end = record.end, end != start { return start + " to " + end }
    return start
  }

  private static let iso = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
  private static func date(_ text: String) -> Date? { try? iso.parse(text) }
  private static func monthLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    return formatter.string(from: date)
  }
  private static var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    value.firstWeekday = 2
    value.minimumDaysInFirstWeek = 4
    return value
  }
}

private struct RecordThumbnail: View {
  let key: String
  let load: @MainActor (String) async throws -> PreviewImage
  @State private var preview: PreviewImage?

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 5).fill(.quaternary)
      if let preview {
        Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
          .accessibilityHidden(true)
      } else {
        Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
          .accessibilityLabel("Thumbnail unavailable")
      }
    }
    .frame(width: 34, height: 34)
    .task(id: key) {
      preview = nil
      guard let result = try? await load(key), !Task.isCancelled else { return }
      preview = result
    }
    .onDisappear { preview = nil }
  }
}

public struct LiveWorkVisualView: View {
  let definition: WorkVisual
  let revision: String
  let load: @MainActor (String?) async throws -> WorkVisualData
  let openRecord: ((String) -> Void)?
  let thumbnail: (@MainActor (String) async throws -> PreviewImage)?
  let change: ((WorkVisualData.Record, String, String?, String?) -> Void)?
  @State private var data: WorkVisualData?
  @State private var error: String?
  @State private var pages: [String] = []
  @State private var page = 0

  public init(
    definition: WorkVisual, revision: String,
    load: @escaping @MainActor (String?) async throws -> WorkVisualData,
    openRecord: ((String) -> Void)? = nil,
    thumbnail: (@MainActor (String) async throws -> PreviewImage)? = nil,
    change: ((WorkVisualData.Record, String, String?, String?) -> Void)? = nil
  ) {
    self.definition = definition
    self.revision = revision
    self.load = load
    self.openRecord = openRecord
    self.thumbnail = thumbnail
    self.change = change
  }

  private var cursor: String? { page > 0 && pages.count >= page ? pages[page - 1] : nil }

  public var body: some View {
    Group {
      if let error {
        Label(error, systemImage: "rectangle.on.rectangle").foregroundStyle(.secondary)
      } else if let data {
        VStack(alignment: .leading, spacing: 9) {
          WorkVisualView(
            definition: definition, data: data, openRecord: openRecord,
            thumbnail: thumbnail,
            change: (page == 0 || pages.count >= page)
              ? change.map { action in
                { record, value, end in action(record, value, end, cursor) }
              } : nil)
          if page > 0 || data.nextCursor != nil {
            HStack {
              Button("Previous page") { page -= 1 }.disabled(page == 0)
              Text("Page " + (page + 1).formatted()).font(.caption).foregroundStyle(.secondary)
              Button("Next page") {
                guard let next = data.nextCursor else { return }
                if pages.count == page { pages.append(next) }
                page += 1
              }.disabled(data.nextCursor == nil || page >= 999)
            }
          }
        }
      } else {
        ProgressView("Loading records…")
      }
    }.onChange(of: revision) { _, _ in
      pages = []
      page = 0
    }
    .onChange(of: definition) { _, _ in
      pages = []
      page = 0
    }
    .task(id: [revision, (try? encoded(definition).json()) ?? "", cursor ?? ""]) {
      data = nil
      error = nil
      do {
        let result = try await load(cursor)
        try Task.checkCancellation()
        data = result
      } catch {
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
}
