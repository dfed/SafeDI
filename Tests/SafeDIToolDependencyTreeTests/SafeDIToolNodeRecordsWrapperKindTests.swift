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

/// Node records (`NodeRecords`) of the kinds a wrapper or an erasure makes: a `SendableInstantiator`, an erased constant
/// or instantiator, and a `LazilyInstantiated` or `SendableLazilyInstantiated` property with the receivers that read its
/// instance. Each test compares the whole file with what the tree's places wrote, with its root laid out from the
/// records and nothing that makes the run build the root's tree (`TreeForcer`) wherever the records accept its world;
/// the last shows that a world whose `@Sendable` function captures a wrapper keeps the tree's error.
struct SafeDIToolNodeRecordsWrapperKindTests: ~Copyable {
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
	mutating func generate_laysOutRootFromNodeRecords_whenItBuildsASendableInstantiator() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let shared: Shared", "@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
				seamFixtureType(named: "Shared", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Screen", declarations: ["@Forwarded let id: Int", "@Received let shared: Shared", "@Instantiated let model: Model"]),
				seamFixtureType(named: "Model", declarations: ["@Received let id: Int", "@Received let shared: Shared"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let shared = Shared()
			        @Sendable nonisolated func __safeDI_screenBuilder(id: Int) -> Screen {
			            let model = Model(id: id, shared: shared)
			            return Screen(id: id, shared: shared, model: model)
			        }
			        let screenBuilder = SendableInstantiator<Screen> {
			            __safeDI_screenBuilder(id: $0)
			        }
			        self.init(shared: shared, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenItBuildsErasedConstantsAndErasedInstantiators() async throws {
		// An erased constant built in place, one with a child, and both erased instantiators, which forward the panel's ID.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: [
					"@Instantiated(fulfilledByType: \"DefaultLogger\", erasedToConcreteExistential: true) let logger: AnyLogger",
					"@Instantiated(fulfilledByType: \"DefaultService\", erasedToConcreteExistential: true) let service: AnyService",
					"@Instantiated(fulfilledByType: \"DefaultPanel\", erasedToConcreteExistential: true) let panelBuilder: ErasedInstantiator<Int, AnyPanel>",
					"@Instantiated(fulfilledByType: \"DefaultPanel\", erasedToConcreteExistential: true) let sendablePanelBuilder: SendableErasedInstantiator<Int, AnyPanel>",
				]),
				"""
				public protocol Logger: Sendable {}

				public struct AnyLogger: Sendable {
				    public init(_ logger: some Logger) {}
				}

				""" + seamFixtureType(named: "DefaultLogger", declarations: [], conformances: ", Logger"),
				"""
				public protocol Service {}

				public struct AnyService {
				    public init(_ service: some Service) {}
				}

				""" + seamFixtureType(named: "DefaultService", declarations: ["@Instantiated let cache: Cache"], conformances: ", Service"),
				seamFixtureType(named: "Cache", declarations: []),
				"""
				public protocol Panel: Sendable {}

				public struct AnyPanel: Sendable {
				    public init(_ panel: some Panel) {}
				}

				""" + seamFixtureType(named: "DefaultPanel", declarations: ["@Forwarded let id: Int", "@Instantiated let row: Row"], conformances: ", Panel"),
				seamFixtureType(named: "Row", declarations: ["@Received let id: Int"], conformances: ", Sendable"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let logger = AnyLogger(DefaultLogger())
			        func __safeDI_service() -> DefaultService {
			            let cache = Cache()
			            return DefaultService(cache: cache)
			        }
			        let service = AnyService(__safeDI_service())
			        func __safeDI_panelBuilder(id: Int) -> DefaultPanel {
			            let row = Row(id: id)
			            return DefaultPanel(id: id, row: row)
			        }
			        let panelBuilder = ErasedInstantiator<Int, AnyPanel> {
			            AnyPanel(__safeDI_panelBuilder(id: $0))
			        }
			        @Sendable nonisolated func __safeDI_sendablePanelBuilder(id: Int) -> DefaultPanel {
			            let row = Row(id: id)
			            return DefaultPanel(id: id, row: row)
			        }
			        let sendablePanelBuilder = SendableErasedInstantiator<Int, AnyPanel> {
			            AnyPanel(__safeDI_sendablePanelBuilder(id: $0))
			        }
			        self.init(logger: logger, service: service, panelBuilder: panelBuilder, sendablePanelBuilder: sendablePanelBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheWrappersInstance_whenTypesBeneathALazilyInstantiatedPropertyReceiveItsValue() async throws {
		// `Reader` and its `Detail` receive the session by value beneath the root's wrapper, so each reads its instance;
		// `Holder` receives the wrapper itself; `Flow` declares a session of its own, by value, which its `Step` reads as it
		// is; and the erased service is a wrapper around the erasure of what its function builds.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: [
					"@Instantiated let session: LazilyInstantiated<Session>",
					"@Instantiated(fulfilledByType: \"DefaultService\", erasedToConcreteExistential: true) let service: LazilyInstantiated<AnyService>",
					"@Instantiated let reader: Reader",
					"@Instantiated let holder: Holder",
					"@Instantiated let flow: Flow",
				]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				"""
				public protocol Service {}

				public struct AnyService {
				    public init(_ service: some Service) {}
				}

				""" + seamFixtureType(named: "DefaultService", declarations: ["@Received let session: Session"], conformances: ", Service"),
				seamFixtureType(named: "Reader", declarations: ["@Received let session: Session", "@Instantiated let detail: Detail"]),
				seamFixtureType(named: "Detail", declarations: ["@Received let session: Session"]),
				seamFixtureType(named: "Holder", declarations: ["@Received let session: LazilyInstantiated<Session>"]),
				seamFixtureType(named: "Flow", declarations: ["@Instantiated let session: Session", "@Instantiated let step: Step"]),
				seamFixtureType(named: "Step", declarations: ["@Received let session: Session"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_session() -> Session {
			            Session()
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        func __safeDI_service() -> DefaultService {
			            DefaultService(session: session.instance)
			        }
			        let service = LazilyInstantiated<AnyService> {
			            AnyService(__safeDI_service())
			        }
			        func __safeDI_reader() -> Reader {
			            let detail = Detail(session: session.instance)
			            return Reader(session: session.instance, detail: detail)
			        }
			        let reader: Reader = __safeDI_reader()
			        let holder = Holder(session: session)
			        func __safeDI_flow() -> Flow {
			            let session = Session()
			            let step = Step(session: session)
			            return Flow(session: session, step: step)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(session: session, service: service, reader: reader, holder: holder, flow: flow)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheWrappersInstanceInsideASendableFunction_whenASendableInstantiatorsTypeReceivesTheValue() async throws {
		// The worker's `@Sendable` builder function captures the `Sendable` wrapper and reads its instance where it builds
		// the worker; the screen forwards a wrapper of its own, whose instance its model reads.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: [
					"@Instantiated let session: SendableLazilyInstantiated<Session>",
					"@Instantiated let workerBuilder: SendableInstantiator<Worker>",
					"@Instantiated let screenBuilder: Instantiator<Screen>",
				]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Worker", declarations: ["@Received let session: Session"]),
				seamFixtureType(named: "Screen", declarations: ["@Forwarded let draft: LazilyInstantiated<Draft>", "@Instantiated let model: Model"]),
				seamFixtureType(named: "Draft", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Model", declarations: ["@Received let draft: Draft", "@Received let session: Session"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_session() -> Session {
			            Session()
			        }
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
			            Worker(session: session.instance)
			        }
			        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
			        func __safeDI_screenBuilder(draft: LazilyInstantiated<Draft>) -> Screen {
			            let model = Model(draft: draft.instance, session: session.instance)
			            return Screen(draft: draft, model: model)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(draft: $0)
			        }
			        self.init(session: session, workerBuilder: workerBuilder, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheForwardedWrappersInstance_whenTypesBeneathTheTypeThatForwardsItReceiveItsValue() async throws {
		// `Editor` forwards the wrapper, so no node of the world is a lazy one: its `Toolbar` and that type's `Button` read
		// the instance of the wrapper their builder function is handed, its `Preview` receives the wrapper itself, and its
		// `Panel` reads the instance inside a builder function of its own, which is handed the wrapper too.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let editorBuilder: Instantiator<Editor>"]),
				seamFixtureType(named: "Editor", declarations: [
					"@Forwarded let draft: LazilyInstantiated<Draft>",
					"@Instantiated let toolbar: Toolbar",
					"@Instantiated let preview: Preview",
					"@Instantiated let panelBuilder: Instantiator<Panel>",
				]),
				seamFixtureType(named: "Draft", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Toolbar", declarations: ["@Received let draft: Draft", "@Instantiated let button: Button"]),
				seamFixtureType(named: "Button", declarations: ["@Received let draft: Draft"]),
				seamFixtureType(named: "Preview", declarations: ["@Received let draft: LazilyInstantiated<Draft>"]),
				seamFixtureType(named: "Panel", declarations: ["@Received let draft: Draft"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_toolbar(draft: LazilyInstantiated<Draft>) -> Toolbar {
			            let button = Button(draft: draft.instance)
			            return Toolbar(draft: draft.instance, button: button)
			        }
			        func __safeDI_panelBuilder(draft: LazilyInstantiated<Draft>) -> Panel {
			            Panel(draft: draft.instance)
			        }
			        func __safeDI_editorBuilder(draft: LazilyInstantiated<Draft>) -> Editor {
			            let toolbar: Toolbar = __safeDI_toolbar(draft: draft)
			            let preview = Preview(draft: draft)
			            let panelBuilder = Instantiator<Panel> {
			                __safeDI_panelBuilder(draft: draft)
			            }
			            return Editor(draft: draft, toolbar: toolbar, preview: preview, panelBuilder: panelBuilder)
			        }
			        let editorBuilder = Instantiator<Editor> {
			            __safeDI_editorBuilder(draft: $0)
			        }
			        self.init(editorBuilder: editorBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTheWrapperBeforeItsReader_whenTheReaderIsDeclaredFirst() async throws {
		// A type that receives a wrapper's value waits for the wrapper, as it would wait for the value.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let reader: Reader", "@Instantiated let session: LazilyInstantiated<Session>"]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Reader", declarations: ["@Received let session: Session"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_session() -> Session {
			            Session()
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        let reader = Reader(session: session.instance)
			        self.init(reader: reader, session: session)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheWrappersInstance_whenATypeBeneathItReceivesTheValueOnlyIfAvailable() async throws {
		// The wrapper is the nearest declaration of `session`, so a receive only if available of the value is handed its
		// instance, as a required one is.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let session: Session?"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_session() -> Session {
			            Session()
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        let reader = Reader(session: session.instance)
			        self.init(session: session, reader: reader)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsTheRenameFromTheWrappersInstance_whenARenameIsFulfilledByALazilyInstantiatedProperty() async throws {
		// `Reader` receives `session` as `store`, and the nearest declaration of `session` is a wrapper, so the rename is
		// bound from its instance. A rename's record binds from the label alone, so this root is written from its tree.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				"""
				@Instantiable
				public struct Reader: Instantiable {
				    public init(store: Session) {
				        self.store = store
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self) let store: Session
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_session() -> Session {
			            Session()
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        func __safeDI_reader() -> Reader {
			            let store: Session = session.instance // Declared as Reader.store
			            return Reader(store: store)
			        }
			        let reader: Reader = __safeDI_reader()
			        self.init(session: session, reader: reader)
			    }
			}
			""",
		])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsEachPlacesOwnDeclaration_whenOneTypeIsBuiltBeneathAWrapperAndBeneathAValue() async throws {
		// `Reader` is one node built at two places: beneath `Lazy`'s wrapper, whose instance it reads, and beneath `Eager`'s
		// value, which it reads as it is. Its two bodies are two variants of the node, so one record cannot stand for both.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let lazy: Lazy", "@Instantiated let eager: Eager"]),
				seamFixtureType(named: "Lazy", declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Eager", declarations: ["@Instantiated let session: Session", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Reader", declarations: ["@Received let session: Session"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_session() -> Session {
			            Session()
			        }
			        func __safeDI_lazy() -> Lazy {
			            let session = LazilyInstantiated<Session>(__safeDI_session)
			            let reader = Reader(session: session.instance)
			            return Lazy(session: session, reader: reader)
			        }
			        let lazy: Lazy = __safeDI_lazy()
			        func __safeDI_eager() -> Eager {
			            let session = Session()
			            let reader = Reader(session: session)
			            return Eager(session: session, reader: reader)
			        }
			        let eager: Eager = __safeDI_eager()
			        self.init(lazy: lazy, eager: eager)
			    }
			}
			""",
		])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenEachInstantiatorIsReadInTheFunctionThatDeclaresIt() async throws {
		// A `@Sendable` function captures no wrapper here: `rowBuilder` is declared inside the function that reads it, which
		// names only the function that builds a row, laid out once beside it, and `footerBuilder` is read outside every
		// `@Sendable` function. A world in which one would capture a wrapper keeps its tree, which reports the error
		// (`SafeDIToolCodeGenerationErrorTests`' `…DeclaredOutsideIt` tests).
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: [
					"@Instantiated let screenBuilder: SendableInstantiator<Screen>",
					"@Instantiated let footerBuilder: Instantiator<Footer>",
					"@Instantiated let header: Header",
				]),
				seamFixtureType(named: "Screen", declarations: ["@Instantiated let rowBuilder: Instantiator<Row>", "@Instantiated let list: List"]),
				seamFixtureType(named: "List", declarations: ["@Received let rowBuilder: Instantiator<Row>"]),
				seamFixtureType(named: "Row", declarations: []),
				seamFixtureType(named: "Header", declarations: ["@Received let footerBuilder: Instantiator<Footer>"]),
				seamFixtureType(named: "Footer", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_rowBuilder() -> Row {
			            Row()
			        }
			        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            let rowBuilder = Instantiator<Row>(__safeDI_rowBuilder)
			            let list = List(rowBuilder: rowBuilder)
			            return Screen(rowBuilder: rowBuilder, list: list)
			        }
			        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			        func __safeDI_footerBuilder() -> Footer {
			            Footer()
			        }
			        let footerBuilder = Instantiator<Footer>(__safeDI_footerBuilder)
			        let header = Header(footerBuilder: footerBuilder)
			        self.init(screenBuilder: screenBuilder, footerBuilder: footerBuilder, header: header)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.treeForcers) == [])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheInstanceOfWhatTheSeamsRootIsHanded_whenTypesBeneathTheSeamReceiveItsDeferredParameter() async throws {
		// `Vault`'s initializer holds `database` in a `LazilyInstantiated`, which no node of its tree declares: what the
		// root is handed answers the reads of `Store` and `Index`, at two depths, as that wrapper's instance. A seam's own
		// root is compared with its tree and never laid out, which its report calls `notLaidOut`.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let database: Database", "@Instantiated let vault: Vault"]),
				seamFixtureType(named: "Vault", isSeam: true, declarations: ["@Instantiated let store: Store"]),
				seamFixtureType(named: "Store", declarations: ["@Received let database: Database", "@Instantiated let index: Index"]),
				seamFixtureType(named: "Index", declarations: ["@Received let database: Database"]),
				seamFixtureType(named: "Database", isFinalClass: true, declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let database = Database()
			        func __safeDI_vault() -> Vault {
			            _ = Vault.__safeDI_Vault_699FBEB932A6412E.self
			            return Vault(__safeDI_database: database)
			        }
			        let vault: Vault = __safeDI_vault()
			        self.init(database: database, vault: vault)
			    }
			}
			""",
			"Vault+SafeDI.swift": generatedFileHeader + """
			extension Vault {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_database: @autoclosure @escaping () -> Database) {
			        let database = LazilyInstantiated<Database>(__safeDI_database)
			        @inline(never) func __safeDI_store() -> Store {
			            let index = Index(database: database.instance)
			            return Store(database: database.instance, index: index)
			        }
			        let store: Store = __safeDI_store()
			        self.init(store: store)
			    }
			}

			extension Vault {
			    public enum __safeDI_Vault_699FBEB932A6412E {}
			}
			""",
		])
		let seamReports = reports.filter { $0.root == "Vault" }
		#expect(seamReports.map(\.refusal) == ["notLaidOut"])
		#expect(seamReports.map(\.everyRefusal) == [[]])
		#expect(seamReports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTheTreesCaptureError_whenRootsAreLaidOutFromNodeRecordsAndASendableFunctionCapturesAnInstantiator() async {
		// The records cannot report the capture, so the world is refused (`NodeRecordRefusal.sendableFunctionCapturesWrapper`)
		// and its root keeps the tree whose check reports it, also where every root node records accept is laid out from
		// them.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `Root`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `Root`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				"""
			},
		) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
						        fatalError("SafeDI doesn't inspect the initializer body")
						    }

						    @Instantiated let childBuilder: Instantiator<Child>
						    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
						}
						""",
						"""
						@Instantiable
						public final class Child: Instantiable {
						    public init() {}
						}
						""",
						"""
						@Instantiable
						public final class Settings: Instantiable {
						    public init(childBuilder: Instantiator<Child>) {
						        fatalError("SafeDI doesn't inspect the initializer body")
						    }

						    @Received let childBuilder: Instantiator<Child>
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTheTreesFirstError_whenTwoPlacesErrorBesideARootLaidOutFromNodeRecords() async {
		// `Alpha`'s world is accepted, so the run lays it out from its records and builds no tree for it; each of the other
		// roots holds a place whose capture the tree reports. The run reports the errors a run that builds every tree
		// reports, in its order.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `Root`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `Root` and `SecondRoot`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: SecondRoot -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `SecondRoot` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `SecondRoot`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `Root` and `SecondRoot`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["SecondRoot.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				"""
			},
		) {
			var filesMade = [URL]()
			defer { filesToDelete += filesMade }
			return try await executeSafeDIToolTest(
				swiftFileContent: Self.twoErroringPlacesFixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesMade,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Three roots: `Alpha`, which node records lay out, and two that each build `Settings` in a `@Sendable` function
	/// that captures their own `childBuilder`, which is not `Sendable`.
	private static let twoErroringPlacesFixture = [
		"""
		@Instantiable(isRoot: true)
		public final class Alpha: Instantiable {
		    public init(child: Child) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Instantiated let child: Child
		}
		""",
		"""
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Instantiated let childBuilder: Instantiator<Child>
		    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
		}
		""",
		"""
		@Instantiable(isRoot: true)
		public final class SecondRoot: Instantiable {
		    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Instantiated let childBuilder: Instantiator<Child>
		    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
		}
		""",
		"""
		@Instantiable
		public final class Child: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public final class Settings: Instantiable {
		    public init(childBuilder: Instantiator<Child>) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Received let childBuilder: Instantiator<Child>
		}
		""",
	]

	/// What `body` returns with every root node records accept laid out from them, and the report of each root of the run.
	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
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
