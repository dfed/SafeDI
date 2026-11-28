// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The oracle that compares what a seam's signature reads of its tree with what the per-type facts of that tree hold at
/// its root (`SeamTreeReadsObservation`, `SeamTreeReadsChecks`), which every test and fuzzer graph runs under. `Screen`'s
/// tree requires `config` and `onTap` of its caller, receives `theme` only if available, requires `token` only through
/// `Detail`'s `onlyIfAvailable` alias of it, and declares `OnTap` `@escaping`, so each field the facts produce is
/// non-empty: the oracle reports nothing, and reports each field emptied. Of its by-value pass-throughs, `config` is read
/// in plain code, `session` inside a `SendableInstantiator`'s builder, and `clock` by `Panel`, a nested seam that takes it
/// `@Sendable`; a pass-through no read reaches, whose label a fill binds from its struct, is
/// `generate_reportsNoDifference_whenFillOfSeamCallBindsLabelOfReceiveThatLeavesSeam`'s.
struct SafeDIToolSeamTreeReadsTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFactsOfSeamsTreeHoldWhatTreeHolds(integration: MultiModuleIntegration) async throws {
		let comparisons = try await observedComparisons(under: integration)
		#expect(!comparisons.isEmpty)
		#expect(Set(comparisons.map(\.seam)) == ["Panel", "Screen"])
		let differences = comparisons.flatMap(\.differences)
		#expect(differences.isEmpty)
	}

	@Test(arguments: SeamTreeReadsObservation.FactsField.allCases, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDifference_whenFactsFieldIsPerturbed(field: SeamTreeReadsObservation.FactsField, integration: MultiModuleIntegration) async throws {
		// The harness records an issue for each comparison that differs, which is what this test makes happen.
		var comparisons = [SeamTreeReadsComparison]()
		try await withKnownIssue {
			comparisons = try await SeamTreeReadsObservation.$perturbsFactsField.withValue(field) {
				try await observedComparisons(under: integration)
			}
		}
		let tree = switch field {
		case .requiredReceivedProperties:
			["clock: Clock", "config: Config", "onTap: OnTap", "session: Session"]
		case .requiredAliasFulfillingProperties:
			["token: Token"]
		case .typesDeclaredEscaping:
			["OnTap"]
		case .builderFunctionNames:
			[
				"with hole sites: __safeDI_authToken",
				"with hole sites: __safeDI_badge",
				"with hole sites: __safeDI_child",
				"with hole sites: __safeDI_detail",
				"with hole sites: __safeDI_panel",
				"with hole sites: __safeDI_pollerBuilder",
				"with hole sites: __safeDI_reader",
				"without hole sites: __safeDI_authToken",
				"without hole sites: __safeDI_badge",
				"without hole sites: __safeDI_child",
				"without hole sites: __safeDI_detail",
				"without hole sites: __safeDI_panel",
				"without hole sites: __safeDI_pollerBuilder",
				"without hole sites: __safeDI_reader",
			]
		case .receivers:
			[
				"property=onTap: OnTap; declaringType=TapReader; location=TapReader.swift 0 here(line: 4, column: 5); access=public; module=Feature; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
				"property=config: Config; declaringType=TapReader; location=TapReader.swift 0 here(line: 5, column: 5); access=public; module=Feature; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
				"property=theme: Theme?; declaringType=Badge; location=Badge.swift 0 here(line: 4, column: 5); access=public; module=Feature; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
				"property=token: Token; declaringType=Detail; location=Detail.swift 0 here(line: 4, column: 5); access=public; module=Feature; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=authToken: Token?; fromReportedSeamCall=false",
				"property=session: Session; declaringType=Poller; location=Poller.swift 0 here(line: 4, column: 5); access=public; module=Feature; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
				"property=clock: Clock; declaringType=Ticker; location=Ticker.swift 0 here(line: 4, column: 5); access=public; module=Feature; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
			]
		case .parameterReads:
			[
				"clock: read true, inside a @Sendable function true",
				"config: read true, inside a @Sendable function false",
				"onTap: read true, inside a @Sendable function false",
				"session: read true, inside a @Sendable function true",
				"theme: read true, inside a @Sendable function false",
				"token: read true, inside a @Sendable function false",
			]
		}
		// `Panel`'s tree holds no alias and no escaping type, and its `clock` is read where `Screen`'s is; its builder function
		// names are checked by the cells below.
		let screenComparisons = comparisons.filter { $0.seam == "Screen" }
		#expect(!screenComparisons.isEmpty)
		for comparison in screenComparisons {
			#expect(comparison.differences.map(\.field) == [field.rawValue])
			#expect(comparison.differences.map(\.tree).map(Self.withFileNames) == [tree])
			// An emptied `ParameterReads` reads no label.
			#expect(comparison.differences.map(\.facts) == [field == .parameterReads ? tree.map { $0.replacingOccurrences(of: "true", with: "false") } : []])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenSeamsTreeHoldsHoleSiteAndFillOfSeamCall(integration: MultiModuleIntegration) async throws {
		let comparisons = try await observedComparisons(of: Self.holeAndFillModules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Inner", "Top"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTreesNamesWithAndWithoutHoleSites_whenBuilderFunctionNamesOfSeamsWithHoleSiteAndFillArePerturbed(integration: MultiModuleIntegration) async throws {
		// `Inner`'s hole site `service` names a function only with hole sites; the fill `Top`'s call of `Inner` passes, built
		// as `service` by `ServiceImpl`, which instantiates `helper`, names both in `Top`'s tree, with hole sites or without.
		var comparisons = [SeamTreeReadsComparison]()
		try await withKnownIssue {
			comparisons = try await SeamTreeReadsObservation.$perturbsFactsField.withValue(.builderFunctionNames) {
				try await observedComparisons(of: Self.holeAndFillModules, under: integration)
			}
		}
		let expectedTreeNamesBySeam = [
			"Inner": [
				"with hole sites: __safeDI_leaf",
				"with hole sites: __safeDI_service",
				"without hole sites: __safeDI_leaf",
			],
			"Top": [
				"with hole sites: __safeDI_helper",
				"with hole sites: __safeDI_inner",
				"with hole sites: __safeDI_service",
				"without hole sites: __safeDI_helper",
				"without hole sites: __safeDI_inner",
				"without hole sites: __safeDI_service",
			],
		]
		#expect(Set(comparisons.map(\.seam)) == ["Inner", "Top"])
		for comparison in comparisons {
			#expect(comparison.differences.map(\.field) == [SeamTreeReadsObservation.FactsField.builderFunctionNames.rawValue])
			#expect(comparison.differences.map(\.tree) == [expectedTreeNamesBySeam[comparison.seam] ?? []])
			#expect(comparison.differences.map(\.facts) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillOfSeamCallBindsLabelOfReceiveThatLeavesSeam() async throws {
		// `Top`'s fill of `Inner`'s place, which `Outer` passes up, binds `token` from its struct, so `WrapperReader`'s
		// receive of `token` reaches no parameter of `Top`: the graph is rejected (`declarationHiddenByField`), and the
		// signature pass before the error compares `Top`.
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		await #expect(throws: (any Error).self) {
			try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: Self.fillBindingLabelModules,
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream where comparison.seam == "Top" {
			comparisons.append(comparison)
		}
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenPlainMemoHandedToFillServesValueButNotSendableWrapperReadOnlyIfAvailable() async throws {
		// `Desk`'s fill of `Parcel`, a place `Office` passes up from inside its fill of `Inbox`, is handed `Inbox`'s plain
		// `LazilyInstantiated` memo of `credential`: it provides `StampImpl`'s value, but not `CredentialReader`'s optional
		// `SendableLazilyInstantiated`, which leaves `Desk` there, before `StampImpl`'s receive leaves on `clerkBuilder`'s
		// path. The graph is rejected (`Inbox`'s two forms of `credential`), after the signature pass compares `Desk`.
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		await #expect(throws: (any Error).self) {
			try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: Self.plainMemoBesideOptionalSendableWrapperModules,
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream where comparison.seam == "Desk" {
			comparisons.append(comparison)
		}
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillHandedPlainMemoCallsSeamThatDefersLabelSendable() async throws {
		// `Desk`'s fill of `Parcel` is handed `Inbox`'s plain memo of `credential`, and calls `Vault`, whose tree reads
		// `credential` inside a `SendableInstantiator`'s builder, so `Vault` takes it `@Sendable`: the fill binds the memo's
		// value, which serves no read of the wrapper, so `LazyReader`'s receive of it leaves `Desk`.
		let comparisons = try await comparisonsAllowingRejection(ofSeam: "Desk", in: Self.modules(besideParcelReader: Self.vaultDeclarations, parcelBuilds: "vault: Vault"))
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillHandedPlainMemoFillsPlaceSeamBuildsInSendableFunction() async throws {
		// `Desk`'s fill of `Parcel` is handed `Inbox`'s plain memo of `credential`, and calls `Safe`, whose `seal` place is
		// built in a `SendableInstantiator`'s builder, so `Safe` takes its builder `@Sendable` and its fill is `@Sendable`; the
		// fill reads `credential` there, so the outer fill binds the memo's value, which serves no read of the wrapper.
		let comparisons = try await comparisonsAllowingRejection(ofSeam: "Desk", in: Self.modules(besideParcelReader: Self.safeDeclarations, Self.sealImplDeclaration, parcelBuilds: "safe: Safe"))
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillHandedPlainMemoReadsLabelInBuilderFunctionCycleMakesSendable() async throws {
		// `Desk`'s fill of `Parcel` is handed `Inbox`'s plain memo of `credential`, and builds `Alpha` through
		// `alphaBuilder`, whose function a cycle closing inside `Beta`'s `SendableInstantiator` refers to, which makes it
		// `@Sendable`; `Alpha` reads `credential` there, so the fill binds the memo's value, which serves no read of the
		// wrapper.
		let comparisons = try await comparisonsAllowingRejection(ofSeam: "Desk", in: Self.modules(besideParcelReader: "", Self.sendableCycleDeclarations, parcelBuilds: "alphaBuilder: Instantiator<Alpha>"))
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillHandedPlainMemoReadsLabelThroughAliasInsideSendableInstantiator() async throws {
		// `Desk`'s fill of `Parcel` is handed `Inbox`'s plain memo of `credential`, and builds `Stamp` in a
		// `SendableInstantiator`; `Stamp` renames `credential` to `token`, so the fill's tree reads `credential` inside a
		// `@Sendable` function through the alias, and the fill binds the memo's value, which serves no read of the wrapper.
		let comparisons = try await comparisonsAllowingRejection(ofSeam: "Desk", in: Self.modules(besideParcelReader: "", Self.aliasReaderDeclaration, parcelBuilds: "stampBuilder: SendableInstantiator<Stamp>"))
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillOfSeamCallRequiresValueOfSeamsCaller() async throws {
		// `Desk`'s fill of `Drawer`'s place builds `PenImpl`, which requires `clock` of `Desk`'s caller: the tree's
		// required receives count it, as the facts' must.
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillRequiringCallersValueModules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream where comparison.seam == "Desk" {
			comparisons.append(comparison)
		}
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifferenceInReceivers_whenTypeReachedUnderTwoParentsReceivesLabelOnlyOneProvides(integration: MultiModuleIntegration) async throws {
		// `Gauge` is built by `Dial`, which declares `unit`, and by `Knob`, which does not: its receive of `unit` leaves
		// `Console` on `Knob`'s path alone, and is kept once, where the walk first reaches it, after `Knob`'s own receive.
		let comparisons = try await observedComparisons(of: Self.twoParentsModules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Console"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
		let receivers = try await treeReceivers(ofSeam: "Console", in: Self.twoParentsModules, under: integration)
		#expect(receivers == [
			"property=label: Label; declaringType=Knob; location=Knob.swift 0 here(line: 4, column: 5); access=public; module=Panel; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
			"property=unit: Unit; declaringType=Gauge; location=Gauge.swift 0 here(line: 4, column: 5); access=public; module=Panel; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifferenceInReceivers_whenAliasFulfillingPropertyLeavesSeamAndAliasOfOwnPropertyDoesNot(integration: MultiModuleIntegration) async throws {
		// `Meter`'s alias of `unit` leaves `Console`; `Lamp`'s alias of `glow`, which `Lamp` instantiates, does not.
		let comparisons = try await observedComparisons(of: Self.aliasModules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Console"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
		let receivers = try await treeReceivers(ofSeam: "Console", in: Self.aliasModules, under: integration)
		#expect(receivers == [
			"property=unit: Unit; declaringType=Meter; location=Meter.swift 0 here(line: 4, column: 5); access=public; module=Panel; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=reading: Unit; fromReportedSeamCall=false",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifferenceInReceivers_whenNestedSeamsTierOmitsReceiveOfItsTree(integration: MultiModuleIntegration) async throws {
		// `Shell` calls the `public` tier of `Service`, which omits `theme`, a `package` type's value `Badge` receives: the
		// receive reaches `Shell` as a no-tier receive, with the nested call that omits it.
		let comparisons = try await observedComparisons(of: Self.noTierModules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Service", "Shell"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
		let receivers = try await treeReceivers(ofSeam: "Shell", in: Self.noTierModules, under: integration)
		// Under module info `Shell` reads `Service`'s stored signature, which holds no positions.
		let location = switch integration {
		case .moduleInfo: "none"
		case .swiftPackagePlugin: "Badge.swift 0 here(line: 4, column: 5)"
		}
		#expect(receivers == [
			"property=theme: Theme?; declaringType=Badge; location=\(location); access=package; module=Base; instantiateMethodParameter=false; noTier=true; noTierCallTier=public; nestedSeamCall=Service of Base at public for public from Mid, parameter tier package, receiving [\"Badge\"]; alias=none; fromReportedSeamCall=false",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifferenceInReceivers_whenLazyCycleClosesOnTypeThatReceives(integration: MultiModuleIntegration) async throws {
		// `Page` builds `Page` again through `nextBuilder`, a cycle the tree closes there; `Page`'s receive of `unit` is
		// one receiver, from the first build.
		let comparisons = try await observedComparisons(of: Self.cycleModules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Console"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
		let receivers = try await treeReceivers(ofSeam: "Console", in: Self.cycleModules, under: integration)
		#expect(receivers == [
			"property=unit: Unit; declaringType=Page; location=Page.swift 0 here(line: 6, column: 5); access=public; module=Panel; instantiateMethodParameter=false; noTier=false; noTierCallTier=none; nestedSeamCall=none; alias=none; fromReportedSeamCall=false",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillReadsLabelOnlyIfAvailableThatCalledSeamBindsLazilyOnFirstRouteToPlace(integration: MultiModuleIntegration) async throws {
		// `Kiosk` calls `Terminal`, which reaches `Ledger`'s place inside `Booth`, first in builder order, which binds
		// `ticket` as a `LazilyInstantiated`, and beside it, where nothing binds `ticket`: the one fill serves both routes,
		// so on the second it reads `Kiosk`'s own `ticket`, and `DefaultCourier`'s receive of it leaves `Kiosk`.
		let modules = Self.ticketRouteModules(ticketReceive: "@Received(onlyIfAvailable: true) let ticket: Ticket?")
		let comparisons = try await observedComparisons(of: modules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Kiosk", "Terminal"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillRequiresLabelThatCalledSeamBindsLazilyOnFirstRouteToPlace(integration: MultiModuleIntegration) async throws {
		// `generate_reportsNoDifference_whenFillReadsLabelOnlyIfAvailableThatCalledSeamBindsLazilyOnFirstRouteToPlace`'s
		// shape, where `DefaultCourier` and `Kiosk` require `ticket`.
		let modules = Self.ticketRouteModules(ticketReceive: "@Received let ticket: Ticket")
		let comparisons = try await observedComparisons(of: modules, under: integration)
		#expect(Set(comparisons.map(\.seam)) == ["Kiosk", "Terminal"])
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesSameSignaturesAndCode_whenSignaturePassesProceedWithFactsReads() async throws {
		let fromTree = try await signaturesAndCode(proceedingWith: .tree)
		let fromFacts = try await signaturesAndCode(proceedingWith: .facts)
		#expect(fromTree.signatures.contains("Screen"))
		#expect(fromTree.code.values.contains { $0.contains("__safeDI_onTap") })
		#expect(fromFacts.signatures == fromTree.signatures)
		#expect(fromFacts.code == fromTree.code)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Every comparison the oracle makes of `seam` while `modules` generate under module info, whether or not the graph is
	/// accepted: the signature passes before an error compare their seams too.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func comparisonsAllowingRejection(ofSeam seam: String, in modules: [ModuleFixture]) async throws -> [SeamTreeReadsComparison] {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		do {
			try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: modules,
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		} catch {}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream where comparison.seam == seam {
			comparisons.append(comparison)
		}
		return comparisons
	}

	/// `Feature`'s stored seam signatures, as JSON, and every module's generated code, each with the fixture root spelled
	/// `$FIXTURE_ROOT`, when every signature pass proceeds with `producer`'s reads.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func signaturesAndCode(proceedingWith producer: SeamTreeReadsObservation.Producer) async throws -> (signatures: String, code: [String: String]) {
		let output = try await SeamTreeReadsObservation.$producer.withValue(producer) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		let fixtureRoot = output.fixtureRoot.path
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		let moduleInfoFile = try #require(output.modules["Feature"]?.moduleInfoFile)
		let storedSignatures = try moduleInfoFile.seamSignatures.decoded
		let signatures = try String(decoding: encoder.encode(storedSignatures), as: UTF8.self)
			.replacingOccurrences(of: fixtureRoot, with: "$FIXTURE_ROOT")
		var code = [String: String]()
		for (moduleName, module) in output.modules {
			for (fileName, content) in module.generatedFiles {
				code["\(moduleName)/\(fileName)"] = content.replacingOccurrences(of: fixtureRoot, with: "$FIXTURE_ROOT")
			}
		}
		return (signatures, code)
	}

	/// The tree's receivers of `seam`, as the comparison spells them with each location's file named alone, from the first
	/// comparison of `seam` while `modules` generate with the facts' receivers emptied.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func treeReceivers(ofSeam seam: String, in modules: [ModuleFixture], under integration: MultiModuleIntegration) async throws -> [String] {
		var comparisons = [SeamTreeReadsComparison]()
		try await withKnownIssue(isIntermittent: true) {
			comparisons = try await SeamTreeReadsObservation.$perturbsFactsField.withValue(.receivers) {
				try await observedComparisons(of: modules, under: integration)
			}
		}
		let comparison = try #require(comparisons.first { $0.seam == seam })
		return Self.withFileNames(comparison.differences.first { $0.field == SeamTreeReadsObservation.FactsField.receivers.rawValue }?.tree ?? [])
	}

	/// `spellings` with the path of each receiver's location spelled as its file's name alone.
	private static func withFileNames(_ spellings: [String]) -> [String] {
		spellings.map { spelling in
			spelling.components(separatedBy: "; ").map { part in
				guard part.hasPrefix("location="), part != "location=none" else { return part }
				let location = part.dropFirst("location=".count)
				let path = location.prefix { $0 != " " }
				return "location=\(URL(fileURLWithPath: String(path)).lastPathComponent)\(location.dropFirst(path.count))"
			}.joined(separator: "; ")
		}
	}

	/// Every comparison the oracle makes while `modules`, `App` and `Feature` by default, generate.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func observedComparisons(of modules: [ModuleFixture] = Self.modules, under integration: MultiModuleIntegration) async throws -> [SeamTreeReadsComparison] {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: modules,
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream {
			comparisons.append(comparison)
		}
		return comparisons
	}

	private static let modules = [
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			"""
			public typealias OnTap = (Int) -> Void
			""",
			"""
			@Instantiable
			public final class Config: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Theme: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class TapReader: Instantiable {
			    public init(onTap: @escaping OnTap, config: Config) { self.onTap = onTap; self.config = config }
			    @Received let onTap: OnTap
			    @Received let config: Config
			}
			""",
			"""
			@Instantiable
			public final class Badge: Instantiable {
			    public init(theme: Theme?) { self.theme = theme }
			    @Received(onlyIfAvailable: true) let theme: Theme?
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(authToken: Token?) { self.authToken = authToken }
			    @Received let authToken: Token?
			}
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init(authToken: Token?, child: Child) { self.authToken = authToken; self.child = child }
			    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Session: Instantiable, Sendable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Poller: Instantiable, Sendable {
			    public init(session: Session) { self.session = session }
			    @Received let session: Session
			}
			""",
			"""
			@Instantiable
			public final class Clock: Instantiable, Sendable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Ticker: Instantiable, Sendable {
			    public init(clock: Clock) { self.clock = clock }
			    @Received let clock: Clock
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Panel: Instantiable {
			    public init(tickerBuilder: SendableInstantiator<Ticker>) { self.tickerBuilder = tickerBuilder }
			    @Instantiated let tickerBuilder: SendableInstantiator<Ticker>
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Screen: Instantiable {
			    public init(reader: TapReader, badge: Badge, detail: Detail, pollerBuilder: SendableInstantiator<Poller>, panel: Panel) { self.reader = reader; self.badge = badge; self.detail = detail; self.pollerBuilder = pollerBuilder; self.panel = panel }
			    @Instantiated let reader: TapReader
			    @Instantiated let badge: Badge
			    @Instantiated let detail: Detail
			    @Instantiated let pollerBuilder: SendableInstantiator<Poller>
			    @Instantiated let panel: Panel
			}
			""",
		]),
		ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
			"""
			import Feature

			@Instantiable
			public final class Home: Instantiable {
			    public init(onTap: @escaping OnTap, config: Config, token: Token, session: Session, clock: Clock, screen: Screen) { self.onTap = onTap; self.config = config; self.token = token; self.session = session; self.clock = clock; self.screen = screen }
			    @Forwarded let onTap: OnTap
			    @Instantiated let config: Config
			    @Instantiated let token: Token
			    @Instantiated let session: Session
			    @Instantiated let clock: Clock
			    @Instantiated let screen: Screen
			}
			""",
			"""
			import Feature

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			    @Instantiated let homeBuilder: Instantiator<Home>
			}
			""",
		], dependencies: ["Feature"]),
	]

	/// `Inner`, a seam of `Core`, builds `leaf` and takes a builder for `service`, a hole site of its tree; `Top`, a seam of
	/// `Feature`, calls `Inner` and fills the place with `ServiceImpl`, which instantiates `helper`.
	private static let holeAndFillModules = [
		ModuleFixture(name: "Core", packageName: "Hub", swiftFileContent: ["""
		import SafeDI

		public protocol Service {}

		@Instantiable
		public final class Leaf: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable {
		    public init(leaf: Leaf, service: any Service) { self.leaf = leaf; self.service = service }
		    @Instantiated public let leaf: Leaf
		    @Instantiated public let service: any Service
		}
		"""]),
		ModuleFixture(name: "Feature", packageName: "Hub", swiftFileContent: ["""
		import Core
		import SafeDI

		@Instantiable
		public final class Helper: Instantiable {
		    public init() {}
		}

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class ServiceImpl: Instantiable, Service {
		    public init(helper: Helper) { self.helper = helper }
		    @Instantiated public let helper: Helper
		}

		@Instantiable(generateDependencyTree: true)
		public final class Top: Instantiable {
		    public init(inner: Inner) { self.inner = inner }
		    @Instantiated public let inner: Inner
		}
		"""], dependencies: ["Core"]),
	]

	/// `Inner`, a seam of `Core`, takes a builder for `service`; `Outer`, a seam of `Session`, declares `token` and calls
	/// `Inner`, passing the place up; `Top`, a seam of `Feature`, calls `Outer` and fills the place with `ServiceImpl`, whose
	/// `WrapperReader` receives `token` as a wrapper, a form the place's field does not provide.
	private static let fillBindingLabelModules = [
		ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
		import SafeDI

		public protocol Service: Sendable {}

		@Instantiable
		public final class Token: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Leaf: Instantiable, Sendable {
		    public init(token: Token) { self.token = token }
		    @Received public let token: Token
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable, Sendable {
		    public init(leafBuilder: SendableInstantiator<Leaf>, service: any Service) { self.leafBuilder = leafBuilder; self.service = service }
		    @Instantiated public let leafBuilder: SendableInstantiator<Leaf>
		    @Instantiated public let service: any Service
		}
		"""]),
		ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
		import Core
		import SafeDI

		@Instantiable(generateDependencyTree: true)
		public final class Outer: Instantiable, Sendable {
		    public init(token: SendableLazilyInstantiated<Token>, inner: Inner) { self.token = token; self.inner = inner }
		    @Instantiated public let token: SendableLazilyInstantiated<Token>
		    @Instantiated public let inner: Inner
		}
		"""], dependencies: ["Core"]),
		ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
		import Core
		import Session
		import SafeDI

		@Instantiable
		public final class WrapperReader: Instantiable, Sendable {
		    public init(token: SendableLazilyInstantiated<Token>) { self.token = token }
		    @Received public let token: SendableLazilyInstantiated<Token>
		}

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class ServiceImpl: Instantiable, Service, Sendable {
		    public init(wrapperReader: WrapperReader) { self.wrapperReader = wrapperReader }
		    @Instantiated public let wrapperReader: WrapperReader
		}

		@Instantiable(generateDependencyTree: true)
		public final class Top: Instantiable, Sendable {
		    public init(outer: Outer) { self.outer = outer }
		    @Instantiated public let outer: Outer
		}
		"""], dependencies: ["Core", "Session"]),
	]

	/// `Desk`, a seam of `Feature`, calls `Office`, which receives `credential` as a `SendableLazilyInstantiated` and calls
	/// `Inbox`, whose `Note` defers `credential` by value; `Office` fills `Inbox`'s `courier` with `CourierImpl`, whose
	/// `parcel` it passes up to `Desk`, which fills it with `ParcelImpl`. `ParcelImpl` builds `Clerk` through
	/// `clerkBuilder`, as `Desk` itself does after its call of `Office`.
	private static let plainMemoBesideOptionalSendableWrapperModules = [
		ModuleFixture(name: "Core", packageName: "Post", swiftFileContent: ["""
		import SafeDI

		public protocol Courier: Sendable {}

		@Instantiable
		public final class Credential: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Note: Instantiable, Sendable {
		    public init(credential: Credential) { self.credential = credential }
		    @Received public let credential: Credential
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inbox: Instantiable, Sendable {
		    public init(noteBuilder: Instantiator<Note>, courier: any Courier) { self.noteBuilder = noteBuilder; self.courier = courier }
		    @Instantiated public let noteBuilder: Instantiator<Note>
		    @Instantiated public let courier: any Courier
		}
		"""]),
		ModuleFixture(name: "Session", packageName: "Post", swiftFileContent: ["""
		import Core
		import SafeDI

		public protocol Parcel: Sendable {}

		@Instantiable(fulfillingAdditionalTypes: [Courier.self])
		public final class CourierImpl: Instantiable, Courier, Sendable {
		    public init(parcel: any Parcel) { self.parcel = parcel }
		    @Instantiated public let parcel: any Parcel
		}

		@Instantiable(generateDependencyTree: true)
		public final class Office: Instantiable, Sendable {
		    public init(credential: SendableLazilyInstantiated<Credential>, inbox: Inbox) { self.credential = credential; self.inbox = inbox }
		    @Received public let credential: SendableLazilyInstantiated<Credential>
		    @Instantiated public let inbox: Inbox
		}
		"""], dependencies: ["Core"]),
		ModuleFixture(name: "Feature", packageName: "Post", swiftFileContent: ["""
		import Core
		import Session
		import SafeDI

		public protocol Stamp: Sendable {}

		@Instantiable
		public final class CredentialReader: Instantiable, Sendable {
		    public init(credential: SendableLazilyInstantiated<Credential>?) { self.credential = credential }
		    @Received(onlyIfAvailable: true) public let credential: SendableLazilyInstantiated<Credential>?
		}

		@Instantiable(fulfillingAdditionalTypes: [Stamp.self])
		public final class StampImpl: Instantiable, Stamp, Sendable {
		    public init(credential: Credential, credentialReader: CredentialReader) { self.credential = credential; self.credentialReader = credentialReader }
		    @Received public let credential: Credential
		    @Instantiated public let credentialReader: CredentialReader
		}

		@Instantiable
		public final class Clerk: Instantiable, Sendable {
		    public init(stamp: any Stamp) { self.stamp = stamp }
		    @Instantiated public let stamp: any Stamp
		}

		@Instantiable(fulfillingAdditionalTypes: [Parcel.self])
		public final class ParcelImpl: Instantiable, Parcel, Sendable {
		    public init(clerkBuilder: Instantiator<Clerk>) { self.clerkBuilder = clerkBuilder }
		    @Instantiated public let clerkBuilder: Instantiator<Clerk>
		}

		@Instantiable(generateDependencyTree: true)
		public final class Desk: Instantiable, Sendable {
		    public init(office: Office, clerkBuilder: Instantiator<Clerk>) { self.office = office; self.clerkBuilder = clerkBuilder }
		    @Instantiated public let office: Office
		    @Instantiated public let clerkBuilder: Instantiator<Clerk>
		}
		"""], dependencies: ["Core", "Session"]),
		ModuleFixture(name: "App", packageName: "Post", swiftFileContent: ["""
		import Core
		import Feature
		import SafeDI

		@Instantiable(isRoot: true)
		public final class Root: Instantiable, Sendable {
		    public init(credential: SendableLazilyInstantiated<Credential>, desk: Desk) { self.credential = credential; self.desk = desk }
		    @Instantiated let credential: SendableLazilyInstantiated<Credential>
		    @Instantiated let desk: Desk
		}
		"""], dependencies: ["Core", "Session", "Feature"]),
	]

	/// `Vault`, a seam of `Core` that reads `credential` inside a `SendableInstantiator`'s builder.
	private static let vaultDeclarations = """
	@Instantiable(generateDependencyTree: true)
	public final class Vault: Instantiable, Sendable {
	    public init(noteBuilder: SendableInstantiator<Note>) { self.noteBuilder = noteBuilder }
	    @Instantiated public let noteBuilder: SendableInstantiator<Note>
	}
	"""

	/// `Safe`, a seam of `Core` whose `seal` place `Locker` builds inside a `SendableInstantiator`'s builder.
	private static let safeDeclarations = """
	public protocol Seal: Sendable {}

	@Instantiable
	public final class Locker: Instantiable, Sendable {
	    public init(seal: any Seal) { self.seal = seal }
	    @Instantiated public let seal: any Seal
	}

	@Instantiable(generateDependencyTree: true)
	public final class Safe: Instantiable, Sendable {
	    public init(lockerBuilder: SendableInstantiator<Locker>) { self.lockerBuilder = lockerBuilder }
	    @Instantiated public let lockerBuilder: SendableInstantiator<Locker>
	}
	"""

	/// `Alpha`, of `Feature`, which receives `credential` and builds `Beta` in a `SendableInstantiator`; `Beta` declares
	/// `credential` and builds `Alpha` again through `alphaBuilder`, closing a lazy cycle. `Beta` is not `Sendable`, since
	/// the `Instantiator` it holds is not.
	private static let sendableCycleDeclarations = """
	@Instantiable
	public final class Alpha: Instantiable, Sendable {
	    public init(credential: Credential, betaBuilder: SendableInstantiator<Beta>) { self.credential = credential; self.betaBuilder = betaBuilder }
	    @Received public let credential: Credential
	    @Instantiated public let betaBuilder: SendableInstantiator<Beta>
	}

	@Instantiable
	public final class Beta: Instantiable {
	    public init(credential: Credential, alphaBuilder: Instantiator<Alpha>) { self.credential = credential; self.alphaBuilder = alphaBuilder }
	    @Instantiated public let credential: Credential
	    @Instantiated public let alphaBuilder: Instantiator<Alpha>
	}
	"""

	/// `Stamp`, of `Feature`, which receives `credential` through an alias of it, `token`.
	private static let aliasReaderDeclaration = """
	@Instantiable
	public final class Stamp: Instantiable, Sendable {
	    public init(token: Credential) { self.token = token }
	    @Received(fulfilledByDependencyNamed: "credential", ofType: Credential.self) public let token: Credential
	}
	"""

	/// `SealImpl`, of `Feature`, which fills `Safe`'s `seal` place and receives `credential`.
	private static let sealImplDeclaration = """
	@Instantiable(fulfillingAdditionalTypes: [Seal.self])
	public final class SealImpl: Instantiable, Seal, Sendable {
	    public init(credential: Credential) { self.credential = credential }
	    @Received public let credential: Credential
	}
	"""

	/// `Desk`, a seam of `Feature`, calls `Office`, which receives `credential` as a `SendableLazilyInstantiated` and calls
	/// `Inbox`, whose `Note` defers `credential` by value; `Office` fills `Inbox`'s `courier` with `CourierImpl`, whose
	/// `parcel` it passes up to `Desk`, which fills it with `ParcelImpl`. `ParcelImpl` builds `LazyReader`, which reads
	/// `credential` as an optional `LazilyInstantiated`, and `parcelBuilds`, of `coreDeclarations`, which `Core` declares
	/// too, beside `featureDeclarations` of `Feature`.
	private static func modules(besideParcelReader coreDeclarations: String, _ featureDeclarations: String = "", parcelBuilds: String) -> [ModuleFixture] {
		let parcelLabel = parcelBuilds.prefix { $0 != ":" }
		return [
			ModuleFixture(name: "Core", packageName: "Post", swiftFileContent: ["""
			import SafeDI

			public protocol Courier: Sendable {}

			@Instantiable
			public final class Credential: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable
			public final class Note: Instantiable, Sendable {
			    public init(credential: Credential) { self.credential = credential }
			    @Received public let credential: Credential
			}

			@Instantiable(generateDependencyTree: true)
			public final class Inbox: Instantiable, Sendable {
			    public init(noteBuilder: Instantiator<Note>, courier: any Courier) { self.noteBuilder = noteBuilder; self.courier = courier }
			    @Instantiated public let noteBuilder: Instantiator<Note>
			    @Instantiated public let courier: any Courier
			}

			\(coreDeclarations)
			"""]),
			ModuleFixture(name: "Session", packageName: "Post", swiftFileContent: ["""
			import Core
			import SafeDI

			public protocol Parcel: Sendable {}

			@Instantiable(fulfillingAdditionalTypes: [Courier.self])
			public final class CourierImpl: Instantiable, Courier, Sendable {
			    public init(parcel: any Parcel) { self.parcel = parcel }
			    @Instantiated public let parcel: any Parcel
			}

			@Instantiable(generateDependencyTree: true)
			public final class Office: Instantiable, Sendable {
			    public init(credential: SendableLazilyInstantiated<Credential>, inbox: Inbox) { self.credential = credential; self.inbox = inbox }
			    @Received public let credential: SendableLazilyInstantiated<Credential>
			    @Instantiated public let inbox: Inbox
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Feature", packageName: "Post", swiftFileContent: ["""
			import Core
			import Session
			import SafeDI

			@Instantiable
			public final class LazyReader: Instantiable, Sendable {
			    public init(credential: LazilyInstantiated<Credential>?) { self.credential = credential }
			    @Received(onlyIfAvailable: true) public let credential: LazilyInstantiated<Credential>?
			}

			\(featureDeclarations)

			@Instantiable(fulfillingAdditionalTypes: [Parcel.self])
			public final class ParcelImpl: Instantiable, Parcel, Sendable {
			    public init(lazyReader: LazyReader, \(parcelBuilds)) { self.lazyReader = lazyReader; self.\(parcelLabel) = \(parcelLabel) }
			    @Instantiated public let lazyReader: LazyReader
			    @Instantiated public let \(parcelBuilds)
			}

			@Instantiable(generateDependencyTree: true)
			public final class Desk: Instantiable, Sendable {
			    public init(office: Office) { self.office = office }
			    @Instantiated public let office: Office
			}
			"""], dependencies: ["Core", "Session"]),
			ModuleFixture(name: "App", packageName: "Post", swiftFileContent: ["""
			import Core
			import Feature
			import SafeDI

			@Instantiable(isRoot: true)
			public final class Root: Instantiable, Sendable {
			    public init(credential: SendableLazilyInstantiated<Credential>, desk: Desk) { self.credential = credential; self.desk = desk }
			    @Instantiated let credential: SendableLazilyInstantiated<Credential>
			    @Instantiated let desk: Desk
			}
			"""], dependencies: ["Core", "Session", "Feature"]),
		]
	}

	/// `Console`, a seam of `Panel`, builds `Gauge`, which receives `unit`, beneath `Dial`, which declares `unit`, and
	/// beneath `Knob`, which does not and receives `label`.
	private static let twoParentsModules = [
		ModuleFixture(name: "Panel", packageName: "Desk", swiftFileContent: [
			"""
			@Instantiable
			public final class Unit: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Label: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Gauge: Instantiable {
			    public init(unit: Unit) { self.unit = unit }
			    @Received let unit: Unit
			}
			""",
			"""
			@Instantiable
			public final class Dial: Instantiable {
			    public init(unit: Unit, gauge: Gauge) { self.unit = unit; self.gauge = gauge }
			    @Instantiated let unit: Unit
			    @Instantiated let gauge: Gauge
			}
			""",
			"""
			@Instantiable
			public final class Knob: Instantiable {
			    public init(label: Label, gauge: Gauge) { self.label = label; self.gauge = gauge }
			    @Received let label: Label
			    @Instantiated let gauge: Gauge
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Console: Instantiable {
			    public init(dial: Dial, knob: Knob) { self.dial = dial; self.knob = knob }
			    @Instantiated let dial: Dial
			    @Instantiated let knob: Knob
			}
			""",
		]),
		ModuleFixture(name: "App", packageName: "Desk", swiftFileContent: [
			"""
			import Panel

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(unit: Unit, label: Label, console: Console) { self.unit = unit; self.label = label; self.console = console }
			    @Instantiated let unit: Unit
			    @Instantiated let label: Label
			    @Instantiated let console: Console
			}
			""",
		], dependencies: ["Panel"]),
	]

	/// `Console`, a seam of `Panel`, builds `Meter`, whose alias `reading` is fulfilled by `unit`, and `Lamp`, whose alias
	/// `shine` is fulfilled by `glow`, which `Lamp` instantiates.
	private static let aliasModules = [
		ModuleFixture(name: "Panel", packageName: "Desk", swiftFileContent: [
			"""
			@Instantiable
			public final class Unit: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Glow: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Meter: Instantiable {
			    public init(reading: Unit) { self.reading = reading }
			    @Received(fulfilledByDependencyNamed: "unit", ofType: Unit.self) let reading: Unit
			}
			""",
			"""
			@Instantiable
			public final class Lamp: Instantiable {
			    public init(glow: Glow, shine: Glow) { self.glow = glow; self.shine = shine }
			    @Instantiated let glow: Glow
			    @Received(fulfilledByDependencyNamed: "glow", ofType: Glow.self) let shine: Glow
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Console: Instantiable {
			    public init(meter: Meter, lamp: Lamp) { self.meter = meter; self.lamp = lamp }
			    @Instantiated let meter: Meter
			    @Instantiated let lamp: Lamp
			}
			""",
		]),
		ModuleFixture(name: "App", packageName: "Desk", swiftFileContent: [
			"""
			import Panel

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(unit: Unit, console: Console) { self.unit = unit; self.console = console }
			    @Instantiated let unit: Unit
			    @Instantiated let console: Console
			}
			""",
		], dependencies: ["Panel"]),
	]

	/// `Console`, a seam of `Panel`, builds `Page`, which receives `unit` and builds itself again through `nextBuilder`.
	private static let cycleModules = [
		ModuleFixture(name: "Panel", packageName: "Desk", swiftFileContent: [
			"""
			@Instantiable
			public final class Unit: Instantiable {
			    public init() {}
			}
			""",
			"""
			import SafeDI

			@Instantiable
			public final class Page: Instantiable {
			    public init(unit: Unit, nextBuilder: Instantiator<Page>) { self.unit = unit; self.nextBuilder = nextBuilder }
			    @Received let unit: Unit
			    @Instantiated let nextBuilder: Instantiator<Page>
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Console: Instantiable {
			    public init(page: Page) { self.page = page }
			    @Instantiated let page: Page
			}
			""",
		]),
		ModuleFixture(name: "App", packageName: "Desk", swiftFileContent: [
			"""
			import Panel

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(unit: Unit, console: Console) { self.unit = unit; self.console = console }
			    @Instantiated let unit: Unit
			    @Instantiated let console: Console
			}
			""",
		], dependencies: ["Panel"]),
	]

	/// `Service`, a seam of `Base`, builds `Badge`, which receives `theme`, of a `package` type, only if available, so its
	/// `public` tier omits it; `Shell`, a seam of `Mid` in another package, calls that tier.
	private static let noTierModules = [
		ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
			"""
			package final class Theme {}
			""",
			"""
			@Instantiable
			public struct Badge: Instantiable {
			    package init(theme: Theme?) { self.theme = theme }
			    @Received(onlyIfAvailable: true) let theme: Theme?
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Service: Instantiable {
			    public init(badge: Badge) { self.badge = badge }
			    @Instantiated let badge: Badge
			}
			""",
		]),
		ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
			"""
			import Base

			@Instantiable(generateDependencyTree: true)
			public struct Shell: Instantiable {
			    public init(service: Service) { self.service = service }
			    @Instantiated let service: Service
			}
			""",
		], dependencies: ["Base"]),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"""
			import Base
			import Mid

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(shell: Shell) { self.shell = shell }
			    @Instantiated let shell: Shell
			}
			""",
		], dependencies: ["Base", "Mid"]),
	]

	/// `Drawer`, a seam of `Supplies`, takes a builder for `pen`; `Desk`, a seam of `Office`, calls `Drawer` and fills the
	/// place with `PenImpl`, which requires `clock`, a value no type of `Desk`'s tree declares.
	/// `Terminal`, a seam of `Feature`, builds `Ledger`, whose `courier` is a place, inside `Booth`, which it builds first
	/// and which binds `ticket: LazilyInstantiated<Ticket>`, and beside it, where nothing binds `ticket`. `Kiosk`, a seam of
	/// `App` that calls `Terminal`, and `DefaultCourier`, the fill of the place, each receive `ticket` as `ticketReceive`
	/// declares it.
	private static func ticketRouteModules(ticketReceive: String) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Courier {}",
				seamFixtureType(named: "Ticket", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Ledger", declarations: ["@Instantiated let courier: any Courier"]),
				seamFixtureType(named: "Booth", declarations: ["@Instantiated let ticket: LazilyInstantiated<Ticket>", "@Instantiated let ledger: Ledger"]),
				seamFixtureType(named: "Terminal", isSeam: true, declarations: ["@Instantiated let booth: Booth", "@Instantiated let ledger: Ledger"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultCourier", fulfilling: "Courier", declarations: [ticketReceive]),
				seamFixtureType(named: "Kiosk", isSeam: true, declarations: [ticketReceive, "@Instantiated let terminal: Terminal"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let ticket: Ticket", "@Instantiated let kiosk: Kiosk"]),
			],
		)
	}

	private static let fillRequiringCallersValueModules = [
		ModuleFixture(name: "Supplies", packageName: "Stationery", swiftFileContent: ["""
		import SafeDI

		public protocol Pen {}

		@Instantiable
		public final class Clock: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true)
		public final class Drawer: Instantiable {
		    public init(pen: any Pen) { self.pen = pen }
		    @Instantiated public let pen: any Pen
		}
		"""]),
		ModuleFixture(name: "Office", packageName: "Stationery", swiftFileContent: ["""
		import Supplies
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Pen.self])
		public final class PenImpl: Instantiable, Pen {
		    public init(clock: Clock) { self.clock = clock }
		    @Received public let clock: Clock
		}

		@Instantiable(generateDependencyTree: true)
		public final class Desk: Instantiable {
		    public init(drawer: Drawer) { self.drawer = drawer }
		    @Instantiated public let drawer: Drawer
		}
		"""], dependencies: ["Supplies"]),
	]
}
