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

/// A production tree reuses the generator of a place whose key and read log match an earlier place's. Each test here is
/// a shape where two places look alike to the memo in one way and differ in another; it generates the module with the
/// memo and without it and expects the same files, and `executeSafeDIToolTest` also builds every tree both ways and
/// compares them by reflection, path by path.
struct SafeDIToolConstructionMemoTests: ~Copyable {
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
	mutating func generate_generatesSameTreeWithMemoAsWithout_whenTwoPlacesReadEqualLogsFromDifferentProvidersUnderCycleWithParameters() async throws {
		// `A` is built beneath `Root` and beneath `D`; each declares `x` two levels above `B`, which receives it, so the two
		// places of `A` read equal logs from different declarations. `S`, between `A` and the scope closing the cycle on
		// it, declares `x` too, so `A`'s builder function takes `x` as a parameter.
		try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let d: D"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameTreeWithMemoAsWithout_whenLazilyInstantiatedInstancesInScopeDifferWhereReadsDoNot() async throws {
		// `C` is built beneath `Root`, where `x`'s instance is in scope through its wrapper, and beneath `D`, whose own `x`
		// hides the wrapper; `C`'s tree reads no `x`.
		try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let c: C", "@Instantiated let d: D"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let c: C"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let e: E"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: []),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsSameErrorWithMemoAsWithout_whenSiblingSubtreesSharingKeyThrow() async {
		// `P` and `Q` each build `G`, whose `childBuilder` spells a first generic that is not `Child`'s forwarded
		// properties, which construction throws; no partial build of `G` is kept.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let p: P", "@Instantiated let q: Q"]),
			seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let g: G"]),
			seamFixtureType(named: "G", isFinalClass: true, declarations: [#"@Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>"#]),
			"""
			public final class AnyChild {
			    public init(_ child: Child) {}
			}
			""",
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Forwarded let name: String"]),
		]
		for isEnabled in [true, false] {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["G.swift"]):7:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `G` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			}) {
				try await ConstructionMemo.$isEnabled.withValue(isEnabled) { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsSendableOnClosedOnFunctionInBothRoots_whenOneRootDeclaresLazilyInstantiatedAndOtherConstantAndCycleClosesInsideSendableInstantiator() async throws {
		// `First` declares `a: LazilyInstantiated<A>` and `Second` declares `a: A`; in both, `C`, built in a `@Sendable`
		// function, closes the cycle on `a`'s builder function, which must therefore be `@Sendable` in both.
		let output = try await expectSameFilesWithMemoAsWithout(of: [
			seamFixtureType(named: "First", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: LazilyInstantiated<A>"]),
			seamFixtureType(named: "Second", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let cBuilder: SendableInstantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let a: A"]),
		])
		#expect(output == [
			"First+SafeDI.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			extension First {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            @Sendable func __safeDI_cBuilder() -> C {
			                let a: A = __safeDI_a()
			                return C(a: a)
			            }
			            let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			            return A(cBuilder: cBuilder)
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        self.init(a: a)
			    }
			}
			""",
			"Second+SafeDI.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			extension Second {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            @Sendable func __safeDI_cBuilder() -> C {
			                let a: A = __safeDI_a()
			                return C(a: a)
			            }
			            let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			            return A(cBuilder: cBuilder)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Generates `fixture` with the memo and without it, expects the same generated files, and returns them.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	@discardableResult
	private mutating func expectSameFilesWithMemoAsWithout(of fixture: [String]) async throws -> [String: String] {
		let withMemo = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let withoutMemo = try await ConstructionMemo.$isEnabled.withValue(false) { [fixture] in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(!withMemo.dependencyTreeFiles.isEmpty)
		#expect(withMemo.dependencyTreeFiles == withoutMemo.dependencyTreeFiles)
		return withMemo.dependencyTreeFiles
	}
}
