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

/// Node records of a type that receives a property only if available (`NodeRecords.receivesOnlyIfAvailableClaim(of:in:)`):
/// each place reads the declaration its call finds, or `nil`, as the tree's place does.
struct SafeDIToolNodeRecordsOnlyIfAvailableTests: ~Copyable {
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
	mutating func generate_laysOutRootFromNodeRecords_whenReceivesOnlyIfAvailableFindValueNilOrSiblingBuiltBefore() async throws {
		// `Screen` receives `theme` only if available, which no declaration above provides, and `session`, which its sibling
		// is, built before it; `Banner` receives `screen` only if available, but `Screen` requires `banner`, so
		// `Banner` is built first and passed `nil`.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(session: Session, banner: Banner, screen: Screen) {
				        self.session = session
				        self.banner = banner
				        self.screen = screen
				    }
				    @Instantiated let session: Session
				    @Instantiated let banner: Banner
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public final class Banner: Instantiable {
				    public init(screen: Screen?) {
				        self.screen = screen
				    }
				    @Received(onlyIfAvailable: true) let screen: Screen?
				}
				""",
				"""
				@Instantiable
				public final class Screen: Instantiable {
				    public init(banner: Banner, session: Session?, theme: Theme?) {
				        self.banner = banner
				        self.session = session
				        self.theme = theme
				    }
				    @Received let banner: Banner
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Received(onlyIfAvailable: true) let theme: Theme?
				}
				""",
				"""
				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}
				""",
				"""
				public struct Theme {}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let session = Session()
			        let banner = Banner(screen: nil)
			        let screen = Screen(banner: banner, session: session, theme: nil)
			        self.init(session: session, banner: banner, screen: screen)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenAReceiveOnlyIfAvailableIsDeclaredByAWrapperBuiltAfterIt() async throws {
		// `Session` requires `reader`, so the root builds `reader` before the wrapper of `session`: the call of `Reader` is
		// handed no declaration of the label it receives only if available, which its record passes `nil`, as the tree does.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(reader: Reader, session: LazilyInstantiated<Session>) {
				        self.reader = reader
				        self.session = session
				    }
				    @Instantiated let reader: Reader
				    @Instantiated let session: LazilyInstantiated<Session>
				}
				""",
				"""
				@Instantiable
				public final class Reader: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }
				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
				"""
				@Instantiable
				public final class Session: Instantiable {
				    public init(reader: Reader) {
				        self.reader = reader
				    }
				    @Received let reader: Reader
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let reader = Reader(session: nil)
			        func __safeDI_session() -> Session {
			            Session(reader: reader)
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        self.init(reader: reader, session: session)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenTwoCallsOfOneTypeFindValueAndNil() async throws {
		// `Badge` is built inside `first`, before `session`, which requires `first`, and inside `second`, after it: one
		// variant under rule 1, whose read is the value. Its place is inline at both calls, so the call inside `first`
		// writes `nil`, as the tree writes it.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(first: First, session: Session, second: Second) {
				        self.first = first
				        self.session = session
				        self.second = second
				    }
				    @Instantiated let first: First
				    @Instantiated let session: Session
				    @Instantiated let second: Second
				}
				""",
				"""
				@Instantiable
				public final class First: Instantiable {
				    public init(badge: Badge) {
				        self.badge = badge
				    }
				    @Instantiated let badge: Badge
				}
				""",
				"""
				@Instantiable
				public final class Second: Instantiable {
				    public init(session: Session, badge: Badge) {
				        self.session = session
				        self.badge = badge
				    }
				    @Received let session: Session
				    @Instantiated let badge: Badge
				}
				""",
				"""
				@Instantiable
				public final class Badge: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }
				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
				"""
				@Instantiable
				public final class Session: Instantiable {
				    public init(first: First) {
				        self.first = first
				    }
				    @Received let first: First
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenTypeReceivesInstantiatorThatBuildsItOnlyIfAvailable() async throws {
		// `Editor` receives `editorBuilder`, the `Instantiator` being built around it: a loop of one, whose function begins by
		// making `editorBuilder` again, so its read only if available reads that.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(editorBuilder: Instantiator<Editor>) {
				        self.editorBuilder = editorBuilder
				    }
				    @Instantiated let editorBuilder: Instantiator<Editor>
				}
				""",
				"""
				@Instantiable
				public struct Editor: Instantiable {
				    public init(editorBuilder: Instantiator<Editor>?) {
				        self.editorBuilder = editorBuilder
				    }
				    @Received(onlyIfAvailable: true) let editorBuilder: Instantiator<Editor>?
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_editorBuilder() -> Editor {
			            let editorBuilder = Instantiator<Editor>(__safeDI_editorBuilder)
			            return Editor(editorBuilder: editorBuilder)
			        }
			        let editorBuilder = Instantiator<Editor>(__safeDI_editorBuilder)
			        self.init(editorBuilder: editorBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenLoopMemberReceivesSiblingsBuilderOnlyIfAvailable() async throws {
		// `A` receives `bBuilder` only if available and `B` receives `aBuilder`: `A`'s function begins by making `bBuilder`
		// again, which its construction reads, though the root builds `bBuilder` after `aBuilder`.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	// MARK: Private

	private var filesToDelete: [URL]

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
