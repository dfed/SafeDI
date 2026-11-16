# Profile of `generate` for module Feature of E24-seam, main a6d44aff

Command (Linux, Swift 6.2 release build, pinned to one core while another benchmark ran on the others):

```
perf record -e cpu-clock -F 300 --call-graph dwarf,16384 SafeDITool generate f.csv --combined-output out.swift \
  --module-info-output Feature.safedi --module-name Feature --package-name Benchmark --active-compilation-conditions DEBUG
```

f.csv lists `fixtures/E24-seam/Feature/Types.swift`. Wall time about 7 s on one core. CPU-time samples, not instructions.

## Reading

- 57% of samples are under `DependencyTreeGenerator.seamRoot`: `holes(of:…)` 25%, `shapedBuilders` 32%.
- Quadratic: `internalName(ofBuilderLabeled:)` (`SeamBuilderParameters.swift:163`, about 20% inclusive) runs once per hole
  site and rebuilds `builderFunctionNames.union(namesBoundByEarlierBuilders).union(unrenamedBuilderNames.filter {…})`
  each time (`Set.union` 19%, `Set.insert` 20%, hashing 10%): O(sites) per site. Candidate fix: test `name` against the
  three collections without building the union, with `unrenamedBuilderNames` a `Set` built once; identical names.
- n log n with a heavy constant: `holesBySite.keys.sorted { $0.sortKey < $1.sortKey }` (`SeamBuilderFamilies.swift:307`,
  `:322`) builds `Hole.Site.sortKey` (a string of the whole path's `Property.asSource`) on every comparison
  (`sortKey` 18.6%, `Property.asSource` 17.4%); `valuesBindingNames`' `sortKey(of:)` (`SeamScopeEnumsByType.swift:880`,
  9.7%) and the inner-scope `sortKey(of:)` (`SeamBuilderFamilies.swift:446`) likewise. Candidate fix: compute keys once,
  sort (key, element) pairs.
- E24 → E32: about 9x the sites and lines, 60x the time (8.6 s → 516 s), consistent with the quadratic term taking over.

## Top functions (1536 samples)

### Self

- 10.3% `swift_retain`
- 7.7% `swift_release`
- 6.4% `Hasher.combine(bytes:)`
- 4.4% `__memcpy_avx512_unaligned_erms (inlined)`
- 2.5% `_ZN5swift9RefCountsINS_13RefCountBitsTILNS_19RefCountInlinednessE1EEEE15doDecrementSlowILNS_13PerformDeinitE1EEEbS3_j`
- 2.3% `_StringGuts.append(_:)`
- 2.1% `Hasher.init(_seed:)`
- 2.1% `Hasher._finalize()`
- 2.1% `__memcmp_evex_movbe`
- 1.8% `__GI___libc_malloc (inlined)`
- 1.4% `_int_free`
- 1.4% `String._uncheckedIndex(after:)`
- 1.4% `swift_bridgeObjectRelease`
- 1.4% `specialized UnsafeMutablePointer.initialize(from:count:)`
- 1.4% `_StringGuts.prepareForAppendInPlace(totalCount:otherUTF8Count:)`
- 1.2% `tcache_get_n (inlined)`
- 1.2% `swift_bridgeObjectRetain`
- 1.1% `specialized Set._Variant.insert(_:)`
- 1.0% `_int_malloc`
- 1.0% `specialized static String._uncheckedFromUTF8(_:isASCII:)`

### Inclusive

