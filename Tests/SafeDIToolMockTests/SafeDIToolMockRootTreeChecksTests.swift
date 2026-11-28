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

/// A mock root's scopes say which checks of its generator tree can find anything there (`MockRootTreeChecks`), so that each
/// check walks only the trees that need it. The executors' oracle (`MockRootTreeChecksOracle`) holds every test to the
/// answers' soundness; these tests pin what the scopes answer for each shape.
struct SafeDIToolMockRootTreeChecksTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	mutating func mock_needsNoTreeForAnyCheck_whenEveryTypeOfRingOfInstantiatorsIsMocked() async throws {
		let needingTreeByRoot = try await needingTreeByRoot(of: [
			Self.ringType(named: "RingA", building: "RingB"),
			Self.ringType(named: "RingB", building: "RingC"),
			Self.ringType(named: "RingC", building: "RingA"),
		])
		#expect(needingTreeByRoot == ["RingA": [], "RingB": [], "RingC": []])
	}

	@Test
	mutating func mock_needsTreeForSendableCapturesAlone_whenTreeBuildsSendableInstantiator() async throws {
		let needingTreeByRoot = try await needingTreeByRoot(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(detailBuilder: SendableInstantiator<Detail>) {
			        self.detailBuilder = detailBuilder
			    }

			    @Instantiated let detailBuilder: SendableInstantiator<Detail>
			}
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init() {}
			}
			""",
		])
		#expect(needingTreeByRoot == ["Screen": [.sendableCaptures]])
	}

	@Test
	mutating func mock_needsTreeForCycleLabelsAlone_whenTreeDeclaresLabelItReceivesInTwoForms() async throws {
		let needingTreeByRoot = try await needingTreeByRoot(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(token: Token, panel: Panel, badge: Badge) {
			        self.token = token
			        self.panel = panel
			        self.badge = badge
			    }

			    @Instantiated let token: Token
			    @Instantiated let panel: Panel
			    @Instantiated let badge: Badge
			}
			""",
			"""
			@Instantiable
			public final class Panel: Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""",
			"""
			@Instantiable
			public final class Badge: Instantiable {
			    public init(token: Token?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Token?
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
		])
		#expect(needingTreeByRoot == ["Screen": [.cycleLabels]])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The checks each mock root's scopes say need its tree, by mocked type, of a run over `swiftFileContent`.
	private mutating func needingTreeByRoot(of swiftFileContent: [String]) async throws -> [String: Set<MockRootTreeCheck>] {
		let (comparisons, continuation) = AsyncStream.makeStream(of: MockRootTreeChecksComparison.self)
		_ = try await MockRootTreeChecksObservation.$comparesTree.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: swiftFileContent,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var needingTreeByRoot = [String: Set<MockRootTreeCheck>]()
		for await comparison in comparisons {
			needingTreeByRoot[comparison.root] = comparison.needingTree
		}
		return needingTreeByRoot
	}

	private static func ringType(named name: String, building builtName: String) -> String {
		let label = "\(builtName.prefix(1).lowercased())\(builtName.dropFirst())Builder"
		return """
		@Instantiable(generateMock: true)
		public final class \(name): Instantiable {
		    public init(\(label): Instantiator<\(builtName)>) {
		        self.\(label) = \(label)
		    }

		    @Instantiated let \(label): Instantiator<\(builtName)>
		}
		"""
	}
}
