# In-app update between two headers, November 20, 2026

Phase H4 asks for an in-app update between two builds whose prompt headers differ.

- **Build 4** (`0.9.0-qa.4`, header `793529b6`, 2,572 tokens) was installed from its disk image
  into an empty folder. Its app, CLI and a CLI link found the header, and About showed
  "Version 0.9.0 (4)".
- **Build 5** (`0.9.0-qa.5`, built clean from `46f6b58`, header `4b5222b7`, 2,707 tokens,
  152,015,708 bytes) was listed in a QA appcast signed with the QA key and served on the
  loopback address the QA builds read.
- In build 4, **Sevra → Check for Updates…** showed "A new version of Sevra QA is available!"
  with the release notes. Install Update downloaded the disk image, Sparkle verified it, and
  Install and Relaunch replaced the app and started it again. About showed "Version 0.9.0 (5)".

After the update, [result.json](result.json) records:

- the bundle is build 5, its header manifest equals the build 5 receipt, and its executable UUID
  equals the one in build 5's disk image;
- with the build tree denied, the app, its CLI and a CLI link each found header `4b5222b7` and
  loaded 2,111 Metal kernels;
- with the prompt cache emptied, the first chat from the updated copy resumed the shipped
  header: 2,688 prompt tokens matched and none were computed.

The update ran on the build Mac with ad-hoc QA signing, as in the November 18 rehearsal. A clean
Mac, Developer ID signing, notarization and the public HTTPS feed remain public-release checks.
