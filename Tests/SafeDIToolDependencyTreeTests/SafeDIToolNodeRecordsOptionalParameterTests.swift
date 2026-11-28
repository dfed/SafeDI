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
/// it has none, off every cycle, laid out from node records (`OnlyIfAvailableAnswers`,
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

	@Test(arguments: ShapeLaidOut.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromRecordsAsTheTreeWritesIt_whenSeamInModuleAndOnlyOneCallerAnswersReadOnlyIfAvailable(shape: ShapeLaidOut) async throws {
		// A root of a module that holds a seam is laid out from its records where nothing in its world forces its tree
		// (`seamWorldRootLayout`): this root calls no seam, so its records lay it out, and the comparison approves the
		// optional parameter's difference only where the two texts are equal.
		let seam = """
		@Instantiable(generateDependencyTree: true)
		public struct Harbor: Instantiable {
		    public init(dock: Dock) {
		        self.dock = dock
		    }

		    @Instantiated let dock: Dock
		}

		@Instantiable
		public struct Dock: Instantiable {
		    public init() {}
		}
		"""
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		_ = try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(swiftFileContent: [shape.fixture, seam], buildSwiftOutputDirectory: true, filesToDelete: &filesMade)
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream where report.root == "Root" {
			reports.append(report)
		}
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.map(\.differences.isEmpty) == [false])
		#expect(reports.map { $0.comparedTexts.map { $0.tree == $0.nodeRecords } } == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWorldAsRefused_whenRootThatCannotBeLaidOutDiffersOnlyByOptionalParametersArguments() async throws {
		// `Leaf` is built by `A`, which builds a `mark` first, and by `B` and `Flow`, which build none, so one function with
		// an optional parameter serves its `widget`. `A`, `B` and `C` are a loop of builders, which keeps the root's tree
		// in a plain run, and the engine lays out no text of it to approve the difference against.
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		_ = try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(flow: Flow) {
					        self.flow = flow
					    }

					    @Instantiated let flow: Flow
					}

					@Instantiable
					public struct Flow: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, cBuilder: Instantiator<C>, leaf: Leaf) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					        self.cBuilder = cBuilder
					        self.leaf = leaf
					    }

					    @Instantiated let aBuilder: Instantiator<A>
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let cBuilder: Instantiator<C>
					    @Instantiated let leaf: Leaf
					}

					@Instantiable
					public struct A: Instantiable {
					    public init(mark: Mark, leaf: Leaf) {
					        self.mark = mark
					        self.leaf = leaf
					    }

					    @Instantiated let mark: Mark
					    @Instantiated let leaf: Leaf
					}

					@Instantiable
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>, leaf: Leaf) {
					        self.aBuilder = aBuilder
					        self.leaf = leaf
					    }

					    @Received let aBuilder: Instantiator<A>
					    @Instantiated let leaf: Leaf
					}

					@Instantiable
					public struct C: Instantiable {
					    public init(bBuilder: Instantiator<B>, id: Int) {
					        self.bBuilder = bBuilder
					        self.id = id
					    }

					    @Received let bBuilder: Instantiator<B>
					    @Forwarded let id: Int
					}

					@Instantiable
					public struct Leaf: Instantiable {
					    public init(cBuilder: Instantiator<C>, widget: Widget) {
					        self.cBuilder = cBuilder
					        self.widget = widget
					    }

					    @Received let cBuilder: Instantiator<C>
					    @Instantiated let widget: Widget
					}

					@Instantiable
					public struct Widget: Instantiable {
					    public init(mark: Mark?) {
					        self.mark = mark
					    }

					    @Received(onlyIfAvailable: true) let mark: Mark?
					}

					@Instantiable
					public final class Mark: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesMade,
			)
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		#expect(reports.map(\.root) == ["Root"])
		#expect(reports.map(\.refusal) == ["onlyIfAvailableAnsweredApart"])
		#expect(reports.map(\.everyRefusal) == [["onlyIfAvailableAnsweredApart"]])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [false])
		#expect(reports.map(\.differences) == [[]])
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

	// MARK: Shapes

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

		var fixture: String {
			switch self {
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
		/// `Leaf` builds itself again through `leafBuilder`, which `A` builds where nothing declares `session` and `B` where it does.
		case typeIsOnCycle
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
