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

/// The mock roots of a module share one construction memo: a place a mock root built is reused by a later mock root
/// that reaches the same place. Every test here runs the module three ways, with the memo shared between mock roots,
/// with it shared and the mock roots built in reverse order, and with no memo, and expects the same diagnostics or
/// mocks each time; `executeSafeDIToolTest` also builds every tree with the memo and without it and compares them by
/// reflection, so a reused place that holds what another path would not fails each test.
struct SafeDIToolMockConstructionMemoTests: ~Copyable {
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

	@Test(arguments: [
		// `P` fails first, in the middle and last of the mock roots, which are built in type order.
		["Q", "R"],
		["N", "Q"],
		["M", "N"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reportsSameErrorWithMemoAsWithout_whenMockRootFailingAfterItsConstructionSharesSubtreesWithOtherMockRoots(otherMockRootNames: [String]) async {
		// `P`'s mock builds `A`, whose label `x` no one cycle parameter can carry (`unpassableCycleLabel`), which is
		// thrown after its tree is built, so the places of `G`'s subtree it built are kept and the other roots reuse them.
		let fixture = [
			Self.mockedType(named: "P", declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let g: G"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: LazilyInstantiated<X>.self, onlyIfAvailable: true) let lazyX: LazilyInstantiated<X>?"#]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let h: H", "@Instantiated let kBuilder: Instantiator<K>"]),
			seamFixtureType(named: "H", isFinalClass: true, declarations: ["@Instantiated let k: K"]),
			seamFixtureType(named: "K", isFinalClass: true, declarations: []),
		] + otherMockRootNames.map { Self.mockedType(named: $0, declarations: ["@Instantiated let g: G"]) }
		for setting in MemoSetting.allCases {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:5: error: @Received property `x: LazilyInstantiated<X>` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>` and `x: X?`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>` and `x: X?` under different labels to fix.
				\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
				"""
			}) {
				try await setting.run { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
		}
	}

	@Test(arguments: [
		// `P` fails first, in the middle and last of the mock roots, which are built in type order.
		["Q", "R"],
		["N", "Q"],
		["M", "N"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reportsSameErrorWithMemoAsWithout_whenMockRootThrowsDuringItsConstruction(otherMockRootNames: [String]) async {
		// `P`'s construction throws, which ends the mock pass, so no later mock root reads what the memo kept before it.
		let fixture = [
			Self.mockedType(named: "P", declarations: [#"@Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>"#, "@Instantiated let g: G"]),
			"""
			public final class AnyChild {
			    public init(_ child: Child) {}
			}
			""",
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Forwarded let name: String"]),
			seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let h: H"]),
			seamFixtureType(named: "H", isFinalClass: true, declarations: []),
		] + otherMockRootNames.map { Self.mockedType(named: $0, declarations: ["@Instantiated let g: G"]) }
		for setting in MemoSetting.allCases {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["P.swift"]):8:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `P` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			}) {
				try await setting.run { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
		}
	}

	@Test(arguments: [
		// `P1` reaches `S` directly and `P2` through `X`, each first in turn.
		["P1", "P2"],
		["P2", "P1"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMocksWithMemoAsWithout_whenTwoPublicMocksReachTypeWithHoleByDifferentPaths(names: [String]) async throws {
		// `S` instantiates `api: any Api`, which nothing fulfills, so each public mock's tree holds a place there, whose
		// hole stack is the path from the mock's root. A place holding it is stored in no memo.
		let fixture = [
			"public protocol Api {}",
			seamFixtureType(named: "S", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "X", declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: names[0], declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: names[1], declarations: ["@Instantiated public let x: X"]),
		]
		try await expectSameMocksInEverySetting(of: fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMockWithMemoAsWithout_whenPublicMockReachesTypeWithHoleByTwoPaths() async throws {
		// `P` reaches `S`, whose `api` is a place, as its own child and beneath `X`: two places, two hole stacks.
		let fixture = [
			"public protocol Api {}",
			seamFixtureType(named: "S", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "X", declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: "P", declarations: ["@Instantiated public let s: S", "@Instantiated public let x: X"]),
		]
		try await expectSameMocksInEverySetting(of: fixture)
	}

	// MARK: Private

	/// How the module's mock roots share the construction memo.
	private enum MemoSetting: CaseIterable {
		case shared
		case sharedInReverseOrder
		case off

		func run<T>(_ body: () async throws -> T) async throws -> T {
			switch self {
			case .shared:
				try await body()
			case .sharedInReverseOrder:
				try await ConstructionMemoOracle.$buildsMockRootsInReverseOrder.withValue(true) { try await body() }
			case .off:
				try await ConstructionMemo.$isEnabled.withValue(false) { try await body() }
			}
		}
	}

	private var filesToDelete: [URL]

	/// Expects `fixture`'s mocks to be the same in every `MemoSetting`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSameMocksInEverySetting(of fixture: [String]) async throws {
		var mocksBySetting = [[String: String]]()
		for setting in MemoSetting.allCases {
			let output = try await setting.run { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			mocksBySetting.append(output.mockFiles)
		}
		#expect(!mocksBySetting[0].isEmpty)
		for mocks in mocksBySetting.dropFirst() {
			#expect(mocks == mocksBySetting[0])
		}
	}

	/// A final class named `name` whose mock is generated.
	private static func mockedType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	/// A struct named `name` whose public mock is generated.
	private static func publicMockedType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
	}
}
