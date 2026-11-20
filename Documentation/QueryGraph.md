# The `query graph` export

[`SafeDITool query graph`](Manual.md#exporting-the-dependency-graph) exports the `@Instantiable` declarations of a set of modules as one JSON document. A tool or a coding agent can then answer its own questions about the dependency graph, without a SafeDI command for each one. The Manual introduces the command; this page describes the format and gives recipes.

> `query graph` is in alpha. Its options and JSON may change in any release; the JSON’s `formatVersion` is `0`.

## What the export holds

The export reads the modules as [`query needs`](QueryNeeds.md) reads them: each `--include` directory is a module, and so is each `--module-info` file. It resolves the types they name as `generate` does. It describes declarations, not the trees `generate` builds from them, so each type and each dependency appears once, however many trees reach it. The same inputs give the same bytes: the output follows neither the order the modules are named in nor how a module’s files are spelled.

Keys are sorted, every array is present, and an optional key is left out rather than `null`.

```json
{
  "errors" : [],
  "formatVersion" : 0,
  "fulfillment" : [
    { "fulfilledBy" : "App.DefaultService", "type" : "Service" }
  ],
  "modules" : [ "App" ],
  "resolved" : true,
  "types" : [
    {
      "declarationKind" : "class",
      "edges" : [
        {
          "builds" : "DefaultService",
          "filePath" : "Sources/App/Root.swift",
          "fulfilledBy" : "App.DefaultService",
          "kind" : "instantiated",
          "label" : "service",
          "line" : 12,
          "type" : "any Service"
        }
      ],
      "filePath" : "Sources/App/Root.swift",
      "fulfills" : [ "Root" ],
      "id" : "App.Root",
      "isRoot" : true,
      "isSeam" : false,
      "line" : 3,
      "module" : "App",
      "name" : "Root"
    }
  ]
}
```

- **`types`**: each production `@Instantiable` declaration, sorted by module, then name, then line. A `mockOnly` declaration describes a mock and is left out. `id` is opaque: match it whole and never split it. `fulfills` lists the types the declaration fulfills, its own first. `declarationKind` is `class`, `actor`, `struct` or `extension`. `isSeam` is set for a type declared with `generateDependencyTree: true`. `filePath` is spelled under the `--include` argument as given, or as a `--module-info` file records it.
- **`edges`**: each dependency of the type, in declaration order. `kind` is one of:
  - `instantiated`, built when its owner is;
  - `lazy`, held in a `LazilyInstantiated` or `SendableLazilyInstantiated` and built once, when first read;
  - `builder`, held in an instantiator and built each time it is asked;
  - `forwarded`, passed in by whoever builds the owner;
  - `received`, taken from a type above the owner;
  - `alias`, a `@Received(fulfilledByDependencyNamed:ofType:)`, with `aliasOf` naming the property it renames.

  `type` is the property’s type as declared. `wrapper` names the SafeDI wrapper the property is held in. An instantiated, lazy or builder edge has `builds`, the type SafeDI looks up (its `fulfilledByType:`, or its type without the wrapper), and, in a resolved graph, `fulfilledBy`, the id of the type that fulfills it. `fulfilledBy` is absent when no production declaration does. `onlyIfAvailable` and `erased` are present only when set.
- **`fulfillment`**: for each type SafeDI can build, the id of the type that fulfills it, sorted by the fulfilled type.
- **`resolved`** and **`errors`**: when SafeDI cannot resolve the types, such as when two declarations fulfill one type, `resolved` is `false`, `errors` lists what `generate` would report, and neither `fulfillment` nor any `fulfilledBy` is present. The declarations are still exported, and the command still succeeds, so an export taken in the middle of an edit still answers questions.

The export does not say which value a received edge gets, or the order a type builds its dependencies in. Those depend on the tree a type is built in, and a later format may add them.

## Recipes

These use [`jq`](https://jqlang.org).

Where `Cache` is used – built, received or renamed – with each site’s file and line:

```bash
jq --arg T Cache '[.types[] as $owner | $owner.edges[]
  | select(.builds == $T or (.type | sub("^any "; "") | sub("\\?$"; "")) == $T or (.aliasOf.type // "") == $T)
  | {owner: $owner.id, kind, label, filePath, line}]' graph.json
```

The types that build `App.Log`:

```bash
jq --arg T App.Log '[.types[] as $owner | $owner.edges[] | select(.fulfilledBy == $T) | $owner.id] | unique' graph.json
```

What `App.Root` depends on, and which type fulfills each dependency:

```bash
jq --arg T App.Root '.types[] | select(.id == $T) | [.edges[] | {kind, label, type, fulfilledBy}]' graph.json
```

## Keeping the export current

`--output` writes the file only when its bytes change, so a file watcher or a build system sees a change only when the graph changed. A project whose build writes `.safedi` files exports from them with `--module-info` and parses no source.
