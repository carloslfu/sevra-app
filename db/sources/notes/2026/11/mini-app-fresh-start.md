---
type: note
id: 01m7asa14v9grnr8rge3080vt0
created: 2026-11-13T15:44:35.482964+00:00
updated: 2026-11-13T15:44:35.482964+00:00
summary: 'Owner confirms fresh development baseline: clear obsolete mini-app fixtures and avoid migration or legacy compatibility burdens.'
told_by: Carlos
---
# Owner direction

The owner clarified: “We’re starting from scratch: there are no users and you should just clean up old stuff and make it so new apps and new stuff would work.”

The owner then confirmed the understood scope: one current implementation, removal of obsolete development state and disposable fixtures, no migration or compatibility burden for nonexistent customers, and a working create → review → enable → use flow with current security boundaries preserved.

This follows [[sources/notes/2026/11/native-app-adversarial-review]] and reaffirms [[sources/notes/2026/10/pre-1-production-compatibility-policy]]. The continuing native-app installation/UI authorization applies. This does not authorize deleting unrelated workbooks, model files, source evidence or the explicitly preserved baseline app.
