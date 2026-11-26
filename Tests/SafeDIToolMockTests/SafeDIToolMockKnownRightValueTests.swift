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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// Every other value check of a generated `mock()` compares it with something the same generator wrote: the production
/// tree, or another mock. Each test here compares a generated `mock()` with a build written by hand from the Manual's
/// rules, in a file the tool never reads (`<Row>Expected.swift`), so a defect that changes what the generator builds on
/// both sides of those comparisons still shows here. The hand builds are never derived from generated output.
///
/// The rows share one compile and one link: one batch of graphs of probe pairs (`knownRightMockResults`), each test
/// reading its own row's comparison. Each class of a fixture stores every value it takes and a creation stamp
/// (`DifferentialValueCreationStamp`), so the comparator sees identity, `nil`, and an instance built before a lazy
/// wrapper's first read. Under `SAFEDI_SKIP_COMPILE_CHECK` nothing is compiled and every test passes without judging.
struct SafeDIToolMockKnownRightValueTests {
	// MARK: Tests

	/// The mocked type and its child each receive `x`, which the mock builds once and hands to both.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsOneInstanceToMockedTypeAndChild_whenBothReceiveIt() async throws {
		try await expectAgreement(of: .b1)
	}

	/// Two children receive `x: X` and `x2: X`, two dependencies of one type, which the mocked type also holds: each
	/// child holds the instance of its own label.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsEachLabelItsOwnInstance_whenTwoChildrenReceiveTwoLabelsOfOneType() async throws {
		try await expectAgreement(of: .b2)
	}

	/// Two children receive one label as two types the mock cannot build, which `mock()` takes named apart: each child
	/// holds the value passed for its own type.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsEachChildItsOwnParameter_whenTwoChildrenReceiveOneLabelAsTwoTypes() async throws {
		try await expectAgreement(of: .b3)
	}

	/// A protocol nothing fulfills is received at three depths: every receiver holds the one value passed to `mock()`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsPassedValueToEveryDepth_whenTreeReceivesValueMockCannotBuild() async throws {
		try await expectAgreement(of: .b4)
	}

	/// The mocked type's own default-valued initializer parameter defaults to the initializer's default.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_usesInitializersDefault_whenOwnDefaultValuedParameterIsNotPassed() async throws {
		try await expectAgreement(of: .b5)
	}

	/// An override of the mocked type's own child replaces it at the mocked type and at the child's receiver beneath.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsOverrideToEveryReceiver_whenOwnChildIsOverridden() async throws {
		try await expectAgreement(of: .b6)
	}

	/// An override in a nested configuration two levels down replaces exactly that node, and not its sibling of the same
	/// type.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_replacesOnlyThatNode_whenNestedConfigurationOverridesOneOfTwoSiblingsOfOneType() async throws {
		try await expectAgreement(of: .b7)
	}

	/// An override of an `Instantiator`'s type builds every instance the instantiator hands out.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_runsOverrideOnEveryCall_whenInstantiatorsTypeIsOverridden() async throws {
		try await expectAgreement(of: .b8)
	}

	/// An override of a `LazilyInstantiated` dependency builds its instance, on the first read.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_runsOverrideOnFirstRead_whenLazilyInstantiatedDependencyIsOverridden() async throws {
		try await expectAgreement(of: .b9)
	}

	/// A dependency received only if available that nothing builds is `nil`, and the value its override builds when
	/// overridden.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsOverridesValueOrNil_whenDependencyReceivedOnlyIfAvailableIsOverriddenOrNot() async throws {
		try await expectAgreement(of: .b10)
	}

	/// A type a cycle of instantiators builds again reads the overrides of the nearest type of its kind above it: of two
	/// places of the type, each overridden differently, each cycle reads its own place's.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_appliesNearestSameTypeOverride_whenInstantiatorCycleBuildsTypeAgain() async throws {
		try await expectAgreement(of: .b11)
	}

	/// Two mocked types build one child that receives `x` only if available: the one that instantiates `x` hands it
	/// over, the other passes `nil`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_buildsEachMocksOwnPlace_whenTwoMocksDifferOnlyInWhetherTheyInstantiateReceivedLabel() async throws {
		try await expectAgreement(of: .b12)
	}

	/// The mocked type receives `x` only if available and nothing in its tree builds it: `nil`, and `mock()` takes no
	/// parameter for it; given a value through its overrides, the mocked type holds that value.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_passesNil_whenNothingBuildsDependencyReceivedOnlyIfAvailable() async throws {
		try await expectAgreement(of: .b13)
	}

	/// The mocked type receives `x` only if available, and its child requires it: the mock builds one `x` for both.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsPromotedInstanceToOptionalReceiver_whenChildRequiresIt() async throws {
		try await expectAgreement(of: .b14)
	}

	/// A type built at two places of the mock receives `token` only if available: `nil` where a required instantiator of
	/// `token` above it pins the declaration, the instance where a required by-value receive does.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_passesNilOnlyWhereInstantiatorPinsDeclaration_whenTypeIsBuiltAtTwoPlaces() async throws {
		try await expectAgreement(of: .b15)
	}

	/// One child receives `x` as a `LazilyInstantiated` and another receives it by value: the by-value receiver holds the
	/// wrapper's instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsWrappersInstanceToByValueReceiver_whenTreeReceivesLabelLazilyAndByValue() async throws {
		try await expectAgreement(of: .b16)
	}

	/// A promoted `LazilyInstantiated` nobody reads by value is not built when `mock()` returns.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_buildsNothingUpFront_whenPromotedLazilyInstantiatedIsReceivedOnlyAsTheWrapper() async throws {
		try await expectAgreement(of: .b17)
	}

	/// A child type with a hand-written `mock()` is built by it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_buildsChildWithItsHandWrittenMock_whenChildDeclaresOne() async throws {
		try await expectAgreement(of: .b18)
	}

	/// A child type whose generated mock sits beside a `customMockName` method is built by that method.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_buildsChildWithCustomMockNameMethod_whenChildAlsoGeneratesMock() async throws {
		try await expectAgreement(of: .b19)
	}

	/// A `mockOnly` extension of a type with a production declaration builds the type in mocks, and production uses the
	/// initializer.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_buildsTypeWithMockOnlyExtensionsMock_whileProductionUsesInitializer() async throws {
		try await expectAgreement(of: .b20)
	}

	/// `fulfilledByType:` names one of two conformers: the mock builds the named one.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_buildsNamedConformer_whenFulfilledByTypeNamesOneOfTwo() async throws {
		try await expectAgreement(of: .b21)
	}

	/// An erased child received again beneath the mocked type wraps one concrete instance at both places.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_wrapsOneConcreteInstance_whenErasedChildIsReceivedBeneath() async throws {
		try await expectAgreement(of: .b22)
	}

	/// A `SendableInstantiator`'s type takes a default-valued parameter that is not `Sendable`: each call evaluates the
	/// default.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_evaluatesDefaultOnEveryCall_whenSendableInstantiatorsTypeTakesDefaultValuedParameter() async throws {
		try await expectAgreement(of: .b23)
	}

	/// Inside a `SendableInstantiator`, a type with a default-valued parameter is received by two types beneath its
	/// binding: both hold the one instance of each call.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneInstancePerCall_whenTwoReceiversInsideSendableInstantiatorReceiveTypeWithDefault() async throws {
		try await expectAgreement(of: .b24)
	}

	/// The mocked type and a child its `Instantiator` builds each forward `id`: the mock's argument reaches the mocked
	/// type's receivers, and each call's argument only that child's tree.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_handsEachForwardedValueToItsOwnTree_whenMockedTypeAndInstantiatedChildForwardOneLabel() async throws {
		try await expectAgreement(of: .b25)
	}

	/// A type built beside a reader of `token` and beneath a holder that declares its own: each place reads the nearest
	/// declaration.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_readsNearestDeclaration_whenTypeIsBuiltBesideReaderAndBeneathHolderOfItsOwn() async throws {
		try await expectAgreement(of: .b26)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenOptionalReceiverIsBesideNonOptionalReader() async throws {
		try await expectAgreement(of: .o1)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenOptionalReceiverIsBesideNonOptionalReaderOfFlatParameter() async throws {
		try await expectAgreement(of: .o2)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenOptionalReceiverIsAboveNonOptionalReader() async throws {
		try await expectAgreement(of: .o3)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenOptionalReceiverIsAboveNonOptionalReaderOfFlatParameter() async throws {
		try await expectAgreement(of: .o4)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenOptionalReceiverIsInsideSendableBuilder() async throws {
		try await expectAgreement(of: .o5)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenOptionalReceiverIsInsideSendableBuilderBesideFlatParameter() async throws {
		try await expectAgreement(of: .o6)
	}

	/// A value one receiver requires optionally and another non-optionally is one non-optional instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mock_sharesOneNonOptionalValue_whenNonOptionalReaderReceivesLazilyInstantiated() async throws {
		try await expectAgreement(of: .o7)
	}

	// MARK: Private

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func expectAgreement(of row: KnownRightMockRow, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let outcomes = try await knownRightMockResults.value
		guard compileVerificationIsEnabled else { return }
		let outcome = try #require(outcomes[row.rawValue], "The batch compared no graph for \(row.rawValue).", sourceLocation: sourceLocation)
		switch outcome {
		case let .failed(error):
			Issue.record("The comparator could not compare \(row.rawValue): \(error)", sourceLocation: sourceLocation)
		case let .compared(comparedNodeCount, differences, report):
			#expect(comparedNodeCount > 0, "The comparator compared no value for \(row.rawValue).", sourceLocation: sourceLocation)
			for difference in differences {
				Issue.record("The mock builds other values than the hand build for \(difference)\n\(report)", sourceLocation: sourceLocation)
			}
		}
	}
}

// MARK: - Rows

/// What the batch found for one row.
enum KnownRightMockOutcome: Sendable {
	/// The comparison ran: how many nodes both paths' descriptions hold, the differences, and the comparator's report.
	case compared(comparedNodeCount: Int, differences: [String], report: String)
	case failed(String)
}

/// The batch's outcome per row, or an empty dictionary when compile verification is off.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let knownRightMockResults = SharedTestWork<[String: KnownRightMockOutcome]> {
	var filesToDelete = [URL]()
	defer {
		for file in filesToDelete {
			try? FileManager.default.removeItem(at: file)
		}
	}
	var graphs = [DifferentialValueGraph]()
	for row in KnownRightMockRow.allCases {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: row.fixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
		var fixtureFiles = [String: String]()
		for (index, file) in row.fixture.enumerated() {
			fixtureFiles["\(row.rawValue)_\(index).swift"] = file
		}
		fixtureFiles["\(row.rawValue)Expected.swift"] = row.expectedBuild
		var generatedFiles = [String: String]()
		for (fileName, contents) in output.generatedFiles ?? [:] {
			generatedFiles["\(row.rawValue)_\(fileName)"] = contents
		}
		graphs.append(DifferentialValueGraph(
			name: row.rawValue,
			path: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: generatedFiles),
			probePairs: row.probePairs.map { DifferentialValueProbePair(name: $0.feature, featureExpression: $0.feature, knownRightExpression: $0.knownRight) },
			samples: row.samples,
		))
	}
	guard let comparisons = try await DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete) else { return [:] }
	var outcomes = [String: KnownRightMockOutcome]()
	for comparison in comparisons {
		switch comparison.result {
		case let .success(result):
			let comparedNodeCount = min(
				result.featureDescription.split(separator: "\n").count,
				result.knownRightDescription.split(separator: "\n").count,
			)
			outcomes[comparison.name] = .compared(comparedNodeCount: comparedNodeCount, differences: result.differences.map(\.description), report: result.report)
		case let .failure(error):
			outcomes[comparison.name] = .failed("\(error)")
		}
	}
	return outcomes
}

