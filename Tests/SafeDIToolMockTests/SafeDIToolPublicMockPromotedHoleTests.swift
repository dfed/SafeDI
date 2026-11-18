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

/// A public mock whose tree receives a dependency the mock promotes to its root, where the promoted dependency's tree holds
/// a place no declaration fulfills: that place is a place of the mock like any other, so `mock()` takes a builder for it
/// rather than a flat value.
struct SafeDIToolPublicMockPromotedHoleTests: ~Copyable {
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
	mutating func generate_takesABuilderForEachFamily_whenPublicMockPromotesASendableInstantiatorOfItself() async throws {
		try await expectOutput(
			of: Self.adopterModules(featAttribute: "@Instantiable(generateMock: .public)"),
			probes: [],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: SendableInstantiator<D>
				        }

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct d_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let d: @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(d: @escaping @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.d = d
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.d = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_d__d_leaf_safeDIBuilder = safeDIOverrides.d.leaf
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d.safeDIBuilder
				        @Sendable func __safeDI_d() -> D {
				            let __safeDI_apiSendableBuilder_d = __safeDI_apiSendableBuilder.d(SafeDISendableMockScope_Api.d_Values())
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            let __safeDI_apiSendableBuilder_leaf = __safeDI_apiSendableBuilder_d.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				            func __safeDI_leaf() -> Leaf {
				                let api: any Api = __safeDI_apiSendableBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				                return if let safeDIBuilder = __safeDI_d__d_leaf_safeDIBuilder { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				            }
				            let leaf: Leaf = __safeDI_leaf()
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: __safeDI_d__safeDIBuilder)
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_9254F2CA9ECAA712 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: (@Sendable (Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?,
				            safeDIBuilder: (@Sendable (Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?
				        let safeDIBuilder: (@Sendable (Leaf) -> D)?
				    }
				}

				extension D {
				    static func __safeDI_init(leaf: Leaf, safeDIBuilder: (@Sendable (Leaf) -> D)?) -> D {
				        if let safeDIBuilder { safeDIBuilder(leaf) } else { D(leaf: leaf) }
				    }
				}
				#endif

				""",
				"App": """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesABuilderForEachFamily_whenSeamsPublicMockPromotesASendableInstantiatorOfItself() async throws {
		try await expectOutput(
			of: Self.adopterModules(featAttribute: "@Instantiable(generateDependencyTree: true, generateMock: .public)"),
			probes: [],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				extension D {
				    nonisolated public enum SafeDIScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: SendableInstantiator<D>
				        }

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_d d: SendableInstantiator<D>, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIScope_Api.Leaf_Scope.api_Values())
				            return Leaf(api: api, d: d)
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        self.init(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_CB365CB5638FE581 {}
				}

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: SendableInstantiator<D>
				        }

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct d_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let d: @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(d: @escaping @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.d = d
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.d = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_d__d_leaf_safeDIBuilder = safeDIOverrides.d.leaf
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d.safeDIBuilder
				        @Sendable func __safeDI_d() -> D {
				            let __safeDI_apiSendableBuilder_d = __safeDI_apiSendableBuilder.d(SafeDISendableMockScope_Api.d_Values())
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            let __safeDI_apiSendableBuilder_leaf = __safeDI_apiSendableBuilder_d.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				            func __safeDI_leaf() -> Leaf {
				                let api: any Api = __safeDI_apiSendableBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				                return if let safeDIBuilder = __safeDI_d__d_leaf_safeDIBuilder { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				            }
				            let leaf: Leaf = __safeDI_leaf()
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: __safeDI_d__safeDIBuilder)
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_9254F2CA9ECAA712 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: (@Sendable (Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?,
				            safeDIBuilder: (@Sendable (Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?
				        let safeDIBuilder: (@Sendable (Leaf) -> D)?
				    }
				}

				extension D {
				    static func __safeDI_init(leaf: Leaf, safeDIBuilder: (@Sendable (Leaf) -> D)?) -> D {
				        if let safeDIBuilder { safeDIBuilder(leaf) } else { D(leaf: leaf) }
				    }
				}
				#endif

				""",
				"App": """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachFamilyOfThePlace_whenInternalMockCallsPublicMockPromotingASendableInstantiatorOfItself() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSendableInstantiatorOfItself, caller: .internal),
			probes: [DifferentialValueProbe("{ let screen = Screen.mock(); return [screen.screenD.leaf.api, screen.screenD.leaf.d.instantiate().leaf.api, screen.screenD.leaf.d.instantiate().leaf.api] as [any Api] }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: SendableInstantiator<D>
				        }

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct d_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let d: @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(d: @escaping @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.d = d
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.d = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_d__d_leaf_safeDIBuilder = safeDIOverrides.d.leaf
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d.safeDIBuilder
				        @Sendable func __safeDI_d() -> D {
				            let __safeDI_apiSendableBuilder_d = __safeDI_apiSendableBuilder.d(SafeDISendableMockScope_Api.d_Values())
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            let __safeDI_apiSendableBuilder_leaf = __safeDI_apiSendableBuilder_d.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				            func __safeDI_leaf() -> Leaf {
				                let api: any Api = __safeDI_apiSendableBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				                return if let safeDIBuilder = __safeDI_d__d_leaf_safeDIBuilder { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				            }
				            let leaf: Leaf = __safeDI_leaf()
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: __safeDI_d__safeDIBuilder)
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_9254F2CA9ECAA712 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: (@Sendable (Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?,
				            safeDIBuilder: (@Sendable (Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?
				        let safeDIBuilder: (@Sendable (Leaf) -> D)?
				    }
				}

				extension D {
				    static func __safeDI_init(leaf: Leaf, safeDIBuilder: (@Sendable (Leaf) -> D)?) -> D {
				        if let safeDIBuilder { safeDIBuilder(leaf) } else { D(leaf: leaf) }
				    }
				}
				#endif

				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            d: (@Sendable () -> D.SafeDIOverrides)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                screenD: screenD
				            )
				        }

				        var d: (@Sendable () -> D.SafeDIOverrides)? { __safeDI_storage.d }
				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: (@Sendable () -> D.SafeDIOverrides)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.d = d
				                self.screenD = screenD
				            }

				            let d: (@Sendable () -> D.SafeDIOverrides)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable func __safeDI_d() -> D {
				            let d = SendableInstantiator<D>(__safeDI_d)
				            @Sendable nonisolated func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(d: { _ in __safeDI_apiBuilder_D() })
				            }
				            _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
				        }
				        let d = SendableInstantiator<D>(__safeDI_d)
				        func __safeDI_screenD() -> D {
				            @Sendable nonisolated func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(d: { _ in __safeDI_apiBuilder_D() })
				            }
				            _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachFamilyOfThePlace_whenPublicMockCallsPublicMockPromotingASendableInstantiatorOfItself() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSendableInstantiatorOfItself, caller: .public),
			probes: [DifferentialValueProbe("{ let screen = Screen.mock(); return [screen.screenD.leaf.api, screen.screenD.leaf.d.instantiate().leaf.api, screen.screenD.leaf.d.instantiate().leaf.api] as [any Api] }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: SendableInstantiator<D>
				        }

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct d_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let d: @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(d: @escaping @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.d = d
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.d = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_d__d_leaf_safeDIBuilder = safeDIOverrides.d.leaf
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d.safeDIBuilder
				        @Sendable func __safeDI_d() -> D {
				            let __safeDI_apiSendableBuilder_d = __safeDI_apiSendableBuilder.d(SafeDISendableMockScope_Api.d_Values())
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            let __safeDI_apiSendableBuilder_leaf = __safeDI_apiSendableBuilder_d.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				            func __safeDI_leaf() -> Leaf {
				                let api: any Api = __safeDI_apiSendableBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				                return if let safeDIBuilder = __safeDI_d__d_leaf_safeDIBuilder { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				            }
				            let leaf: Leaf = __safeDI_leaf()
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: __safeDI_d__safeDIBuilder)
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_9254F2CA9ECAA712 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: (@Sendable (Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?,
				            safeDIBuilder: (@Sendable (Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?
				        let safeDIBuilder: (@Sendable (Leaf) -> D)?
				    }
				}

				extension D {
				    static func __safeDI_init(leaf: Leaf, safeDIBuilder: (@Sendable (Leaf) -> D)?) -> D {
				        if let safeDIBuilder { safeDIBuilder(leaf) } else { D(leaf: leaf) }
				    }
				}
				#endif

				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: (@Sendable () -> D.SafeDIOverrides)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                screenD: screenD
				            )
				        }

				        public var d: (@Sendable () -> D.SafeDIOverrides)? { __safeDI_storage.d }
				        public var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: (@Sendable () -> D.SafeDIOverrides)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.d = d
				                self.screenD = screenD
				            }

				            let d: (@Sendable () -> D.SafeDIOverrides)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    public static func mock(
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable func __safeDI_d() -> D {
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            @Sendable nonisolated func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(d: { _ in __safeDI_apiBuilder_D() })
				            }
				            _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        func __safeDI_screenD() -> D {
				            @Sendable nonisolated func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(d: { _ in __safeDI_apiBuilder_D() })
				            }
				            _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_05CC8F66B28766ED {}
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachFamilyOfThePlace_whenListedMockCallsPublicMockPromotingASendableInstantiatorOfItself() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSendableInstantiatorOfItself, caller: .listedInAnotherModule),
			probes: [DifferentialValueProbe("{ let screen = Screen.mock(); return [screen.screenD.leaf.api, screen.screenD.leaf.d.instantiate().leaf.api, screen.screenD.leaf.d.instantiate().leaf.api] as [any Api] }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: SendableInstantiator<D>
				        }

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct d_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let d: @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(d: @escaping @Sendable (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.d = d
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.d = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((any Api, SendableInstantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_d__d_leaf_safeDIBuilder = safeDIOverrides.d.leaf
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d.safeDIBuilder
				        @Sendable func __safeDI_d() -> D {
				            let __safeDI_apiSendableBuilder_d = __safeDI_apiSendableBuilder.d(SafeDISendableMockScope_Api.d_Values())
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            let __safeDI_apiSendableBuilder_leaf = __safeDI_apiSendableBuilder_d.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				            func __safeDI_leaf() -> Leaf {
				                let api: any Api = __safeDI_apiSendableBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				                return if let safeDIBuilder = __safeDI_d__d_leaf_safeDIBuilder { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				            }
				            let leaf: Leaf = __safeDI_leaf()
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: __safeDI_d__safeDIBuilder)
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_9254F2CA9ECAA712 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: (@Sendable (Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?,
				            safeDIBuilder: (@Sendable (Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: (@Sendable (any Api, SendableInstantiator<D>) -> Leaf)?
				        let safeDIBuilder: (@Sendable (Leaf) -> D)?
				    }
				}

				extension D {
				    static func __safeDI_init(leaf: Leaf, safeDIBuilder: (@Sendable (Leaf) -> D)?) -> D {
				        if let safeDIBuilder { safeDIBuilder(leaf) } else { D(leaf: leaf) }
				    }
				}
				#endif

				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"AppMocks": """
				#if canImport(App)
				import App
				#endif
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            d: (@Sendable () -> D.SafeDIOverrides)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                screenD: screenD
				            )
				        }

				        var d: (@Sendable () -> D.SafeDIOverrides)? { __safeDI_storage.d }
				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: (@Sendable () -> D.SafeDIOverrides)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.d = d
				                self.screenD = screenD
				            }

				            let d: (@Sendable () -> D.SafeDIOverrides)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable func __safeDI_d() -> D {
				            let d = SendableInstantiator<D>(__safeDI_d)
				            @Sendable nonisolated func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(d: { _ in __safeDI_apiBuilder_D() })
				            }
				            _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
				        }
				        let d = SendableInstantiator<D>(__safeDI_d)
				        func __safeDI_screenD() -> D {
				            @Sendable nonisolated func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(d: { _ in __safeDI_apiBuilder_D() })
				            }
				            _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesAPlainBuilder_whenPublicMockPromotesAnInstantiatorOfItself() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingInstantiatorOfItself, caller: .internal),
			probes: [DifferentialValueProbe("{ let screen = Screen.mock(); return [screen.screenD.leaf.api, screen.screenD.leaf.d.instantiate().leaf.api, screen.screenD.leaf.d.instantiate().leaf.api] as [any Api] }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct leaf_Values {
				            public let d: Instantiator<D>
				        }

				        nonisolated public struct d_Values {}

				        nonisolated public enum Leaf_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let leaf: (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>
				            public let d: (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(leaf: @escaping (leaf_Values) -> SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>, d: @escaping (d_Values) -> SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.leaf = leaf
				                self.d = d
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.leaf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				                self.d = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((any Api, Instantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((any Api, Instantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((any Api, Instantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((any Api, Instantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        d: Instantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        d: Instantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_d = __safeDI_apiBuilder.d(SafeDIMockScope_Api.d_Values())
				        func __safeDI_d() -> D {
				            let d = if let d { d } else { Instantiator<D>(__safeDI_d) }
				            let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder_d.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				            func __safeDI_leaf() -> Leaf {
				                let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				                return if let safeDIBuilder = safeDIOverrides.d.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				            }
				            let leaf: Leaf = __safeDI_leaf()
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: safeDIOverrides.d.safeDIBuilder)
				        }
				        let d = if let d { d } else { Instantiator<D>(__safeDI_d) }
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(SafeDIMockScope_Api.leaf_Values(d: d))
				        func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api(SafeDIMockScope_Api.Leaf_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(api, d) } else { Leaf(api: api, d: d) }
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_410ED56A65A0ECCB {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: ((any Api, Instantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: ((Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: ((any Api, Instantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: ((any Api, Instantiator<D>) -> Leaf)?,
				            safeDIBuilder: ((Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: ((any Api, Instantiator<D>) -> Leaf)?
				        let safeDIBuilder: ((Leaf) -> D)?
				    }
				}

				extension D {
				    static func __safeDI_init(leaf: Leaf, safeDIBuilder: ((Leaf) -> D)?) -> D {
				        if let safeDIBuilder { safeDIBuilder(leaf) } else { D(leaf: leaf) }
				    }
				}
				#endif

				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            d: D.SafeDIOverrides = .init(),
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                screenD: screenD
				            )
				        }

				        var d: D.SafeDIOverrides { __safeDI_storage.d }
				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: D.SafeDIOverrides,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.d = d
				                self.screenD = screenD
				            }

				            let d: D.SafeDIOverrides
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_d() -> D {
				            let d = Instantiator<D>(__safeDI_d)
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() }, d: { _ in __safeDI_apiBuilder_D() })
				            }
				            func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_410ED56A65A0ECCB.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.d)
				        }
				        let d = Instantiator<D>(__safeDI_d)
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(leaf: { _ in __safeDI_apiBuilder_D_Leaf_Scope() }, d: { _ in __safeDI_apiBuilder_D() })
				            }
				            func __safeDI_apiBuilder_D_Leaf_Scope() -> D.SafeDIMockScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_410ED56A65A0ECCB.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesASendableBuilder_whenPublicMockPromotesASendableInstantiatorOfAnotherType() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSendableInstantiatorOfOther, caller: .internal),
			probes: [DifferentialValueProbe("{ let screen = Screen.mock(); return [screen.screenD.leaf.other.instantiate().api, screen.screenD.leaf.other.instantiate().api] as [any Api] }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public enum Other_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct other_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let other: @Sendable (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping @Sendable (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.other = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: (@Sendable (any Api) -> Other)? = nil,
				            leaf: ((SendableInstantiator<Other>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var other: (@Sendable (any Api) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((SendableInstantiator<Other>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: (@Sendable (any Api) -> Other)?,
				                leaf: ((SendableInstantiator<Other>) -> Leaf)?
				            ) {
				                self.other = other
				                self.leaf = leaf
				            }

				            let other: (@Sendable (any Api) -> Other)?
				            let leaf: ((SendableInstantiator<Other>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        other: SendableInstantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        other: SendableInstantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_other__safeDIBuilder = safeDIOverrides.other
				        @Sendable func __safeDI_other() -> Other {
				            let __safeDI_apiSendableBuilder_other = __safeDI_apiSendableBuilder.other(SafeDISendableMockScope_Api.other_Values())
				            let api: any Api = __safeDI_apiSendableBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = __safeDI_other__safeDIBuilder { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = if let other { other } else { SendableInstantiator<Other>(__safeDI_other) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_4A149E99AEC1590A {}
				}
				#endif
				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                screenD: D.SafeDIOverrides
				            ) {
				                self.screenD = screenD
				            }

				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_screenD() -> D {
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_D_Other_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Other_Scope() -> D.SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_4A149E99AEC1590A.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiSendableBuilder: __safeDI_apiSendableBuilder_D(), other: nil, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesAPlainBuilder_whenPublicMockPromotesAnotherTypeByValue() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingOtherByValue, caller: .internal),
			probes: [DifferentialValueProbe("Screen.mock().screenD.leaf.other.api")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct other_Values {}

				        nonisolated public enum Other_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let other: (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.other = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((any Api) -> Other)? = nil,
				            leaf: ((Other) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var other: ((any Api) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((Other) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((any Api) -> Other)?,
				                leaf: ((Other) -> Leaf)?
				            ) {
				                self.other = other
				                self.leaf = leaf
				            }

				            let other: ((any Api) -> Other)?
				            let leaf: ((Other) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other: Other = if let other { other } else { __safeDI_other() }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_389F8635950AB28C {}
				}
				#endif
				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                screenD: D.SafeDIOverrides
				            ) {
				                self.screenD = screenD
				            }

				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_D_Other_Scope() })
				            }
				            func __safeDI_apiBuilder_D_Other_Scope() -> D.SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_389F8635950AB28C.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), other: nil, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesAPlainBuilder_whenPublicMockPromotesALazilyInstantiatedOtherType() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingLazilyInstantiatedOther, caller: .internal),
			probes: [DifferentialValueProbe("{ let before = LiveApi.created; let screen = Screen.mock(); let createdByMock = LiveApi.created - before; let api = screen.screenD.leaf.other.instance.api; return (createdByMock, LiveApi.created - before, api) }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct other_Values {}

				        nonisolated public enum Other_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let other: (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.other = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((any Api) -> Other)? = nil,
				            leaf: ((LazilyInstantiated<Other>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var other: ((any Api) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((LazilyInstantiated<Other>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((any Api) -> Other)?,
				                leaf: ((LazilyInstantiated<Other>) -> Leaf)?
				            ) {
				                self.other = other
				                self.leaf = leaf
				            }

				            let other: ((any Api) -> Other)?
				            let leaf: ((LazilyInstantiated<Other>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let other { other } else if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = LazilyInstantiated<Other>(__safeDI_other)
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_389F8635950AB28C {}
				}
				#endif
				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                screenD: D.SafeDIOverrides
				            ) {
				                self.screenD = screenD
				            }

				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_D_Other_Scope() })
				            }
				            func __safeDI_apiBuilder_D_Other_Scope() -> D.SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_389F8635950AB28C.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_D(), other: nil, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesASendableBuilder_whenPublicMockPromotesASendableLazilyInstantiatedOtherType() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSendableLazilyInstantiatedOther, caller: .internal),
			probes: [DifferentialValueProbe("{ let before = LiveApi.created; let screen = Screen.mock(); let createdByMock = LiveApi.created - before; let api = screen.screenD.leaf.other.instance.api; return (createdByMock, LiveApi.created - before, api) }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public enum Other_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct other_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let other: @Sendable (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping @Sendable (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.other = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: (@Sendable (any Api) -> Other)? = nil,
				            leaf: ((SendableLazilyInstantiated<Other>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var other: (@Sendable (any Api) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((SendableLazilyInstantiated<Other>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: (@Sendable (any Api) -> Other)?,
				                leaf: ((SendableLazilyInstantiated<Other>) -> Leaf)?
				            ) {
				                self.other = other
				                self.leaf = leaf
				            }

				            let other: (@Sendable (any Api) -> Other)?
				            let leaf: ((SendableLazilyInstantiated<Other>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_other__safeDIBuilder = safeDIOverrides.other
				        @Sendable func __safeDI_other() -> Other {
				            let __safeDI_apiSendableBuilder_other = __safeDI_apiSendableBuilder.other(SafeDISendableMockScope_Api.other_Values())
				            let api: any Api = __safeDI_apiSendableBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let other { other } else if let safeDIBuilder = __safeDI_other__safeDIBuilder { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = SendableLazilyInstantiated<Other>(__safeDI_other)
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_B192D2DD3E3AFEEA {}
				}
				#endif
				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                screenD: D.SafeDIOverrides
				            ) {
				                self.screenD = screenD
				            }

				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_screenD() -> D {
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_D_Other_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_D_Other_Scope() -> D.SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_B192D2DD3E3AFEEA.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiSendableBuilder: __safeDI_apiSendableBuilder_D(), other: nil, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesABuilderOfTheErasedType_whenPublicMockPromotesAnotherTypeWithAnErasedPlace() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingOtherWithAnErasedPlace, caller: .internal, liveApi: Self.liveApiErasedToAnyApi),
			probes: [DifferentialValueProbe("Screen.mock().screenD.leaf.other.api")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_LiveApi_AnyApi {
				        nonisolated public struct other_Values {}

				        nonisolated public enum Other_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.api = { _ in __safeDI_builder() }
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let other: (other_Values) -> SafeDIMockScope_LiveApi_AnyApi.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping (other_Values) -> SafeDIMockScope_LiveApi_AnyApi.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.other = { _ in .init(__safeDI_noScope: __safeDI_builder) }
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((AnyApi) -> Other)? = nil,
				            leaf: ((Other) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var other: ((AnyApi) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((Other) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((AnyApi) -> Other)?,
				                leaf: ((Other) -> Leaf)?
				            ) {
				                self.other = other
				                self.leaf = leaf
				            }

				            let other: ((AnyApi) -> Other)?
				            let leaf: ((Other) -> Leaf)?
				        }
				    }

				    public static func mock(
				        liveApi_AnyApiBuilder: @escaping () -> AnyApi,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(liveApi_AnyApiBuilder: .init(__safeDI_noScope: liveApi_AnyApiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        liveApi_AnyApiBuilder __safeDI_liveApi_AnyApiBuilder: D.SafeDIMockScope_LiveApi_AnyApi.__safeDI_Builder<AnyApi>,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_liveApi_AnyApiBuilder_other = __safeDI_liveApi_AnyApiBuilder.other(SafeDIMockScope_LiveApi_AnyApi.other_Values())
				        func __safeDI_other() -> Other {
				            let api: AnyApi = __safeDI_liveApi_AnyApiBuilder_other.api(SafeDIMockScope_LiveApi_AnyApi.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other: Other = if let other { other } else { __safeDI_other() }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_8512D2834E3F810F {}
				}
				#endif
				""",
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                screenD: D.SafeDIOverrides
				            ) {
				                self.screenD = screenD
				            }

				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_screenD() -> D {
				            func __safeDI_liveApi_AnyApiBuilder_D() -> D.SafeDIMockScope_LiveApi_AnyApi.__safeDI_Builder<AnyApi> {
				                .init(other: { _ in __safeDI_liveApi_AnyApiBuilder_D_Other_Scope() })
				            }
				            func __safeDI_liveApi_AnyApiBuilder_D_Other_Scope() -> D.SafeDIMockScope_LiveApi_AnyApi.Other_Scope.__safeDI_Builder<AnyApi> {
				                .init(api: { _ in
				                    let api = AnyApi(LiveApi())
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_8512D2834E3F810F.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(liveApi_AnyApiBuilder: __safeDI_liveApi_AnyApiBuilder_D(), other: nil, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}
				#endif
				""",
			],
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects each module's generated file to be exactly its entry of `expected`, after the file header, every module to
	/// compile, and the calling mock to build, for each of `probes`, the values the same graph's mock builds inline: every
	/// declaration in one module, every mock internal.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectOutput(
		of modules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		expected: KeyValuePairs<String, String>,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		for (module, expected) in expected {
			let generated = output.modules[module]?.generatedFiles["\(module).swift"]
			#expect(generated == generatedFileHeader + expected, sourceLocation: sourceLocation)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(module).swift\n" + generated.dropFirst(generatedFileHeader.count)), sourceLocation: sourceLocation)
			}
		}
		guard compileVerificationIsEnabled, !probes.isEmpty else { return }
		let inlineModules = [ModuleFixture(
			name: "Feat",
			packageName: "feat",
			swiftFileContent: modules.flatMap(\.swiftFileContent).map {
				$0.replacingOccurrences(of: "import Feat\n", with: "")
					.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
					.replacingOccurrences(of: "@Instantiable\npublic struct Screen", with: "@Instantiable(generateMock: true)\npublic struct Screen")
			},
		)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// The adopter's modules: `Feat`, which declares `D` with `featAttribute`, and `App`, another package, whose code calls
	/// `D`'s public mock as a person writes the call.
	private static func adopterModules(featAttribute: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [adopterShape.replacingOccurrences(of: "@Instantiable(generateMock: .public)", with: featAttribute)]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [adopterCall], dependencies: ["Feat"]),
		]
	}

	/// `Feat`, which declares the public mock in `feat`, and `App`, another package, whose `Screen` mock, of the kind `caller`
	/// says, calls it, and whose `LiveApi`, `liveApi`, fills every place of it.
	private static func callingModules(feat: String, caller: CallingMock, liveApi: String = liveApi) -> [ModuleFixture] {
		var modules = [
			ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [feat]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [screen.replacingOccurrences(of: "@Instantiable(generateMock: true)", with: caller.attribute), liveApi], dependencies: ["Feat"]),
		]
		if caller == .listedInAnotherModule {
			modules.append(ModuleFixture(
				name: "AppMocks",
				packageName: "app",
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n"],
				dependencies: ["Feat", "App"],
			))
		}
		return modules
	}

	/// Which mock of `Screen` calls `D`'s public mock, and where it is generated.
	private enum CallingMock {
		/// `Screen`'s own internal mock.
		case `internal`
		/// `Screen`'s own public mock.
		case `public`
		/// An internal mock of `Screen` that module `AppMocks` lists in `additionalMocksToGenerate`.
		case listedInAnotherModule

		/// The attribute `Screen` is declared with.
		var attribute: String {
			switch self {
			case .internal:
				"@Instantiable(generateMock: true)"
			case .public:
				"@Instantiable(generateMock: .public)"
			case .listedInAnotherModule:
				"@Instantiable"
			}
		}
	}

	/// The shape an adopter reported: `D`'s child `Leaf` has a place, `api`, and receives a `SendableInstantiator` of `D`,
	/// which `D`'s mock promotes, so the promoted instantiator builds `D` again, with `Leaf`'s place, in a `@Sendable`
	/// function.
	private static let adopterShape = """
	import SafeDI

	public protocol Api: Sendable {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable, Sendable {
	    public init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init(api: any Api, d: SendableInstantiator<D>) {
	        self.api = api
	        self.d = d
	    }

	    @Instantiated let api: any Api
	    @Received let d: SendableInstantiator<D>
	}
	"""

	/// The adopter's call of `D`'s public mock, in another module.
	private static let adopterCall = """
	import Feat
	import SafeDI

	#if DEBUG
	struct StubApi: Api {}

	func makeD() -> D {
	    D.mock(apiBuilder: { StubApi() }, apiSendableBuilder: { StubApi() })
	}
	#endif
	"""

	/// `adopterShape` with `D`'s initializer `internal`, so a mock in another module calls `D`'s public mock rather than
	/// building it.
	private static let promotingSendableInstantiatorOfItself = """
	import SafeDI

	public protocol Api: Sendable {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable, Sendable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init(api: any Api, d: SendableInstantiator<D>) {
	        self.api = api
	        self.d = d
	    }

	    @Instantiated let api: any Api
	    @Received let d: SendableInstantiator<D>
	}
	"""

	/// `promotingSendableInstantiatorOfItself` with an `Instantiator`, so `D` is built again in plain code.
	private static let promotingInstantiatorOfItself = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(api: any Api, d: Instantiator<D>) {
	        self.api = api
	        self.d = d
	    }

	    @Instantiated let api: any Api
	    @Received let d: Instantiator<D>
	}
	"""

	/// `D`'s child `Leaf` receives a `SendableInstantiator` of `Other`, whose place is `api`, and which `D`'s mock promotes.
	/// `Other`'s initializer is `internal`, so `App` cannot build it and passes `D`'s mock none.
	private static let promotingSendableInstantiatorOfOther = """
	import SafeDI

	public protocol Api: Sendable {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable, Sendable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init(other: SendableInstantiator<Other>) {
	        self.other = other
	    }

	    @Received let other: SendableInstantiator<Other>
	}

	@Instantiable
	public final class Other: Instantiable, Sendable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `promotingSendableInstantiatorOfOther`, `Leaf` receiving `Other` itself.
	private static let promotingOtherByValue = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(other: Other) {
	        self.other = other
	    }

	    @Received let other: Other
	}

	@Instantiable
	public final class Other: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `promotingSendableInstantiatorOfOther`, `Leaf` receiving `Other` lazily.
	private static let promotingLazilyInstantiatedOther = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(other: LazilyInstantiated<Other>) {
	        self.other = other
	    }

	    @Received let other: LazilyInstantiated<Other>
	}

	@Instantiable
	public final class Other: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `promotingSendableInstantiatorOfOther`, `Leaf` receiving `Other` lazily in a `Sendable` wrapper.
	private static let promotingSendableLazilyInstantiatedOther = """
	import SafeDI

	public protocol Api: Sendable {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable, Sendable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init(other: SendableLazilyInstantiated<Other>) {
	        self.other = other
	    }

	    @Received let other: SendableLazilyInstantiated<Other>
	}

	@Instantiable
	public final class Other: Instantiable, Sendable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `promotingOtherByValue`, `Other`'s place erased: `App`'s `LiveApi` fills it, erased to `AnyApi`.
	private static let promotingOtherWithAnErasedPlace = """
	import SafeDI

	public protocol Api {}

	public struct AnyApi: Api {
	    public init(_ value: any Api) {
	        self.value = value
	    }

	    public let value: any Api
	}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(other: Other) {
	        self.other = other
	    }

	    @Received let other: Other
	}

	@Instantiable
	public final class Other: Instantiable {
	    init(api: AnyApi) {
	        self.api = api
	    }

	    @Instantiated(fulfilledByType: "LiveApi", erasedToConcreteExistential: true) let api: AnyApi
	}
	"""

	/// A type in `App` whose mock builds `D`.
	private static let screen = """
	import Feat
	import SafeDI

	@Instantiable(generateMock: true)
	public struct Screen: Instantiable {
	    public init(screenD: D) {
	        self.screenD = screenD
	    }

	    @Instantiated let screenD: D
	}
	"""

	/// `App`'s fulfiller of `Api`, which fills every place of `D`'s mock, a class, so that two builds of it differ by identity,
	/// counting the instances it creates.
	private static let liveApi = """
	import Feat
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Api, Instantiable {
	    public init() {
	        Self.created += 1
	    }

	    nonisolated(unsafe) static var created = 0
	}
	"""

	/// `App`'s `LiveApi`, which fills `Other`'s erased place by its name.
	private static let liveApiErasedToAnyApi = """
	import Feat
	import SafeDI

	@Instantiable
	public final class LiveApi: Api, Instantiable {
	    public init() {}
	}
	"""
}
