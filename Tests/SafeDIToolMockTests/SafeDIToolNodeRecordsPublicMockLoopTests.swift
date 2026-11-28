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

/// A loop of builders in a public mock's own tree (`generateMock: .public`), whose members another module's mock may pass:
/// the public mock takes each member its root receives as an optional parameter and builds the loop where none is passed.
/// The cells compare values with the walk's around the loop, each builder called until it is called twice on a path (three
/// builds of a member: two laps), for a loop at the public mock's root and at a level below it, with no member, one member
/// and every member passed, each override set alone and all together. Node records do not lay out a public mock's own world yet;
/// once they do, each cell compares the laid-out mock's values with these.
struct SafeDIToolNodeRecordsPublicMockLoopTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Values

	/// Where the loop is in the public mock's tree.
	enum LoopPlace: String, CaseIterable, CustomTestStringConvertible {
		/// `Screen`, the public mock's root, declares the loop's members.
		case root
		/// `Holder`, which `Screen` instantiates, declares them.
		case level

		var testDescription: String { rawValue }
	}

	/// Which of the loop's members `App`'s mock passes the public mock.
	enum PassedMembers: String, CaseIterable, CustomTestStringConvertible {
		case none
		case some
		case every

		var testDescription: String { rawValue }
	}

	@Test(arguments: LoopPlace.allCases, PassedMembers.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenPublicMocksLoopIsOverriddenOnEveryLap(place: LoopPlace, passed: PassedMembers) async throws {
		let modules = Self.modules(place: place, passed: passed)
		let walkOutput = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesMade)
			}
		}
		filesToDelete += filesMade
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream where report.isMockRoot {
			reports.append(report)
		}
		// Node records do not lay out a public mock's own world yet, and the calling mock keeps its layout.
		#expect(reports.map(\.root) == ["Root"])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		let overrides = Self.overrides(place: place, passed: passed)
		var probes = [DifferentialValueProbe("Root.mock()")]
		for override in overrides {
			probes.append(DifferentialValueProbe(name: "only \(override.marker)", expression: Self.mockCall(overriding: [override])))
		}
		probes.append(DifferentialValueProbe(name: "every override", expression: Self.mockCall(overriding: overrides)))
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: walkOutput, modules: modules),
			probes: probes,
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override the walk reads marks the value its closure built.
		for marker in Self.markersRead(place: place, passed: passed) {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	/// An override a probe sets: where it sits in `Root.mock`'s overrides, its label there, and the value it is set to, which
	/// marks what it builds with `marker`.
	struct Override {
		enum Level {
			case root
			case screen
			case holder
		}

		let level: Level
		let label: String
		let marker: String

		var value: String {
			switch label {
			case "aBuilder":
				".init(leaf: { marked(Leaf(), \"\(marker).leaf\") }, { marked(A(bBuilder: $0, leaf: $1), \"\(marker)\") })"
			case "bBuilder":
				"{ marked(B(aBuilder: $0), \"\(marker)\") }"
			default:
				"{ marked(Leaf(), \"\(marker)\") }"
			}
		}
	}

	/// Every override of the case, in the order each initializer takes its labels.
	private static func overrides(place: LoopPlace, passed: PassedMembers) -> [Override] {
		let root: [Override] = passed == .none ? [] : [
			Override(level: .root, label: "aBuilder", marker: "root.aBuilder"),
			Override(level: .root, label: "bBuilder", marker: "root.bBuilder"),
		]
		func at(_ level: Override.Level, _ labels: [String]) -> [Override] {
			labels.map { Override(level: level, label: $0, marker: "\(level).\($0)") }
		}
		switch (place, passed) {
		case (.root, .none):
			return root + at(.screen, ["aBuilder", "bBuilder", "leaf"])
		case (.root, .some):
			return root + at(.screen, ["bBuilder", "aBuilder", "leaf"])
		case (.root, .every):
			return root + at(.screen, ["leaf", "aBuilder", "bBuilder"])
		case (.level, .none):
			return root + at(.holder, ["aBuilder", "bBuilder", "leaf"])
		case (.level, .some):
			return root + at(.screen, ["aBuilder", "bBuilder"]) + at(.holder, ["bBuilder", "leaf"])
		case (.level, .every):
			return root + at(.screen, ["aBuilder", "bBuilder"]) + at(.holder, ["leaf"])
		}
	}

	/// The markers of the overrides the walk reads. The public mock reads a member's override only where it builds the
	/// member, which it does not where the member is passed; at a level, the public mock's own overrides of the members
	/// build only the fallback of a member that is passed, so a level with a member passed reads none of them.
	private static func markersRead(place: LoopPlace, passed: PassedMembers) -> [String] {
		let root = ["root.aBuilder", "root.aBuilder.leaf", "root.bBuilder"]
		switch (place, passed) {
		case (.root, .none):
			return ["screen.aBuilder", "screen.aBuilder.leaf", "screen.bBuilder", "screen.leaf"]
		case (.root, .some):
			return root + ["screen.bBuilder", "screen.leaf"]
		case (.root, .every):
			return root + ["screen.leaf"]
		case (.level, .none):
			return ["holder.aBuilder", "holder.aBuilder.leaf", "holder.bBuilder", "holder.leaf"]
		case (.level, .some):
			return root + ["holder.bBuilder", "holder.leaf"]
		case (.level, .every):
			return root + ["holder.leaf"]
		}
	}

	/// `Root.mock` with `overrides` set.
	private static func mockCall(overriding overrides: [Override]) -> String {
		func arguments(_ level: Override.Level) -> [String] {
			overrides.filter { $0.level == level }.map { "\($0.label): \($0.value)" }
		}
		let holder = arguments(.holder)
		let screen = arguments(.screen) + (holder.isEmpty ? [] : ["holder: .init(\(holder.joined(separator: ", ")))"])
		let root = arguments(.root) + (screen.isEmpty ? [] : ["screen: .init(\(screen.joined(separator: ", ")))"])
		return "Root.mock(safeDIOverrides: .init(\(root.joined(separator: ", "))))"
	}

	// MARK: Fixtures

	/// `Feed` declares the loop `A` → `bBuilder` → `B` → `aBuilder` → `A` and `Screen`'s public mock; `App`'s `Root`
	/// instantiates `screen`, and the loop's members it passes.
	private static func modules(place: LoopPlace, passed: PassedMembers) -> [ModuleFixture] {
		let members = [("aBuilder", "A"), ("bBuilder", "B")]
		let passedLabels: Set<String> = switch passed {
		case .none: []
		case .some: ["aBuilder"]
		case .every: ["aBuilder", "bBuilder"]
		}
		let loopDeclarations = members.map { label, type in
			"    @\(passedLabels.contains(label) ? "Received" : "Instantiated") let \(label): Instantiator<\(type)>"
		}
		let loopParameters = members.map { label, type in "\(label): Instantiator<\(type)>" }.joined(separator: ", ")
		let loopAssignments = members.map { label, _ in "        self.\(label) = \(label)" }
		let owner: String
		switch place {
		case .root:
			owner = """
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable, Marked {
			    init(\(loopParameters), leaf: Leaf) {
			\(loopAssignments.joined(separator: "\n"))
			        self.leaf = leaf
			    }

			\(loopDeclarations.joined(separator: "\n"))
			    @Instantiated let leaf: Leaf
			    public var marker = "built"
			}
			"""
		case .level:
			owner = """
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable, Marked {
			    init(holder: Holder) {
			        self.holder = holder
			    }

			    @Instantiated let holder: Holder
			    public var marker = "built"
			}

			@Instantiable
			public final class Holder: Instantiable, Marked {
			    init(\(loopParameters), leaf: Leaf) {
			\(loopAssignments.joined(separator: "\n"))
			        self.leaf = leaf
			    }

			\(loopDeclarations.joined(separator: "\n"))
			    @Instantiated let leaf: Leaf
			    public var marker = "built"
			}
			"""
		}
		let feed = """
		import SafeDI

		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}

		@Instantiable
		public final class A: Instantiable, Marked {
		    public init(bBuilder: Instantiator<B>, leaf: Leaf) {
		        self.bBuilder = bBuilder
		        self.leaf = leaf
		    }

		    @Received let bBuilder: Instantiator<B>
		    @Instantiated let leaf: Leaf
		    public var marker = "built"
		}

		@Instantiable
		public final class B: Instantiable, Marked {
		    public init(aBuilder: Instantiator<A>) {
		        self.aBuilder = aBuilder
		    }

		    @Received let aBuilder: Instantiator<A>
		    public var marker = "built"
		}

		@Instantiable
		public final class Leaf: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}

		\(owner)
		"""
		let rootMembers = passed == .none ? [] : members
		let rootParameters = (rootMembers.map { label, type in "\(label): Instantiator<\(type)>" } + ["screen: Screen"]).joined(separator: ", ")
		let rootAssignments = (rootMembers.map(\.0) + ["screen"]).map { "        self.\($0) = \($0)" }.joined(separator: "\n")
		let rootDeclarations = (rootMembers.map { label, type in "    @Instantiated let \(label): Instantiator<\(type)>" } + ["    @Instantiated let screen: Screen"]).joined(separator: "\n")
		let app = """
		import Feed
		import SafeDI

		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(\(rootParameters)) {
		\(rootAssignments)
		    }

		\(rootDeclarations)
		}
		"""
		return [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: ["Screen.swift": feed]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Root.swift": app], dependencies: ["Feed"]),
		]
	}

	private var filesToDelete: [URL]
}
