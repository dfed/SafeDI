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

/// A public mock's body is laid out by the type key only behind `MockLowering.laysOutPublicMocksWithTypeKey`, since the
/// records of its places do not carry everything its body reads. Each place whose record cannot say what the walk writes
/// refuses its root where the record is made, so the root keeps the walk's body, and a root that reports `laidOut` is one
/// whose records carried its whole body.
struct SafeDIToolPublicMockTypeKeyRefusalTests: ~Copyable {
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
	mutating func mock_keepsWalksBody_whenPublicMockPromotesValueItsCallerMayPass() async throws {
		// `Screen.mock()` promotes the `service` it receives, so its body reads its caller's `service` before the override
		// and the construction, a read no alternative of the place's record holds.
		let fixture = [
			"""
			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    public init(service: Service) { self.service = service }
			    @Received let service: Service
			}
			""",
		]
		let laidOut = try await layingOutPublicMocks(fixture)
		let walk = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(laidOut.outcomes == ["Screen: unrecorded:promotedParameter"])
		#expect(laidOut.output.mockFiles == walk.mockFiles)
	}

	@Test
	mutating func mock_keepsWalksBody_whenPublicMockBuildsConfiguredTypeWithItsConstructionFunction() async throws {
		// `Child` builds a `Leaf`, so it has a configuration, and a public mock builds it by calling `Child.__safeDI_init`,
		// which it hands the override: a target and an argument no record names.
		let fixture = [
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(leaf: Leaf) { self.leaf = leaf }
			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    public init(child: Child) { self.child = child }
			    @Instantiated let child: Child
			}
			""",
		]
		let laidOut = try await layingOutPublicMocks(fixture)
		let walk = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(laidOut.outcomes == ["Screen: unrecorded:publicConstructionFunction"])
		#expect(laidOut.output.mockFiles == walk.mockFiles)
	}

	@Test
	mutating func mock_laysOutBody_whenPublicMockBuildsOnlyWhatItsRecordsCarry() async throws {
		// `Screen` builds one `Leaf`, which has no configuration and is not promoted: the record of its place holds the
		// override and the construction, which is all the walk writes of it.
		let fixture = [
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    public init(leaf: Leaf) { self.leaf = leaf }
			    @Instantiated let leaf: Leaf
			}
			""",
		]
		let laidOut = try await layingOutPublicMocks(fixture)
		let walk = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(laidOut.outcomes == ["Screen: laidOut"])
		#expect(laidOut.output.mockFiles == walk.mockFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What `generate` writes of `fixture` with public mocks laid out by the type key, and each mocked type's layout outcome.
	private mutating func layingOutPublicMocks(_ fixture: [String]) async throws -> (output: TestOutput, outcomes: [String]) {
		let (outcomeStream, outcomeContinuation) = AsyncStream.makeStream(of: String.self)
		var filesToDelete = filesToDelete
		let output = try await MockLowering.$laysOutPublicMocksWithTypeKey.withValue(true) {
			try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in outcomeContinuation.yield("\(mockedType): \(outcome)") }) {
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		self.filesToDelete = filesToDelete
		outcomeContinuation.finish()
		var outcomes = [String]()
		for await outcome in outcomeStream {
			outcomes.append(outcome)
		}
		return (output, outcomes)
	}
}
