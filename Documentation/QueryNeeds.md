# The `query needs` report

[`SafeDITool query needs`](Manual.md#querying-what-a-type-needs) reports what `@Instantiable` types and their mocks need, so that a focused app can be assembled from exactly the modules one feature needs. The Manual introduces the command and how to run it in each integration. This page describes what the report covers, and the JSON a script reads with `--json`.

> `query needs` is in beta. Its options, text, and JSON may change in any release; the JSON’s `formatVersion` is `0` until the format is stable.

## What the report covers

Each type gets a report, in the order named. Each `--include` directory is a module holding the Swift files found in it recursively, so the targets of a package laid out as `Sources/<Target>` are included with `--include Sources/*/`. Each `--module-info` file is a module holding the declarations its build read, under that build’s compilation conditions, so `--active-compilation-conditions` applies only to the directories. A file written by another version of SafeDI cannot be read.

For each type, the query reports the modules the type is built from in production, each with the declarations that build it, the type’s `@Forwarded` parameters, and the dependencies no `@Instantiable` declaration fulfills, each with its reason. It then reports the same for the type’s mock – the generated `mock()` when the project generates one (`generated`), else a hand-written mock (`handWritten`), else the `mock()` that listing the type in `additionalMocksToGenerate` would generate (`wouldBeGenerated`) – with the `@Forwarded` parameters it requires and those it defaults, and the dependencies it takes as parameters. Both reports are read from the dependency tree `generate` builds, so they never disagree with the generated code.

Name each type as `additionalMocksToGenerate` names it, such as `Feature.Consumer` for a nested type. Include only modules that could build together; the query does not follow `additionalDirectoriesToInclude`, and reports what a build would report for the type.

## The JSON report

Pass `--json` for the same report as JSON. The root object carries a `formatVersion`, which is `0` while the command is in beta and the shape may change in any release; `1` will be the first stable format. Keys are sorted, every array is present, and an optional key is left out rather than `null`. For `Feature` with `generateMock: true` in `Sources/FeatureModule`, which forwards a `user` and a `config` and receives an `Analytics` nothing declares, where a `mockOnly` extension in `Sources/ConfigMocks` gives `Config` a `mock()`:

```json
{
  "formatVersion" : 0,
  "types" : [
    {
      "forwardedParameters" : [
        {
          "label" : "config",
          "type" : "Config"
        },
        {
          "label" : "user",
          "type" : "User"
        }
      ],
      "mock" : {
        "forwardedParameters" : [
          {
            "defaultExpression" : "Config.mock()",
            "label" : "config",
            "type" : "Config"
          },
          {
            "label" : "user",
            "type" : "User"
          }
        ],
        "generatedIn" : [
          "FeatureModule"
        ],
        "kind" : "generated",
        "methodName" : "mock",
        "modules" : [
          {
            "declarations" : [
              {
                "filePath" : "Sources/ConfigMocks/Config+Mock.swift",
                "kind" : "handWrittenMock",
                "methodName" : "mock",
                "typeName" : "Config"
              }
            ],
            "name" : "ConfigMocks",
            "paths" : [
              "Sources/ConfigMocks"
            ]
          },
          {
            "declarations" : [
              {
                "filePath" : "Sources/FeatureModule/Feature.swift",
                "kind" : "instantiable",
                "typeName" : "Feature"
              }
            ],
            "name" : "FeatureModule",
            "paths" : [
              "Sources/FeatureModule"
            ]
          }
        ],
        "unfulfilledDependencies" : [
          {
            "label" : "analytics",
            "reason" : "No @Instantiable declaration fulfills `Analytics`.",
            "reasonKind" : "noInstantiableFulfillsType",
            "type" : "Analytics"
          }
        ]
      },
      "modules" : [
        {
          "declarations" : [
            {
              "filePath" : "Sources/FeatureModule/Feature.swift",
              "kind" : "instantiable",
              "typeName" : "Feature"
            }
          ],
          "name" : "FeatureModule",
          "paths" : [
            "Sources/FeatureModule"
          ]
        }
      ],
      "typeName" : "Feature",
      "unfulfilledDependencies" : [
        {
          "label" : "analytics",
          "reason" : "No @Instantiable declaration fulfills `Analytics`.",
          "reasonKind" : "noInstantiableFulfillsType",
          "type" : "Analytics"
        }
      ]
    }
  ]
}
```

| Key | Value |
| --- | --- |
| `formatVersion` | The format’s version: `0` while the command is in beta, `1` once the format is stable. |
| `types` | One report per type named, in the order named. |
| `types[].typeName` | The concrete type queried, as its declaration spells it. |
| `types[].modules` | The modules the type is built from in production, sorted by `name`. `paths` are the `--include` or `--module-info` arguments that named the module, as given, which a script maps back to a build target. `declarations` are sorted by type: `kind` is `instantiable` (an `@Instantiable` declaration, `typeName` the type), `handWrittenMock` (`typeName` the mocked type, `methodName` the method), or `erasure` (`typeName` the type declaring the erasing property, and `erasure` holding the `property` as declared, the `erasedTypeName` received, the `concreteTypeName` built, and `alsoDeclaredInModules`, the other modules any of which would do instead). `filePath` is the file that holds the declaration: under the `--include` argument that named its module, so it opens from where the tool ran, or, for a module named with `--module-info`, as that file records it. |
| `types[].forwardedParameters` | The type’s `@Forwarded` parameters in the order `mock()` declares them: `label` and `type`. A `label`, here and in `unfulfilledDependencies`, is spelled as the generated `mock()` declares it, in backticks only where Swift requires them: a keyword reads `` `default` ``, and a name a declaration escaped without need, such as `` `user` ``, reads `user`. |
| `types[].unfulfilledDependencies` | The dependencies no `@Instantiable` declaration fulfills, in the order `mock()` would take them: `label`, `type`, `reasonKind` (`noInstantiableFulfillsType`, `typeHasForwardedProperties`, or `erasedToMultipleConcreteTypes`), and the `reason` as the text report states it. |
| `types[].mock` | What the type’s mock needs. `kind` is `generated`, `handWritten`, or `wouldBeGenerated`, for the three mocks [What the report covers](#what-the-report-covers) names; `methodName` is the method to call; `generatedIn`, present only when `kind` is `generated`, names the modules that generate it; `modules` is as above, for the mock; `forwardedParameters` adds `defaultExpression` where the mock defaults a parameter; `unfulfilledDependencies` are the dependencies the mock still takes as parameters, spelled as the type’s. |
| `types[].noMock` | Present instead of `mock` when SafeDI can build no mock for the type: `reasonKind` (`handWrittenMockNamedMockReturnsAnotherType`) and the `reason` the text report prints. |

With `--json`, an error is printed to standard output as JSON too, with the same `formatVersion`, and the command exits non-zero. `error.kind` is the query’s own kind – `noModuleIncluded`, `moduleHasNoSwiftFiles`, `moduleInfoNotReadable`, `fileInTwoModules`, `filesWithUnexpectedNodes`, `noInstantiableNamed`, or `onlyMockOnlyDeclarationNamed` – or `diagnostics` for what a build would report, or `other`; `error.message` is what the text mode prints.

| Error key | Value |
| --- | --- |
| `error.kind` and `error.message` | Present on every error, as above. |
| `error.typeName`, `error.fulfilledBy`, `error.similarlyNamed` | A `noInstantiableNamed` error’s type name, the types that fulfill it, and the types named most like it; an `onlyMockOnlyDeclarationNamed` error has `typeName` only. |
| `error.paths` | The paths a `moduleHasNoSwiftFiles`, `moduleInfoNotReadable`, `fileInTwoModules`, or `filesWithUnexpectedNodes` error names. |
| `error.diagnostics` | For a `diagnostics` error, each diagnostic’s `severity`, `filePath`, `line`, `column`, and `message`. |
