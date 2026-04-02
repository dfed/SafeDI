# Mock Test Audit Issues

Issues found during audit that need CODE fixes (not test updates):

## Known Issues

1. **Duplicate parameter: forwarded + promoted collision** (mock_generatedForLotsOfInterdependentDependencies)
   - `LoggedInViewController` has `@Forwarded let userManager: UserManager` AND `UserManager` gets promoted from receivedProperties
   - Result: two `userManager:` parameters — invalid Swift
   - Fix: filter promoted dependencies that collide with forwarded properties

2. **Protocol type not resolved in scope map** (mock_transitiveProtocolDependencyFulfilledByExtensionIsOptional)
   - `StringStorage` (protocol) fulfilled by `SomeExternalType` via `fulfillingAdditionalTypes`
   - `receivedProperties` contains `stringStorage: StringStorage`
   - Scope map has `StringStorage` key from `fulfillingAdditionalTypes`
   - But promotion guard `typeDescriptionToScopeMap[dependencyType]` fails
   - Need to debug TypeDescription matching

## Issues Found During Audit

3. **LoggedInViewController duplicate userManager** (mock_generatedForLotsOfInterdependentDependencies)
   - `@Forwarded userManager: UserManager` satisfies `@Received userManager: UserManager` deep in tree
   - `receivedProperties` should subtract forwarded properties, so `userManager` should NOT bubble up
   - Current test has duplicate `userManager:` parameter — expectation is WRONG
   - CORRECT expectation: single `userManager: UserManager` (bare forwarded), no closure version
   - CODE issue: `createMockRootScopeGenerator` promotes `userManager` from `receivedProperties` even though forwarded already provides it. The initial `receivedProperties` should NOT include `userManager` since it's forwarded. Need to verify `ScopeGenerator.receivedProperties` correctly subtracts forwarded.

4. **EditProfileViewController standalone mock** (mock_generatedForLotsOfInterdependentDependencies)
   - Has `@Received userVendor: UserVendor`, `@Received userManager: UserManager`, `@Received userNetworkService: NetworkService`
   - `UserVendor` fulfilled by `UserManager`, `NetworkService` fulfilled by `DefaultNetworkService`
   - `UserManager` IS @Instantiable (no-arg init)
   - All three should be optional parameters with defaults
   - Need to verify current expectation matches this

5. **StringStorage protocol resolution** — TEST CORRECTED, CODE FIX NEEDED (mock_transitiveProtocolDependencyFulfilledByExtensionIsOptional)
   - Protocol `StringStorage` fulfilled by `SomeExternalType` via `fulfillingAdditionalTypes`
   - Should be optional parameter, currently `@escaping` (required)
   - Root cause: type matching issue in scope map lookup during promotion
   - The `receivedProperties` contains `stringStorage: StringStorage` (property type)
   - The scope map has `StringStorage` as key → `SomeExternalType` scope
   - `receivedProperty.typeDescription.asInstantiatedType` should give `StringStorage`
   - Need to debug why the lookup fails
