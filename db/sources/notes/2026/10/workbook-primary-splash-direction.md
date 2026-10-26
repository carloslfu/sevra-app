---
type: note
id: 01m5wps1pnqdcv1e59hk4g2m8q
created: 2026-10-26T18:15:17.973778+00:00
updated: 2026-10-26T18:15:17.973778+00:00
summary: 'Owner direction: Workbook is primary; reuse Splash C++/Metal with Swift integration and a tested repo-owned maintenance skill.'
title: Workbook primary and native Splash integration
told_by: Carlos Galarza
---
# Owner direction, October 26, 2026

Carlos's conversation selects the Workbook app as Sevra's primary product and
homepage, with a small Websites link at the top for the secondary website service.
It replaces the earlier website-first homepage direction.

Carlos proposes reusing Splash's C++ and Metal engine while implementing the
necessary Python-layer behavior in Swift. A skill in the app repository should
fetch upstream source, inspect changes, update the adapter step by step and test
equivalent requests, failures and performance. The unchanged upstream engine owns
inference. Removing Python is a target, not proof of a speed improvement.

After receiving the complete design/status summary, Carlos instructs:
“Okay update everything and continue with the work”.

The independent public app repository owns its implementation and specifications.
These decisions do not rename the existing Slotstream project or combine website
customer data with workbooks.
