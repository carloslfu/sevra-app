---
type: review
id: 01m7n8kn1nwzztkxwcmb4fzda9
created: 2026-11-17T17:24:23.733361+00:00
updated: 2026-11-17T17:27:44.658044+00:00
summary: 'Four-pass README review: natural launch copy, local AI and workbook differentiation, factual limits and preserved setup links.'
title: README launch copy review
---
# README launch copy review

Authority: [[sources/notes/2026/11/readme-launch-wording]].

## Naming decision

Use Sevra or Sevra Workbook in current public product copy. Do not call the product an MVP. Mac preview and source-build wording remain appropriate descriptions of actual distribution. This naming decision does not assert production signing, notarization, broad hardware qualification or universal Excel compatibility. Historical source evidence and dated acceptance records retain their original names.

## Pass 1: product truth

Keep the same four distinctions as the website: local AI and files, inspectable evidence and calculation inputs, reusable tables/charts/native apps, and a portable owner-held workbook. These describe the combined workflow without claiming that individual capabilities are unique to Sevra. Separate offline operation after setup from initial dependency/model downloads. Separate native controls working without inference from operating an app through AI chat. Only included files are promised to travel with the workbook, and device execution approval does not travel.

Sources of feature and qualification truth: [[records/operations/build-and-run]], [[records/operations/agent-handoff]], [[records/operations/implementation]], [[records/specs/local-model-native-apps]], [[records/specs/chat-primary-operation]], [[records/specs/excel-application-reconstruction]] and [[records/operations/inference-context-execution]]. The website is [sevrahq.com](https://www.sevrahq.com). This is a documentation review, not new native-app qualification.

## Pass 2: natural language and hierarchy

Lead with a concise explanation of the app and concrete supplier-cost/document/recurring-work uses. Replace internal language such as bounded workflows, unqualified and accepted checkpoints with practical explanations. Keep the four distinctions before setup. Rename the setup section Try Sevra on your Mac. Use Get started as its action. Keep source-build availability, hardware/model requirements and current installer status clear.

## Pass 3: skeptical reader

Describe macro reconstruction as an attempt, not guaranteed conversion. Explain that original macros never execute and output comparisons cover the supplied cases. Keep fresh-generation failure/time limits, required testing with the user's own cases, one-step Undo/Redo scope and current hardware/signing limits. Do not turn removing an MVP label into an unsupported production-readiness claim. The installation command block and actual bundle name stay unchanged.

## Pass 4: publication checks

The README and current installation/walkthrough headings use the new wording. Hidden legacy anchors preserve existing website and documentation links. Historical references are not rewritten. Validate local links and both new/legacy anchors, unchanged install commands, public destinations, image identity and desktop/narrow Markdown rendering before publication. Verify the exact README bytes and live GitHub anchors after push. The focused documentation policy in [[records/specs/distribution]] applies; no app launch, build or native-suite rerun is implied by this copy change. Concurrent native catalog implementation is outside this revision.


Local acceptance passed: repository Markdown links, 24 README local links and anchors, both new and compatibility fragment names, unchanged installation commands and zero visible MVP labels. Chrome inspection covered desktop and 375px rendering with no horizontal page overflow. Candidate-store validation reports zero errors and warnings. The image is unchanged. Public GitHub bytes and fragment behavior are verified after publication; this documentation checkpoint does not qualify a new app build.