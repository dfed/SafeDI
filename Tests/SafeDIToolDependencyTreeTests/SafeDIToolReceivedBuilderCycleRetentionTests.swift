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

/// Loops of instantiators that receive one another free what their owner releases: each builder function on a loop
/// wraps again the functions of the members its tree receives, so what one call builds owns its wrappers and holds
/// only values declared before the loop. Each test runs the code the tool generates in a program whose classes count
/// their live instances, walks the loop, releases the root while keeping some of what it built, and prints the count.
struct SafeDIToolReceivedBuilderCycleRetentionTests: ~Copyable {
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
	mutating func generatedCode_freesWhatItsOwnerReleases_whenSeamsInModulesOfTheirOwnOpenOneAnotherThroughRootsErasedInstantiators() async throws {
		// Eight screens, each a seam in a module of its own that sees only `Core`, receive three erased instantiators each,
		// which `Root` declares, one for each screen, so the instantiators are one loop. A walk opens 1,000 screens through
		// the loop and keeps five; releasing the root frees it, and the screens kept hold only the service.
		let edges = [[2, 3, 4], [2, 3, 7], [1, 4, 7], [0, 2, 6], [2, 3, 5], [3, 6, 7], [0, 4, 5], [0, 2, 3]]
		let modules = Self.screenModules(edges: edges)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let printed = try await DifferentialValueOracle.output(of: DifferentialValuePath(output: output, modules: modules), running: """
		struct Generator {
		    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
		    mutating func next(_ bound: Int) -> Int {
		        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
		        return Int((state >> 33) % UInt64(bound))
		    }
		}

		func walk() -> [Screen] {
		    var generator = Generator()
		    var kept = [Screen]()
		    var reached = Set<ObjectIdentifier>()
		    let root = Root()
		    let service = root.service
		    print("alive after building the root: \\(LiveObjects.count)")
		    var isEachScreenBuiltAsDeclared = true
		    for walk in 0..<20 {
		        var screen = root.builders[generator.next(root.builders.count)].instantiate(walk)
		        for step in 0..<50 {
		            isEachScreenBuiltAsDeclared = isEachScreenBuiltAsDeclared && screen.identifier == (step == 0 ? walk : walk * 1_000 + step) && screen.heldService === service
		            reached.insert(ObjectIdentifier(type(of: screen)))
		            if step == 25, walk.isMultiple(of: 4) {
		                kept.append(screen)
		            }
		            screen = screen.builders[generator.next(screen.builders.count)].instantiate(walk * 1_000 + step + 1)
		        }
		    }
		    print("each screen holds its own id and the root's service: \\(isEachScreenBuiltAsDeclared)")
		    print("screen types the walk reached: \\(reached.count)")
		    print("alive while the root and \\(kept.count) screens are held: \\(LiveObjects.count)")
		    return kept
		}

		var kept = walk()
		print("alive after releasing the root: \\(LiveObjects.count)")
		print("a screen kept opens others: \\(kept[0].builders[0].instantiate(7).builders[1].instantiate(8).identifier == 8)")
		kept = []
		print("alive after releasing the screens: \\(LiveObjects.count)")
		""", filesToDelete: &filesToDelete)
		guard let printed else { return }
		#expect(printed == """
		alive after building the root: 2
		each screen holds its own id and the root's service: true
		screen types the walk reached: 8
		alive while the root and 5 screens are held: 7
		alive after releasing the root: 6
		a screen kept opens others: true
		alive after releasing the screens: 0

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generatedCode_freesWhatItsOwnerReleases_whenEachLoopMemberFunctionTakesTheOtherAsCycleParameter() async throws {
		// `A`'s tree receives `bBuilder`, and `StepA` closes a cycle on `aBuilder` and declares `bBuilder` again; `B` mirrors
		// it. Each member's function takes the other as a cycle parameter, so each is wrapped by a function of its own.
		let fixture = [
			Self.trackedType("DetailA", "@Received let bBuilder: Instantiator<B>"),
			Self.trackedType("DetailB", "@Received let aBuilder: Instantiator<A>"),
			Self.trackedType("A", "@Instantiated let detail: DetailA", "@Instantiated let stepBuilder: Instantiator<StepA>"),
			Self.trackedType("B", "@Instantiated let detail: DetailB", "@Instantiated let stepBuilder: Instantiator<StepB>"),
			Self.trackedType("StepA", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.trackedType("StepB", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.trackedType("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.liveObjects,
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let printed = try await DifferentialValueOracle.output(of: Self.path(fixture: fixture, output: output), running: """
		func walk() {
		    let root = Root()
		    let a = root.aBuilder.instantiate()
		    let b = a.detail.bBuilder.instantiate()
		    let a2 = b.detail.aBuilder.instantiate()
		    let stepA = a2.stepBuilder.instantiate()
		    let bUnderStepA = stepA.bBuilder.instantiate()
		    let aUnderStepA = stepA.aBuilder.instantiate()
		    let deep = bUnderStepA.stepBuilder.instantiate().aBuilder.instantiate().detail.bBuilder.instantiate().detail.aBuilder.instantiate().stepBuilder.instantiate().bBuilder.instantiate()
		    let viaRootB = root.bBuilder.instantiate().stepBuilder.instantiate().aBuilder.instantiate().detail.bBuilder.instantiate()
		    print("every instantiate() builds a new instance: \\(a !== a2 && a2 !== aUnderStepA && deep !== b && viaRootB !== b)")
		    print("alive while the walk's instances are held: \\(LiveObjects.count)")
		}

		walk()
		print("alive after releasing the root and the walk: \\(LiveObjects.count)")
		func outlivingB() -> B {
		    Root().aBuilder.instantiate().stepBuilder.instantiate().bBuilder.instantiate()
		}
		var survivor: B? = outlivingB()
		print("alive while a B built beneath a released root is held: \\(LiveObjects.count)")
		print("that B builds through the loop: \\(survivor?.detail.aBuilder.instantiate().detail.bBuilder.instantiate() != nil)")
		survivor = nil
		print("alive after releasing that B: \\(LiveObjects.count)")
		""", filesToDelete: &filesToDelete)
		guard let printed else { return }
		// While the walk is held: the root; `a`, `a2` and `aUnderStepA` with their details; `b`, `bUnderStepA`, `deep` and
		// `viaRootB` with theirs; and `stepA`.
		#expect(printed == """
		every instantiate() builds a new instance: true
		alive while the walk's instances are held: 16
		alive after releasing the root and the walk: 0
		alive while a B built beneath a released root is held: 2
		that B builds through the loop: true
		alive after releasing that B: 0

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generatedMocks_freeWhatTheirOwnerReleases_whenBuildersOfMockedTypesReceiveEachOther() async throws {
		// `Root`'s mock builds its production tree, whose `aBuilder` and `bBuilder` receive each other. `A`'s mock promotes
		// `bBuilder`, and `aBuilder`, which only `B`'s tree requires, so its promoted builders are a loop too.
		let fixture = [
			Self.trackedType("Service"),
			Self.trackedType("A", attributes: "(generateMock: true)", "@Received let service: Service", "@Received let bBuilder: Instantiator<B>"),
			Self.trackedType("B", "@Received let service: Service", "@Received let aBuilder: Instantiator<A>"),
			Self.trackedType("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let service: Service", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.liveObjects,
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let printed = try await DifferentialValueOracle.output(of: Self.path(fixture: fixture, output: output), running: """
		func walk() {
		    var overrideCalls = 0
		    let a = A.mock(safeDIOverrides: .init(aBuilder: { service, bBuilder in
		        overrideCalls += 1
		        return A(service: service, bBuilder: bBuilder)
		    }))
		    let a2 = a.bBuilder.instantiate().aBuilder.instantiate()
		    let a3 = a2.bBuilder.instantiate().aBuilder.instantiate()
		    print("A's mock builds each A through its loop with the override: \\(overrideCalls == 2 && a2 !== a && a3 !== a2)")
		    print("and hands each the mock's one service: \\(a3.service === a.service)")
		    let root = Root.mock(safeDIOverrides: .init(bBuilder: { service, aBuilder in
		        overrideCalls += 1
		        return B(service: service, aBuilder: aBuilder)
		    }))
		    let rootB = root.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()
		    print("Root's mock builds each B through its loop with the override: \\(overrideCalls == 4 && rootB.service === root.service)")
		    print("alive while the mocks and what they built are held: \\(LiveObjects.count)")
		}

		walk()
		print("alive after releasing the mocks: \\(LiveObjects.count)")
		""", filesToDelete: &filesToDelete)
		guard let printed else { return }
		// While held: `a`, `a2`, `a3` and the service of `A`'s mock, and the root, its service and `rootB`.
		#expect(printed == """
		A's mock builds each A through its loop with the override: true
		and hands each the mock's one service: true
		Root's mock builds each B through its loop with the override: true
		alive while the mocks and what they built are held: 7
		alive after releasing the mocks: 0

		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The live instance count every tracked type's `tracker` adds to while its owner is alive.
	private static let liveObjects = """
	/// How many instances of the fixture's tracked classes are alive.
	public enum LiveObjects {
	    nonisolated(unsafe) public static var count = 0
	}

	/// A stored property of this type makes its owner count as alive until the owner is freed.
	public final class Tracker {
	    public init() {
	        LiveObjects.count += 1
	    }

	    deinit {
	        LiveObjects.count -= 1
	    }
	}
	"""

	/// A public `@Instantiable` final class with `declarations`, an initializer taking each, and a `Tracker`.
	private static func trackedType(_ name: String, attributes: String = "", _ declarations: String...) -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
		let attributedType = attributes.isEmpty ? type : "@Instantiable\(attributes)" + type.dropFirst("@Instantiable".count)
		return attributedType.dropLast("}".count) + "\n    let tracker = Tracker()\n}"
	}

	/// The path of `fixture`, a test's files in one module, with the code the tool generated for it.
	private static func path(fixture: [String], output: TestOutput) throws -> DifferentialValuePath {
		var fixtureFiles = [String: String]()
		for (index, file) in fixture.enumerated() {
			fixtureFiles["Fixture\(index).swift"] = file
		}
		return try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
	}

	/// `Core`, which declares `Service`, the open class `Screen`, and the live instance count; one module `M<i>` per screen,
	/// which sees only `Core` and declares `Screen<i>`, a seam that forwards `id`, receives `service`, instantiates a
	/// `Model<i>` that receives both, and receives an erased instantiator of each screen `edges[i]` names, in that order,
	/// which it lists as its `builders`; and `App`, whose `Root` declares `service` and an erased instantiator of each
	/// screen, in order, which the screen's module fulfills. `Service`, each screen and `Root` count as alive.
	private static func screenModules(edges: [[Int]]) -> [ModuleFixture] {
		let core = ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
			"""
			@Instantiable
			public final class Service: Instantiable {
			    public init() {}

			    let tracker = Tracker()
			}

			open class Screen {
			    public init() {}

			    open var builders: [ErasedInstantiator<Int, Screen>] { [] }
			    open var identifier: Int { -1 }
			    open var heldService: Service? { nil }

			    let tracker = Tracker()
			}

			\(liveObjects)
			""",
		])
		let screens = edges.enumerated().map { index, opened in
			let properties = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", "model\(index)", "Model\(index)")]
				+ opened.map { ("@Received", "screen\($0)Builder", "ErasedInstantiator<Int, Screen>") }
			return ModuleFixture(name: "M\(index)", packageName: "Shop", swiftFileContent: [
				"""
				import Core

				@Instantiable(generateDependencyTree: true)
				public final class Screen\(index): Screen, Instantiable {
				    public init(\(properties.map { "\($0.1): \($0.2)" }.joined(separator: ", "))) {
				\(properties.map { "        self.\($0.1) = \($0.1)" }.joined(separator: "\n"))
				        super.init()
				    }

				\(properties.map { "    \($0.0) let \($0.1): \($0.2)" }.joined(separator: "\n"))

				    override public var builders: [ErasedInstantiator<Int, Screen>] { [\(opened.map { "screen\($0)Builder" }.joined(separator: ", "))] }
				    override public var identifier: Int { id }
				    override public var heldService: Service? { service }
				}

				@Instantiable
				public final class Model\(index): Instantiable {
				    public init(id: Int, service: Service) {
				        self.id = id
				        self.service = service
				    }

				    @Received let id: Int
				    @Received let service: Service
				}
				""",
			], dependencies: ["Core"])
		}
		let rootProperties = [("@Instantiated", "service", "Service")]
			+ edges.indices.map { (#"@Instantiated(fulfilledByType: "Screen\#($0)")"#, "screen\($0)Builder", "ErasedInstantiator<Int, Screen>") }
		let app = ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"""
			import Core
			\(edges.indices.map { "import M\($0)" }.joined(separator: "\n"))

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    init(\(rootProperties.map { "\($0.1): \($0.2)" }.joined(separator: ", "))) {
			\(rootProperties.map { "        self.\($0.1) = \($0.1)" }.joined(separator: "\n"))
			    }

			\(rootProperties.map { "    \($0.0) let \($0.1): \($0.2)" }.joined(separator: "\n"))

			    var builders: [ErasedInstantiator<Int, Screen>] { [\(edges.indices.map { "screen\($0)Builder" }.joined(separator: ", "))] }

			    let tracker = Tracker()
			}
			""",
		], dependencies: ["Core"] + edges.indices.map { "M\($0)" })
		return [core] + screens + [app]
	}
}
