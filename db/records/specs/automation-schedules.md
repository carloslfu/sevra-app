---
type: spec
id: 01m63bka3cbj5a9x85kjh25ffn
created: 2026-10-29T08:14:36.652680+00:00
updated: 2026-10-29T09:06:00.829840+00:00
summary: 'Reviewed native calendar preview contract: explicit zones, recurrence, DST, bounded coverage and no execution authority. First E4 slice; runtime open.'
title: Native calendar schedule previews
status: implemented
---
# Native calendar schedule previews

This is the first E4 slice under [[records/specs/native-app-engine]]. It plans local calendar occurrences without opening a workbook, saving an automation, activating a trigger, invoking a workflow or loading a model. The full E4 runtime remains open. [[records/specs/manual-workflows]] still owns deliberate manual execution.

## Contract

A validated native-calendar-v1 descriptor contains exactly policy, timeZone, hour, minute and recurrence. The time zone is an explicit named IANA identifier (or UTC), never the computer's mutable current zone or an ambiguous abbreviation. Gregorian calendar and ISO weekday numbers (Monday 1 through Sunday 7) are fixed. Support daily, weekly with a nonempty unique weekday set, monthly with an exact day 1 through 31 or last, and yearly with a valid month/day including February 29. Invalid dates are skipped, not normalized: monthly day 31 skips short months and February 29 skips nonleap years. Last day is an explicit distinct choice. No interval, cron or RFC import/export is implied.

The requested hour/minute is wall time. A nonexistent clock time moves forward to the next valid time on the same local date. A repeated time uses only its first instance, including when the query starts between the two instances. A skipped whole civil date has no occurrence. Resolve each selected date independently from its day boundary. Scan the bounded local day chronologically in minute samples and refine the first crossing or offset transition to whole seconds. Select the first instant whose wall time is at or after the requested time, including historical gaps with nonzero seconds. The bound is a 48-hour calendar day; cancellation is checked during resolution. Foundation supplies the local components and day boundaries, not an unchecked recurrence answer. Advance by actual calendar day boundaries, not 86,400 seconds.

Preview returns strictly increasing UTC instants after the explicit query instant. Each occurrence includes its civil date, requested and actual local time, zone and whether the clock time shifted. Its local date key identifies the slot only within the same exact schedule version. It is not a globally unique trigger identity or an inventory occurrence ID. Future activation must bind it to the automation and trigger version and preserve durable deduplication through the existing capture/apply ledger.

Bound requests to 1 through 100 occurrences and 1 through 3,660 examined local days, checking cancellation/deadline every day. Report whether the count was reached or the horizon was exhausted, and the exclusive end of inspected calendar days. Never present a bounded empty result as proof that no future occurrence exists. Reject unknown fields, invalid types, duplicate weekdays, nonexistent zones, invalid clock values and unsupported policy/kind. Date instants must be finite in the supported Gregorian year range 1 through 9998. CLI query timestamps require explicit seconds and zone; the existing BusinessTime parser normalizes them.

## Development interface

The shared Swift core exposes NativeCalendarSchedule validation and read-only preview. The CLI command schedule-preview SCHEDULE_JSON_OR_@FILE AFTER_ISO [COUNT] [HORIZON_DAYS] uses it before workbook loading. File input is explicitly selected and bounded to 64 KiB. Responses say execution none and schedule-preview-only. No additional model tool or ordinary prompt growth. The future native saved-description/next-occurrence view must consume this same planner; there is no UI activation claim from a developer CLI.

Example descriptor: {"policy":"native-calendar-v1","timeZone":"America/Bogota","hour":9,"minute":0,"recurrence":{"kind":"weekly","weekdays":[1,2,3,4,5]}}.

## Three design passes

1. Semantic review: calendar mornings differ from elapsed 24-hour intervals. Preserve a named zone, exact recurrence and explicit DST policy. Native shifted gaps differ from RFC 5545 rules. Keep unsupported formats and interval execution out of this slice rather than silently changing their semantics.
2. Adversarial review: query between repeated instances must not schedule the second; half-hour gaps, midnight transitions, skipped dates, invalid monthly dates, leap years, offset changes, strict after-boundaries, enormous counts/horizons and cancellation all require focused cases. Sort weekday sets canonically without accepting duplicates or fractional integers. Bound file input before reading it.
3. Integration review: a preview grants no execution authority, persists no new state and cannot create business effects. No schema, new ledger, helper, background access or inference change. Durable occurrence IDs, missed-run/overlap policy, activation/edit/pause, event/condition triggers and resource-aware dispatch remain E4/E5 work and must inherit complete capture and inert reconstruction before shipping.

