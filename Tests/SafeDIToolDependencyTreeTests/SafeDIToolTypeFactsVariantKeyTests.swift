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

/// The two parameter rules of a world's variant key (`TypeFactsGraph.optionalParameterKey`): a difference a body's
/// parameter carries keys alike, so a type built under parents that differ only in it has one body.
struct SafeDIToolTypeFactsVariantKeyTests: ~Copyable {
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
	mutating func generate_keysOneVariant_whenReceiveOnlyIfAvailableIsAnsweredUnderOneParentAndNilUnderTheOther() async throws {
		// Rule 1: `Child` reads `x` only if available; `First` declares it and `Second` does not, so one place is handed
		// the value and the other `nil`, which an optional parameter carries.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(report.places.count(where: { $0.declaration == "Child as child: Child" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 1, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysVariantPerParameterType_whenReceiveOnlyIfAvailableIsAnsweredByValueUnderOneParentAndLazilyUnderTheOther() async throws {
		// Rule 1 keeps whether a lazy wrapper answers: `First` declares `x` by value and `Second` lazily, so the place under
		// `Second` reads the wrapper's instance where it reads `x`, and its body takes the wrapper, not the value.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 2, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysVariantPerParameterType_whenReceiveOnlyIfAvailableIsAnsweredLazilyUnderOneParentAndNilUnderTheOther() async throws {
		// `nil` keys apart from a lazy wrapper's answer until rule 3 is ruled, which would let a `nil` wrapper parameter
		// stand for it: this count is the one that ruling changes.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 2, "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenAlternatingParentsDeclareTokenOnOneSideAndEveryLayerDoublesThePaths() async throws {
		// rows.py's alternating row: layer i's left parent declares `token<i>` and its right one does not, both open both
		// parents of the next layer, and a reader beneath every parent receives each token only if available. Rule 1
		// keys every answer alike, so the paths double at each layer while the variants stay one per node.
		for layerCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left0Builder: Instantiator<Left0>", "@Instantiated let right0Builder: Instantiator<Right0>"])]
			types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: (0..<layerCount).map { "@Received(onlyIfAvailable: true) let token\($0): Token\($0)?" }))
			for layer in 0..<layerCount {
				let next = layer == layerCount - 1
					? ["@Instantiated let reader: Reader"]
					: ["@Instantiated let left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "@Instantiated let right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
				types.append(seamFixtureType(named: "Token\(layer)", isFinalClass: true, declarations: []))
				types.append(seamFixtureType(named: "Left\(layer)", isFinalClass: true, declarations: ["@Instantiated let token\(layer): Token\(layer)"] + next))
				types.append(seamFixtureType(named: "Right\(layer)", isFinalClass: true, declarations: next))
			}
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.places.count(where: { $0.declaration == "Reader as reader: Reader" }) == 1 << layerCount, "\(layerCount)")
			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(layerCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenReaderReceivesEveryLayersBuilderStillBeingBuiltOnHalfThePaths() async throws {
		// rows.py's being-built row: each layer's two parents both open both builders of the next, and the reader receives
		// every layer's left builder, which is still being built on each path through `Left<i>` and built on the others.
		// Rule 2 keys a wrapper alike either way.
		for layerCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left0Builder: Instantiator<Left0>", "@Instantiated let right0Builder: Instantiator<Right0>"])]
			types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: (0..<layerCount).map { "@Received let left\($0)Builder: Instantiator<Left\($0)>" }))
			for layer in 0..<layerCount {
				let next = layer == layerCount - 1
					? ["@Instantiated let reader: Reader"]
					: ["@Instantiated let left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "@Instantiated let right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
				types.append(seamFixtureType(named: "Left\(layer)", isFinalClass: true, declarations: next))
				types.append(seamFixtureType(named: "Right\(layer)", isFinalClass: true, declarations: next))
			}
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.places.count(where: { $0.declaration == "Reader as reader: Reader" }) == 1 << layerCount, "\(layerCount)")
			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(layerCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsVariantsPerNodeFixed_whenHubsLeafReceivesEveryMembersLabelOnlyIfAvailable() async throws {
		// rows.py's hub-members row: a hub opens each member, each member declares its own label and opens the hub again,
		// and the hub's leaf receives every member's label only if available. Rule 1 keys every answer alike, so the hub
		// has one variant however many members reach it. (The lazy row waits on rule 3.)
		for memberCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>"])]
			types.append(seamFixtureType(named: "Hub", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"] + (0..<memberCount).map { "@Instantiated let member\($0)Builder: Instantiator<Member\($0)>" }))
			types.append(seamFixtureType(named: "Leaf", isFinalClass: true, declarations: (0..<memberCount).map { "@Received(onlyIfAvailable: true) let label\($0): Label\($0)?" }))
			for member in 0..<memberCount {
				types.append(seamFixtureType(named: "Label\(member)", isFinalClass: true, declarations: []))
				types.append(seamFixtureType(named: "Member\(member)", isFinalClass: true, declarations: ["@Instantiated let label\(member): Label\(member)", "@Instantiated let hubBuilder: Instantiator<Hub>"]))
			}
			let report = try await rootReport(of: types, skipCompileVerification: true)

			#expect(report.variantCountsByNode.allSatisfy { $0 == 1 }, "\(memberCount): \(report.world)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysOneVariant_whenReceivedWrapperIsBeingBuiltUnderOneParentOnly() async throws {
		// Rule 2: `Child` receives `firstBuilder`, which is still being built where `First` builds `Child` and is not
		// where `Second` does; the wrapper is passed and made again at the call, so the difference keys alike.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let firstBuilder: Instantiator<First>", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let firstBuilder: Instantiator<First>"]),
		])

		#expect(report.places.count(where: { $0.declaration == "Child as child: Child" }) >= 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Child as child: Child", in: report) == 1, "\(report.world)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func rootReport(of types: [String], skipCompileVerification: Bool = false) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			var filesToDelete = [URL]()
			defer {
				for file in filesToDelete {
					try? FileManager.default.removeItem(at: file)
				}
			}
			return try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: skipCompileVerification)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && !report.forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last)
	}

	private func variantCount(ofNodeDeclaring declaration: String, in report: TypeFactsReport) -> Int? {
		guard let node = report.places.first(where: { $0.declaration == declaration })?.node else {
			return nil
		}
		return report.variantCountsByNode[node]
	}
}
