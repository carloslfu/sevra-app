# Sevra native app SDK

TypeScript/JSX authoring for native programmable spaces. The runtime is bundled
into Sevra and does not require Node, a browser or a web view.

```sh
npm ci --prefix sdk
node sdk/build.mjs examples/apps/inventory
output/native/bin/sevra app-install /path/to/Workbook.sevra examples/apps/inventory/app.sevraapp
```

Ask to enable the app in chat, review its table access, and type **Confirm**.
The native Enable control remains available.
Use **Workbook > Add Native App…** to import a package without the CLI.

The complete contract, lifecycle, permission model, limits and authoring guide are
in [the native engine specification](../db/records/specs/programmable-native-engine.md).
The [implementation plan](../db/records/plans/programmable-native-engine.md) retains
acceptance and evidence. Example data is synthetic.

Define business operations once with `action` and call the returned function from
optional buttons. Chat discovers the same operation and supplies its typed inputs:

```ts
const add = action('add', {
  title: 'Add stock',
  inputs: {name: {type: 'text'}, quantity: {type: 'decimal'}}
}, async values => {
  if (!values.name.trim()) throw Error('Enter an item name');
  return await data.transaction([{op: 'insert', table: 'stock', values}]);
});
```

Use exact current record IDs for edits/deletes. Await writes and return their
receipt; throw business validation errors. Avoid requiring a selected visual row.
The authoring checker supports `run_action` with `action`, `inputs`, and optional
expected `error`, followed by persisted-value assertions. Existing input/control
handlers are also callable by chat through the same runtime. See the
[conversational contract](../db/records/specs/chat-primary-operation.md).
