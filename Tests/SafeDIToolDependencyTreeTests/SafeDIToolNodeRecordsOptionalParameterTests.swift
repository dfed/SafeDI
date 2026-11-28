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
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A production root one of whose types is built where a label it receives only if available has a declaration and where
/// it has none, on a cycle or off it, laid out from node records (`OnlyIfAvailableAnswers`,
/// `DeclarationsAnsweringReads`): the type's function takes the label as one optional parameter, and the call that finds
/// no declaration passes `nil`, as the tree writes it.
struct SafeDIToolNodeRecordsOptionalParameterTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToFunctionOfTypeBuiltTwice_whenOneCallerBuildsSessionAfterItAndAnotherBefore() async throws {
		// `Session` and `ViewModel` receive each other only if available, so `A` builds `session` first and `B` builds
		// `viewModel` first: one `__safeDI_viewModel`, which `B` passes `nil`, and whose `avatar` reads its parameter.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [Self.fixtureOfSessionBuiltBeforeAndAfter], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        func __safeDI_viewModel(session: Session?) -> ViewModel {
		            let avatar = Avatar(session: session)
		            return ViewModel(session: session, avatar: avatar)
		        }
		        func __safeDI_a() -> A {
		            let session = Session(viewModel: nil)
		            let viewModel: ViewModel = __safeDI_viewModel(session: session)
		            return A(viewModel: viewModel, session: session)
		        }
		        let a: A = __safeDI_a()
		        func __safeDI_b() -> B {
		            let viewModel: ViewModel = __safeDI_viewModel(session: nil)
		            let session = Session(viewModel: viewModel)
		            return B(session: session, viewModel: viewModel)
		        }
		        let b: B = __safeDI_b()
		        self.init(a: a, b: b)
		    }
		}
		""", "Unexpected output \(output.dependencyTreeFiles["Root+SafeDI.swift"] ?? "")")
	}

	@Test(arguments: ShapeLaidOut.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeWritesIt_whenOnlyOneCallerAnswersReadOnlyIfAvailable(shape: ShapeLaidOut) async throws {
		let treeOutput = try await executeSafeDIToolTest(swiftFileContent: [shape.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [shape.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		// The records read the declaration at the call the tree's place reads `nil` at, and the two write the same code.
		#expect(reports.map(\.differences.isEmpty) == [false])
		#expect(output.dependencyTreeFiles == treeOutput.dependencyTreeFiles)
	}

	@Test(arguments: 0..<6)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeWritesIt_whateverOrderCallersThatAnswerAndDoNotAreMetIn(rotation: Int) async throws {
		let fixture = Self.fixtureOfSixCallers(rotatedBy: rotation)
		let treeOutput = try await executeSafeDIToolTest(swiftFileContent: [fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.dependencyTreeFiles == treeOutput.dependencyTreeFiles)
	}

	@Test(arguments: [
		"root.a.viewModel: arguments is [] in the tree, [] by node records",
		"root.a.viewModel: callCycleArguments is [] in the tree, [] by node records",
	])
	func outcome_failsRootsDifferences_whenItsTextsAreEqualAndADifferenceIsNoOptionalParameters(difference: String) {
		// Beside a difference the optional parameter makes, any other difference of the arguments or of another field fails
		// the root, though its two texts are equal.
		var report = NodeRecordsReport(root: "Root", refusal: nil, everyRefusal: [], isLaidOutFromNodeRecords: true, differences: ["root.b.viewModel: arguments of an optional parameter is [] in the tree, [] by node records", difference], recordCount: 2, treePlaceCount: 2, treeForcers: [])
		report.comparedTexts = NodeRecordsComparedTexts(tree: "text", nodeRecords: "text")
		let outcome = NodeRecordsChecks.outcome(of: report)
		#expect(outcome.differences == report.differences)
		#expect(outcome.approvedEntries == [])
	}

	@Test
	func outcome_failsNoDifference_whenItsTextsAreEqualAndEveryDifferenceIsAnOptionalParameters() {
		var report = NodeRecordsReport(root: "Root", refusal: nil, everyRefusal: [], isLaidOutFromNodeRecords: true, differences: ["root.b.viewModel: arguments of an optional parameter is [] in the tree, [] by node records"], recordCount: 2, treePlaceCount: 2, treeForcers: [])
		report.comparedTexts = NodeRecordsComparedTexts(tree: "text", nodeRecords: "text")
		let outcome = NodeRecordsChecks.outcome(of: report)
		#expect(outcome.differences == [])
		#expect(outcome.approvedEntries == [])
	}

	/// What the records read where the tree reads `nil` of `mark`, with whether the comparison names the difference an
	/// optional parameter's.
	enum RecordsArguments: CaseIterable {
		case theSame
		case declarationOfTheLabel
		case declarationOfAnotherLabel
		case lazyInstanceOfTheLabel
		case anotherArgumentLabel
		case oneArgumentMore
		case noArgument

		var isOfAnOptionalParameter: Bool {
			switch self {
			case .theSame, .declarationOfTheLabel:
				true
			case .declarationOfAnotherLabel, .lazyInstanceOfTheLabel, .anotherArgumentLabel, .oneArgumentMore, .noArgument:
				false
			}
		}
	}

	@Test(arguments: RecordsArguments.allCases)
	func differOnlyWhereTreeReadsNilOfLabel_namesOnlyTheDeclarationOfTheLabelReadWhereTheTreeReadsNil(recordsArguments: RecordsArguments) {
		let property = Property(label: "mark", typeDescription: .optional(.simple(name: "Mark")))
		let unchanged = PlaceRead(argumentLabel: "name", label: "name", property: Property(label: "name", typeDescription: .simple(name: "Name")), source: .binding(label: "name"))
		let tree = [unchanged, PlaceRead(argumentLabel: "mark", label: "mark", property: property, source: .nil)]
		let nodeRecords: [PlaceRead] = switch recordsArguments {
		case .theSame:
			tree
		case .declarationOfTheLabel:
			[unchanged, PlaceRead(argumentLabel: "mark", label: "mark", property: property, source: .binding(label: "mark"))]
		case .declarationOfAnotherLabel:
			[unchanged, PlaceRead(argumentLabel: "mark", label: "mark", property: property, source: .binding(label: "name"))]
		case .lazyInstanceOfTheLabel:
			[unchanged, PlaceRead(argumentLabel: "mark", label: "mark", property: property, source: .lazyInstance(label: "mark", throughOptional: false))]
		case .anotherArgumentLabel:
			[unchanged, PlaceRead(argumentLabel: "other", label: "mark", property: property, source: .binding(label: "mark"))]
		case .oneArgumentMore:
			tree + [PlaceRead(argumentLabel: "mark", label: "mark", property: property, source: .binding(label: "mark"))]
		case .noArgument:
			[]
		}
		#expect(NodeRecordsObservation.differOnlyWhereTreeReadsNilOfLabel(tree, nodeRecords) == recordsArguments.isOfAnOptionalParameter)
	}

	@Test(arguments: ShapeRefused.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesWorldAsOnlyIfAvailableAnsweredApart_whenOneOptionalParameterCannotServeEveryCall(shape: ShapeRefused) async throws {
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [shape.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == ["onlyIfAvailableAnsweredApart"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesWorldAsCycleVariantsPartitionApart_whenCycleMemberReceivesLabelOnlyOneCallerAnswers() async throws {
		// `Leaf` receives `session` only if available and builds itself again through `leafBuilder`, so its function would
		// take `session` as a cycle parameter, which `A`'s call passes `nil` and `B`'s call its `session`. Its variant
		// holds an optional parameter's key, so the world is refused, and the tree writes the root.
		let treeOutput = try await executeSafeDIToolTest(swiftFileContent: [Self.fixtureOfCycleMemberReadingSession], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [Self.fixtureOfCycleMemberReadingSession], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == ["cycleVariantsPartitionApart"])
		#expect(output.dependencyTreeFiles == treeOutput.dependencyTreeFiles)
	}

	@Test(arguments: LazyWrapperAnsweredApart.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenALazyWrapperOneCallOfAVariantAnswersIsReadInsideASendableFunction(shape: LazyWrapperAnsweredApart) async {
		// `T0` is built through the `SendableErasedInstantiator` `T4` receives, so before the wrapper, where its read only if
		// available is answered `nil`, and through a second builder declared before the wrapper, where it is answered. One
		// variant for both calls would capture the wrapper inside the `@Sendable` function that builds `T1`, which no check
		// of the records sees: the records refuse the world (`onlyIfAvailableAnsweredApart`), and the tree reports the
		// capture.
		await assertThrowsError(diagnostics: { fixtures in shape.expectedDiagnostics(fixtures) }) {
			try await executeSafeDIToolTest(swiftFileContent: [shape.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Shapes

	/// `A` builds `Leaf` where nothing declares `session`, and `B` where it does; `Leaf` receives it and is on a cycle.
	private static let fixtureOfCycleMemberReadingSession =
		"""
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let a: A
		    @Instantiated let b: B
		    public init(a: A, b: B) { self.a = a; self.b = b }
		}
		@Instantiable public final class A: Instantiable {
		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
		}
		@Instantiable public final class B: Instantiable {
		    @Instantiated let session: Session
		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    public init(session: Session, leafBuilder: Instantiator<Leaf>) { self.session = session; self.leafBuilder = leafBuilder }
		}
		@Instantiable public final class Leaf: Instantiable {
		    @Received(onlyIfAvailable: true) let session: Session?
		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    public init(session: Session?, leafBuilder: Instantiator<Leaf>) { self.session = session; self.leafBuilder = leafBuilder }
		}
		@Instantiable public final class Session: Instantiable {
		    public init() {}
		}
		"""

	enum ShapeLaidOut: CaseIterable {
		/// `A` declares no `session`, and `B` builds one before its `viewModel`.
		case callerDeclaresNothing
		/// The type is built through an `Instantiator`, with a forwarded argument.
		case builtThroughInstantiator
		/// The type is built through a `LazilyInstantiated`.
		case builtThroughLazilyInstantiated
		/// `A` forwards `session`, and `B` declares none.
		case answerIsForwarded
		/// `A` forwards an optional `session`, and `B` declares none.
		case answerIsForwardedOptional
		/// `A` and `B` each build two types that read `session`, which only `B` declares.
		case twoTypesInOneBody
		/// `Leaf` builds itself again through `leafBuilder`, which `A` builds where nothing declares `session` and `B` where it does.
		case typeIsOnCycle

		var fixture: String {
			switch self {
			case .typeIsOnCycle:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let a: A
				    @Instantiated let b: B
				    @Instantiated let reader: Reader
				    public init(a: A, b: B, reader: Reader) { self.a = a; self.b = b; self.reader = reader }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    public init(session: Session, leafBuilder: Instantiator<Leaf>) { self.session = session; self.leafBuilder = leafBuilder }
				}
				@Instantiable public final class Leaf: Instantiable {
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				@Instantiable public final class Reader: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				"""
			case .callerDeclaresNothing:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let a: A
				    @Instantiated let b: B
				    public init(a: A, b: B) { self.a = a; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let viewModel: ViewModel
				    public init(viewModel: ViewModel) { self.viewModel = viewModel }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let viewModel: ViewModel
				    public init(session: Session, viewModel: ViewModel) { self.session = session; self.viewModel = viewModel }
				}
				@Instantiable public final class ViewModel: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			case .builtThroughInstantiator:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let a: A
				    @Instantiated let b: B
				    public init(a: A, b: B) { self.a = a; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    public init(session: Session, screenBuilder: Instantiator<Screen>) { self.session = session; self.screenBuilder = screenBuilder }
				}
				@Instantiable public final class Screen: Instantiable {
				    @Forwarded let title: String
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(title: String, session: Session?, avatar: Avatar) { self.title = title; self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Received let title: String
				    public init(session: Session?, title: String) { self.session = session; self.title = title }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			case .builtThroughLazilyInstantiated:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let a: A
				    @Instantiated let b: B
				    public init(a: A, b: B) { self.a = a; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let formatter: LazilyInstantiated<Formatter>
				    public init(formatter: LazilyInstantiated<Formatter>) { self.formatter = formatter }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let formatter: LazilyInstantiated<Formatter>
				    public init(session: Session, formatter: LazilyInstantiated<Formatter>) { self.session = session; self.formatter = formatter }
				}
				@Instantiable public final class Formatter: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			case .answerIsForwarded:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let b: B
				    public init(aBuilder: Instantiator<A>, b: B) { self.aBuilder = aBuilder; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Forwarded let session: Session
				    @Instantiated let viewModel: ViewModel
				    public init(session: Session, viewModel: ViewModel) { self.session = session; self.viewModel = viewModel }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let viewModel: ViewModel
				    public init(viewModel: ViewModel) { self.viewModel = viewModel }
				}
				@Instantiable public final class ViewModel: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			case .answerIsForwardedOptional:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let b: B
				    public init(aBuilder: Instantiator<A>, b: B) { self.aBuilder = aBuilder; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Forwarded let session: Session?
				    @Instantiated let viewModel: ViewModel
				    public init(session: Session?, viewModel: ViewModel) { self.session = session; self.viewModel = viewModel }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let viewModel: ViewModel
				    public init(viewModel: ViewModel) { self.viewModel = viewModel }
				}
				@Instantiable public final class ViewModel: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			case .twoTypesInOneBody:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let a: A
				    @Instantiated let b: B
				    public init(a: A, b: B) { self.a = a; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let viewModel: ViewModel
				    @Instantiated let footer: Footer
				    public init(viewModel: ViewModel, footer: Footer) { self.viewModel = viewModel; self.footer = footer }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let footer: Footer
				    @Instantiated let viewModel: ViewModel
				    public init(session: Session, footer: Footer, viewModel: ViewModel) { self.session = session; self.footer = footer; self.viewModel = viewModel }
				}
				@Instantiable public final class Footer: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class ViewModel: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let avatar: Avatar
				    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			}
		}
	}

	enum ShapeRefused: CaseIterable {
		/// `Avatar` is built inside the root's `session`, which nothing answers; inside `A`'s `session`, whose being built hides
		/// the root's; and inside `B`, which reads the root's. One function taking the root's would be handed it inside `A` too.
		case declarationAboveIsHidden
		/// `Holder` renames `session` only if available, which only `B` declares: the rename is one statement, bound to `nil` or not.
		case labelFulfillsRename

		var fixture: String {
			switch self {
			case .declarationAboveIsHidden:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let a: A
				    @Instantiated let b: B
				    public init(session: Session, a: A, b: B) { self.session = session; self.a = a; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let session: Session
				    public init(session: Session) { self.session = session }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let avatar: Avatar
				    public init(avatar: Avatar) { self.avatar = avatar }
				}
				@Instantiable public final class Session: Instantiable {
				    @Instantiated let avatar: Avatar
				    public init(avatar: Avatar) { self.avatar = avatar }
				}
				@Instantiable public final class Avatar: Instantiable {
				    @Received(onlyIfAvailable: true) let session: Session?
				    public init(session: Session?) { self.session = session }
				}
				"""
			case .labelFulfillsRename:
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let a: A
				    @Instantiated let b: B
				    public init(a: A, b: B) { self.a = a; self.b = b }
				}
				@Instantiable public final class A: Instantiable {
				    @Instantiated let viewModel: Holder
				    public init(viewModel: Holder) { self.viewModel = viewModel }
				}
				@Instantiable public final class B: Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let viewModel: Holder
				    public init(session: Session, viewModel: Holder) { self.session = session; self.viewModel = viewModel }
				}
				@Instantiable public final class Holder: Instantiable {
				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self, onlyIfAvailable: true) let renamed: Session?
				    @Instantiated let reader: Reader
				    public init(renamed: Session?, reader: Reader) { self.renamed = renamed; self.reader = reader }
				}
				@Instantiable public final class Reader: Instantiable {
				    @Received(onlyIfAvailable: true) let renamed: Session?
				    public init(renamed: Session?) { self.renamed = renamed }
				}
				@Instantiable public final class Session: Instantiable {
				    public init() {}
				}
				"""
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let fixtureOfSessionBuiltBeforeAndAfter = """
	@Instantiable(isRoot: true) public final class Root: Instantiable {
	    @Instantiated let a: A
	    @Instantiated let b: B
	    public init(a: A, b: B) { self.a = a; self.b = b }
	}
	@Instantiable public final class A: Instantiable {
	    @Instantiated let viewModel: ViewModel
	    @Instantiated let session: Session
	    public init(viewModel: ViewModel, session: Session) { self.viewModel = viewModel; self.session = session }
	}
	@Instantiable public final class B: Instantiable {
	    @Instantiated let session: Session
	    @Instantiated let viewModel: ViewModel
	    public init(session: Session, viewModel: ViewModel) { self.session = session; self.viewModel = viewModel }
	}
	@Instantiable public final class ViewModel: Instantiable {
	    @Received(onlyIfAvailable: true) let session: Session?
	    @Instantiated let avatar: Avatar
	    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
	}
	@Instantiable public final class Avatar: Instantiable {
	    @Received(onlyIfAvailable: true) let session: Session?
	    public init(session: Session?) { self.session = session }
	}
	@Instantiable public final class Session: Instantiable {
	    @Received(onlyIfAvailable: true) let viewModel: ViewModel?
	    public init(viewModel: ViewModel?) { self.viewModel = viewModel }
	}
	"""

	/// A root of six children, the odd ones building `session` before their `viewModel` and the even ones building only
	/// `viewModel`, declared in the order `rotation` turns them to, so that the call that answers is met first, last and
	/// between.
	private static func fixtureOfSixCallers(rotatedBy rotation: Int) -> String {
		let indices = (0..<6).map { ($0 + rotation) % 6 }
		let callers = indices.map { index in
			index.isMultiple(of: 2)
				? """
				@Instantiable public final class Caller\(index): Instantiable {
				    @Instantiated let viewModel: ViewModel
				    public init(viewModel: ViewModel) { self.viewModel = viewModel }
				}
				"""
				: """
				@Instantiable public final class Caller\(index): Instantiable {
				    @Instantiated let session: Session
				    @Instantiated let viewModel: ViewModel
				    public init(session: Session, viewModel: ViewModel) { self.session = session; self.viewModel = viewModel }
				}
				"""
		}
		return """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		\(indices.map { "    @Instantiated let caller\($0): Caller\($0)" }.joined(separator: "\n"))
		    public init(\(indices.map { "caller\($0): Caller\($0)" }.joined(separator: ", "))) { \(indices.map { "self.caller\($0) = caller\($0)" }.joined(separator: "; ")) }
		}
		\(callers.joined(separator: "\n"))
		@Instantiable public final class ViewModel: Instantiable {
		    @Received(onlyIfAvailable: true) let session: Session?
		    @Instantiated let avatar: Avatar
		    public init(session: Session?, avatar: Avatar) { self.session = session; self.avatar = avatar }
		}
		@Instantiable public final class Avatar: Instantiable {
		    @Received(onlyIfAvailable: true) let session: Session?
		    public init(session: Session?) { self.session = session }
		}
		@Instantiable public final class Session: Instantiable {
		    public init() {}
		}
		"""
	}

	/// A graph of the seed-580 draw: a `LazilyInstantiated` value one call of `T0` is handed and another is not, read only
	/// if available inside a `@Sendable` function.
	struct LazyWrapperAnsweredApart: Sendable, CustomTestStringConvertible {
		enum SecondBuilder: CaseIterable {
			case instantiator
			case erasedInstantiator
			case constant
		}

		/// Whether `T0` builds `T1` through a `SendableErasedInstantiator`, else a `SendableInstantiator`.
		let buildsErasedReader: Bool
		/// Whether the root declares the second builder before the wrapper, else after it.
		let declaresSecondBuilderFirst: Bool
		let secondBuilder: SecondBuilder
		/// Whether `T2`, beneath `T1`, reads the wrapper, else `T1` itself.
		let readsTwoLevelsDown: Bool

		static let allCases: [Self] = [false, true].flatMap { buildsErasedReader in
			[false, true].flatMap { declaresSecondBuilderFirst in
				SecondBuilder.allCases.flatMap { secondBuilder in
					[false, true].map { Self(buildsErasedReader: buildsErasedReader, declaresSecondBuilderFirst: declaresSecondBuilderFirst, secondBuilder: secondBuilder, readsTwoLevelsDown: $0) }
				}
			}
		}

		var testDescription: String {
			"\(buildsErasedReader ? "erased" : "plain") reader, \(declaresSecondBuilderFirst ? "second builder first" : "wrapper first"), \(secondBuilder), \(readsTwoLevelsDown ? "two levels down" : "one level down")"
		}

		var fixture: String {
			let wrapper = (label: "lazyT4", type: "LazilyInstantiated<T4>", attribute: "@Instantiated")
			let builder = (label: "anyT0Builder", type: "SendableErasedInstantiator<(), AnyT0>", attribute: #"@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true)"#)
			let second = switch secondBuilder {
			case .instantiator:
				(label: "t0Builder", type: "Instantiator<T0>", attribute: "@Instantiated")
			case .erasedInstantiator:
				(label: "anyT0BuilderB", type: "ErasedInstantiator<(), AnyT0>", attribute: #"@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true)"#)
			case .constant:
				(label: "t0", type: "T0", attribute: "@Instantiated")
			}
			let properties = declaresSecondBuilderFirst ? [second, wrapper, builder] : [wrapper, second, builder]
			let readerBuilder = buildsErasedReader
				? (label: "anyT1Builder", type: "SendableErasedInstantiator<(), AnyT1>", attribute: #"@Instantiated(fulfilledByType: "T1", erasedToConcreteExistential: true)"#)
				: (label: "t1Builder", type: "SendableInstantiator<T1>", attribute: "@Instantiated")
			let reader = """
				public init(lazyT4: LazilyInstantiated<T4>?) { self.lazyT4 = lazyT4 }
				@Received(onlyIfAvailable: true) let lazyT4: LazilyInstantiated<T4>?
			"""
			let readers = readsTwoLevelsDown
				? """
				@Instantiable
				public final class T1: Instantiable, @unchecked Sendable {
					public init(t2: T2) { self.t2 = t2 }
					@Instantiated let t2: T2
				}
				@Instantiable
				public final class T2: Instantiable, @unchecked Sendable {
				\(reader)
				}
				"""
				: """
				@Instantiable
				public final class T1: Instantiable, @unchecked Sendable {
				\(reader)
				}
				"""
			return """
			import SafeDI

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
				public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			\(properties.map { "\t\tself.\($0.label) = \($0.label)" }.joined(separator: "\n"))
				}
			\(properties.map { "\t\($0.attribute) let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}
			@Instantiable
			public final class T0: Instantiable, @unchecked Sendable {
				public init(\(readerBuilder.label): \(readerBuilder.type)) { self.\(readerBuilder.label) = \(readerBuilder.label) }
				\(readerBuilder.attribute) let \(readerBuilder.label): \(readerBuilder.type)
			}
			public final class AnyT0: Sendable {
				public init(_ value: T0) { self.value = value }
				public let value: T0
			}
			\(readers)
			public final class AnyT1: Sendable {
				public init(_ value: T1) { self.value = value }
				public let value: T1
			}
			@Instantiable
			public final class T4: Instantiable, @unchecked Sendable {
				public init(anyT0Builder: SendableErasedInstantiator<(), AnyT0>) { self.anyT0Builder = anyT0Builder }
				@Received let anyT0Builder: SendableErasedInstantiator<(), AnyT0>
			}
			"""
		}

		func expectedDiagnostics(_ fixtures: FixturePaths) -> String {
			let readerBuilder = buildsErasedReader ? "anyT1Builder: SendableErasedInstantiator<(), AnyT1>" : "t1Builder: SendableInstantiator<T1>"
			return """
			\(fixtures["Root.swift"]):\(readsTwoLevelsDown ? 31 : 26):2: error: @Received property `lazyT4: LazilyInstantiated<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> T0 -> T1\(readsTwoLevelsDown ? " -> T2" : ""). SafeDI builds `\(readerBuilder)` on `T0` in a `@Sendable` function, which cannot capture `lazyT4: LazilyInstantiated<T4>` on `Root`, because `LazilyInstantiated<T4>` is not `Sendable`. Declare `lazyT4` on `Root`, and this property, as `SendableLazilyInstantiated<T4>` to fix. A `SendableLazilyInstantiated` requires its instance type, `T4`, to be `Sendable`.
			\(fixtures["Root.swift"]):\(declaresSecondBuilderFirst ? 11 : 10):2: note: `lazyT4: LazilyInstantiated<T4>` is declared here
			"""
		}
	}

	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}
}
