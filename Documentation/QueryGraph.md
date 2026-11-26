# The `query graph` export

[`SafeDITool query graph`](Manual.md#exporting-the-dependency-graph) exports the `@Instantiable` declarations of a set of modules as one JSON document. A tool or a coding agent can then answer its own questions about the dependency graph, without a SafeDI command for each one. The Manual introduces the command; this page describes the format and gives recipes.

> `query graph` is in alpha. Its options and JSON may change in any release; the JSON’s `formatVersion` is `0`.

## What the export holds

The export reads the modules as [`query needs`](QueryNeeds.md) reads them: each `--include` directory is a module, and so is each `--module-info` file. It resolves the types they name, and builds the trees of their roots, as `generate` does. It describes declarations, not those trees, so each declaration and each dependency appears once, however many trees reach it. The same inputs give the same bytes: the output follows neither the order the modules are named in nor how a module’s files are spelled.

Keys are sorted, every array is present, and an optional key is left out rather than `null`. Each type is given twice: `type` as the declaration spells it, and `plainType`, the type of the value with no optional, no SafeDI wrapper and no `any`, so a script matches types by comparing `plainType` and never needs to take a spelling apart.

```json
{
  "command" : "graph",
  "completeness" : "trees",
  "declarations" : [
    {
      "constructedBy" : [
        { "declaredBy" : "App.Root", "label" : "cache" }
      ],
      "declarationKind" : "extension",
      "dependencies" : [],
      "filePath" : "Sources/App/Cache.swift",
      "fulfills" : [ "Cache" ],
      "generatesDependencyTree" : false,
      "id" : "App.Cache",
      "isReachedByRoot" : true,
      "isRoot" : false,
      "line" : 3,
      "module" : "App",
      "typeName" : "Cache"
    },
    {
      "constructedBy" : [
        { "declaredBy" : "App.Root", "label" : "service" }
      ],
      "declarationKind" : "class",
      "dependencies" : [
        {
          "filePath" : "Sources/App/DefaultService.swift",
          "isErased" : false,
          "isOnlyIfAvailable" : true,
          "label" : "cache",
          "line" : 8,
          "plainType" : "Cache",
          "provenance" : [
            { "declaredBy" : "App.Root", "label" : "cache", "source" : "declaration" }
          ],
          "source" : "received",
          "type" : "Cache?"
        }
      ],
      "filePath" : "Sources/App/DefaultService.swift",
      "fulfills" : [ "DefaultService", "Service" ],
      "generatesDependencyTree" : false,
      "id" : "App.DefaultService",
      "isReachedByRoot" : true,
      "isRoot" : false,
      "line" : 1,
      "module" : "App",
      "typeName" : "DefaultService"
    },
    {
      "constructedBy" : [],
      "declarationKind" : "class",
      "dependencies" : [
        {
          "filePath" : "Sources/App/Root.swift",
          "fulfilledBy" : "App.DefaultService",
          "fulfilledByType" : "DefaultService",
          "isErased" : false,
          "isOnlyIfAvailable" : false,
          "label" : "service",
          "lifetime" : "eager",
          "line" : 11,
          "plainType" : "Service",
          "source" : "instantiated",
          "type" : "any Service"
        },
        {
          "filePath" : "Sources/App/Root.swift",
          "fulfilledBy" : "App.Cache",
          "isErased" : false,
          "isOnlyIfAvailable" : false,
          "label" : "cache",
          "lifetime" : "lazy",
          "line" : 13,
          "plainType" : "Cache",
          "source" : "instantiated",
          "type" : "LazilyInstantiated<Cache>",
          "wrapper" : "LazilyInstantiated"
        }
      ],
      "filePath" : "Sources/App/Root.swift",
      "fulfills" : [ "Root" ],
      "generatesDependencyTree" : false,
      "id" : "App.Root",
      "isReachedByRoot" : true,
      "isRoot" : true,
      "line" : 3,
      "module" : "App",
      "typeName" : "Root"
    }
  ],
  "errors" : [],
  "formatVersion" : 0,
  "fulfillments" : [
    { "fulfilledBy" : "App.Cache", "plainType" : "Cache" },
    { "fulfilledBy" : "App.DefaultService", "plainType" : "DefaultService" },
    { "fulfilledBy" : "App.Root", "plainType" : "Root" },
    { "fulfilledBy" : "App.DefaultService", "plainType" : "Service" }
  ],
  "modules" : [
    { "name" : "App", "paths" : [ "Sources/App" ] }
  ]
}
```

- **`command`** is `graph`, and **`modules`** lists each module read, by name, with the `--include` directories or `--module-info` files it was read from.
- **`declarations`**: each production `@Instantiable` declaration, sorted by module, then type name, then line. A `mockOnly` declaration describes a mock and is left out. `id` is opaque: match it whole and never split it. `typeName` is the type’s name, a nested type’s qualified by the types enclosing it. `fulfills` lists the types the declaration fulfills, its own first. `declarationKind` is `class`, `actor`, `struct` or `extension`. `isRoot` is set for a root, and `generatesDependencyTree` for a type declared with `generateDependencyTree: true`. `filePath` is spelled under the `--include` argument as given, or as a `--module-info` file records it.
- **`constructedBy`** points up the graph: each instantiated dependency, of any declaration, that this declaration fulfills, as `{ "declaredBy", "label" }`, sorted by `declaredBy`, then label. It is empty for a declaration nothing instantiates, such as a root.
- **`isReachedByRoot`** is `true` when some root’s tree builds the declaration. A type only another module’s root reaches is not reached when that module is not read.
- **`dependencies`**: each dependency the declaration declares, in declaration order. `source` is one of:
  - `instantiated`, built by the declaration, with `lifetime`:
    - `eager`, built when its owner is;
    - `lazy`, held in a `LazilyInstantiated` or `SendableLazilyInstantiated` and built once, when first read;
    - `builder`, held in an instantiator and built each time it is asked;
  - `received`, handed down by a declaration above the owner: a `@Received` property, or an alias, a `@Received(fulfilledByDependencyNamed:ofType:)`, which has `aliasOf` naming the property it renames, with its `label`, `type` and `plainType`;
  - `forwarded`, passed in by whoever builds the owner.

  `wrapper` names the SafeDI wrapper the property is held in. An instantiated dependency declared with `fulfilledByType:` has **`fulfilledByType`**, the type SafeDI builds, as a `plainType` is spelled; its `plainType` stays the property’s. **`fulfilledBy`** points down the graph: in a resolved graph, the id of the declaration that fulfills the type an instantiated dependency builds, its `fulfilledByType` or else its `plainType`, absent when no production declaration does. `isErased` and `isOnlyIfAvailable` say whether the dependency is `erasedToConcreteExistential` and whether it is received or instantiated only if available. A dependency instantiated only if available that has no `fulfilledBy` is `nil`, and so is every dependency whose `provenance` names it.
- **`provenance`**: where a received dependency’s value comes from. Each received dependency and alias of a declaration some root’s tree builds has it, once the trees are built: every value the trees hand it, in every place they build its type. A value is one of:
  - `{ "source" : "declaration", "declaredBy", "label" }`: the value of the dependency `label` of declaration `declaredBy`, which instantiates, forwards or aliases it. An alias’s values are those of what it renames. A value that is itself an alias is that alias, so follow the alias’s own `provenance` to what it renames;
  - `{ "source" : "nil", "reason" : { "kind", "message" } }`: generated code hands it `nil`, as it hands a dependency received only if available. `kind` is `noProvidingDeclaration`, where no declaration in scope provides the form it reads, or `providerNotYetBuilt`, where the nearest declaration that provides it is built after it, or is still being built around it. `message` says the same in a sentence.

  Declarations come first, sorted by `declaredBy`, then label, then `nil` values by `kind`. The values are read from the trees `generate` builds, the order it builds each type’s dependencies in included, so they are what generated code does. A type declared with `generateDependencyTree: true` is read inline, as a module that calls no such type builds it, which hands each dependency the value the type’s generated initializer passes it.
- **`fulfillments`**: for each type SafeDI can build, by `plainType`, the id of the declaration that fulfills it, sorted by `plainType`.
- **`completeness`** and **`errors`**: `completeness` says how much SafeDI worked out. It is `trees` when the trees are built. It is `fulfillment` when the types resolve but the trees are not valid, such as when a type no declaration fulfills is instantiated: no dependency has `provenance` and no declaration has `isReachedByRoot`. It is `declarations` when SafeDI cannot resolve the types, such as when two declarations fulfill one type: `fulfillments` is empty, and no declaration has `constructedBy` and no dependency `fulfilledBy`. `errors` lists what `generate` would report, each with its `message` and, where it has one, its `filePath` and `line`. The declarations are still exported, and the command still succeeds, so an export taken in the middle of an edit still answers questions.

The export does not say the order a type builds its dependencies in, which can differ between the places a type is built.

## Recipes

These use [`jq`](https://jqlang.org).

Where `Cache` is used – held, received or renamed as `Cache`, or built as `App.Cache`, also through a type it fulfills – with each site’s file and line:

```bash
jq --arg T Cache --arg ID App.Cache '[.declarations[] as $owner | $owner.dependencies[]
  | select(.plainType == $T or .aliasOf.plainType == $T
    or .fulfilledByType == $T or .fulfilledBy == $ID)
  | {owner: $owner.id, source, lifetime, label, filePath, line}]' graph.json
```

The declarations that instantiate `App.Log`:

```bash
jq --arg T App.Log '.declarations[] | select(.id == $T) | .constructedBy' graph.json
```

The roots whose trees build `App.Cache`, following `constructedBy` up the graph:

```bash
jq --arg T App.Cache '(.declarations | INDEX(.id)) as $byID
  | {seen: [$T], next: [$T]}
  | until(.next == [];
      (([.next[] | $byID[.].constructedBy[]?.declaredBy] | unique) - .seen) as $new
      | .seen += $new | .next = $new)
  | [.seen[] | select($byID[.].isRoot)]' graph.json
```

Every declaration `App.Root`’s tree builds, following `fulfilledBy` down the graph:

```bash
jq --arg T App.Root '(.declarations | INDEX(.id)) as $byID
  | {seen: [$T], next: [$T]}
  | until(.next == [];
      (([.next[] | $byID[.].dependencies[].fulfilledBy // empty] | unique) - .seen) as $new
      | .seen += $new | .next = $new)
  | .seen - [$T]' graph.json
```

Where `App.Screen`’s `session` comes from:

```bash
jq --arg T App.Screen --arg L session '.declarations[] | select(.id == $T)
  | .dependencies[] | select(.label == $L) | .provenance' graph.json
```

Every dependency generated code hands `nil`, and why:

```bash
jq '[.declarations[] as $owner | $owner.dependencies[]
  | select(any(.provenance[]?; .source == "nil"))
  | {owner: $owner.id, label, reasons: [.provenance[] | select(.source == "nil") | .reason.message]}]' graph.json
```

The declaration that fulfills `Service`:

```bash
jq --arg T Service '.fulfillments[] | select(.plainType == $T) | .fulfilledBy' graph.json
```

## Keeping the export current

`--output` writes the file only when its bytes change, so a file watcher or a build system sees a change only when the graph changed. A project whose build writes `.safedi` files exports from them with `--module-info` and parses no source.
