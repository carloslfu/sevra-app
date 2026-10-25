# Sevra

A native Mac workbook for working with documents, tables and business information
through conversation. Local AI, inspectable calculations, and files you own.

**In development.** This repository starts with a reviewed specification and
will record implemented features and verification as the first version is built.
It is MIT licensed from the first commit. It is separate from Sevra Websites.

Start with [the project knowledge map](db/records/overview/start-here.md),
[the specification](db/records/specs/product.md) and
[the implementation plan](db/records/operations/implementation.md).

The app uses SwiftUI, AppKit, SQLite and Slotstream (Swift/MLX/Metal). A workbook
contains a database and ordinary asset files. The repository's `db/` is its
independent [db.md](https://github.com/carloslfu/db.md) knowledge store, not the
workbook storage format.
