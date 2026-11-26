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
	private func rootReport(of types: [String]) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			var filesToDelete = [URL]()
			defer {
				for file in filesToDelete {
					try? FileManager.default.removeItem(at: file)
				}
			}
			return try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
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
