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

/// A carrier level wider than the positional limit hands its values on in run structs, each formed by consuming the one
/// before. Each test runs the code the tool generates in a program whose classes record which of them are alive, holds
/// one builder of the seam's tree past its owner, and prints what is still alive, which is what the tree built inline keeps.
struct SafeDIToolSeamCarrierWideLevelRetentionTests: ~Copyable {
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
	mutating func generatedCode_keepsOnlyWhatEachBuilderReads_whenCarrierLevelsAreWiderThanPositionalLimit() async throws {
		// `Home`, a seam of `Feature`, binds ten values (`s1`…`s6` it receives, `h1`…`h4` it builds, interleaved by what
		// each receives) before two builders: `screenBuilder`, whose `Screen` binds nine (`id` and `m1`…`m8`) before
		// `detailBuilder`, whose `Detail` holds a place of `Api`; and `panelBuilder`, whose `Panel` holds a place of `Api2`.
		// `App` fills both: `LiveApi` reads `detailID`, `s1`, `h3` and `m1`, and builds `client` and `retryBuilder`;
		// `LiveApi2` reads `panelID`, `s6` and `screenBuilder`, a value of `Home`'s level after its first run of values.
		// Holding one builder past the root keeps alive only what that builder's tree reads, as inline.
		let values = (1...6).map { "S\($0)" }
		var feature = [
			"public protocol Api: AnyObject {}",
			"public protocol Api2: AnyObject {}",
			Self.liveObjects,
		]
		feature += values.map { Self.trackedType($0) }
		feature += [
			Self.trackedType("H1", "@Received let s2: S2"),
			Self.trackedType("H2"),
			Self.trackedType("H3", "@Received let h1: H1", "@Received let s5: S5"),
			Self.trackedType("H4", "@Received let h3: H3"),
			Self.trackedType("M1", "@Received let h1: H1", "@Received let s3: S3"),
			Self.trackedType("M2"),
			Self.trackedType("M3", "@Received let m1: M1", "@Received let h4: H4"),
			Self.trackedType("M4"),
			Self.trackedType("M5", "@Received let m3: M3", "@Received let s6: S6", "@Received let h2: H2"),
			Self.trackedType("M6"),
			Self.trackedType("M7"),
			Self.trackedType("M8"),
			Self.trackedType("D1", "@Received let m2: M2", "@Received let s4: S4", "@Received let m8: M8"),
			Self.trackedType("Detail", "@Forwarded let detailID: Int", "@Received let id: Int", "@Instantiated let d1: D1", "@Instantiated let api: any Api"),
			Self.trackedType("Screen", ["@Forwarded let id: Int", "@Received let h2: H2"] + (1...8).map { "@Instantiated let m\($0): M\($0)" } + ["@Instantiated let detailBuilder: Instantiator<Detail>"]),
			Self.trackedType("Home", attributes: "(generateDependencyTree: true)", values.map { "@Received let \($0.lowercased()): \($0)" } + (1...4).map { "@Instantiated let h\($0): H\($0)" } + ["@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let panelBuilder: Instantiator<Panel>"]),
			Self.trackedType("Panel", "@Forwarded let panelID: Int", "@Received let h4: H4", "@Instantiated let api2: any Api2"),
			Self.trackedType("Client", "@Received let m1: M1", "@Received let s1: S1"),
			Self.trackedType("Retry", "@Forwarded let attempt: Int", "@Received let detailID: Int", "@Received let client: Client"),
		]
		let app = [
			"import Feature\n\n" + Self.trackedType("LiveApi", attributes: "(fulfillingAdditionalTypes: [(any Api).self])", conformances: "Api, Instantiable", ["@Received let detailID: Int", "@Received let s1: S1", "@Received let h3: H3", "@Received let m1: M1", "@Instantiated let client: Client", "@Instantiated let retryBuilder: Instantiator<Retry>"]),
			"import Feature\n\n" + Self.trackedType("LiveApi2", attributes: "(fulfillingAdditionalTypes: [(any Api2).self])", conformances: "Api2, Instantiable", ["@Received let panelID: Int", "@Received let s6: S6", "@Received let screenBuilder: Instantiator<Screen>"]),
			"import Feature\n\n" + Self.trackedType("Root", attributes: "(isRoot: true)", values.map { "@Instantiated let \($0.lowercased()): \($0)" } + ["@Instantiated let home: Home"]),
		]
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let printed = try await DifferentialValueOracle.output(of: DifferentialValuePath(output: output, modules: modules), running: """
		func run(holding which: String) {
		    var instantiateHeld: (() -> Void)?
		    do {
		        let root = Root()
		        let screen = root.home.screenBuilder.instantiate(1)
		        let detail = screen.detailBuilder.instantiate(10)
		        let live = detail.api as! LiveApi
		        _ = live.retryBuilder.instantiate(100)
		        _ = root.home.screenBuilder.instantiate(2).detailBuilder.instantiate(20)
		        switch which {
		        case "screen":
		            let builder = root.home.screenBuilder
		            instantiateHeld = { _ = builder.instantiate(3) }
		        case "panel":
		            let builder = root.home.panelBuilder
		            instantiateHeld = { _ = builder.instantiate(5) }
		            _ = (builder.instantiate(4).api2 as! LiveApi2).screenBuilder.instantiate(4)
		        case "detail":
		            let builder = screen.detailBuilder
		            instantiateHeld = { _ = builder.instantiate(11) }
		        default:
		            let builder = live.retryBuilder
		            instantiateHeld = { _ = builder.instantiate(101) }
		        }
		    }
		    print("holding the \\(which) builder: \\(LiveObjects.alive)")
		    instantiateHeld = nil
		    print("after dropping it: \\(LiveObjects.alive)")
		}

		run(holding: "screen")
		run(holding: "detail")
		run(holding: "retry")
		run(holding: "panel")
		""", filesToDelete: &filesToDelete)
		guard let printed else { return }
		#expect(printed == """
		holding the screen builder: H1, H2, H3, H4, S1, S2, S3, S4, S5, S6
		after dropping it: none
		holding the detail builder: H1, H3, M1, M2, M8, S1, S2, S3, S4, S5
		after dropping it: none
		holding the retry builder: Client, H1, M1, S1, S2, S3
		after dropping it: none
		holding the panel builder: H1, H2, H3, H4, S1, S2, S3, S4, S5, S6
		after dropping it: none

		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The names of the fixture's tracked classes with an instance alive.
	private static let liveObjects = """
	/// How many instances of each of the fixture's tracked classes are alive.
	public enum LiveObjects {
	    nonisolated(unsafe) static var counts = [String: Int]()

	    /// The names of the classes with an instance alive, sorted, or `none`.
	    public static var alive: String {
	        let names = counts.filter { $0.value > 0 }.keys.sorted()
	        return names.isEmpty ? "none" : names.joined(separator: ", ")
	    }
	}

	/// A stored property of this type makes its owner count as alive until the owner is freed.
	public final class Tracker {
	    public init(_ name: String) {
	        self.name = name
	        LiveObjects.counts[name, default: 0] += 1
	    }

	    deinit {
	        LiveObjects.counts[name, default: 0] -= 1
	    }

	    private let name: String
	}
	"""

	private static func trackedType(_ name: String, attributes: String = "", conformances: String = "Instantiable", _ declarations: String...) -> String {
		trackedType(name, attributes: attributes, conformances: conformances, declarations)
	}

	/// A public `@Instantiable` final class with `declarations` (each `<attribute> let <label>: <type>`), an initializer
	/// taking each, and a `Tracker` of its name.
	private static func trackedType(_ name: String, attributes: String = "", conformances: String = "Instantiable", _ declarations: [String]) -> String {
		let parameters = declarations.map { String($0.split(separator: " let ", maxSplits: 1)[1]) }
		let labels = parameters.map { String($0.split(separator: ":", maxSplits: 1)[0]) }
		return """
		@Instantiable\(attributes)
		public final class \(name): \(conformances) {
		    public init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(declarations.map { "    \($0)" }.joined(separator: "\n"))
		    let tracker = Tracker("\(name)")
		}
		"""
	}
}
