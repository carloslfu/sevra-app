# Sevra app

This is the open-source native local-AI workbook app, separate from Sevra's
website service and Slotstream's app/engine. Read db/DB.md and
[Start here](db/records/overview/start-here.md) before changing the project.

Swift/SwiftUI/AppKit; shared Swift core and CLI; native Slotstream inference.
Every file asset is outside SQLite inside the workbook unless explicitly linked.
Use deterministic calculations, immutable input versions, lineage, bounded
retrieval, and truthful completion. No hidden hosted model or telemetry.

Keep specifications and work records in this repo's db.md store. No private
paths, private repository requirements, credentials, or real business fixtures.
Use meaningful invariant/integration tests. Run scripts/check.sh before release.
Preserve unrelated changes. Do not change the website business or Slotstream
repository as a side effect. Keep public claims tied to measured acceptance.