/// The shapes of internal mocks whose values a hand build pins.
enum KnownRightMockRow: String, CaseIterable {
	case b1 = "B1"
	case b2 = "B2"
	case b3 = "B3"
	case b4 = "B4"
	case b5 = "B5"
	case b6 = "B6"
	case b7 = "B7"
	case b8 = "B8"
	case b9 = "B9"
	case b10 = "B10"
	case b11 = "B11"
	case b12 = "B12"
	case b13 = "B13"
	case b14 = "B14"
	case b15 = "B15"
	case b16 = "B16"
	case b17 = "B17"
	case b18 = "B18"
	case b19 = "B19"
	case b20 = "B20"
	case b21 = "B21"
	case b22 = "B22"
	case b23 = "B23"
	case b24 = "B24"
	case b25 = "B25"
	case b26 = "B26"
	case o1 = "O1"
	case o2 = "O2"
	case o3 = "O3"
	case o4 = "O4"
	case o5 = "O5"
	case o6 = "O6"
	case o7 = "O7"

	/// The files the tool reads.
	var fixture: [String] {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "\(rawValue)Stamp")
		var files = Self.fixtures(stamp: stamp)[self] ?? []
		files.append(DifferentialValueCreationStamp.counterDeclaration(named: "\(rawValue)Stamp"))
		return files
	}

	/// The hand build, written from the Manual, in a file only the comparator compiles.
	var expectedBuild: String {
		Self.expectedBuilds[self] ?? ""
	}

	/// Each pair's generated expression and the hand-built one.
	var probePairs: [(feature: String, knownRight: String)] {
		switch self {
		case .b3:
			[("B3Screen.mock(token_B3Base: B3Base(id: 1), token_B3Sub: B3Sub(id: 2))", "b3Expected(base: B3Base(id: 1), sub: B3Sub(id: 2))")]
		case .b4:
			[("B4Screen.mock(service: B4ServiceImpl())", "b4Expected(service: B4ServiceImpl())")]
		case .b6:
			[("{ let sentinel = B6Child(); return (B6Screen.mock(safeDIOverrides: .init(child: { sentinel })), sentinel) }()", "{ let sentinel = B6Child(); return (b6Expected(child: sentinel), sentinel) }()")]
		case .b7:
			[("B7Screen.mock(safeDIOverrides: .init(mid: .init(inner: .init(left: { B7Sentinel() }))))", "b7Expected()")]
		case .b8:
			[("B8Screen.mock(safeDIOverrides: .init(childBuilder: { B8Sentinel() }))", "b8Expected()")]
		case .b9:
			[("B9Screen.mock(safeDIOverrides: .init(child: { B9Sentinel() }))", "b9Expected()")]
		case .b10:
			[
				("B10Screen.mock()", "b10Expected(x: nil)"),
				("B10Screen.mock(safeDIOverrides: .init(x: B10X()))", "b10Expected(x: B10X())"),
			]
		case .b11:
			[("B11Shell.mock(safeDIOverrides: .init(screen: .init(leaf: { B11Sentinel() }), panel: .init(screen: .init(leaf: { B11PanelSentinel() }))))", "b11Expected()")]
		case .b12:
			[("B12ScreenA.mock()", "b12ExpectedA()"), ("B12ScreenB.mock()", "b12ExpectedB()")]
		case .b20:
			[("B20Screen.mock()", "b20Expected()"), ("B20Root()", "b20ExpectedRoot()")]
		case .b25:
			[("B25Screen.mock(id: 1)", "b25Expected(id: 1)")]
		case .b13:
			[
				("B13Screen.mock()", "b13Expected()"),
				("{ let x = B13X(); return (B13Screen.mock(safeDIOverrides: .init(x: x)), x) }()", "{ let x = B13X(); return (b13Expected(x: x), x) }()"),
			]
		case .o1:
			[
				("O1Screen.mock()", "o1Expected()"),
				("{ let x = O1X(); return (O1Screen.mock(safeDIOverrides: .init(x: { x })), x) }()", "{ let x = O1X(); return (o1Expected(x: x), x) }()"),
			]
		case .o2:
			[("{ let x = O2X(); return (O2Screen.mock(x: x), x) }()", "{ let x = O2X(); return (o2Expected(x: x), x) }()")]
		case .o3:
			[
				("O3Screen.mock()", "o3Expected()"),
				("{ let x = O3X(); return (O3Screen.mock(safeDIOverrides: .init(x: { x })), x) }()", "{ let x = O3X(); return (o3Expected(x: x), x) }()"),
			]
		case .o4:
			[("{ let x = O4X(); return (O4Screen.mock(x: x), x) }()", "{ let x = O4X(); return (o4Expected(x: x), x) }()")]
		case .o5:
			[
				("O5Screen.mock()", "o5Expected()"),
				("{ let x = O5X(); return (O5Screen.mock(safeDIOverrides: .init(x: { x })), x) }()", "{ let x = O5X(); return (o5Expected(x: x), x) }()"),
			]
		case .o6:
			[("{ let x = O6X(); return (O6Screen.mock(x: x), x) }()", "{ let x = O6X(); return (o6Expected(x: x), x) }()")]
		case .o7:
			[
				("O7Screen.mock()", "o7Expected()"),
				("{ let x = O7X(); return (O7Screen.mock(safeDIOverrides: .init(x: { x })), x) }()", "{ let x = O7X(); return (o7Expected(x: x), x) }()"),
			]
		case .b1, .b2, .b5, .b14, .b15, .b16, .b17, .b18, .b19, .b21, .b22, .b23, .b24, .b26:
			[("\(rawValue)Screen.mock()", "\(rawValue.lowercased())Expected()")]
		}
	}

	/// The sample values the describer calls an instantiator with forwarded properties with.
	var samples: [DifferentialValueSample] {
		switch self {
		case .b25:
			[DifferentialValueSample(type: "Int", expression: "2")]
		case .b1, .b2, .b3, .b4, .b5, .b6, .b7, .b8, .b9, .b10, .b11, .b12, .b13, .b14, .b15, .b16, .b17, .b18, .b19, .b20, .b21, .b22, .b23, .b24, .b26, .o1, .o2, .o3, .o4, .o5, .o6, .o7:
			[]
		}
	}

	private static func fixtures(stamp: String) -> [KnownRightMockRow: [String]] {
		[
			.b1: [
				"""
				@Instantiable(generateMock: true)
				public final class B1Screen: Instantiable {
				    public init(x: B1X, child: B1Child) {
				        self.x = x
				        self.child = child
				    }

				    @Received let x: B1X
				    @Instantiated let child: B1Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B1Child: Instantiable {
				    public init(x: B1X) {
				        self.x = x
				    }

				    @Received let x: B1X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B1X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b2: [
				"""
				@Instantiable(generateMock: true)
				public final class B2Screen: Instantiable {
				    public init(x: B2X, x2: B2X, childA: B2ChildA, childB: B2ChildB) {
				        self.x = x
				        self.x2 = x2
				        self.childA = childA
				        self.childB = childB
				    }

				    @Received let x: B2X
				    @Received let x2: B2X
				    @Instantiated let childA: B2ChildA
				    @Instantiated let childB: B2ChildB
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B2ChildA: Instantiable {
				    public init(x: B2X) {
				        self.x = x
				    }

				    @Received let x: B2X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B2ChildB: Instantiable {
				    public init(x2: B2X) {
				        self.x2 = x2
				    }

				    @Received let x2: B2X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B2X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b3: [
				"""
				@Instantiable(generateMock: true)
				public final class B3Screen: Instantiable {
				    public init(childBase: B3ChildBase, childSub: B3ChildSub) {
				        self.childBase = childBase
				        self.childSub = childSub
				    }

				    @Instantiated let childBase: B3ChildBase
				    @Instantiated let childSub: B3ChildSub
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B3ChildBase: Instantiable {
				    public init(token: B3Base) {
				        self.token = token
				    }

				    @Received let token: B3Base
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B3ChildSub: Instantiable {
				    public init(token: B3Sub) {
				        self.token = token
				    }

				    @Received let token: B3Sub
				    \(stamp)
				}
				""",
				"""
				public class B3Base {
				    public init(id: Int) {
				        self.id = id
				    }

				    let id: Int
				    \(stamp)
				}

				public final class B3Sub: B3Base {}
				""",
			],
			.b4: [
				"""
				@Instantiable(generateMock: true)
				public final class B4Screen: Instantiable {
				    public init(service: any B4Service, child: B4Child) {
				        self.service = service
				        self.child = child
				    }

				    @Received let service: any B4Service
				    @Instantiated let child: B4Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B4Child: Instantiable {
				    public init(service: any B4Service, grandchild: B4Grandchild) {
				        self.service = service
				        self.grandchild = grandchild
				    }

				    @Received let service: any B4Service
				    @Instantiated let grandchild: B4Grandchild
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B4Grandchild: Instantiable {
				    public init(service: any B4Service) {
				        self.service = service
				    }

				    @Received let service: any B4Service
				    \(stamp)
				}
				""",
				"""
				public protocol B4Service: AnyObject {}

				public final class B4ServiceImpl: B4Service {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b5: [
				"""
				@Instantiable(generateMock: true)
				public final class B5Screen: Instantiable {
				    public init(child: B5Child, retries: Int = 7) {
				        self.child = child
				        self.retries = retries
				    }

				    @Instantiated let child: B5Child
				    let retries: Int
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B5Child: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b6: [
				"""
				@Instantiable(generateMock: true)
				public final class B6Screen: Instantiable {
				    public init(child: B6Child, other: B6Other) {
				        self.child = child
				        self.other = other
				    }

				    @Instantiated let child: B6Child
				    @Instantiated let other: B6Other
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B6Other: Instantiable {
				    public init(child: B6Child) {
				        self.child = child
				    }

				    @Received let child: B6Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B6Child: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b7: [
				"""
				@Instantiable(generateMock: true)
				public final class B7Screen: Instantiable {
				    public init(mid: B7Mid) {
				        self.mid = mid
				    }

				    @Instantiated let mid: B7Mid
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B7Mid: Instantiable {
				    public init(inner: B7Inner) {
				        self.inner = inner
				    }

				    @Instantiated let inner: B7Inner
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B7Inner: Instantiable {
				    public init(left: B7Leaf, right: B7Leaf) {
				        self.left = left
				        self.right = right
				    }

				    @Instantiated let left: B7Leaf
				    @Instantiated let right: B7Leaf
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public class B7Leaf: Instantiable {
				    public init() {}
				    \(stamp)
				}

				public final class B7Sentinel: B7Leaf {}
				""",
			],
			.b8: [
				"""
				@Instantiable(generateMock: true)
				public final class B8Screen: Instantiable {
				    public init(childBuilder: Instantiator<B8Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<B8Child>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public class B8Child: Instantiable {
				    public init() {}
				    \(stamp)
				}

				public final class B8Sentinel: B8Child {}
				""",
			],
			.b9: [
				"""
				@Instantiable(generateMock: true)
				public final class B9Screen: Instantiable {
				    public init(child: LazilyInstantiated<B9Child>) {
				        self.child = child
				    }

				    @Instantiated let child: LazilyInstantiated<B9Child>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public class B9Child: Instantiable {
				    public init() {}
				    \(stamp)
				}

				public final class B9Sentinel: B9Child {}
				""",
			],
			.b10: [
				"""
				@Instantiable(generateMock: true)
				public final class B10Screen: Instantiable {
				    public init(child: B10Child) {
				        self.child = child
				    }

				    @Instantiated let child: B10Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B10Child: Instantiable {
				    public init(x: B10X?) {
				        self.x = x
				    }

				    @Received(onlyIfAvailable: true) let x: B10X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B10X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b11: [
				"""
				@Instantiable(generateMock: true)
				public final class B11Shell: Instantiable {
				    public init(screen: B11Screen, panel: B11Panel) {
				        self.screen = screen
				        self.panel = panel
				    }

				    @Instantiated let screen: B11Screen
				    @Instantiated let panel: B11Panel
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B11Panel: Instantiable {
				    public init(screen: B11Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: B11Screen
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B11Screen: Instantiable {
				    public init(leaf: B11Leaf, stepBuilder: Instantiator<B11Step>) {
				        self.leaf = leaf
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated let leaf: B11Leaf
				    @Instantiated let stepBuilder: Instantiator<B11Step>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B11Step: Instantiable {
				    public init(screenBuilder: Instantiator<B11Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: Instantiator<B11Screen>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public class B11Leaf: Instantiable {
				    public init() {}
				    \(stamp)
				}

				public final class B11Sentinel: B11Leaf {}

				public final class B11PanelSentinel: B11Leaf {}
				""",
			],
			.b12: [
				"""
				@Instantiable(generateMock: true)
				public final class B12ScreenA: Instantiable {
				    public init(x: B12X, leaf: B12Leaf) {
				        self.x = x
				        self.leaf = leaf
				    }

				    @Instantiated let x: B12X
				    @Instantiated let leaf: B12Leaf
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class B12ScreenB: Instantiable {
				    public init(leaf: B12Leaf) {
				        self.leaf = leaf
				    }

				    @Instantiated let leaf: B12Leaf
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B12Leaf: Instantiable {
				    public init(x: B12X?) {
				        self.x = x
				    }

				    @Received(onlyIfAvailable: true) let x: B12X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B12X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b13: [
				"""
				@Instantiable(generateMock: true)
				public final class B13Screen: Instantiable {
				    public init(x: B13X?, child: B13Child) {
				        self.x = x
				        self.child = child
				    }

				    @Received(onlyIfAvailable: true) let x: B13X?
				    @Instantiated let child: B13Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B13Child: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B13X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b14: [
				"""
				@Instantiable(generateMock: true)
				public final class B14Screen: Instantiable {
				    public init(x: B14X?, child: B14Child) {
				        self.x = x
				        self.child = child
				    }

				    @Received(onlyIfAvailable: true) let x: B14X?
				    @Instantiated let child: B14Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B14Child: Instantiable {
				    public init(x: B14X) {
				        self.x = x
				    }

				    @Received let x: B14X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B14X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b15: [
				"""
				@Instantiable(generateMock: true)
				public final class B15Screen: Instantiable {
				    public init(reader: B15Reader, leaf: B15Leaf, source: B15Source) {
				        self.reader = reader
				        self.leaf = leaf
				        self.source = source
				    }

				    @Instantiated let reader: B15Reader
				    @Instantiated let leaf: B15Leaf
				    @Received let source: B15Source
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B15Reader: Instantiable {
				    public init(token: B15Token) {
				        self.token = token
				    }

				    @Received let token: B15Token
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B15Source: Instantiable {
				    public init(token: Instantiator<B15Token>, holder: B15Holder) {
				        self.token = token
				        self.holder = holder
				    }

				    @Received let token: Instantiator<B15Token>
				    @Instantiated let holder: B15Holder
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B15Holder: Instantiable {
				    public init(leaf: B15Leaf) {
				        self.leaf = leaf
				    }

				    @Instantiated let leaf: B15Leaf
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B15Leaf: Instantiable {
				    public init(token: B15Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: B15Token?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B15Token: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b16: [
				"""
				@Instantiable(generateMock: true)
				public final class B16Screen: Instantiable {
				    public init(wrapperReader: B16WrapperReader, valueReader: B16ValueReader) {
				        self.wrapperReader = wrapperReader
				        self.valueReader = valueReader
				    }

				    @Instantiated let wrapperReader: B16WrapperReader
				    @Instantiated let valueReader: B16ValueReader
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B16WrapperReader: Instantiable {
				    public init(x: LazilyInstantiated<B16X>) {
				        self.x = x
				    }

				    @Received let x: LazilyInstantiated<B16X>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B16ValueReader: Instantiable {
				    public init(x: B16X) {
				        self.x = x
				    }

				    @Received let x: B16X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B16X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b17: [
				"""
				@Instantiable(generateMock: true)
				public final class B17Screen: Instantiable {
				    public init(child: B17Child) {
				        self.child = child
				    }

				    @Instantiated let child: B17Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B17Child: Instantiable {
				    public init(x: LazilyInstantiated<B17X>) {
				        self.x = x
				    }

				    @Received let x: LazilyInstantiated<B17X>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B17X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b18: [
				"""
				@Instantiable(generateMock: true)
				public final class B18Screen: Instantiable {
				    public init(child: B18Child) {
				        self.child = child
				    }

				    @Instantiated let child: B18Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B18Child: Instantiable {
				    public init() {
				        madeBy = "init"
				    }

				    #if DEBUG
				        public static func mock() -> B18Child {
				            let child = B18Child()
				            child.madeBy = "mock"
				            return child
				        }
				    #endif

				    var madeBy: String
				    \(stamp)
				}
				""",
			],
			.b19: [
				"""
				@Instantiable(generateMock: true)
				public final class B19Screen: Instantiable {
				    public init(child: B19Child) {
				        self.child = child
				    }

				    @Instantiated let child: B19Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true, customMockName: "preview")
				public final class B19Child: Instantiable {
				    public init() {
				        madeBy = "init"
				    }

				    #if DEBUG
				        public static func preview() -> B19Child {
				            let child = B19Child()
				            child.madeBy = "preview"
				            return child
				        }
				    #endif

				    var madeBy: String
				    \(stamp)
				}
				""",
			],
			.b20: [
				"""
				@Instantiable(isRoot: true)
				public final class B20Root: Instantiable {
				    public init(screen: B20Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: B20Screen
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class B20Screen: Instantiable {
				    public init(service: B20Service) {
				        self.service = service
				    }

				    @Instantiated let service: B20Service
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B20Service: Instantiable {
				    public init() {
				        madeBy = "init"
				    }

				    var madeBy: String
				    \(stamp)
				}
				""",
				"""
				#if DEBUG
				    @Instantiable(mockOnly: true)
				    extension B20Service {
				        public static func mock() -> B20Service {
				            let service = B20Service()
				            service.madeBy = "mock"
				            return service
				        }
				    }
				#endif
				""",
			],
			.b21: [
				"""
				@Instantiable(generateMock: true)
				public final class B21Screen: Instantiable {
				    public init(service: any B21Service) {
				        self.service = service
				    }

				    @Instantiated(fulfilledByType: "B21Named") let service: any B21Service
				    \(stamp)
				}
				""",
				"""
				public protocol B21Service: AnyObject {}

				@Instantiable(fulfillingAdditionalTypes: [B21Service.self])
				public final class B21Listed: B21Service, Instantiable {
				    public init() {}
				    \(stamp)
				}

				@Instantiable
				public final class B21Named: B21Service, Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b22: [
				"""
				@Instantiable(generateMock: true)
				public final class B22Screen: Instantiable {
				    public init(service: B22AnyService, child: B22Child) {
				        self.service = service
				        self.child = child
				    }

				    @Instantiated(fulfilledByType: "B22Concrete", erasedToConcreteExistential: true) let service: B22AnyService
				    @Instantiated let child: B22Child
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B22Child: Instantiable {
				    public init(service: B22AnyService) {
				        self.service = service
				    }

				    @Received let service: B22AnyService
				    \(stamp)
				}
				""",
				"""
				public protocol B22Service: AnyObject {}

				public struct B22AnyService {
				    public init(_ base: any B22Service) {
				        self.base = base
				    }

				    let base: any B22Service
				}

				@Instantiable
				public final class B22Concrete: B22Service, Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b23: [
				"""
				@Instantiable(generateMock: true)
				public final class B23Screen: Instantiable {
				    public init(childBuilder: SendableInstantiator<B23Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: SendableInstantiator<B23Child>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B23Child: Instantiable {
				    public init(note: B23Note = B23Note()) {
				        self.note = note
				    }

				    let note: B23Note
				    \(stamp)
				}
				""",
				"""
				public final class B23Note {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b24: [
				"""
				@Instantiable(generateMock: true)
				public final class B24Screen: Instantiable {
				    public init(childBuilder: SendableInstantiator<B24Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: SendableInstantiator<B24Child>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B24Child: Instantiable {
				    public init(settings: B24Settings, first: B24First, second: B24Second) {
				        self.settings = settings
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let settings: B24Settings
				    @Instantiated let first: B24First
				    @Instantiated let second: B24Second
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B24Settings: Instantiable {
				    public init(note: B24Note = B24Note()) {
				        self.note = note
				    }

				    let note: B24Note
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B24First: Instantiable {
				    public init(settings: B24Settings) {
				        self.settings = settings
				    }

				    @Received let settings: B24Settings
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B24Second: Instantiable {
				    public init(settings: B24Settings) {
				        self.settings = settings
				    }

				    @Received let settings: B24Settings
				    \(stamp)
				}
				""",
				"""
				public final class B24Note {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.b26: [
				"""
				@Instantiable(generateMock: true)
				public final class B26Screen: Instantiable {
				    public init(reader: B26Reader, leaf: B26Leaf, holder: B26Holder) {
				        self.reader = reader
				        self.leaf = leaf
				        self.holder = holder
				    }

				    @Instantiated let reader: B26Reader
				    @Instantiated let leaf: B26Leaf
				    @Instantiated let holder: B26Holder
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B26Reader: Instantiable {
				    public init(token: B26Token) {
				        self.token = token
				    }

				    @Received let token: B26Token
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B26Holder: Instantiable {
				    public init(token: B26Token, leaf: B26Leaf) {
				        self.token = token
				        self.leaf = leaf
				    }

				    @Instantiated let token: B26Token
				    @Instantiated let leaf: B26Leaf
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B26Leaf: Instantiable {
				    public init(token: B26Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: B26Token?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B26Token: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
			],
			.o1: [
				"""
				@Instantiable
				public final class O1X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O1C: Instantiable {
				    public init(x: O1X?) {
				        self.x = x
				    }

				    @Received let x: O1X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O1B: Instantiable {
				    public init(x: O1X) {
				        self.x = x
				    }

				    @Received let x: O1X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O1Svc: Instantiable {
				    public init(b: O1B) {
				        self.b = b
				    }

				    @Instantiated let b: O1B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O1Screen: Instantiable {
				    public init(c: O1C, svc: O1Svc) {
				        self.c = c
				        self.svc = svc
				    }

				    @Instantiated let c: O1C
				    @Received let svc: O1Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O1Feature: Instantiable {
				    public init(x: O1X?, screen: O1Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O1X?
				    @Instantiated let screen: O1Screen
				    \(stamp)
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class O1Root: Instantiable {
				    public init(x: O1X, svc: O1Svc, featureBuilder: Instantiator<O1Feature>) {
				        self.x = x
				        self.svc = svc
				        self.featureBuilder = featureBuilder
				    }

				    @Instantiated let x: O1X
				    @Instantiated let svc: O1Svc
				    @Instantiated let featureBuilder: Instantiator<O1Feature>
				    \(stamp)
				}
				""",
			],
			.o2: [
				"""
				public final class O2X {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O2C: Instantiable {
				    public init(x: O2X?) {
				        self.x = x
				    }

				    @Received let x: O2X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O2B: Instantiable {
				    public init(x: O2X) {
				        self.x = x
				    }

				    @Received let x: O2X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O2Svc: Instantiable {
				    public init(b: O2B) {
				        self.b = b
				    }

				    @Instantiated let b: O2B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O2Screen: Instantiable {
				    public init(c: O2C, svc: O2Svc) {
				        self.c = c
				        self.svc = svc
				    }

				    @Instantiated let c: O2C
				    @Received let svc: O2Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O2Feature: Instantiable {
				    public init(x: O2X?, screen: O2Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O2X?
				    @Instantiated let screen: O2Screen
				    \(stamp)
				}
				""",
			],
			.o3: [
				"""
				@Instantiable
				public final class O3X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O3C: Instantiable {
				    public init(x: O3X?, svc: O3Svc) {
				        self.x = x
				        self.svc = svc
				    }

				    @Received let x: O3X?
				    @Received let svc: O3Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O3B: Instantiable {
				    public init(x: O3X) {
				        self.x = x
				    }

				    @Received let x: O3X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O3Svc: Instantiable {
				    public init(b: O3B) {
				        self.b = b
				    }

				    @Instantiated let b: O3B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O3Screen: Instantiable {
				    public init(c: O3C) {
				        self.c = c
				    }

				    @Instantiated let c: O3C
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O3Feature: Instantiable {
				    public init(x: O3X?, screen: O3Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O3X?
				    @Instantiated let screen: O3Screen
				    \(stamp)
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class O3Root: Instantiable {
				    public init(x: O3X, svc: O3Svc, featureBuilder: Instantiator<O3Feature>) {
				        self.x = x
				        self.svc = svc
				        self.featureBuilder = featureBuilder
				    }

				    @Instantiated let x: O3X
				    @Instantiated let svc: O3Svc
				    @Instantiated let featureBuilder: Instantiator<O3Feature>
				    \(stamp)
				}
				""",
			],
			.o4: [
				"""
				public final class O4X {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O4C: Instantiable {
				    public init(x: O4X?, svc: O4Svc) {
				        self.x = x
				        self.svc = svc
				    }

				    @Received let x: O4X?
				    @Received let svc: O4Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O4B: Instantiable {
				    public init(x: O4X) {
				        self.x = x
				    }

				    @Received let x: O4X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O4Svc: Instantiable {
				    public init(b: O4B) {
				        self.b = b
				    }

				    @Instantiated let b: O4B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O4Screen: Instantiable {
				    public init(c: O4C) {
				        self.c = c
				    }

				    @Instantiated let c: O4C
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O4Feature: Instantiable {
				    public init(x: O4X?, screen: O4Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O4X?
				    @Instantiated let screen: O4Screen
				    \(stamp)
				}
				""",
			],
			.o5: [
				"""
				@Instantiable
				public final class O5X: Instantiable, Sendable {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O5C: Instantiable, Sendable {
				    public init(x: O5X?) {
				        self.x = x
				    }

				    @Received let x: O5X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O5B: Instantiable, Sendable {
				    public init(x: O5X) {
				        self.x = x
				    }

				    @Received let x: O5X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O5Svc: Instantiable, Sendable {
				    public init(b: O5B) {
				        self.b = b
				    }

				    @Instantiated let b: O5B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O5Screen: Instantiable, Sendable {
				    public init(cBuilder: SendableInstantiator<O5C>, svc: O5Svc) {
				        self.cBuilder = cBuilder
				        self.svc = svc
				    }

				    @Instantiated let cBuilder: SendableInstantiator<O5C>
				    @Received let svc: O5Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O5Feature: Instantiable, Sendable {
				    public init(x: O5X?, screen: O5Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O5X?
				    @Instantiated let screen: O5Screen
				    \(stamp)
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class O5Root: Instantiable, Sendable {
				    public init(x: O5X, svc: O5Svc, featureBuilder: SendableInstantiator<O5Feature>) {
				        self.x = x
				        self.svc = svc
				        self.featureBuilder = featureBuilder
				    }

				    @Instantiated let x: O5X
				    @Instantiated let svc: O5Svc
				    @Instantiated let featureBuilder: SendableInstantiator<O5Feature>
				    \(stamp)
				}
				""",
			],
			.o6: [
				"""
				public final class O6X: Sendable {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O6C: Instantiable, Sendable {
				    public init(x: O6X?) {
				        self.x = x
				    }

				    @Received let x: O6X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O6B: Instantiable, Sendable {
				    public init(x: O6X) {
				        self.x = x
				    }

				    @Received let x: O6X
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O6Svc: Instantiable, Sendable {
				    public init(b: O6B) {
				        self.b = b
				    }

				    @Instantiated let b: O6B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O6Screen: Instantiable, Sendable {
				    public init(cBuilder: SendableInstantiator<O6C>, svc: O6Svc) {
				        self.cBuilder = cBuilder
				        self.svc = svc
				    }

				    @Instantiated let cBuilder: SendableInstantiator<O6C>
				    @Received let svc: O6Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O6Feature: Instantiable, Sendable {
				    public init(x: O6X?, screen: O6Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O6X?
				    @Instantiated let screen: O6Screen
				    \(stamp)
				}
				""",
			],
			.o7: [
				"""
				@Instantiable
				public final class O7X: Instantiable {
				    public init() {}
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O7C: Instantiable {
				    public init(x: O7X?) {
				        self.x = x
				    }

				    @Received let x: O7X?
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O7B: Instantiable {
				    public init(x: LazilyInstantiated<O7X>) {
				        self.x = x
				    }

				    @Received let x: LazilyInstantiated<O7X>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O7Svc: Instantiable {
				    public init(b: O7B) {
				        self.b = b
				    }

				    @Instantiated let b: O7B
				    \(stamp)
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class O7Screen: Instantiable {
				    public init(c: O7C, svc: O7Svc) {
				        self.c = c
				        self.svc = svc
				    }

				    @Instantiated let c: O7C
				    @Received let svc: O7Svc
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class O7Feature: Instantiable {
				    public init(x: O7X?, screen: O7Screen) {
				        self.x = x
				        self.screen = screen
				    }

				    @Forwarded let x: O7X?
				    @Instantiated let screen: O7Screen
				    \(stamp)
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class O7Root: Instantiable {
				    public init(x: LazilyInstantiated<O7X>, svc: O7Svc, featureBuilder: Instantiator<O7Feature>) {
				        self.x = x
				        self.svc = svc
				        self.featureBuilder = featureBuilder
				    }

				    @Instantiated let x: LazilyInstantiated<O7X>
				    @Instantiated let svc: O7Svc
				    @Instantiated let featureBuilder: Instantiator<O7Feature>
				    \(stamp)
				}
				""",
			],
			.b25: [
				"""
				@Instantiable(generateMock: true)
				public final class B25Screen: Instantiable {
				    public init(id: Int, other: B25Other, childBuilder: Instantiator<B25Child>) {
				        self.id = id
				        self.other = other
				        self.childBuilder = childBuilder
				    }

				    @Forwarded let id: Int
				    @Instantiated let other: B25Other
				    @Instantiated let childBuilder: Instantiator<B25Child>
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B25Other: Instantiable {
				    public init(id: Int) {
				        self.id = id
				    }

				    @Received let id: Int
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B25Child: Instantiable {
				    public init(id: Int, grandchild: B25Grandchild) {
				        self.id = id
				        self.grandchild = grandchild
				    }

				    @Forwarded let id: Int
				    @Instantiated let grandchild: B25Grandchild
				    \(stamp)
				}
				""",
				"""
				@Instantiable
				public final class B25Grandchild: Instantiable {
				    public init(id: Int) {
				        self.id = id
				    }

				    @Received let id: Int
				    \(stamp)
				}
				""",
			],
		]
	}

	/// Each row's hand build. Each follows the rule of the Manual its comment names, and calls initializers directly.
	private static let expectedBuilds: [KnownRightMockRow: String] = [
		// "Using generated mocks": the mock builds the type's full subtree; a required receive the mock can build is built
		// once, "like @Instantiated", and every receiver of the label beneath reads it.
		.b1: """
		func b1Expected() -> B1Screen {
		    let x = B1X()
		    return B1Screen(x: x, child: B1Child(x: x))
		}
		""",
		// Each label is a dependency of its own, built once and read by each receiver of that label.
		.b2: """
		func b2Expected() -> B2Screen {
		    let x = B2X()
		    let x2 = B2X()
		    return B2Screen(x: x, x2: x2, childA: B2ChildA(x: x), childB: B2ChildB(x2: x2))
		}
		""",
		// "Names": one flat parameter per type the mock cannot build, named by label and type; each goes to its own
		// receiver.
		.b3: """
		func b3Expected(base: B3Base, sub: B3Sub) -> B3Screen {
		    B3Screen(childBase: B3ChildBase(token: base), childSub: B3ChildSub(token: sub))
		}
		""",
		// "One parameter, several types": the mock hands the one value it takes to every type that receives it.
		.b4: """
		func b4Expected(service: any B4Service) -> B4Screen {
		    B4Screen(service: service, child: B4Child(service: service, grandchild: B4Grandchild(service: service)))
		}
		""",
		// Dependency kinds table: a default-valued initializer parameter of the mocked type defaults to its original
		// default expression.
		.b5: """
		func b5Expected() -> B5Screen {
		    B5Screen(child: B5Child(), retries: 7)
		}
		""",
		// "Overriding dependencies": the entry replaces how the dependency is built, and its receivers read that build.
		.b6: """
		func b6Expected(child: B6Child) -> B6Screen {
		    B6Screen(child: child, other: B6Other(child: child))
		}
		""",
		// A nested `SafeDIMockConfiguration` has a field for each of the child's own `@Instantiated` dependencies.
		.b7: """
		func b7Expected() -> B7Screen {
		    B7Screen(mid: B7Mid(inner: B7Inner(left: B7Sentinel(), right: B7Leaf())))
		}
		""",
		// An `Instantiator` creates a new instance each time it is asked; an override replaces how each is built.
		.b8: """
		func b8Expected() -> B8Screen {
		    B8Screen(childBuilder: Instantiator<B8Child> { B8Sentinel() })
		}
		""",
		// "Lazily instantiated dependencies": the entry is a closure the mock calls the first time the instance is read.
		.b9: """
		func b9Expected() -> B9Screen {
		    B9Screen(child: LazilyInstantiated<B9Child> { B9Sentinel() })
		}
		""",
		// Dependency kinds table: `@Received(onlyIfAvailable: true)` is an optional entry whose default is `nil`.
		.b10: """
		func b10Expected(x: B10X?) -> B10Screen {
		    B10Screen(child: B10Child(x: x))
		}
		""",
		// "Dependency cycles": a type the cycle builds again is built with the entry of the nearest place above it that
		// builds the same type the same way, and so is everything built through it.
		.b11: """
		func b11Expected() -> B11Shell {
		    func screen() -> B11Screen {
		        B11Screen(leaf: B11Sentinel(), stepBuilder: Instantiator<B11Step> { B11Step(screenBuilder: Instantiator<B11Screen> { screen() }) })
		    }
		    func panelScreen() -> B11Screen {
		        B11Screen(leaf: B11PanelSentinel(), stepBuilder: Instantiator<B11Step> { B11Step(screenBuilder: Instantiator<B11Screen> { panelScreen() }) })
		    }
		    return B11Shell(screen: screen(), panel: B11Panel(screen: panelScreen()))
		}
		""",
		// "Conditionally receiving dependencies": a receiver gets the nearest declaration above it, and `nil` where
		// there is none; each mock builds its own type's tree.
		.b12: """
		func b12ExpectedA() -> B12ScreenA {
		    let x = B12X()
		    return B12ScreenA(x: x, leaf: B12Leaf(x: x))
		}

		func b12ExpectedB() -> B12ScreenB {
		    B12ScreenB(leaf: B12Leaf(x: nil))
		}
		""",
		// "Dependencies received only if available": the entry defaults to `nil`, `mock()` takes no parameter, and the
		// value the entry is given is handed over.
		.b13: """
		func b13Expected(x: B13X? = nil) -> B13Screen {
		    B13Screen(x: x, child: B13Child())
		}
		""",
		// "It has no entry of its own when the mock builds it anyway: … another type in the tree requires it."
		.b14: """
		func b14Expected() -> B14Screen {
		    let x = B14X()
		    return B14Screen(x: x, child: B14Child(x: x))
		}
		""",
		// "Names": the mock builds every form of `token` its tree receives; "Dependencies received only if available":
		// it passes `nil` to a receiver of `token: Token?` below a type that requires `token: Instantiator<Token>` from the
		// same declaration.
		.b15: """
		func b15Expected() -> B15Screen {
		    let token = B15Token()
		    let tokenBuilder = Instantiator<B15Token> { B15Token() }
		    return B15Screen(
		        reader: B15Reader(token: token),
		        leaf: B15Leaf(token: token),
		        source: B15Source(token: tokenBuilder, holder: B15Holder(leaf: B15Leaf(token: nil))),
		    )
		}
		""",
		// "LazilyInstantiated": a type that receives the instance and one that receives the wrapper yield the same
		// instance.
		.b16: """
		func b16Expected() -> B16Screen {
		    let x = LazilyInstantiated<B16X> { B16X() }
		    return B16Screen(wrapperReader: B16WrapperReader(x: x), valueReader: B16ValueReader(x: x.instance))
		}
		""",
		// "LazilyInstantiated": receiving the wrapper instantiates nothing until `instance` is read.
		.b17: """
		func b17Expected() -> B17Screen {
		    B17Screen(child: B17Child(x: LazilyInstantiated<B17X> { B17X() }))
		}
		""",
		// "Hand-written mocks": the generated mocks of types that instantiate the type call `Type.mock()`.
		.b18: """
		func b18Expected() -> B18Screen {
		    let child = B18Child()
		    child.madeBy = "mock"
		    return B18Screen(child: child)
		}
		""",
		// "Hand-written mocks": with `customMockName`, types that instantiate the type call the method it names.
		.b19: """
		func b19Expected() -> B19Screen {
		    let child = B19Child()
		    child.madeBy = "preview"
		    return B19Screen(child: child)
		}
		""",
		// "Splitting production and mock declarations": the production declaration builds the tree, the `mockOnly`
		// declaration's mock builds the type in mocks.
		.b20: """
		func b20Expected() -> B20Screen {
		    let service = B20Service()
		    service.madeBy = "mock"
		    return B20Screen(service: service)
		}

		func b20ExpectedRoot() -> B20Root {
		    B20Root(screen: B20Screen(service: B20Service()))
		}
		""",
		// "Dependencies built with fulfilledByType:": built as the type `fulfilledByType:` names, even when another type
		// lists the protocol in `fulfillingAdditionalTypes`.
		.b21: """
		func b21Expected() -> B21Screen {
		    B21Screen(service: B21Named())
		}
		""",
		// "Making protocols @Instantiable": the erased property is the eraser around the one concrete instance, which a
		// receiver beneath reads.
		.b22: """
		func b22Expected() -> B22Screen {
		    let service = B22AnyService(B22Concrete())
		    return B22Screen(service: service, child: B22Child(service: service))
		}
		""",
		// "Overriding dependencies": beneath a `Sendable` wrapper, a default-valued initializer parameter is evaluated each
		// time the mock builds the type, as production does.
		.b23: """
		func b23Expected() -> B23Screen {
		    B23Screen(childBuilder: SendableInstantiator<B23Child> { B23Child() })
		}
		""",
		// Each call builds one `settings`, with its default evaluated once for that build, read by both receivers.
		.b24: """
		func b24Expected() -> B24Screen {
		    B24Screen(childBuilder: SendableInstantiator<B24Child> {
		        let settings = B24Settings()
		        return B24Child(settings: settings, first: B24First(settings: settings), second: B24Second(settings: settings))
		    })
		}
		""",
		// "@Forwarded" and "@Received": a receiver reads the nearest declaration of its label above it; the child's
		// forwarded `id` is the value its `Instantiator` is called with.
		// "@Received": a receive reads the nearest declaration of its label, so the leaf beneath the holder reads the holder's
		// own token and the leaf beside the reader reads the token the mock builds for the reader.
		.b26: """
		func b26Expected() -> B26Screen {
		    let token = B26Token()
		    let holderToken = B26Token()
		    return B26Screen(reader: B26Reader(token: token), leaf: B26Leaf(token: token), holder: B26Holder(token: holderToken, leaf: B26Leaf(token: holderToken)))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (beside, override).
		.o1: """
		func o1Expected(x: O1X = O1X()) -> O1Screen {
		    O1Screen(c: O1C(x: x), svc: O1Svc(b: O1B(x: x)))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (beside, flat parameter).
		.o2: """
		func o2Expected(x: O2X) -> O2Screen {
		    O2Screen(c: O2C(x: x), svc: O2Svc(b: O2B(x: x)))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (above, override).
		.o3: """
		func o3Expected(x: O3X = O3X()) -> O3Screen {
		    O3Screen(c: O3C(x: x, svc: O3Svc(b: O3B(x: x))))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (above, flat parameter).
		.o4: """
		func o4Expected(x: O4X) -> O4Screen {
		    O4Screen(c: O4C(x: x, svc: O4Svc(b: O4B(x: x))))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (sendable, override).
		.o5: """
		func o5Expected(x: O5X = O5X()) -> O5Screen {
		    O5Screen(cBuilder: SendableInstantiator<O5C> { O5C(x: x) }, svc: O5Svc(b: O5B(x: x)))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (sendable, flat parameter).
		.o6: """
		func o6Expected(x: O6X) -> O6Screen {
		    O6Screen(cBuilder: SendableInstantiator<O6C> { O6C(x: x) }, svc: O6Svc(b: O6B(x: x)))
		}
		""",
		// "Using generated mocks": a value promoted for an optional receive is built once, non-optional, and every receiver of
		// its label reads that one instance, the optional receiver included (beside, override, LazilyInstantiated).
		.o7: """
		func o7Expected(x instance: O7X = O7X()) -> O7Screen {
		    let x = LazilyInstantiated<O7X> { instance }
		    return O7Screen(c: O7C(x: x.instance), svc: O7Svc(b: O7B(x: x)))
		}
		""",
		.b25: """
		func b25Expected(id: Int) -> B25Screen {
		    B25Screen(
		        id: id,
		        other: B25Other(id: id),
		        childBuilder: Instantiator<B25Child> { childID in B25Child(id: childID, grandchild: B25Grandchild(id: childID)) },
		    )
		}
		""",
	]
}
