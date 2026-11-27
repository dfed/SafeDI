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

/// The names `mock()`'s parameters are chosen from, read from a mock root's per-type world (`MockTreeNamesFromWorld`)
/// rather than walked from its generator tree path by path: each cell is a mock root whose world answers, with every
/// field equal to the tree's (`MockTreeNamesObservation`), and asserts the world's value of the field its shape is about,
/// so that a cell shows the shape was answered, not only that nothing differed. The refusal cells name what the world
/// refuses.
struct SafeDIToolMockTreeNamesWorldTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Answered

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_equalTreesNames_whenUncoveredDependencyIsHiddenByBuilderFunctionOnOnePathAndNotOnAnother() async throws {
		// `Car` instantiates an `Engine` no declaration fulfills. `Dashboard` builds `Car` directly, where nothing hides
		// the parameter, and through `Garage`, whose builder function declares an `engine` of its own.
		let report = try await report(of: "Dashboard", in: [
			"""
			public final class Engine {}

			@Instantiable(generateMock: true)
			public final class Dashboard: Instantiable {
			    public init(car: Car, garage: Garage) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let car: Car
			    @Instantiated let garage: Garage
			}
			""",
			"""
			@Instantiable
			public final class Garage: Instantiable {
			    public init(engine: Toolbox, car: Car) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let engine: Toolbox
			    @Instantiated let car: Car
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
			"""
			@Instantiable
			public final class Toolbox: Instantiable {
			    public init() {}
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "uncoveredDependencies") == "engine: Engine instantiates Engine hidden: true sendable: false creatingTypes: [Car]")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_equalTreesNames_whenUncoveredDependencyIsInstantiatedInsideSendableInstantiatorsTree() async throws {
		// `Garage` builds `Car` inside a `SendableInstantiator`'s builder function first, then by value: `Car`'s `engine`
		// is instantiated inside a `@Sendable` function, and its `radio`, which nothing fulfills, is bound to `nil` outside
		// one, so the mock takes an override of it.
		let report = try await report(of: "Dashboard", in: [
			"""
			public final class Engine: Sendable {}

			public final class Radio: Sendable {}

			@Instantiable(generateMock: true)
			public final class Dashboard: Instantiable {
			    public init(garage: Garage) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let garage: Garage
			}
			""",
			"""
			@Instantiable
			public final class Garage: Instantiable {
			    public init(carBuilder: SendableInstantiator<Car>, car: Car) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let carBuilder: SendableInstantiator<Car>
			    @Instantiated let car: Car
			}
			""",
			"""
			@Instantiable
			public final class Car: Instantiable {
			    public init(engine: Engine, radio: Radio?) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let engine: Engine
			    @Instantiated(onlyIfAvailable: true) let radio: Radio?
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "uncoveredDependencies") == "engine: Engine instantiates Engine hidden: false sendable: true creatingTypes: [Car]")
		#expect(report.worldValue(of: "unavailableDependencyProperties") == "radio: Radio?")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_equalTreesNames_whenDependencyInstantiatedOnlyIfAvailableIsFulfilledByNothing() async throws {
		// The mocked type and a type of its tree each instantiate, only if available, a type no declaration fulfills.
		let report = try await report(of: "Root", in: [
			"""
			public final class Logger {}

			public final class Tracker {}

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(logger: Logger?, child: Child) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated(onlyIfAvailable: true) let logger: Logger?
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(tracker: Tracker?) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated(onlyIfAvailable: true) let tracker: Tracker?
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "unavailableDependencyProperties") == "logger: Logger?, tracker: Tracker?")
		#expect(report.worldValue(of: "rootHoleSiteProperties") == "logger: Logger?")
		#expect(report.worldValue(of: "rootProperties") == "child: Child")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_equalTreesNames_whenTypeReachedAlongTwoPathsIsBuiltInAnOrderOtherThanItsDeclarations() async throws {
		// `Root` declares `a` before `b`, but builds `b` first, since `A` receives it. `C` is reached through both, and `D`
		// only through `B`, so the walk in generation order meets `gauge` before `engine`, which `A` instantiates too.
		let report = try await report(of: "Root", in: [
			"""
			public final class Engine {}

			public final class Gauge {}

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A, b: B) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let a: A
			    @Instantiated let b: B
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(b: B, c: C, engine: Engine) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let b: B
			    @Instantiated let c: C
			    @Instantiated let engine: Engine
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(d: D, c: C) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let d: D
			    @Instantiated let c: C
			}
			""",
			"""
			@Instantiable
			public final class C: Instantiable {
			    public init(engine: Engine) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let engine: Engine
			}
			""",
			"""
			@Instantiable
			public final class D: Instantiable {
			    public init(gauge: Gauge) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let gauge: Gauge
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "rootProperties") == "b: B, a: A")
		#expect(report.worldValue(of: "uncoveredDependencies") == "gauge: Gauge instantiates Gauge hidden: false sendable: false creatingTypes: [D]; engine: Engine instantiates Engine hidden: false sendable: false creatingTypes: [A, C]")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_equalTreesNames_whenTwentyPromotedSiblingsAreReceivedInAnOrderTheirNamesDoNotSort() async throws {
		// The mock promotes each dependency `Root` receives, in the order `Root` declares them, which is not their labels'
		// order nor their types'.
		let indices = (0..<20).map { ($0 * 7) % 20 }
		let labels = indices.map { "dependency\(String(format: "%02d", 19 - $0))" }
		let types = indices.map { "Type\(String(format: "%02d", $0))" }
		var fixture = ["""
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(\(zip(labels, types).map { "\($0): \($1)" }.joined(separator: ", "))) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		\(zip(labels, types).map { "    @Received let \($0): \($1)" }.joined(separator: "\n"))
		}
		"""]
		for type in types {
			fixture.append("""
			@Instantiable
			public final class \(type): Instantiable {
			    public init() {}
			}
			""")
		}
		let report = try await report(of: "Root", in: fixture)
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "rootProperties") == zip(labels, types).map { "\($0): \($1)" }.joined(separator: ", "))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_equalTreesNames_whenMockedTypeAndTypeOfItsTreeInstantiateDependencyNothingFulfills() async throws {
		// `Root` instantiates an `Engine` no declaration fulfills, as does `Child`, which `Root` builds after a lazily
		// instantiated `Cache`.
		let report = try await report(of: "Root", in: [
			"""
			public final class Engine {}

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(engine: Engine, cache: LazilyInstantiated<Cache>, child: Child) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let engine: Engine
			    @Instantiated let cache: LazilyInstantiated<Cache>
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Cache: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(engine: Engine) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let engine: Engine
			}
			""",
		])
		#expect(report.refusal == nil)
		#expect(report.differences == [])
		#expect(report.worldValue(of: "rootProperties") == "cache: LazilyInstantiated<Cache>, child: Child")
		#expect(report.worldValue(of: "mockedTypeUncoveredDependencies") == "engine: Engine instantiates Engine")
		#expect(report.worldValue(of: "uncoveredDependencies") == "engine: Engine instantiates Engine hidden: false sendable: false creatingTypes: [Root, Child]")
	}

	// MARK: Refused

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_refuses_whenTreeClosesLazyCycle() async throws {
		let report = try await report(of: "Root", in: [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let a: A
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
		])
		#expect(report.refusal == "cycle")
		#expect(report.fields == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_refuses_whenMockIsPublic() async throws {
		let report = try await report(of: "Panel", in: [
			"""
			@Instantiable(generateMock: .public)
			public final class Panel: Instantiable {
			    public init(child: Child) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

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
		#expect(report.refusal == "publicMockRoot")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func treeNames_refuses_whenTreeCallsAnotherModulesPublicMock() async throws {
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: ["Screen.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    init(analytics: Analytics) {
			        self.analytics = analytics
			    }

			    @Instantiated let analytics: Analytics
			}
			"""]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Root.swift": """
			import Feed
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			"""], dependencies: ["Feed"]),
		]
		let reports = try await observingReports { filesToDelete in
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter { $0.root == "Root" }.map(\.refusal) == ["callOrPlace"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The report of the mock root `root` of the module of `fixture`, which must be reported once.
	private mutating func report(of root: String, in fixture: [String]) async throws -> MockTreeNamesReport {
		let reports = try await observingReports { filesToDelete in
			_ = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let reportsOfRoot = reports.filter { $0.root == root }
		#expect(reportsOfRoot.count == 1)
		return try #require(reportsOfRoot.first)
	}

	/// The reports of every mock root `body` lowers.
	private mutating func observingReports(_ body: (inout [URL]) async throws -> Void) async throws -> [MockTreeNamesReport] {
		let (stream, continuation) = AsyncStream.makeStream(of: MockTreeNamesReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		try await MockTreeNamesObservation.$observer.withValue({ continuation.yield($0) }) {
			try await body(&filesMade)
		}
		continuation.finish()
		var reports = [MockTreeNamesReport]()
		for await report in stream {
			reports.append(report)
		}
		return reports
	}
}