- 80.9% `[unknown]`
- 57.0% `static DependencyTreeGenerator.seamRoot(of:generator:proof:instantiables:ownScopeEnums:generatesPlainInitializers:)`
- 32.2% `static DependencyTreeGenerator.shapedBuilders(of:generator:holes:parameters:otherParameters:treeFunctionNames:proof:instantiables:ownScopeEnums:scopeTypeNames:bindsReceiv`
- 29.0% `specialized MutableCollection<>.sort(by:)`
- 28.8% `specialized UnsafeMutableBufferPointer._stableSortImpl(by:)`
- 28.8% `specialized closure #1 in UnsafeMutableBufferPointer._stableSortImpl(by:)`
- 25.3% `specialized static DependencyTreeGenerator.holes(of:generator:bindsReceivesAgain:namesApartAtRoot:parameters:proof:instantiables:)`
- 24.3% `static DependencyTreeGenerator.holes(of:generator:bindsReceivesAgain:namesApartAtRoot:parameters:proof:instantiables:) (inlined)`
- 21.5% `specialized Collection.map<A, B>(_:) (inlined)`
- 20.1% `specialized Set._Variant.insert(_:)`
- 19.7% `internalName #1 (ofBuilderLabeled:) in static DependencyTreeGenerator.holes(of:generator:bindsReceivesAgain:namesApartAtRoot:parameters:proof:instantiables:)`
- 19.3% `specialized Set.union<A>(_:)`
- 18.8% `specialized Sequence.sorted(by:) (inlined)`
- 18.6% `closure #10 in static DependencyTreeGenerator.shapedBuilders(of:generator:holes:parameters:otherParameters:treeFunctionNames:proof:instantiables:ownScopeEnums:scopeTypeNa`
- 18.6% `SeamSignature.Hole.Site.sortKey.getter`
- 18.6% `specialized MutableCollection<>._insertionSort(within:sortedEnd:by:) (inlined)`
- 17.4% `Property.asSource.getter (inlined)`
- 17.4% `key path getter for Property.asSource : Property (inlined)`
- 17.3% `_dispatch_worker_thread`
- 17.3% `start_thread`
- 17.3% `clone3`
- 17.2% `_dispatch_async_redirect_invoke`
- 17.2% `_ZN5swift34runJobInEstablishedExecutorContextEPNS_3JobE`
- 17.2% `_dispatch_continuation_pop`
- 17.2% `swift_job_run`
- 13.0% `_StringGuts.append(_:)`
- 11.9% `implicit closure #1 in SeamSignature.Hole.Site.sortKey.getter (inlined)`
- 11.3% `protocol witness for Hashable._rawHashValue(seed:) in conformance String (inlined)`
- 11.3% `specialized static DependencyTreeGenerator.valuesBindingNames(of:reservedNames:)`
- 11.3% `static DependencyTreeGenerator.valuesBindingNames(of:reservedNames:) (inlined)`
- 11.1% `TypeDescription.asSource.getter`
- 10.7% `ScopeGenerator.generateProperties(codeGeneration:propertiesGeneratedLater:enclosingFunctionNames:leadingMemberWhitespace:)`
- 10.6% `specialized Set.union<A>(_:) (inlined)`
- 10.3% `swift_retain`
- 10.2% `_ZN5swift9RefCountsINS_13RefCountBitsTILNS_19RefCountInlinednessE1EEEE15doDecrementSlowILNS_13PerformDeinitE1EEEbS3_j`
- 9.9% `ScopeGenerator.generateCode(codeGeneration:unavailableProperties:propertiesGeneratedLater:builderFunctionNames:leadingWhitespace:) (inlined)`
- 9.8% `specialized _merge<A>(low:mid:high:buffer:by:)`
- 9.8% `closure #1 in static DependencyTreeGenerator.valuesBindingNames(of:reservedNames:) (inlined)`
- 9.7% `sortKey #1 (of:) in static DependencyTreeGenerator.valuesBindingNames(of:reservedNames:)`
- 9.5% `closure #11 in static DependencyTreeGenerator.shapedBuilders(of:generator:holes:parameters:otherParameters:treeFunctionNames:proof:instantiables:ownScopeEnums:scopeTypeNa`
- 9.0% `_StringGuts.prepareForAppendInPlace(totalCount:otherUTF8Count:)`
- 9.0% `specialized DefaultStringInterpolation.appendInterpolation<A>(_:) (inlined)`
- 9.0% `specialized protocol witness for TextOutputStreamable.write<A>(to:) in conformance String (inlined)`
- 9.0% `protocol witness for TextOutputStream.write(_:) in conformance DefaultStringInterpolation (inlined)`
- 9.0% `specialized String.write<A>(to:) (inlined)`
