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

/// A hole whose fulfiller is a seam of another module with a hole of its own that nothing the calling module sees
/// fulfills: the call cannot fill the fulfiller's builder, so the root reports it as it reports a hole one level up.
struct SafeDIToolSeamNestedUnfilledHoleTests: ~Copyable {
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFound_whenFillOfRootsSeamCallIsSeamWithHoleNothingFulfills(integration: MultiModuleIntegration) async {
		// `App` fills `S0`'s place of `P0` with `S1`, whose place of `P1` nothing fulfills: the root reports it as it reports
		// a place of `S0` it cannot fill, at its dependency that reaches `S0`, with a note at `S1`'s property.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let path = { (module: String, file: String) in
				switch integration {
				case .moduleInfo:
					fixtures[module]![file]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures[module]!.compilerPath(of: file)).path
				}
			}
			return """
			\(path("App", "Root.swift")):11:5: error: No @Instantiable type or extension that module `App` can see fulfills `P1`, which @Instantiated property `p: any P1` instantiates in chain: Root -> S0 -> S1. `S1` generates its dependency tree in module `M1`, which cannot see one either, so the initializer SafeDI generated for it takes `p1Builder`, whose member `p` builds `p`, and the root `Root` must fill it. Decorate `P1`, or an extension of it, with @Instantiable; list `P1` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(path("M1", "S1.swift")):9:5: note: `S1` instantiates `p: any P1` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 2, app: [Self.root]),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFound_whenFillOfFillOfRootsSeamCallIsSeamWithHoleNothingFulfills() async {
		// Three levels: `S1` fills `S0`'s place, `S2` fills `S1`'s, and nothing fulfills `S2`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable type or extension that module `App` can see fulfills `P2`, which @Instantiated property `p: any P2` instantiates in chain: Root -> S0 -> S1 -> S2. `S2` generates its dependency tree in module `M2`, which cannot see one either, so the initializer SafeDI generated for it takes `p2Builder`, whose member `p` builds `p`, and the root `Root` must fill it. Decorate `P2`, or an extension of it, with @Instantiable; list `P2` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["M2"]!["S2.swift"]):9:5: note: `S2` instantiates `p: any P2` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 3, app: [Self.root]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [
		(propertyType: "ErasedInstantiator<(), any P1>", builder: "p1Builder"),
		(propertyType: "SendableInstantiator<any P1>", builder: "p1SendableBuilder"),
		(propertyType: "Instantiator<any P1>", builder: "p1Builder"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFound_whenFillsUnfilledHoleIsHeldInWrapper(propertyType: String, builder: String) async {
		// The place nothing fulfills is built in an erased, `@Sendable` or plain instantiator: reported as a plain one is,
		// naming the builder of its family.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):11:5: error: No @Instantiable type or extension that module `App` can see fulfills `any P1`, which @Instantiated property `p: \(propertyType)` instantiates in chain: Root -> S0 -> S1. `S1` generates its dependency tree in module `M1`, which cannot see one either, so the initializer SafeDI generated for it takes `\(builder)`, whose member `p` builds `p`, and the root `Root` must fill it. Decorate `any P1`, or an extension of it, with @Instantiable; list `any P1` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["M1"]!["S1.swift"]):9:5: note: `S1` instantiates `p: \(propertyType)` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 2, innerDeclaration: "@Instantiated let p: \(propertyType)", app: [Self.root]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToFill_whenFillsHoleNothingFulfillsIsInstantiatedOnlyIfAvailable(integration: MultiModuleIntegration) async throws {
		// A place only if available that nothing fulfills is no error: the root's fill of `S1` passes it `nil`, as a root
		// passes `nil` for such a place of the seam it calls.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(depth: 2, innerDeclaration: "@Instantiated(onlyIfAvailable: true) let p: (any P1)?", app: [Self.root]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(M0)
		import M0
		#endif
		#if canImport(M1)
		import M1
		#endif

		extension Root {
		    public init() {
		        func __safeDI_s() -> S0 {
		            _ = S0.__safeDI_S0_BF176DC076DC04EE.self\(integration.seamCallComment(type: "S0", declaringModule: "M0"))
		            func __safeDI_p0Builder_S0_p() -> any P0 {
		                func __safeDI_p() -> S1 {
		                    _ = S1.__safeDI_S1_9C5AE37B60FDC075.self\(integration.seamCallComment(type: "S1", declaringModule: "M1"))
		                    return S1(__safeDI_p1OptionalBuilder: .init(__safeDI_noScope: { nil }))
		                }
		                let p: any P0 = __safeDI_p()
		                return p
		            }
		            func __safeDI_p0Builder_S0() -> S0.__safeDI_P0Carrier<any P0> {
		                .init(p: { __safeDI_p0Builder_S0_p() })
		            }
		            return S0(__safeDI_p0Builder: __safeDI_p0Builder_S0())
		        }
		        let s: S0 = __safeDI_s()
		        self.init(s: s)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFoundNamingPassingUpSeam_whenSeamPassesUpPlaceOfFillsHoleNothingFulfills() async {
		// `Host`, a seam of `Mid`, calls `S0` and fills its place with `S1`, whose place nothing `Mid` sees fulfills, so
		// `Host` passes it up; `App`'s root sees nothing that fulfills it either.
		// The root reported this before it judged the places of each fill's own call too, since `Host`'s builder is a place
		// of the call it makes; the test pins that route beside the nested ones.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable type or extension that module `App` can see fulfills `P1`, which @Instantiated property `p: any P1` instantiates in chain: Root -> Host -> S0 -> S1. `S1` generates its dependency tree in module `M1`, which cannot see one either, so the initializer SafeDI generated for it takes `p1Builder`, whose member `p` builds `p`, and the root `Root` must fill it. Decorate `P1`, or an extension of it, with @Instantiable; list `P1` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["M1"]!["S1.swift"]):9:5: note: `S1` instantiates `p: any P1` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 2, app: [Self.hostRoot], host: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlacePassedUpFromFill_whenRootFillsHoleOfFillOfPassingUpSeam() async throws {
		// The same graph with `App` declaring `Impl`, which fulfills `P1`: `Host` passes `S1`'s place up and the root fills it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(depth: 2, app: [Self.hostRoot, Self.impl], host: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(M0)
		import M0
		#endif
		#if canImport(M1)
		import M1
		#endif
		#if canImport(Mid)
		import Mid
		#endif

		extension Root {
		    public init() {
		        func __safeDI_p1Builder_Host() -> Host.SafeDIScope_P1.__safeDI_Builder<any P1> {
		            .init(s_p0Builder: { _ in __safeDI_p1Builder_S1_S0() })
		        }
		        func __safeDI_p1Builder_S1() -> S1.__safeDI_P1Carrier<any P1> {
		            .init(p: {
		                let p: any P1 = Impl()
		                return p
		            })
		        }
		        func __safeDI_p1Builder_S1_S0() -> S0.__safeDI_P0Carrier<S1.__safeDI_P1Carrier<any P1>> {
		            .init(p: { __safeDI_p1Builder_S1() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_BCC4F392FD24940E.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_p1Builder: __safeDI_p1Builder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsBothInSourceOrder_whenRootHasNestedUnfilledHoleBesideUnfilledHole(nestedFirst: Bool) async {
		// `Root` reaches `S1`'s unfilled place through `S0`, and `T`'s own unfilled place directly, in either order.
		let declarations = ["@Instantiated let s: S0", "@Instantiated let t: T"]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			if nestedFirst {
				"""
				\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable type or extension that module `App` can see fulfills `P1`, which @Instantiated property `p: any P1` instantiates in chain: Root -> S0 -> S1. `S1` generates its dependency tree in module `M1`, which cannot see one either, so the initializer SafeDI generated for it takes `p1Builder`, whose member `p` builds `p`, and the root `Root` must fill it. Decorate `P1`, or an extension of it, with @Instantiable; list `P1` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
				\(fixtures["M1"]!["S1.swift"]):9:5: note: `S1` instantiates `p: any P1` here.
				\(fixtures["App"]!["Root.swift"]):13:5: error: No @Instantiable type or extension that module `App` can see fulfills `Q`, which @Instantiated property `q: any Q` instantiates in chain: Root -> T. `T` generates its dependency tree in module `Base`, which cannot see one either, so the initializer SafeDI generated for it takes `qBuilder`, whose member `q` builds `q`, and the root `Root` must fill it. Decorate `Q`, or an extension of it, with @Instantiable; list `Q` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
				\(fixtures["Base"]!["T.swift"]):7:5: note: `T` instantiates `q: any Q` here.
				"""
			} else {
				"""
				\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable type or extension that module `App` can see fulfills `Q`, which @Instantiated property `q: any Q` instantiates in chain: Root -> T. `T` generates its dependency tree in module `Base`, which cannot see one either, so the initializer SafeDI generated for it takes `qBuilder`, whose member `q` builds `q`, and the root `Root` must fill it. Decorate `Q`, or an extension of it, with @Instantiable; list `Q` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
				\(fixtures["Base"]!["T.swift"]):7:5: note: `T` instantiates `q: any Q` here.
				\(fixtures["App"]!["Root.swift"]):13:5: error: No @Instantiable type or extension that module `App` can see fulfills `P1`, which @Instantiated property `p: any P1` instantiates in chain: Root -> S0 -> S1. `S1` generates its dependency tree in module `M1`, which cannot see one either, so the initializer SafeDI generated for it takes `p1Builder`, whose member `p` builds `p`, and the root `Root` must fill it. Decorate `P1`, or an extension of it, with @Instantiable; list `P1` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
				\(fixtures["M1"]!["S1.swift"]):9:5: note: `S1` instantiates `p: any P1` here.
				"""
			}
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 2, app: [seamFixtureType(named: "Root", isRoot: true, declarations: nestedFirst ? declarations : declarations.reversed())], withT: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesBuilderOfFillsPlace_whenCalledPublicMocksFillIsPublicMockWithHoleNothingFulfills() async throws {
		// A calling mock passes such a place up, as a seam does: `Screen.mock()` takes `p1Builder`, which `S1`'s mock is
		// handed where `Screen`'s fills `S0`'s place.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(depth: 2, app: [Self.screen], publicMocks: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(M0)
		import M0
		#endif
		#if canImport(M1)
		import M1
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            s: ((@escaping () -> any P0) -> S0)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                s: s
		            )
		        }

		        var s: ((@escaping () -> any P0) -> S0)? { __safeDI_storage.s }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                s: ((@escaping () -> any P0) -> S0)?
		            ) {
		                self.s = s
		            }

		            let s: ((@escaping () -> any P0) -> S0)?
		        }
		    }

		    static func mock(
		        p0Builder: (() -> any P0)? = nil,
		        p1Builder: @escaping () -> any P1,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_s() -> S0 {
		            func __safeDI_p0Builder_S0_p() -> any P0 {
		                let p: any P0 = S1.__safeDI_mock(p1Builder: .init(__safeDI_noScope: p1Builder))
		                return p
		            }
		            func __safeDI_p0Builder_S0() -> S0.SafeDIMockScope_P0.__safeDI_Builder<any P0> {
		                .init(p: { _ in __safeDI_p0Builder_S0_p() })
		            }
		            _ = S0.__safeDI_S0_mock_A1594E767333DFEF.self // If this line does not compile, compile the code SafeDI generates for module M0 into M0: under Bazel, add M0’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.s { safeDIBuilder({ if let p0Builder { p0Builder() } else { __safeDI_p0Builder_S0_p() } }) } else { S0.__safeDI_mock(p0Builder: p0Builder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_p0Builder_S0()) }
		        }
		        let s: S0 = __safeDI_s()
		        return Screen(s: s)
		    }
		}
		#endif
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `App`'s root, which instantiates `S0`.
	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let s: S0"])

	/// `App`'s root, which instantiates `Mid`'s `Host`.
	private static let hostRoot = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])

	/// `App`'s type that fulfills `P1`.
	private static let impl = seamFixtureType(named: "Impl", isFinalClass: true, declarations: [], conformances: ", P1")
		.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [P1.self])\n")

	/// `App`'s type whose internal mock calls `S0`'s public mock.
	private static let screen = seamFixtureType(named: "Screen", declarations: ["@Instantiated let s: S0"])
		.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")

	/// A chain of `depth` seams, each in a module of its own: `S0`, in `M0`, instantiates `p: any P0`; each `S<n>`, in
	/// `M<n>`, fulfills `P<n-1>` and instantiates `p: any P<n>`, the last as `innerDeclaration` says; nothing fulfills the
	/// last protocol. With `host`, `Mid`'s seam `Host` instantiates `S0`; with `withT`, `Base`'s seam `T` instantiates
	/// `q: any Q`, which nothing fulfills; with `publicMocks`, each type of the chain is no seam but generates a public
	/// mock and has an internal initializer, so another module's mock calls it. `App` lists every module and declares
	/// `app`.
	private static func modules(depth: Int, innerDeclaration: String? = nil, app: [String], host: Bool = false, withT: Bool = false, publicMocks: Bool = false) -> [ModuleFixture] {
		var base = (0..<depth).map { "public protocol P\($0): AnyObject {}" }
		if withT {
			base += ["public protocol Q: AnyObject {}", seamFixtureType(named: "T", isSeam: true, declarations: ["@Instantiated let q: any Q"])]
		}
		var modules = [ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: base)]
		for index in 0..<depth {
			let declaration = index == depth - 1 ? innerDeclaration ?? "@Instantiated let p: any P\(index)" : "@Instantiated let p: any P\(index)"
			let arguments = [publicMocks ? nil : "generateDependencyTree: true", index == 0 ? nil : "fulfillingAdditionalTypes: [P\(index - 1).self]", publicMocks ? "generateMock: .public" : nil].compactMap(\.self)
			var type = seamFixtureType(named: "S\(index)", isFinalClass: true, declarations: [declaration], conformances: index == 0 ? "" : ", P\(index - 1)")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(\(arguments.joined(separator: ", ")))\n")
			if publicMocks {
				type = type.replacingOccurrences(of: "public init(", with: "init(")
			}
			modules.append(ModuleFixture(name: "M\(index)", packageName: "Shop", swiftFileContent: ["import Base\n\n" + type], dependencies: ["Base"]))
		}
		let chainModules = ["Base"] + (0..<depth).map { "M\($0)" }
		if host {
			modules.append(ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [chainModules.map { "import \($0)\n" }.joined() + "\n" + seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let s: S0"])], dependencies: chainModules))
		}
		let appModules = chainModules + (host ? ["Mid"] : [])
		modules.append(ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { appModules.map { "import \($0)\n" }.joined() + "\n" + $0 }, dependencies: appModules))
		return modules
	}
}
