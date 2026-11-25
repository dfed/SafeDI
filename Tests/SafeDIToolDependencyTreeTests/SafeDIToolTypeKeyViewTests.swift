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

/// How many views the type key lays a production root's body out over (`GenerationWork.Step.layingOutTypeKeyViews`). A
/// view stands for every place of one plan node that agrees on what it reads outside the node, so the views of a tree
/// that reaches each type along many paths grow with its types and the forms of what they read, not with its paths. Each
/// count is the one the type key's views have on the shape; each comment names the places they stand for.
struct SafeDIToolTypeKeyViewTests: ~Copyable {
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
	mutating func generate_laysOutOneViewPerType_whenTreeReachesEachTypeOnManyPaths() async throws {
		// Four layers of three types, each instantiating the three of the layer beneath. The 81 places of the last layer build
		// constants in place, so 3 + 9 + 27 = 39 places have a builder function; the places of each type read nothing, so
		// they agree, and each type is one view.
		let letters = ["A", "B", "C"]
		var fixture = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: letters.map { "@Instantiated let l1\($0.lowercased()): L1\($0)" })]
		for layer in 1...4 {
			for letter in letters {
				let declarations = layer < 4 ? letters.map { "@Instantiated let l\(layer + 1)\($0.lowercased()): L\(layer + 1)\($0)" } : []
				fixture.append(seamFixtureType(named: "L\(layer)\(letter)", isFinalClass: true, declarations: declarations))
			}
		}
		#expect(try await viewCounts(of: fixture) == [9])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsThatGrowWithTheLayers_whenScreensOpenTheNextLayerInline() async throws {
		// N5's screens without seams, as 2.2.0 builds them: layers of four screens, each opening three of the next layer's
		// through an `Instantiator`, so the places of the last layer grow three times with each layer. Every screen's places
		// read the same `service` and their own `id`, so each screen and its model is one view whatever the paths: the views
		// grow by four with each two layers' eight screens and models apart from the last layer's, which build in place.
		var counts = [[Int]]()
		for layerCount in [4, 6] {
			try await counts.append(viewCounts(of: Self.screensOpeningTheNextLayer(layerCount: layerCount)))
		}
		#expect(counts == [[21], [29]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsOfTheReportedGraph_whenTwelveScreensOpenEachOther() async throws {
		// The graph issue #646 reported, at twelve screens: each opens three others through an `Instantiator`, and each
		// declares, receives, receives if available, or ignores a `Context`. A screen's places are apart wherever the
		// `Context` they read, or the function their builders' closers call reads, is another declaration, so the 12 screens
		// are 232 views, of 12 classes in the type key's layout.
		let roles: [ContextRole] = [.receivesIfAvailable, .none, .declares, .none, .receivesIfAvailable, .receivesIfAvailable, .declares, .declares, .none, .receives, .receivesIfAvailable, .declares]
		let targets = [[2, 3, 10], [2, 8, 10], [4, 7, 11], [0, 7, 8], [0, 8, 10], [1, 3, 10], [0, 10, 11], [3, 6, 11], [3, 7, 9], [3, 5, 8], [3, 7, 11], [0, 6, 8]]
		let counts = try await viewCounts(of: Self.screensOpeningEachOther(roles: roles, targets: targets))
		#expect(counts == [232])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsThatGrowWithTheScreens_whenScreensOpenEachOtherAtTwoSizes() async throws {
		// The reported graph's form at eight and twelve screens, each screen `i` opening screens `i + 1`, `i + 3` and `i + 7`
		// (modulo the count) and taking the `i`th of the four roles in turn. Here the views grow with the declarations of
		// `Context` each screen can be reached beneath, which grow with the screens' cycles: 133 at eight screens and 1,918 at
		// twelve.
		var counts = [[Int]]()
		for screenCount in [8, 12] {
			let roles = (0..<screenCount).map { ContextRole.allCases[$0 % ContextRole.allCases.count] }
			let targets = (0..<screenCount).map { screen in [1, 3, 7].map { (screen + $0) % screenCount }.sorted() }
			try await counts.append(viewCounts(of: Self.screensOpeningEachOther(roles: roles, targets: targets)))
		}
		#expect(counts == [[133], [1_918]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsRootFunctionsReadingLevelsThatDoNotGrowWithThePaths_whenScreensOpenTheNextLayerInline() async throws {
		// The layered screens above, whose last layer's places grow three times with each layer. No place holds a root
		// function, and each place records so as it is built, so the walk for root functions reads the root's own levels
		// and no place's tree: its levels are the same at four and six layers. A walk of every place's tree read 3^layers.
		var counts = [[Int]]()
		for layerCount in [4, 6] {
			try await counts.append(workCounts(of: Self.screensOpeningTheNextLayer(layerCount: layerCount), by: .findingRootFunctions))
		}
		#expect(counts == [[4], [4]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_checksEachReadAtEveryMemberOncePerClass_whenScreensOpenEachOtherAtTwoSizes() async throws {
		// The reported graph's form at eight and twelve screens, as above, whose views grow from 133 to 1,918 while their
		// classes stay one per screen: each read is asked once per class, reading each member once, so the work grows with
		// the views (766 and 11,047). Asking it for every member read a class's members once per member, growing with the
		// square of a class's members (15,076 and 2,180,277).
		var totals = [Int]()
		for screenCount in [8, 12] {
			let roles = (0..<screenCount).map { ContextRole.allCases[$0 % ContextRole.allCases.count] }
			let targets = (0..<screenCount).map { screen in [1, 3, 7].map { (screen + $0) % screenCount }.sorted() }
			try await totals.append(workCounts(of: Self.screensOpeningEachOther(roles: roles, targets: targets), by: .checkingReadsAtEveryMember).reduce(0, +))
		}
		#expect(totals == [766, 11_047])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What a screen of `screensOpeningEachOther` does with the `Context` its root declares.
	private enum ContextRole: CaseIterable {
		case declares
		case receives
		case receivesIfAvailable
		case none
	}

	/// The views each production root of `fixture` is laid out over, in the order the roots are laid out.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func viewCounts(of fixture: [String]) async throws -> [Int] {
		try await workCounts(of: fixture, by: .layingOutTypeKeyViews)
	}

	/// The work `step` did each time it ran while `fixture` was generated, in the order it ran.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func workCounts(of fixture: [String], by step: GenerationWork.Step) async throws -> [Int] {
		let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
		_ = try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// The code is what the type key's other tests compare; this one counts how it is laid out.
				skipCompileVerification: true,
			)
		}
		continuation.finish()
		var counts = [Int]()
		for await work in stream where work.step == step {
			counts.append(work.elementCount)
		}
		return counts
	}

	/// Screens that each forward an `id`, receive the root's `Service`, take a `Context` in `roles`' way and open the
	/// screens `targets` names through an `Instantiator`, beneath a root that declares both and opens the first screen.
	private static func screensOpeningEachOther(roles: [ContextRole], targets: [[Int]]) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let context: Context", "@Instantiated let screen0Builder: Instantiator<Screen0>"]),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Context", isFinalClass: true, declarations: []),
		]
		for (screen, role) in roles.enumerated() {
			var declarations = ["@Forwarded let id: String", "@Received let service: Service"]
			switch role {
			case .declares:
				declarations.append("@Instantiated let context: Context")
			case .receives:
				declarations.append("@Received let context: Context")
			case .receivesIfAvailable:
				declarations.append("@Received(onlyIfAvailable: true) let context: Context?")
			case .none:
				break
			}
			declarations += targets[screen].map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
			files.append(seamFixtureType(named: "Screen\(screen)", isFinalClass: true, declarations: declarations))
		}
		return files
	}

	/// `layerCount` layers of four screens beneath a root and a home that opens the first: each screen forwards an `id`,
	/// receives the root's `Service`, instantiates a model of its own and opens the three screens of the next layer but
	/// the one at its own position through an `Instantiator`. The last layer's models instantiate an `Api` the root's
	/// module fulfills.
	private static func screensOpeningTheNextLayer(layerCount: Int) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let home: Home"]),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []) + "\npublic protocol Api {}",
			seamFixtureType(named: "Home", isFinalClass: true, declarations: (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }),
			seamFixtureType(named: "LiveApi", isFinalClass: true, declarations: ["@Received let id: Int", "@Received let service: Service"], conformances: ", Api")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
		]
		for screen in 0..<(layerCount * 4) {
			let layer = screen / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != screen % 4 }.map { (layer + 1) * 4 + $0 } : []
			files.append(seamFixtureType(
				named: "Screen\(screen)",
				isFinalClass: true,
				declarations: ["@Forwarded let id: Int", "@Received let service: Service", "@Instantiated let model\(screen): Model\(screen)"]
					+ opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" },
			))
			files.append(seamFixtureType(
				named: "Model\(screen)",
				isFinalClass: true,
				declarations: ["@Received let id: Int", "@Received let service: Service"] + (opened.isEmpty ? ["@Instantiated let api: any Api"] : []),
			))
		}
		return files
	}
}
