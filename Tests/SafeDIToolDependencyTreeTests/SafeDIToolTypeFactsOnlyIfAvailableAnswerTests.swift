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

/// The facts' answer to a read only if available (`TypeFactsGraph`'s `binding` of the `optional` and `optionalValue`
/// channels): none wherever the tree passes the receive `nil` (`NearestDeclarations.resolvingBinding(of:)` and the
/// `propertiesGeneratedLater` a scope's children are generated with), as type facts check 34 compares at every place.
struct SafeDIToolTypeFactsOnlyIfAvailableAnswerTests: ~Copyable {
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
	mutating func generate_answersNone_whenNearerDeclarationOfLabelHidesReadOnOnePath() async throws {
		// `Left` declares `token: Token`, which provides no form `Reader`'s `token: Secret?` reads, so the tree passes
		// `nil` beneath it, as it does beneath `Right`, where nothing declares the label.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let left: Left", "@Instantiated let right: Right"]),
			seamFixtureType(named: "Left", isFinalClass: true, declarations: ["@Instantiated let token: Token", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Secret?"]),
			seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Secret", isFinalClass: true, declarations: []),
		])

		#expect(TypeFactsChecks.onlyIfAvailableComparisons(of: report).map(\.description) == [
			"place 0 Root optional(token): tree nil, facts none",
			"place 1 Screen as screen: Screen optional(token): tree nil, facts none",
			"place 4 Reader as reader: Reader optional(token): tree nil, facts none",
			"place 5 Right as right: Right optional(token): tree nil, facts none",
			"place 6 Reader as reader: Reader optional(token): tree nil, facts none",
		], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersNone_whenNearestDeclarationOfLabelIsGeneratedLater() async throws {
		// `A` and `B` receive each other only if available, so `b`, declared later, is built first and passed `nil`, and
		// `a` is passed `b`.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let b: B?"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let a: A?"]),
		])

		#expect(TypeFactsChecks.onlyIfAvailableComparisons(of: report).map(\.description) == [
			"place 1 A as a: A optional(b): tree b: B, facts bound declared",
			"place 2 B as b: B optional(a): tree nil, facts none",
		], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersNone_whenNearestDeclarationOfLabelIsBeingBuilt() async throws {
		// `Child` is built inside `x`, the nearest declaration of its label, which is still being built there, so the tree
		// passes it `nil`; `Sibling`, built after `x` beside it, is passed the value.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let sibling: Sibling"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "Sibling", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
		])

		#expect(TypeFactsChecks.onlyIfAvailableComparisons(of: report).map(\.description) == [
			"place 2 Child as child: Child optional(x): tree nil, facts none",
			"place 3 Sibling as sibling: Sibling optional(x): tree x: X, facts bound declared",
		], "\(report.world)")
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
}
