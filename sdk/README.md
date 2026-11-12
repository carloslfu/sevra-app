# Sevra native app SDK

TypeScript/JSX authoring for native programmable spaces. The runtime is bundled
into Sevra and does not require Node, a browser or a web view.

```sh
npm ci --prefix sdk
node sdk/build.mjs examples/apps/inventory
output/native/bin/sevra app-install /path/to/Workbook.sevra examples/apps/inventory/app.sevraapp
```

Open the new space and choose **Enable app** after reviewing its table access.
Use **Workbook > Add Native App…** to import a package without the CLI.

The complete contract, lifecycle, permission model, limits and authoring guide are
in [the native engine specification](../db/records/specs/programmable-native-engine.md).
The [implementation plan](../db/records/plans/programmable-native-engine.md) retains
acceptance and evidence. Example data is synthetic.