## Primary research

Apple documents [nextTime](https://developer.apple.com/documentation/foundation/calendar/matchingpolicy/nexttime) as advancing an unavailable clock time to the next existing time, and [first](https://developer.apple.com/documentation/foundation/calendar/repeatedtimepolicy/first) as choosing the first repeated instance. Both are available before the app's macOS 14 minimum. The [Swift Foundation recurrence proposal](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0009-calendar-recurrence-rule.md) distinguishes matching policies; its default is not this product's chosen native policy. The [reported nanosecond matching issue](https://forums.swift.org/t/repeatedtimepolicy-parameter-of-calendar-nextdate-not-working-when-matching-nanoseconds/82300) motivates matching whole seconds and directly testing folds. These sources establish API semantics, not proof of our implementation or future execution reliability.

## Qualification

The pure Swift native-calendar-v1 planner and schedule-preview CLI now validate exact daily/weekly/monthly/yearly rules, named zones, ISO weekdays, explicit last-day and leap-day behavior. They return strict-after UTC instants, local date slot keys, requested/actual wall time, shifted flags, count-versus-horizon status and the exclusive scanned-day boundary. Limits are100 occurrences,3660 local days,48 hours per resolved day and64 KiB explicitly selected JSON input. Cancellation/deadline checks apply during day and within-day work. No workbook opens, saved activation, schema, model tool, workflow or business effect.

The first implementation passed10 groups and failed the Lord Howe half-hour gap: a retained direct Foundation probe skips the date instead of shifting02:15 to02:30. Bounded chronological resolution now uses local components/day boundaries, with second refinement across the target or offset changes. This also handles first-only folds, midnight gaps and historic subminute offsets. Whole-date47-hour repeats choose the first slot. A zero-length Foundation day interval refuses with schedule_date rather than looping or inventing coverage; historical preview support remains subject to valid native boundaries.

Final V3 passes13 focused calendar groups/0 and strict5-file Swift lint. Frozen V2 production builds the native app/CLI, passes31 installed CLI calls including invalid inputs, oversized UTF-8/file/pipe refusals and a100-occurrence request, plus installed-resource checks with build reads denied,10 missing-resource refusals, altered-resource refusal and ad-hoc signature. V3 adds only two related historical boundary counterexamples in one test group; production bytes match V2, so its package/CLI proof is reused. New checks join the ordinary shared suite and both installed CLI CI paths. Exact457576c prior CI is green; this checkpoint needs its own hosted run. No new inference, full shared-suite or crash matrix for this nonpersistent boundary.

Evidence: [calendar preview receipt](../../../integration/evidence/2026-10-29-calendar-previews.json.gz),27229bytes, SHA-256 e608825e2adedb6d11795bdd26e77997411e2e012b89bd5f47bf7768248b7eb2. All133 previous evidence artifacts remain byte-identical. No inference throughput/accuracy or release claim. The latest native inventory again has no apps and reports locked; visible confirmation/Activity/VoiceOver/dictation/appearance remain unverified. Durable activation and version/occurrence identities, catch-up/overlap, dispatch, event/condition triggers and E5 background/resource work remain open. This is the first E4 planning slice, not an operational scheduler. Full E3/richer graphs, Excel continuity, hardware/performance and production distribution remain open. The whole app and active goal remain unfinished.

## Half-hour correction during implementation

The first frozen check passed 10 groups and failed the Lord Howe half-hour gap. A retained direct Foundation probe reproduces Calendar.nextDate nextTime skipping October 4, 2026 for 02:15, rather than returning that date at 02:30. The first implementation safely discarded the out-of-day result but incorrectly omitted the occurrence. Replace the lookup with bounded within-day resolution and retain the half-hour, first-fold, midnight, skipped-date and historical subminute cases. This is a measured behavior on the qualification Mac, not a claim about every Foundation version. The simpler chronological resolution also avoids selecting the second repeated instance. Final qualification is recorded above; the failed first implementation and its direct probe remain preserved.
