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
import Testing
@testable import SafeDIToolTestSupport

/// The base corpus's value oracle: the mirror model, its cross-check against a generated mock, and the oracle's
/// verdict on a generated mock edited to build a wrong value. See "Graph fuzzer" in CLAUDE.md.
struct SafeDIToolGraphFuzzerValueOracleTests {
	// MARK: Mirrors

	@Test
	func mirror_declaresPromotedDependencyOnce_whenTwoTypesOfTheMockedTypesTreeReceiveIt() throws {
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.sharedStoreFixture) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(detail: S1_Detail, store: S1_Store) {
				self.detail = detail
				self.store = store
				differentialMirrorValue = S1_Screen(detail: detail)
			}

			@Instantiated let detail: S1_Detail
			@Instantiated let store: S1_Store
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	@Test
	func mirror_declaresRequiredDependencyBesideItsOnlyIfAvailableAlias_whenOneTypeRequiresItAndAnotherAliasesIt() throws {
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let editor: S1_Editor", "@Instantiated let preview: S1_Preview"]),
			Self.type("S1_Editor", properties: ["@Received let session: S1_Session"]),
			Self.type("S1_Preview", properties: ["@Received(fulfilledByDependencyNamed: \"session\", ofType: S1_Session.self, onlyIfAvailable: true) let sessionAlias: S1_Session?"]),
			Self.type("S1_Session", properties: []),
		])) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(editor: S1_Editor, preview: S1_Preview, session: S1_Session) {
				self.editor = editor
				self.preview = preview
				self.session = session
				differentialMirrorValue = S1_Screen(editor: editor, preview: preview)
			}

			@Instantiated let editor: S1_Editor
			@Instantiated let preview: S1_Preview
			@Instantiated let session: S1_Session
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	@Test
	func mirror_declaresOneWrapper_whenMockedTypesTreeReceivesDependencyLazilyAndByValue() throws {
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let list: S1_List", "@Instantiated let badge: S1_Badge"]),
			Self.type("S1_List", properties: ["@Received let cache: LazilyInstantiated<S1_Cache>"]),
			Self.type("S1_Badge", properties: ["@Received let cache: S1_Cache"]),
			Self.type("S1_Cache", properties: []),
		])) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(list: S1_List, badge: S1_Badge, cache: LazilyInstantiated<S1_Cache>) {
				self.list = list
				self.badge = badge
				self.cache = cache
				differentialMirrorValue = S1_Screen(list: list, badge: badge)
			}

			@Instantiated let list: S1_List
			@Instantiated let badge: S1_Badge
			@Instantiated let cache: LazilyInstantiated<S1_Cache>
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	@Test
	func mirror_declaresMockedTypesOwnPropertyAsWrapperAndPassesItsInstance_whenPromotedDependencyReceivesItLazily() throws {
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let cache: S1_Cache", "@Received let list: S1_List"]),
			Self.type("S1_List", properties: ["@Received let cache: LazilyInstantiated<S1_Cache>"]),
			Self.type("S1_Cache", properties: []),
		])) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(cache: LazilyInstantiated<S1_Cache>, list: S1_List) {
				self.cache = cache
				self.list = list
				differentialMirrorValue = S1_Screen(cache: cache.instance, list: list)
			}

			@Instantiated let cache: LazilyInstantiated<S1_Cache>
			@Instantiated let list: S1_List
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	@Test
	func mirror_declaresPromotedSiblingsInTheOrderTheTreeFirstReceivesThem_whenTheyReceiveEachOtherOnlyIfAvailable() throws {
		// The mocked type receives `t9` before `t8`, so the mock builds `t9`'s sibling first, whose own receive of `t8`
		// sorts after it by label: the order is where the tree first receives each, not label order.
		#expect(try Self.mirrorSource(of: "S1_T7", in: Self.fixture([
			Self.type("S1_T7", arguments: "generateMock: true", properties: ["@Received let t9: S1_T9", "@Received let t8: S1_T8"]),
			Self.type("S1_T8", properties: ["@Received(onlyIfAvailable: true) let t9: S1_T9?"]),
			Self.type("S1_T9", properties: ["@Received(onlyIfAvailable: true) let t8: S1_T8?"]),
		])) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(t9: S1_T9, t8: S1_T8) {
				self.t9 = t9
				self.t8 = t8
				differentialMirrorValue = S1_T7(t9: t9, t8: t8)
			}

			@Instantiated let t9: S1_T9
			@Instantiated let t8: S1_T8
			let differentialMirrorValue: S1_T7
		}

		""")
	}

	@Test
	func mirror_passesNilForOnlyIfAvailableAlias_whenNothingInTheTreeRequiresItsFulfillingProperty() throws {
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: [
				"@Instantiated let detail: S1_Detail",
				"@Received(fulfilledByDependencyNamed: \"session\", ofType: S1_Session.self, onlyIfAvailable: true) let sessionAlias: S1_Session?",
			]),
			Self.type("S1_Detail", properties: []),
			Self.type("S1_Session", properties: []),
		])) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(detail: S1_Detail) {
				self.detail = detail
				differentialMirrorValue = S1_Screen(detail: detail, sessionAlias: nil)
			}

			@Instantiated let detail: S1_Detail
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	@Test
	func mirror_callsInstantiateWithoutDefaultValuedParameters_whenMockedTypeIsAnExtension() throws {
		#expect(try Self.mirrorSource(of: "S1_Clock", in: Self.fixture([
			"""
			@Instantiable(generateMock: true)
			extension S1_Clock: Instantiable {
				public static func instantiate(store: S1_Store, title: String = "default") -> S1_Clock {
					S1_Clock()
				}
			}

			public final class S1_Clock {
				public init() {}
			}

			""",
			Self.type("S1_Store", properties: []),
		])) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(store: S1_Store) {
				self.store = store
				differentialMirrorValue = S1_Clock.instantiate(store: store)
			}

			@Instantiated let store: S1_Store
			let differentialMirrorValue: S1_Clock
		}

		""")
	}

	@Test
	func mirror_writesAliasOfOptionalFormWithNonOptionalType_whenMockPromotesTheOptionalFormAndBuildsItNonOptional() throws {
		// The mock promotes the received `value: S1_Value?` its alias requires and builds it non-optional, which the
		// alias reads. The mirror declares that property itself, and production reads a rename of its own property as a
		// rename of exactly that property, so the alias names `S1_Value`.
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.retypedAliasFixture) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(valueAlias: S1_Value?, value: S1_Value) {
				self.valueAlias = valueAlias
				self.value = value
				differentialMirrorValue = S1_Screen(valueAlias: valueAlias)
			}

			@Received(fulfilledByDependencyNamed: "value", ofType: S1_Value.self) let valueAlias: S1_Value?
			@Instantiated let value: S1_Value
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	@Test
	func mirror_forwardsMocksRequiredParametersAndIsBuiltByARootOfItsOwn_whenMockTakesRequiredParameters() throws {
		// The mock takes the forwarded `session`, which the mirror forwards in turn, so that a root holding an
		// instantiator of the mirror builds it with the sample the mock is handed.
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.forwardingFixture, forwarding: [GraphFuzzerMirrorProperty(label: "session", type: "S1_Session")]) == """
		@Instantiable
		public final class S1_ZMirror0: Instantiable {
			public init(session: S1_Session, editor: S1_Editor) {
				self.session = session
				self.editor = editor
				differentialMirrorValue = S1_Screen(session: session, editor: editor)
			}

			@Forwarded let session: S1_Session
			@Instantiated let editor: S1_Editor
			let differentialMirrorValue: S1_Screen
		}

		@Instantiable(isRoot: true)
		public final class S1_ZMirror0Host: Instantiable {
			public init(mirrorBuilder: Instantiator<S1_ZMirror0>) {
				self.mirrorBuilder = mirrorBuilder
			}

			@Instantiated let mirrorBuilder: Instantiator<S1_ZMirror0>
		}

		""")
	}

	@Test
	func mirror_skipsMockTakingRequiredParameter_whenTheMockedTypeInstantiatesAnInstanceTheMockCannotBuild() {
		// The mock takes the unbuildable `token` its mocked type instantiates, which no forwarded declaration stands for.
		let fixture = Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let token: S1_Token"]),
			"public final class S1_Token {}\n",
		])

		#expect(Self.mirrorResult(of: "S1_Screen", in: fixture, forwarding: [GraphFuzzerMirrorProperty(label: "token", type: "S1_Token")]) == .failure(.skipped(.requiredParameter)))
	}

	@Test
	func mirror_skipsRequiredOptionalReceive_whenRequiredAliasInPromotedTreeNamesOptionalFormOfNonOptionalDeclaration() {
		// The mock binds `value: S1_Value`, which a required receive promotes, and hands it to the alias of the optional
		// form; production fulfills a required alias of `value: S1_Value?` with no non-optional declaration.
		let fixture = Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Received let value: S1_Value", "@Received let editor: S1_Editor"]),
			Self.type("S1_Editor", properties: ["@Received(fulfilledByDependencyNamed: \"value\", ofType: S1_Value?.self) let valueAlias: S1_Value?"]),
			Self.type("S1_Value", properties: []),
		])

		#expect(Self.mirrorResult(of: "S1_Screen", in: fixture) == .failure(.skipped(.requiredOptionalReceiveOfNonOptionalDeclaration)))
	}

	@Test
	func mirror_declaresNothingForOnlyIfAvailableReceive_whenPromotedTreeReceivesLabelTheMirrorDeclaresWithAnotherType() throws {
		// `S1_Editor`, which the mock promotes, receives `store: S1_Cache?` only if available beneath the mocked type's own
		// `store: S1_Store`: production passes it `nil`, as the mock's override of its own type does, so the pair is compared.
		#expect(try Self.mirrorSource(of: "S1_Screen", in: Self.labelOfAnotherTypeFixture) == """
		@Instantiable(isRoot: true)
		public final class S1_ZMirror0: Instantiable {
			public init(store: S1_Store, editor: S1_Editor) {
				self.store = store
				self.editor = editor
				differentialMirrorValue = S1_Screen(store: store, editor: editor)
			}

			@Instantiated let store: S1_Store
			@Instantiated let editor: S1_Editor
			let differentialMirrorValue: S1_Screen
		}

		""")
	}

	// MARK: Shapes

	@Test
	func shapes_omitOnlyIfAvailableReceiveLeftUnbuilt_whenMockedTypesOwnChildProvidesTheReceive() throws {
		// `S1_B` is handed the mocked type's own `a: S1_A`, which the mock builds: nothing is left to an override.
		#expect(try Self.mirror(of: "S1_T", in: Self.fixture([
			Self.type("S1_T", arguments: "generateMock: true", properties: ["@Instantiated let a: S1_A", "@Instantiated let b: S1_B"]),
			Self.type("S1_A", properties: []),
			Self.type("S1_B", properties: ["@Received(onlyIfAvailable: true) let a: S1_A?"]),
		])).shapes == [])
	}

	@Test
	func shapes_includeOnlyIfAvailableReceiveLeftUnbuilt_whenNothingInTreeProvidesTheReceive() throws {
		// Nothing in the mock's tree declares `c`, so the mock binds it to an override and `S1_B` gets `nil`.
		#expect(try Self.mirror(of: "S1_T", in: Self.fixture([
			Self.type("S1_T", arguments: "generateMock: true", properties: ["@Instantiated let b: S1_B"]),
			Self.type("S1_B", properties: ["@Received(onlyIfAvailable: true) let c: S1_C?"]),
			Self.type("S1_C", properties: []),
		])).shapes == [.onlyIfAvailableReceiveInMockedTypesTreeLeftUnbuilt])
	}

	@Test
	func shapes_omitOnlyIfAvailableReceiveLeftUnbuilt_whenScopeBetweenMockedTypeAndReceiverProvidesTheReceive() throws {
		// `S1_D` is handed the `c: S1_C` that `S1_B`, between it and the mocked type, builds.
		#expect(try Self.mirror(of: "S1_T", in: Self.fixture([
			Self.type("S1_T", arguments: "generateMock: true", properties: ["@Instantiated let b: S1_B"]),
			Self.type("S1_B", properties: ["@Instantiated let c: S1_C", "@Instantiated let d: S1_D"]),
			Self.type("S1_C", properties: []),
			Self.type("S1_D", properties: ["@Received(onlyIfAvailable: true) let c: S1_C?"]),
		])).shapes == [])
	}

	// MARK: Cross-check

	@Test
	func disagreement_isNil_whenMockBuildsWhatTheModelBuilds() {
		let expectation = Self.expectation(of: "S1_Screen", in: Self.sharedStoreFixture)
		#expect(GraphFuzzerMockOverrides.disagreement(between: expectation, andMockFile: Self.sharedStoreMockFile(overrideFields: Self.sharedStoreOverrideFields), typeNamePrefix: "S1_") == nil)
	}

	@Test
	func disagreement_reportsBothMultisets_whenMockBuildsADependencyTwice() {
		let expectation = Self.expectation(of: "S1_Screen", in: Self.sharedStoreFixture)
		let mockFile = Self.sharedStoreMockFile(overrideFields: Self.sharedStoreOverrideFields + [
			"store_S1_Store: (() -> S1_Store)? = nil",
		])
		#expect(GraphFuzzerMockOverrides.disagreement(between: expectation, andMockFile: mockFile, typeNamePrefix: "S1_") == """
		`S1_Screen.mock()` builds ["S1_Detail", "S1_Store", "S1_Store"] beside `S1_Screen` and takes 0 onlyIfAvailable overrides; the mirror model builds ["S1_Detail", "S1_Store"] and expects 0.
		""")
	}

	@Test
	func disagreement_reportsOverrideCounts_whenMockTakesAnOverrideForADependencyItBuilds() {
		let expectation = Self.expectation(of: "S1_Screen", in: Self.sharedStoreFixture)
		let mockFile = Self.sharedStoreMockFile(overrideFields: Self.sharedStoreOverrideFields + ["store_S1_Store: S1_Store? = nil"])
		#expect(GraphFuzzerMockOverrides.disagreement(between: expectation, andMockFile: mockFile, typeNamePrefix: "S1_") == """
		`S1_Screen.mock()` builds ["S1_Detail", "S1_Store"] beside `S1_Screen` and takes 1 onlyIfAvailable overrides; the mirror model builds ["S1_Detail", "S1_Store"] and expects 0.
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func plan_mirrorsMockTakingRequiredParameter_whenTheHarnessHasASampleOfIt() async throws {
		// The forwarded `session` fulfills the promoted editor's `onlyIfAvailable` receive of it, so the mock takes no
		// override for it, and the model agrees; the mock and its mirror are each handed a sample session.
		let generatedFiles = try await Self.generatedFiles(of: GraphFuzzerOracle.toolOutcome(of: Self.forwardingFixture))
		let plan = GraphFuzzerValueOraclePlan(fixture: Self.forwardingFixture, generatedFiles: generatedFiles, storingFixture: Self.forwardingFixture)

		#expect(plan.modelFailures == [])
		#expect(plan.skips.isEmpty)
		#expect(plan.probePairs == [DifferentialValueProbePair(
			name: "S1_Screen.mock()",
			featureExpression: "S1_Screen.mock(session: differentialValueSample(S1_Session()))",
			knownRightExpression: "S1_ZMirror0Host().mirrorBuilder.instantiate(differentialValueSample(S1_Session())).differentialMirrorValue",
		)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func plan_skipsMockTakingRequiredParameter_whenTheHarnessHasNoSampleOfIt() async throws {
		// No type of the graph fulfills the forwarded existential.
		let fixture = Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Forwarded let session: any S1_SessionProtocol"]),
			"public protocol S1_SessionProtocol {}\n",
		])
		let generatedFiles = try await Self.generatedFiles(of: GraphFuzzerOracle.toolOutcome(of: fixture))
		let plan = GraphFuzzerValueOraclePlan(fixture: fixture, generatedFiles: generatedFiles, storingFixture: fixture)

		#expect(plan.modelFailures == [])
		#expect(plan.skips.map { "\($0.typeName): \($0.skip)" } == ["S1_Screen: requiredParameter"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func plan_registersSampleOfForwardedProperties_whenAnInstantiatedTypeForwardsValuesTheHarnessCanBuild() async throws {
		let generatedFiles = try await Self.generatedFiles(of: GraphFuzzerOracle.toolOutcome(of: Self.rootOfForwardingScreenFixture))
		let plan = GraphFuzzerValueOraclePlan(fixture: Self.rootOfForwardingScreenFixture, generatedFiles: generatedFiles, storingFixture: Self.rootOfForwardingScreenFixture)

		#expect(plan.forwardedPropertiesSamples == [DifferentialValueSample(type: "S1_Screen.ForwardedProperties", expression: "differentialValueSample(S1_Session())")])
	}

	// MARK: Sample values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_buildGraphTypeThroughItsInitializerWithUnmarkedSampleOfEachProperty_whenEveryPropertyHasOne() {
		let fixture = Self.fixture([
			Self.type("S1_Session", properties: [
				"@Instantiated let store: S1_Store",
				"@Received(onlyIfAvailable: true) let cache: S1_Cache?",
				"@Instantiated let editorBuilder: Instantiator<S1_Editor>",
				"@Instantiated let lazyStore: LazilyInstantiated<S1_Store>",
				"@Forwarded let count: Int",
			]),
			Self.type("S1_Store", properties: []),
			Self.type("S1_Cache", properties: []),
			Self.type("S1_Editor", properties: []),
		])

		#expect(Self.samples(of: fixture).expression(ofType: "S1_Session") == "differentialValueSample(S1_Session(store: S1_Store(), cache: nil, editorBuilder: Instantiator { differentialValueUnreachableSample() }, lazyStore: LazilyInstantiated { differentialValueUnreachableSample() }, count: 0))")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_holdATupleOfMarkedValuesInLabelOrder_whenATypeForwardsSeveralValues() {
		let fixture = Self.fixture([
			Self.type("S1_Screen", properties: ["@Forwarded let session: S1_Session", "@Forwarded let count: Int", "@Forwarded let format: @Sendable (Int) -> String"]),
			Self.type("S1_Session", properties: []),
		])

		#expect(Self.samples(of: fixture).forwardedPropertiesSamples == [
			DifferentialValueSample(type: "S1_Screen.ForwardedProperties", expression: "(count: 0, format: { _ in \"\" }, session: differentialValueSample(S1_Session()))"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_buildForwardedLazilyInstantiatedWhoseInstanceIsAMarkedSample_whenGeneratedCodeCanReadIt() {
		let fixture = Self.fixture([Self.type("S1_Store", properties: [])])

		#expect(Self.samples(of: fixture).expression(ofType: "SendableLazilyInstantiated<S1_Store>") == "differentialValueSample(SendableLazilyInstantiated { differentialValueSample(S1_Store()) })")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_buildTheFulfillingType_whenAGraphTypeFulfillsTheSampledProtocol() {
		let fixture = Self.fixture([Self.type("S1_Store", arguments: "fulfillingAdditionalTypes: [S1_StoreProtocol.self]", properties: [])])

		#expect(Self.samples(of: fixture).expression(ofType: "S1_StoreProtocol") == "differentialValueSample(S1_Store())")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_eraseASampleOfTheErasedType_whenTheTypeIsAnErasingType() {
		let fixture = Self.fixture([
			Self.type("S1_Store", properties: []),
			"public final class S1_AnyStore {\n\tpublic init(_ value: S1_Store) {\n\t\tself.value = value\n\t}\n\n\tpublic let value: S1_Store\n}\n",
		])

		#expect(Self.samples(of: fixture).expression(ofType: "S1_AnyStore") == "differentialValueSample(S1_AnyStore(S1_Store()))")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_holdNothing_whenATypeTakesItselfByValueThroughItsProperties() {
		let fixture = Self.fixture([
			Self.type("S1_Session", properties: ["@Received let store: S1_Store"]),
			Self.type("S1_Store", properties: ["@Received let session: S1_Session"]),
		])

		#expect(Self.samples(of: fixture).expression(ofType: "S1_Session") == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_holdNothing_whenTheTypesInitializerIsPackage() {
		let fixture = Self.fixture([Self.type("S1_Store", properties: []).replacingOccurrences(of: "public init()", with: "package init()")])

		#expect(Self.samples(of: fixture).expression(ofType: "S1_Store") == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sampleValues_holdAValueOfEveryForwardedTupleElementButTheExistential_whenTheGraphDeclaresItsHelperTypes() {
		let fixture = Self.fixture(GraphFuzzerForwardedTupleElement.allCases.compactMap { $0.helperDeclaration(prefix: "S1_", areSendable: true).map { $0 + "\n" } })
		let samples = Self.samples(of: fixture)

		let expressions = GraphFuzzerForwardedTupleElement.allCases.flatMap { element in
			[false, true].map { isSendable in samples.expression(ofType: element.spelledType(prefix: "S1_", isSendable: isSendable)) ?? "none" }
		}

		#expect(expressions == [
			"nil", "nil",
			"S1_ForwardedTupleSpace.Configuration()", "S1_ForwardedTupleSpace.Configuration()",
			"[]", "[]",
			"S1_ForwardedTupleBox<Int>()", "S1_ForwardedTupleBox<Int>()",
			"[]", "[]",
			"[:]", "[:]",
			"{ }", "{ }",
			"{ _ in \"\" }", "{ _ in \"\" }",
			"nil", "nil",
			"none", "none",
			"nil", "nil",
			"(x: nil, y: \"\")", "(x: nil, y: \"\")",
			"{ }", "{ }",
			"{ _ in }", "{ _ in }",
			"{ }", "{ }",
			"{ }", "{ }",
			"{ }", "{ }",
			"{ }", "{ }",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func plan_reportsDisagreementBeforeSkipping_whenMockTakingRequiredParameterBuildsWhatTheModelDoesNot() async throws {
		var generatedFiles = try await Self.generatedFiles(of: GraphFuzzerOracle.toolOutcome(of: Self.forwardingFixture))
		let mockFile = try #require(generatedFiles["S1_Screen+SafeDIMock.swift"])
		let fieldsStart = "    struct SafeDIOverrides {\n        init(\n"
		try #require(mockFile.contains(fieldsStart), "\(mockFile)")
		generatedFiles["S1_Screen+SafeDIMock.swift"] = mockFile.replacingOccurrences(of: fieldsStart, with: fieldsStart + "            session_S1_Session: (() -> S1_Session)? = nil,\n")
		let plan = GraphFuzzerValueOraclePlan(fixture: Self.forwardingFixture, generatedFiles: generatedFiles, storingFixture: Self.forwardingFixture)

		#expect(plan.modelFailures == [
			"`S1_Screen.mock()` builds [\"S1_Editor\", \"S1_Session\"] beside `S1_Screen` and takes 0 onlyIfAvailable overrides; the mirror model builds [\"S1_Editor\"] and expects 0.",
		])
		#expect(plan.skips.isEmpty)
	}

	// MARK: Known issues

	@Test
	func isolatedValueOracleSeeds_listSeedsOfShapesWhoseValueOracleFixtureDoesNotCompile() {
		let doesNotCompile = GraphFuzzerKnownIssue(reason: "A root mock reproduces a mock shape", signatures: [.valueOracleFixtureDoesNotCompile(containing: "cannot convert value of type")], seeds: [3, 8])
		let rejected = GraphFuzzerKnownIssue(reason: "A fixture the tool rejects", signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain")], seeds: [5])
		let renamed = GraphFuzzerKnownIssue(reason: "An order", signatures: [.renamedGraphDiffers(.mockCode)], seeds: [7])

		#expect(SafeDIToolGraphFuzzerTests.isolatedValueOracleSeeds(of: [doesNotCompile, rejected, renamed]) == [3, 8])
	}

	@Test
	func seamKnownIssues_inheritNoBaseCorpusValueOracleShape() {
		// A shape only the base corpus's value oracle shows is not inherited; one that also documents another failure is,
		// and the seam corpus inherits none of its seeds below its size (`seamCorpusSeedsOfOtherShapes`).
		let doesNotCompile = GraphFuzzerKnownIssue(reason: "A root mock reproduces a mock shape", signatures: [.valueOracleFixtureDoesNotCompile(containing: "cannot convert value of type")], seeds: [3, 8])
		let rejected = GraphFuzzerKnownIssue(reason: "A fixture the tool rejects", signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain")], seeds: [5])
		let rejectedAndRenamed = GraphFuzzerKnownIssue(reason: "A fixture the tool rejects, in a graph whose order changes", signatures: [.valueOracleFixtureRejected(containing: "is hidden in chain"), .renamedGraphDiffers(.mockCode)], seeds: [6])
		let renamed = GraphFuzzerKnownIssue(reason: "An order", signatures: [.renamedGraphDiffers(.mockCode)], seeds: [7])

		#expect([doesNotCompile, rejected, rejectedAndRenamed, renamed].map(\.isBaseCorpusValueOracleShape) == [true, true, false, false])
		#expect(SafeDIToolGraphFuzzerTests.seamKnownIssues.allSatisfy { knownIssue in
			knownIssue.signatures.allSatisfy { signature in
				switch signature {
				case .mockBuildsOtherValuesThanProduction, .valueOracleFixtureDoesNotCompile, .valueOracleFixtureRejected:
					false
				case .compilerError, .compilerWarning, .compilerCrashInGeneratedMock, .renamedGraphDiffers, .integrationsDiffer, .macroRejectsFixture, .seamRejectsGraphInlineAccepts, .seamAcceptsGraphInlineRejects, .integrationsDisagree, .seamPassesNilWhereInlinePassesValue, .seamBuildsOtherValuesThanInline, .valueComparatorCouldNotDescribeGraph, .publicMockRejectsGraphKnownRightAccepts, .publicMockBuildsOtherValuesThanKnownRight, .holeNamesChangeWithSecondPlace:
					true
				}
			}
		})
	}

	@Test
	func finding_isFailure_whenKnownValueDifferenceIsBesideOneNoValueSignatureMatches() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "A root's mock passes nil for an alias", signatures: [.mockBuildsOtherValuesThanProduction(containing: "feature:     t0BuilderAlias: nil")], seeds: [4])
		let documented = "probe `S4_Root0.mock()` at <1> S4_Root0 > t1 > t0BuilderAlias:\n  feature:     t0BuilderAlias: nil\n  known right: t0BuilderAlias: <4> Instantiator<S4_T0>"
		let undocumented = "probe `S4_T2.mock()` at <1> S4_T2 > t3:\n  feature:     t3: nil\n  known right: t3: <2> S4_T3"
		func failure(_ differences: [String]) -> GraphFuzzerFailure {
			GraphFuzzerFailure(seed: 4, kind: .mockBuildsOtherValuesThanProduction, details: differences.joined(separator: "\n"), valueDifferences: differences)
		}

		#expect(GraphFuzzerFinding(failure: failure([documented]), knownIssue: knownIssue) == .knownIssue(knownIssue, failure([documented])))
		#expect(GraphFuzzerFinding(failure: failure([documented, undocumented]), knownIssue: knownIssue) == .failure(failure([documented, undocumented])))
	}

	// MARK: The value-oracle fixture

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracleFixtureFailure_isNil_whenRootsMockAddsConfigurationToMockedTypesFile() async throws {
		// The root's mock builds `S1_Screen`, whose file then also declares the configuration no drawn mock needed.
		let runs = try await Self.valueOracleToolRuns(of: Self.rootOfMockedScreenFixture)
		let drawnMock = try Self.generatedFile("S1_Screen+SafeDIMock.swift", of: runs.firstOutcome)
		let valueOracleMock = try Self.generatedFile("S1_Screen+SafeDIMock.swift", of: #require(runs.valueOracle?.outcome))

		#expect(valueOracleMock != drawnMock)
		#expect(GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks(valueOracleMock) == GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks(drawnMock))
		#expect(runs.valueOracleFixtureFailure == nil)
		// The file R6's allowance passes is counted, as the corpus pins it.
		let valueOracle = try #require(runs.valueOracle)
		#expect(valueOracle.drawnMockFileNamesMatchingOnlyAfterNormalization == ["S1_Screen+SafeDIMock.swift"])
		var counts = GraphFuzzerValueOracleCounts()
		counts.add(valueOracle, isCompared: true)
		#expect(counts.drawnMocksMatchingOnlyAfterNormalizationCount == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracleFixtureFailure_isNil_whenMirrorWritesAliasOfOptionalFormWithNonOptionalType() async throws {
		// Production accepts the retyped alias, and the model agrees with the mock about what it builds.
		let runs = try await Self.valueOracleToolRuns(of: Self.retypedAliasFixture)

		#expect(runs.valueOracle?.plan.mirrors.map(\.mockedTypeName) == ["S1_Screen"])
		#expect(runs.valueOracleFixtureFailure == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracleFixtureFailure_isNil_whenPromotedTreeReceivesOnlyIfAvailableLabelTheMirrorDeclaresWithAnotherType() async throws {
		// Production accepts the mirror, passing the receive `nil`, so the mock is compared rather than skipped.
		let runs = try await Self.valueOracleToolRuns(of: Self.labelOfAnotherTypeFixture)

		#expect(runs.valueOracle?.plan.mirrors.map(\.mockedTypeName) == ["S1_Screen"])
		#expect(runs.valueOracle?.plan.skips.isEmpty == true)
		#expect(runs.valueOracleFixtureFailure == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracleFixtureFailure_reportsChangedDrawnMock_whenValueOracleRunGeneratesAnotherMockBody() async throws {
		let runs = try await Self.valueOracleToolRuns(
			of: Self.rootOfMockedScreenFixture,
			editingValueOracleFile: "S1_Screen+SafeDIMock.swift",
			replacing: "return S1_Screen(detail: detail)",
			with: "return S1_Screen(detail: S1_Detail())",
		)

		let failure = try #require(runs.valueOracleFixtureFailure)
		#expect(failure.kind == .valueOracleFixtureChangesDrawnMocks)
		#expect(failure.details.prefix { $0 != "\n" } == "S1_Screen+SafeDIMock.swift as the corpus run generates it:")
		#expect(runs.valueOracle?.drawnMockFileNamesChanged == ["S1_Screen+SafeDIMock.swift"])
		#expect(runs.valueOracle?.drawnMockFileNamesMatchingOnlyAfterNormalization == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracleFixtureFailure_reportsRootMockTakesParameter_whenRootsMockTakesParameterBesideItsOverrides() async throws {
		let runs = try await Self.valueOracleToolRuns(
			of: Self.rootOfMockedScreenFixture,
			editingValueOracleFile: "S1_Root+SafeDIMock.swift",
			replacing: "        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S1_Root {",
			with: "        detail: S1_Detail,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S1_Root {",
		)

		let failure = try #require(runs.valueOracleFixtureFailure)
		#expect(failure.kind == .rootMockTakesParameter)
		#expect(failure.details.prefix { $0 != "\n" } == "`S1_Root.mock` takes detail: S1_Detail,")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracleFixtureFailure_reportsTypeNameSortingAfterMirror_whenGraphDeclaresOne() async throws {
		// `S1_Zebra` sorts after `S1_ZMirror0`, so the mirror could change the order of the tool's alphabetical walks.
		let runs = try await Self.valueOracleToolRuns(of: Self.fixture(Self.rootOfMockedScreenFixture.swiftFileContent + [
			Self.type("S1_Zebra", arguments: "isRoot: true", properties: []),
		]))

		#expect(runs.valueOracle?.plan.mirrorNamesSortingBeforeTypeNames == ["S1_Zebra"])
		#expect(runs.valueOracleFixtureFailure?.kind == .valueOracleFixtureChangesDrawnMocks)
	}

	// MARK: Overrides

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func overrideProbes_passSentinelThroughConfigurationOfRootsChildAndBuilderOfMockedTypesChild_whenEachMockHasOneField() async throws {
		let runs = try await Self.valueOracleToolRuns(of: Self.rootOfMockedScreenFixture)

		#expect(try #require(runs.valueOracle).overrideProbes == [
			GraphFuzzerOverrideProbe(
				mockedTypeName: "S1_Root",
				label: "screen",
				builtTypeName: "S1_Screen",
				fieldKind: .configuration,
				pair: DifferentialValueProbePair(
					name: "S1_Root.mock(safeDIOverrides: .init(screen: sentinel))",
					featureExpression: "{ S1_ZOverrideSentinel.value = nil; let value = S1_Root.mock(safeDIOverrides: .init(screen: .init(S1_ZOverrideSentinel.recording(S1_Screen.init)))); return (value, S1_ZOverrideSentinel.value) }()",
					knownRightExpression: "{ let known = S1_Root(); return (known, known.screen as Any?) }()",
				),
			),
			GraphFuzzerOverrideProbe(
				mockedTypeName: "S1_Screen",
				label: "detail",
				builtTypeName: "S1_Detail",
				fieldKind: .builder,
				pair: DifferentialValueProbePair(
					name: "S1_Screen.mock(safeDIOverrides: .init(detail: sentinel))",
					featureExpression: "{ S1_ZOverrideSentinel.value = nil; let value = S1_Screen.mock(safeDIOverrides: .init(detail: S1_ZOverrideSentinel.recording(S1_Detail.init))); return (value, S1_ZOverrideSentinel.value) }()",
					knownRightExpression: "{ let known = S1_ZMirror0(); return (known.differentialMirrorValue, known.detail as Any?) }()",
				),
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func overrideProbes_passSentinelToBuilderOfPromotedDependencyOnly_whenMockedTypesOwnChildIsAnInstantiator() async throws {
		// The instantiator's field builds `S1_Detail` once per `instantiate()`, so no one instance takes the sentinel's place.
		let runs = try await Self.valueOracleToolRuns(of: Self.overriddenStoreFixture)

		#expect(try #require(runs.valueOracle).overrideProbes.map(\.pair) == [
			DifferentialValueProbePair(
				name: "S1_Screen.mock(safeDIOverrides: .init(store: sentinel))",
				featureExpression: "{ S1_ZOverrideSentinel.value = nil; let value = S1_Screen.mock(safeDIOverrides: .init(store: S1_ZOverrideSentinel.recording(S1_Store.init))); return (value, S1_ZOverrideSentinel.value) }()",
				knownRightExpression: "{ let known = S1_ZMirror0(); return (known.differentialMirrorValue, known.store as Any?) }()",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func overrideProbes_passMocksSamplesAndBuildMirrorThroughItsRoot_whenMockTakesRequiredParameters() async throws {
		// The mock takes the forwarded `session`, so the override's call hands it the sample its own pair hands it, and
		// the known-right side builds the forwarding mirror through its root with the same sample.
		let runs = try await Self.valueOracleToolRuns(of: Self.forwardingFixture)

		#expect(try #require(runs.valueOracle).overrideProbes.map(\.pair) == [
			DifferentialValueProbePair(
				name: "S1_Screen.mock(safeDIOverrides: .init(editor: sentinel))",
				featureExpression: "{ S1_ZOverrideSentinel.value = nil; let value = S1_Screen.mock(session: differentialValueSample(S1_Session()), safeDIOverrides: .init(editor: S1_ZOverrideSentinel.recording(S1_Editor.init))); return (value, S1_ZOverrideSentinel.value) }()",
				knownRightExpression: "{ let known = S1_ZMirror0Host().mirrorBuilder.instantiate(differentialValueSample(S1_Session())); return (known.differentialMirrorValue, known.editor as Any?) }()",
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func overrideProbes_passInstantiateEveryParameterButUnlabeledDefaultValuedOne_whenOverriddenTypeIsAnExtension() async throws {
		// The configuration's builder takes each labeled default-valued parameter, and no unlabeled one.
		let runs = try await Self.valueOracleToolRuns(of: Self.fixture([
			// Seed 1 takes the root's second field.
			Self.type("S1_Root", arguments: "isRoot: true", properties: ["@Instantiated let store: S1_Store", "@Instantiated let clock: S1_Clock"]),
			"""
			@Instantiable
			extension S1_Clock: Instantiable {
				public static func instantiate(store: S1_Store, title: String = "default", _ note: String = "") -> S1_Clock {
					S1_Clock()
				}
			}

			public final class S1_Clock {
				public init() {}
			}

			""",
			Self.type("S1_Store", properties: []),
		]))

		let probes = try #require(runs.valueOracle).overrideProbes
		#expect(probes.map(\.fieldKind) == [.configuration])
		#expect(probes.map(\.pair.featureExpression) == [
			"{ S1_ZOverrideSentinel.value = nil; let value = S1_Root.mock(safeDIOverrides: .init(clock: .init({ S1_ZOverrideSentinel.recorded(S1_Clock.instantiate(store: $0, title: $1)) }))); return (value, S1_ZOverrideSentinel.value) }()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func overrideProbes_omitField_whenItBuildsAProtocolOrAWrapper() async throws {
		// A fulfilled-by-type protocol's field returns the protocol, which the built type's initializer does not, and an
		// instantiator's builds an instance per call.
		let runs = try await Self.valueOracleToolRuns(of: Self.fixture([
			Self.type("S1_Root", arguments: "isRoot: true", properties: [
				"@Instantiated(fulfilledByType: \"S1_Service\") let service: S1_ServiceProtocol",
				"@Instantiated let storeBuilder: Instantiator<S1_Store>",
			]),
			"""
			@Instantiable(fulfillingAdditionalTypes: [S1_ServiceProtocol.self])
			public final class S1_Service: Instantiable, S1_ServiceProtocol {
				public init() {}
			}

			public protocol S1_ServiceProtocol: AnyObject {}

			""",
			Self.type("S1_Store", properties: []),
		]))

		#expect(try #require(runs.valueOracle).overrideProbes == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func overrideProbes_chooseOneFieldByTheSeedAndThePairsPosition_whenMocksHaveSeveralFields() async throws {
		// Seed 1: the first root's pair takes its second field, the second root's its third.
		let runs = try await Self.valueOracleToolRuns(of: Self.fixture([
			Self.type("S1_Root0", arguments: "isRoot: true", properties: ["@Instantiated let a: S1_A", "@Instantiated let b: S1_B", "@Instantiated let c: S1_C"]),
			Self.type("S1_Root1", arguments: "isRoot: true", properties: ["@Instantiated let a: S1_A", "@Instantiated let b: S1_B", "@Instantiated let c: S1_C"]),
			Self.type("S1_A", properties: []),
			Self.type("S1_B", properties: []),
			Self.type("S1_C", properties: []),
		]))

		let probes = try #require(runs.valueOracle).overrideProbes
		#expect(probes.map { "\($0.mockedTypeName).\($0.label)" } == ["S1_Root0.b", "S1_Root1.c"])
		var counts = GraphFuzzerValueOracleCounts()
		counts.add(try #require(runs.valueOracle), isCompared: true)
		#expect(counts.overridePairCount == 2)
		#expect(counts.overrideFieldKindCounts == [.builder: 2])
	}

	// MARK: Values

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportOtherValues_whenGeneratedMockIgnoresOverride() async throws {
		let runs = try await Self.valueOracleRuns(
			of: Self.overriddenStoreFixture,
			editingMockOf: "S1_Screen",
			replacing: "if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { S1_Store() }",
			with: "S1_Store()",
		)

		let failure = try #require(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures[1])

		#expect(failure.kind == .mockBuildsOtherValuesThanProduction)
		#expect(failure.valueDifferences == [
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .1:
			  feature:     .1: nil
			  known right: .1: <4> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detailBuilder > instantiate() > store)
			""",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportOtherValues_whenOverrideReachesOneOfTwoReceivers() async throws {
		// The mock called without the override still builds what production builds, so only the override's pair differs.
		let runs = try await Self.valueOracleRuns(
			of: Self.overriddenStoreFixture,
			editingMockOf: "S1_Screen",
			replacing: "S1_Detail(store: store)",
			with: "S1_Detail(store: safeDIOverrides.store == nil ? store : S1_Store())",
		)

		let failure = try #require(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures[1])

		#expect(failure.kind == .mockBuildsOtherValuesThanProduction)
		#expect(failure.valueDifferences == [
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .0 > detailBuilder > instantiate() again > store:
			  feature:     store: <6> S1_Store
			  known right: store: <4> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detailBuilder > instantiate() > store)
			""",
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .0 > store:
			  feature:     store: <7> S1_Store
			  known right: store: <4> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detailBuilder > instantiate() > store)
			""",
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .1:
			  feature:     .1: <7> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > store)
			  known right: .1: <4> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detailBuilder > instantiate() > store)
			""",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportOtherValues_whenGeneratedMockBuildsSecondInstanceOfPromotedDependency() async throws {
		let runs = try await Self.valueOracleRuns(of: Self.sharedStoreFixture, editingMockOf: "S1_Screen", replacing: "S1_Row(store: store)", with: "S1_Row(store: S1_Store())")

		let failure = try #require(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures[1])

		#expect(failure.kind == .mockBuildsOtherValuesThanProduction)
		#expect(failure.valueDifferences == [
			"""
			probe `S1_Screen.mock()` at <1> S1_Screen > detail > store:
			  feature:     store: <5> S1_Store
			  known right: store: <4> S1_Store (seen, first at <1> S1_Screen > detail > row > store)
			""",
			// The override oracle's pair, which passes the mock the dependency's sentinel, shows the second instance too.
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .0 > detail > store:
			  feature:     store: <5> S1_Store
			  known right: store: <4> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detail > row > store)
			""",
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .1:
			  feature:     .1: <5> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detail > store)
			  known right: .1: <4> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detail > row > store)
			""",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportOtherValues_whenGeneratedMockPassesNilWhereItsMirrorPassesValue() async throws {
		let fixture = Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let detail: S1_Detail", "@Received(onlyIfAvailable: true) let store: S1_Store?"]),
			Self.type("S1_Detail", properties: ["@Received let store: S1_Store"]),
			Self.type("S1_Store", properties: []),
		])
		let runs = try await Self.valueOracleRuns(of: fixture, editingMockOf: "S1_Screen", replacing: "S1_Screen(detail: detail, store: store)", with: "S1_Screen(detail: detail, store: nil)")

		let failure = try #require(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures[1])

		#expect(failure.kind == .mockBuildsOtherValuesThanProduction)
		#expect(failure.valueDifferences == [
			"""
			probe `S1_Screen.mock()` at <1> S1_Screen > store:
			  feature:     store: nil
			  known right: store: <3> S1_Store (seen, first at <1> S1_Screen > detail > store)
			""",
			// The override oracle's pair, which passes the mock the dependency's sentinel, shows the `nil` too.
			"""
			probe `S1_Screen.mock(safeDIOverrides: .init(store: sentinel))` at (S1_Screen, Optional<Any>) > .0 > store:
			  feature:     store: nil
			  known right: store: <3> S1_Store (seen, first at (S1_Screen, Optional<Any>) > .0 > detail > store)
			""",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportNoFailure_whenRootAndMockTakingForwardedValueBuildWhatProductionBuilds() async throws {
		// The root's instantiator of the forwarding screen is called with a sample, and the screen's mock, which takes the
		// forwarded value, is compared with its forwarding mirror.
		let fixture = Self.fixture([
			Self.type("S1_Root", arguments: "isRoot: true", properties: ["@Instantiated let screenBuilder: Instantiator<S1_Screen>"]),
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Forwarded let session: S1_Session", "@Instantiated let detail: S1_Detail"]),
			Self.type("S1_Detail", properties: ["@Received let session: S1_Session"]),
			Self.type("S1_Session", properties: []),
		])
		let runs = try await Self.valueOracleToolRuns(of: fixture)

		#expect(runs.valueOracle?.plan.mirrors.map(\.mockedTypeName) == ["S1_Screen"])
		#expect(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures.isEmpty)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportOtherValues_whenGeneratedMockHandsChildAnotherInstanceThanTheForwardedValue() async throws {
		let fixture = Self.fixture([
			Self.type("S1_Screen", arguments: "generateMock: true", properties: ["@Forwarded let session: S1_Session", "@Instantiated let detail: S1_Detail"]),
			Self.type("S1_Detail", properties: ["@Received let session: S1_Session"]),
			Self.type("S1_Session", properties: []),
		])
		let runs = try await Self.valueOracleRuns(of: fixture, editingMockOf: "S1_Screen", replacing: "S1_Detail(session: session)", with: "S1_Detail(session: S1_Session())")

		let failure = try #require(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures[1])

		#expect(failure.kind == .mockBuildsOtherValuesThanProduction)
		#expect(failure.valueDifferences == [
			"""
			probe `S1_Screen.mock()` at <1> S1_Screen > detail > session:
			  feature:     session: <4> S1_Session
			  known right: session: <2> S1_Session (seen, first at <1> S1_Screen > session)
			""",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueComparisons_reportOtherValues_whenRootsMockHandsChildBeneathForwardingInstantiatorAnotherInstanceThanTheForwardedValue() async throws {
		let runs = try await Self.valueOracleToolRuns(of: Self.rootOfForwardingScreenFixture, editingValueOracleFile: "S1_Root+SafeDIMock.swift", replacing: "S1_Detail(session: session)", with: "S1_Detail(session: S1_Session())")

		let failure = try #require(try await GraphFuzzerOracle.valueComparisons(of: [runs]).failures[1])

		#expect(failure.kind == .mockBuildsOtherValuesThanProduction)
		#expect(failure.valueDifferences == [
			"""
			probe `S1_Root.mock()` at <1> S1_Root > screenBuilder > instantiate(sample) > detail > session:
			  feature:     session: <6> S1_Session
			  known right: session: <4> S1_Session (seen, first at <1> S1_Root > screenBuilder > instantiate(sample) > session)
			""",
			"""
			probe `S1_Root.mock()` at <1> S1_Root > screenBuilder > instantiate(sample) again > detail > session:
			  feature:     session: <10> S1_Session
			  known right: session: <7> S1_Session (seen, first at <1> S1_Root > screenBuilder > instantiate(sample) again > session)
			""",
		])
	}

	// MARK: Private

	/// A root holding an instantiator of a type that forwards a session, which the type's child receives.
	private static let rootOfForwardingScreenFixture = fixture([
		type("S1_Root", arguments: "isRoot: true", properties: ["@Instantiated let screenBuilder: Instantiator<S1_Screen>"]),
		type("S1_Screen", properties: ["@Forwarded let session: S1_Session", "@Instantiated let detail: S1_Detail"]),
		type("S1_Detail", properties: ["@Received let session: S1_Session"]),
		type("S1_Session", properties: []),
	])

	/// A mocked type whose child and grandchild both receive a dependency the mock builds beside it.
	private static let sharedStoreFixture = fixture([
		type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let detail: S1_Detail"]),
		type("S1_Detail", properties: ["@Instantiated let row: S1_Row", "@Received let store: S1_Store"]),
		type("S1_Row", properties: ["@Received let store: S1_Store"]),
		type("S1_Store", properties: []),
	])

	/// A root that builds a mocked type with a child, so that the root's mock needs the mocked type's configuration.
	private static let rootOfMockedScreenFixture = fixture([
		type("S1_Root", arguments: "isRoot: true", properties: ["@Instantiated let screen: S1_Screen"]),
		type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let detail: S1_Detail"]),
		type("S1_Detail", properties: []),
	])

	/// A mocked type that receives a dependency its mock builds beside it, which the type its instantiator builds receives
	/// too: the override oracle's one field of the mock.
	private static let overriddenStoreFixture = fixture([
		type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let detailBuilder: Instantiator<S1_Detail>", "@Received let store: S1_Store"]),
		type("S1_Detail", properties: ["@Received let store: S1_Store"]),
		type("S1_Store", properties: []),
	])

	/// A mocked type with a required alias of the optional form of a property it receives, which the mock promotes from
	/// that optional form and builds non-optional.
	private static let retypedAliasFixture = fixture([
		type("S1_Screen", arguments: "generateMock: true", properties: ["@Received(fulfilledByDependencyNamed: \"value\", ofType: S1_Value?.self) let valueAlias: S1_Value?"]),
		type("S1_Value", properties: []),
	])

	/// A mocked type that instantiates `store: S1_Store` and receives a type that receives `store: S1_Cache?` only if
	/// available, which nothing provides.
	private static let labelOfAnotherTypeFixture = fixture([
		type("S1_Screen", arguments: "generateMock: true", properties: ["@Instantiated let store: S1_Store", "@Received let editor: S1_Editor"]),
		type("S1_Editor", properties: ["@Received(onlyIfAvailable: true) let store: S1_Cache?"]),
		type("S1_Store", properties: []),
		type("S1_Cache", properties: []),
	])

	/// A mocked type that forwards `session`, which a type it receives receives only if available.
	private static let forwardingFixture = fixture([
		type("S1_Screen", arguments: "generateMock: true", properties: ["@Forwarded let session: S1_Session", "@Received let editor: S1_Editor"]),
		type("S1_Editor", properties: ["@Received(onlyIfAvailable: true) let session: S1_Session?"]),
		type("S1_Session", properties: []),
	])

	/// The `SafeDIOverrides` fields of `S1_Screen.mock()` in `sharedStoreFixture`.
	private static let sharedStoreOverrideFields = [
		"detail: S1_Detail.SafeDIMockConfiguration = .init(),",
		"store: (() -> S1_Store)? = nil",
	]

	/// A mock file whose `SafeDIOverrides` initializer takes `overrideFields`.
	private static func sharedStoreMockFile(overrideFields: [String]) -> String {
		let fields = overrideFields.enumerated().map { index, field in
			let trimmed = field.hasSuffix(",") ? String(field.dropLast()) : field
			return "            " + trimmed + (index < overrideFields.count - 1 ? "," : "")
		}
		return """
		#if DEBUG
		extension S1_Screen {
		    struct SafeDIOverrides {
		        init(
		\(fields.joined(separator: "\n"))
		        ) {}
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> S1_Screen {
		        fatalError()
		    }
		}
		#endif
		"""
	}

	/// The source of a fuzzer-shaped `@Instantiable` class named `name` that stores each of `properties`.
	private static func type(_ name: String, arguments: String? = nil, properties: [String]) -> String {
		let parsed = properties.map { property -> (label: String, type: String) in
			let declaration = property[property.range(of: " let ")!.upperBound...]
			let colon = declaration.firstIndex(of: ":")!
			return (String(declaration[..<colon]), declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces))
		}
		var lines = [arguments.map { "@Instantiable(\($0))" } ?? "@Instantiable", "public final class \(name): Instantiable {"]
		if parsed.isEmpty {
			lines.append("\tpublic init() {}")
		} else {
			lines.append("\tpublic init(\(parsed.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {")
			lines += parsed.map { "\t\tself.\($0.label) = \($0.label)" }
			lines += ["\t}", ""]
			lines += properties.map { "\t\($0)" }
		}
		lines.append("}")
		return lines.joined(separator: "\n") + "\n"
	}

	private static func fixture(_ files: [String]) -> GraphFuzzerFixture {
		GraphFuzzerFixture(seed: 1, swiftFileContent: files)
	}

	private static func mirror(of typeName: String, in fixture: GraphFuzzerFixture, forwarding requiredParameters: [GraphFuzzerMirrorProperty] = []) throws -> GraphFuzzerMockMirror {
		let model = GraphFuzzerMockMirrorModel(fixture: fixture)
		var cache = GraphFuzzerMockMirrorModel.ReceivedPropertiesCache()
		return try model.mirror(ofMockedTypeNamed: typeName, named: "\(fixture.typeNamePrefix)ZMirror0", forwarding: requiredParameters, cache: &cache).get()
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func samples(of fixture: GraphFuzzerFixture) -> GraphFuzzerSampleValues {
		GraphFuzzerSampleValues(fixture: fixture, model: GraphFuzzerMockMirrorModel(fixture: fixture))
	}

	private static func expectation(of typeName: String, in fixture: GraphFuzzerFixture) -> GraphFuzzerMockRootExpectation {
		let model = GraphFuzzerMockMirrorModel(fixture: fixture)
		var cache = GraphFuzzerMockMirrorModel.ReceivedPropertiesCache()
		return model.expectation(of: model.mockRoot(ofTypeNamed: typeName, cache: &cache), mockedTypeName: typeName)
	}

	private static func mirrorResult(of typeName: String, in fixture: GraphFuzzerFixture, forwarding requiredParameters: [GraphFuzzerMirrorProperty] = []) -> Result<GraphFuzzerMockMirror, GraphFuzzerMirrorFailure> {
		let model = GraphFuzzerMockMirrorModel(fixture: fixture)
		var cache = GraphFuzzerMockMirrorModel.ReceivedPropertiesCache()
		return model.mirror(ofMockedTypeNamed: typeName, named: "\(fixture.typeNamePrefix)ZMirror0", forwarding: requiredParameters, cache: &cache)
	}

	private static func mirrorSource(of typeName: String, in fixture: GraphFuzzerFixture, forwarding requiredParameters: [GraphFuzzerMirrorProperty] = []) throws -> String {
		try mirror(of: typeName, in: fixture, forwarding: requiredParameters).source(conformance: "", stamp: nil)
	}

	/// The runs of `fixture` with its value-oracle run, in both of which the generated mock of `mockedTypeName` is edited
	/// to replace `original` with `replacement`, as a generator defect would generate it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func valueOracleRuns(of fixture: GraphFuzzerFixture, editingMockOf mockedTypeName: String, replacing original: String, with replacement: String) async throws -> GraphFuzzerToolRuns {
		let mockFileName = "\(mockedTypeName)+SafeDIMock.swift"
		func edited(_ outcome: GraphFuzzerToolOutcome) throws -> GraphFuzzerToolOutcome {
			guard case let .accepted(generatedFiles, warnings) = outcome else { throw ValueOracleTestError.graphRejected("\(outcome)") }
			let mockFile = try #require(generatedFiles[mockFileName])
			try #require(mockFile.contains(original), "\(mockFile)")
			var editedFiles = generatedFiles
			editedFiles[mockFileName] = mockFile.replacingOccurrences(of: original, with: replacement)
			return .accepted(generatedFiles: editedFiles, warnings: warnings)
		}
		let editedOutcome = try await edited(GraphFuzzerOracle.toolOutcome(of: fixture))
		let plan = try GraphFuzzerValueOraclePlan(fixture: fixture, generatedFiles: generatedFiles(of: editedOutcome), storingFixture: fixture)
		#expect(plan.modelFailures == [])
		#expect(plan.mirrors.map(\.mockedTypeName) == [mockedTypeName])
		return try await GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: editedOutcome,
			secondOutcome: editedOutcome,
			valueOracle: GraphFuzzerValueOracleRun(plan: plan, outcome: edited(GraphFuzzerOracle.toolOutcome(of: plan.valueOracleFixture(storingEveryParameter: false)))),
		)
	}

	/// The runs of `fixture` with its value-oracle run, in which the value-oracle run's generated file `fileName`, when
	/// given, is edited to replace `original` with `replacement`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func valueOracleToolRuns(of fixture: GraphFuzzerFixture, editingValueOracleFile fileName: String? = nil, replacing original: String = "", with replacement: String = "") async throws -> GraphFuzzerToolRuns {
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		guard case let .accepted(generatedFiles, _) = outcome else { throw ValueOracleTestError.graphRejected("\(outcome)") }
		let plan = GraphFuzzerValueOraclePlan(fixture: fixture, generatedFiles: generatedFiles, storingFixture: fixture)
		#expect(plan.modelFailures == [])
		var valueOracleOutcome = try await GraphFuzzerOracle.toolOutcome(of: plan.valueOracleFixture(storingEveryParameter: false))
		if let fileName {
			guard case let .accepted(valueOracleFiles, warnings) = valueOracleOutcome else { throw ValueOracleTestError.graphRejected("\(valueOracleOutcome)") }
			let file = try #require(valueOracleFiles[fileName])
			try #require(file.contains(original), "\(file)")
			var editedFiles = valueOracleFiles
			editedFiles[fileName] = file.replacingOccurrences(of: original, with: replacement)
			valueOracleOutcome = .accepted(generatedFiles: editedFiles, warnings: warnings)
		}
		return GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: outcome,
			secondOutcome: outcome,
			valueOracle: GraphFuzzerValueOracleRun(plan: plan, outcome: valueOracleOutcome),
		)
	}

	/// The generated file `fileName` of `outcome`, which the tool accepted.
	private static func generatedFile(_ fileName: String, of outcome: GraphFuzzerToolOutcome) throws -> String {
		try #require(generatedFiles(of: outcome)[fileName])
	}

	/// The generated files of `outcome`, which the tool accepted.
	private static func generatedFiles(of outcome: GraphFuzzerToolOutcome) throws -> [String: String] {
		guard case let .accepted(generatedFiles, _) = outcome else { throw ValueOracleTestError.graphRejected("\(outcome)") }
		return generatedFiles
	}

	private enum ValueOracleTestError: Error {
		case graphRejected(String)
	}
}
