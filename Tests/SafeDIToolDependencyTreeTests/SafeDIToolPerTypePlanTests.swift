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

/// The plan of a tree by declaration (`PerTypePlan`), which nothing reads to generate code yet: what it finds of each
/// tree's declarations and cycles, read from the frozen table.
struct SafeDIToolPerTypePlanTests: ~Copyable {
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
	mutating func generate_plansNoTree_whenNoDeclarationIsOnACycle() async throws {
		let projections = try await projections(of: """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
			public init(leafBuilder: Instantiator<Leaf>, leaf: Leaf) {
				self.leafBuilder = leafBuilder
				self.leaf = leaf
			}

			@Instantiated let leafBuilder: Instantiator<Leaf>
			@Instantiated let leaf: Leaf
		}

		@Instantiable
		public struct Leaf: Instantiable {
			public init() {}
		}
		""")

		#expect(projections == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_plansOneDeclarationPerProperty_whenScreensOpenEachOther() async throws {
		// `Home` and `Detail` open each other, so a path of the tree builds `Detail` beneath `Home` and closes on
		// `homeBuilder` there. The plan holds each property once: the root, the two screens, and the erased service each
		// screen builds as its own property.
		let projections = try await projections(of: """
		public protocol Service {}

		public final class AnyService: Service {
			public init(_ service: some Service) {}
		}

		@Instantiable
		public struct DefaultService: Service, Instantiable {
			public init() {}
		}

		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
			public init(homeBuilder: Instantiator<Home>) {
				self.homeBuilder = homeBuilder
			}

			@Instantiated let homeBuilder: Instantiator<Home>
		}

		@Instantiable
		public struct Home: Instantiable {
			public init(service: AnyService, detailBuilder: Instantiator<Detail>) {
				self.service = service
				self.detailBuilder = detailBuilder
			}

			@Instantiated(fulfilledByType: "DefaultService", erasedToConcreteExistential: true) let service: AnyService
			@Instantiated let detailBuilder: Instantiator<Detail>
		}

		@Instantiable
		public struct Detail: Instantiable {
			public init(homeBuilder: Instantiator<Home>, service: AnyService) {
				self.homeBuilder = homeBuilder
				self.service = service
			}

			@Instantiated let homeBuilder: Instantiator<Home>
			@Instantiated(fulfilledByType: "DefaultService", erasedToConcreteExistential: true) let service: AnyService
		}
		""")

		#expect(projections == [
			"""
			0: Root -> 1
			1: Home as homeBuilder: Instantiator<Home> cycle 1 -> 2 -> 3
			2: DefaultService as service: AnyService erased
			3: Detail as detailBuilder: Instantiator<Detail> cycle 1 -> 1 -> 2
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksTwins_whenCycleHoldsConstantAndLazyDeclarationOfOneLabelAndType() async throws {
		// `Detail` builds `home: Home` and `Panel` builds `home: LazilyInstantiated<Home>`: cycle validation sees one
		// property built for one type, so a path closes on whichever of the two it built first.
		let projections = try await projections(of: """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
			public init(home: Home) {
				self.home = home
			}

			@Instantiated let home: Home
		}

		@Instantiable
		public struct Home: Instantiable {
			public init(detailBuilder: Instantiator<Detail>) {
				self.detailBuilder = detailBuilder
			}

			@Instantiated let detailBuilder: Instantiator<Detail>
		}

		@Instantiable
		public struct Detail: Instantiable {
			public init(panelBuilder: Instantiator<Panel>, home: Home) {
				self.panelBuilder = panelBuilder
				self.home = home
			}

			@Instantiated let panelBuilder: Instantiator<Panel>
			@Instantiated let home: Home
		}

		@Instantiable
		public struct Panel: Instantiable {
			public init(home: LazilyInstantiated<Home>) {
				self.home = home
			}

			@Instantiated let home: LazilyInstantiated<Home>
		}
		""")

		#expect(projections == [
			"""
			0: Root -> 1
			1: Home as home: Home cycle 0 twin -> 2
			2: Detail as detailBuilder: Instantiator<Detail> cycle 0 -> 3 -> 1
			3: Panel as panelBuilder: Instantiator<Panel> cycle 0 -> 4
			4: Home as home: LazilyInstantiated<Home> cycle 0 twin -> 2
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The plan of each tree `generate` builds from `swiftFileContent` that reaches a cycle, as text, in the order first
	/// built. A run builds a root's tree more than once (to validate it, then to generate from it), and every build of
	/// one tree has one plan, so each distinct plan is listed once.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func projections(of swiftFileContent: String) async throws -> [String] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		try await PerTypePlanObservation.$observer.withValue(TaskLocalFunction { projection in
			continuation.yield(projection)
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var projections = [String]()
		for await projection in stream where !projections.contains(projection) {
			projections.append(projection)
		}
		return projections
	}
}
