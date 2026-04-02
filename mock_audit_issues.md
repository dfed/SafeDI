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

5. **Protocol/type resolution in scope map during promotion** — MULTIPLE TESTS AFFECTED
   - StringStorage (mock_transitiveProtocolDependencyFulfilledByExtensionIsOptional)
   - TransitiveDep (mock_threadsTransitiveDependenciesNotInParentScope)
   - Types that ARE @Instantiable and in the scope map are not being found during
     the promotion loop in createMockRootScopeGenerator
   - Root cause: `receivedProperty.typeDescription.asInstantiatedType` doesn't match
     the scope map key for some types. Need to debug TypeDescription matching.
   - Protocol `StringStorage` fulfilled by `SomeExternalType` via `fulfillingAdditionalTypes`
   - Should be optional parameter, currently `@escaping` (required)
   - Root cause: type matching issue in scope map lookup during promotion
   - TransitiveDep test expectation CORRECTED (was @escaping, should be optional)

6. **Cosmetic: enum name disambiguation produces ugly names** (SharedThing_SharedThing)
   - Same type at multiple paths triggers disambiguation with `_SourceType` suffix
   - Not a compilation error, just ugly. Low priority.

## Audit Summary

Tests verified CORRECT (passing, expectations match desired behavior):
- All simple tests (no deps, single dep, extension-based, config tests)
- mock_receivedConcreteExistentialWrapperConstructsUnderlyingType — AnyUserService wrapping OK
- mock_sharedTransitiveReceivedDependencyPromotedAtRootScope — root promotion OK
- mock_onlyIfAvailableDependencyUsesVariableInReturnStatement — threading OK
- mock_sendableInstantiatorDependencyClosuresAreMarkedSendable — @Sendable OK
- mock_disambiguatesParameterLabelsWhenSameInitLabelAppearsTwice — disambiguation OK
- mock_inlineConstructsWithNilForMissingOptionalArgs — onlyIfAvailable handling OK
- All @escaping params verified as non-@Instantiable types (correct)

Tests with CORRECTED expectations (now fail, need CODE fixes):
- mock_generatedForLotsOfInterdependentDependencies — duplicate userManager removed
- mock_transitiveProtocolDependencyFulfilledByExtensionIsOptional — StringStorage optional
- mock_threadsTransitiveDependenciesNotInParentScope — TransitiveDep optional
   - The `receivedProperties` contains `stringStorage: StringStorage` (property type)
   - The scope map has `StringStorage` as key → `SomeExternalType` scope
   - `receivedProperty.typeDescription.asInstantiatedType` should give `StringStorage`
   - Need to debug why the lookup fails
