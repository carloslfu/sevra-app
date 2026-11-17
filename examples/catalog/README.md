# Catalog fixtures

All files here are synthetic, contain no customer data and are only packaged in
the developer UI Catalog. Workbook records and IDs are generated through the
production APIs in `Sources/SevraApp/Catalog` on each reset.

- PNGs contain simple color panels, including portrait and transparency variants.
- Quote.pdf contains a short fictional supplier quote.
- Quotes.xlsx contains two fictional supplier rows, with no macros or external links.
- Evidence.zip contains a short note and CSV.
- Workshop.wav is a half-second generated tone. Its catalog transcript is explicitly
  scripted and does not claim speech recognition.
- Workshop.mp4 is a short solid-color video used to exercise the real media viewer.

`sdk-types.ts` checks the actual public SDK declarations, including all six action
input types, actions/forms and declared views. Run `npm run typecheck --prefix sdk`.
The native recipes use the shipped SDK and signed XPC workers, not mock renderers.
