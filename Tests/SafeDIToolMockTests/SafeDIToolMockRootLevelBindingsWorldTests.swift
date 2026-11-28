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

/// What a mock root's level binds (`MockLowering.rootLevelBindings(of:signature:rootLevelNodes:callsBindNothing:)`), read
/// from the root's world beside the tree's, in the tree names comparison (`MockTreeNamesObservation`).
struct SafeDIToolMockRootLevelBindingsWorldTests: ~Copyable {
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
	mutating func rootLevelBindings_bindOnlyNodes_whenRootLevelNamesNothingApart() async throws {
		let report = try await report(of: "Root", in: [
			"""
			public final class Config {}

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(config: Config, child: Child) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let config: Config
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init() {}
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "rootNamesApart") == "")
		#expect(report.worldValue(of: "rootPropertyNodeBindingNames") == "child")
		#expect(report.worldValue(of: "bindsOnlyNodes") == "true")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func rootLevelBindings_nameSiblingsApart_whenMockPromotesLabelInTwoForms() async throws {
		// `First` receives `log` by value and `Second` an instantiator of it, so the mock promotes both forms of `log`, which
		// its level names apart.
		let report = try await report(of: "Root", in: [
			"""
			public final class Config {}

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(config: Config, first: First, second: Second) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let config: Config
			    @Instantiated let first: First
			    @Instantiated let second: Second
			}
			""",
			"""
			@Instantiable
			public final class First: Instantiable {
			    public init(log: Log) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let log: Log
			}
			""",
			"""
			@Instantiable
			public final class Log: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Second: Instantiable {
			    public init(log: Instantiator<Log>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let log: Instantiator<Log>
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "rootNamesApart") == "log: Instantiator<Log> -> log_Instantiator__Log; log: Log -> log_Log")
		#expect(report.worldValue(of: "rootPropertyNodeBindingNames") == "first, log_Instantiator__Log, log_Log, second")
		#expect(report.worldValue(of: "bindsOnlyNodes") == "true")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func rootLevelBindings_bindOtherThanNodes_whenMockTakesSendableAutoclosure() async throws {
		// `Car` instantiates an `Engine` nothing fulfills inside a `SendableInstantiator`'s builder function, so `mock()`
		// takes it as a `@Sendable` autoclosure, read into a local before the nodes.
		let report = try await report(of: "Root", in: [
			"""
			public final class Config {}
			public final class Engine {}

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(config: Config, carBuilder: SendableInstantiator<Car>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let config: Config
			    @Instantiated let carBuilder: SendableInstantiator<Car>
			}
			""",
			"""
			@Instantiable
			public final class Car: Instantiable {
			    public init(engine: Engine) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let engine: Engine
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "bindsOnlyNodes") == "false")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The report of the mock root `root` of the module of `fixture`, which must be reported once.
	private mutating func report(of root: String, in fixture: [String]) async throws -> MockTreeNamesReport {
		let (stream, continuation) = AsyncStream.makeStream(of: MockTreeNamesReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		try await MockTreeNamesObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
			_ = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesMade)
		}
		continuation.finish()
		var reports = [MockTreeNamesReport]()
		for await report in stream where report.root == root {
			reports.append(report)
		}
		#expect(reports.count == 1)
		return try #require(reports.first)
	}
}
