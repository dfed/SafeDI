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

/// The oracle that no generated configuration stores another configuration by value (`GraphFuzzerConfigurationStorage`).
struct SafeDIToolGraphFuzzerConfigurationStorageTests {
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func configurationStorageFailure_isNil_whenToolGeneratesConfigurationsThatHoldOthers() async throws {
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: Self.nestedConfigurationsFixture)
		let runs = GraphFuzzerToolRuns(fixture: Self.nestedConfigurationsFixture, firstOutcome: outcome, secondOutcome: outcome)

		// The mock's overrides, the child's and the leaf's configurations, the public mock's overrides, and the public
		// configurations of the child and the leaf.
		#expect(GraphFuzzerConfigurationStorage.configurationCount(in: runs.generatedFiles) == 6)
		#expect(runs.configurationStorageFailure == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func configurationStorageFailure_reportsEachField_whenConfigurationsStoreOthersByValue() {
		let outcome = GraphFuzzerToolOutcome.accepted(
			generatedFiles: [
				"S1_Root+SafeDIMock.swift": """
				extension S1_Root {
				    struct SafeDIOverrides {
				        init(
				            child: S1_Child.SafeDIMockConfiguration = .init(),
				            service: (() -> S1_Service)? = nil
				        ) {
				            self.child = child
				            self.service = service
				        }

				        let child: S1_Child.SafeDIMockConfiguration
				        let service: (() -> S1_Service)?
				    }
				}
				""",
				"SafeDIMockConfiguration.swift": """
				nonisolated public struct __safeDI_S1_Child_MockConfiguration {
				    public init(
				        leaf: __safeDI_S1_Leaf_MockConfiguration = .init()
				    ) {
				        self.leaf = leaf
				    }

				    public let leaf: __safeDI_S1_Leaf_MockConfiguration
				}
				""",
			],
			warnings: [],
		)
		let failure = GraphFuzzerToolRuns(fixture: Self.nestedConfigurationsFixture, firstOutcome: outcome, secondOutcome: outcome).configurationStorageFailure

		#expect(failure?.kind == .configurationStoresAnotherByValue)
		// In file name order, which puts `S1_Root+SafeDIMock.swift` first, since a digit sorts before a letter.
		#expect(failure?.details.split(separator: "\n").prefix(2) == [
			"`SafeDIOverrides` in `S1_Root+SafeDIMock.swift` stores `child: S1_Child.SafeDIMockConfiguration` by value.",
			"`__safeDI_S1_Child_MockConfiguration` in `SafeDIMockConfiguration.swift` stores `leaf: __safeDI_S1_Leaf_MockConfiguration` by value.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func configurationStorageFailure_isNil_whenOverridesStoreOverrideOfReceiveOnlyIfAvailableBesideStorage() {
		let outcome = GraphFuzzerToolOutcome.accepted(
			generatedFiles: [
				"S1_Root+SafeDIMock.swift": """
				extension S1_Root {
				    struct SafeDIOverrides {
				        init(
				            child: S1_Child.SafeDIMockConfiguration = .init(),
				            user: S1_User? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                child: child
				            )
				            self.user = user
				        }

				        var child: S1_Child.SafeDIMockConfiguration { __safeDI_storage.child }
				        let user: S1_User?

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                child: S1_Child.SafeDIMockConfiguration
				            ) {
				                self.child = child
				            }

				            let child: S1_Child.SafeDIMockConfiguration
				        }
				    }
				}
				""",
			],
			warnings: [],
		)

		#expect(GraphFuzzerToolRuns(fixture: Self.nestedConfigurationsFixture, firstOutcome: outcome, secondOutcome: outcome).configurationStorageFailure == nil)
	}

	// MARK: Private

	/// A graph whose internal mock and public mock each configure a child whose configuration holds its leaf's.
	private static let nestedConfigurationsFixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
		"""
		@Instantiable(generateMock: true)
		public final class S1_Root: Instantiable {
		    public init(child: S1_Child) {
		        self.child = child
		    }

		    @Instantiated let child: S1_Child
		}
		""",
		"""
		@Instantiable(generateMock: .public)
		public final class S1_Feature: Instantiable {
		    public init(child: S1_Child) {
		        self.child = child
		    }

		    @Instantiated let child: S1_Child
		}
		""",
		"""
		@Instantiable
		public final class S1_Child: Instantiable {
		    public init(leaf: S1_Leaf) {
		        self.leaf = leaf
		    }

		    @Instantiated let leaf: S1_Leaf
		}
		""",
		"""
		@Instantiable
		public final class S1_Leaf: Instantiable {
		    public init(count: Int = 1) {}
		}
		""",
	])
}
