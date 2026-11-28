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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(leaf: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				                self.init(d: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let leaf: (SendableInstantiator<D>) -> __safeDI_ApiCarrier_Leaf<__safeDI_Built>

				        public init(leaf: @escaping (SendableInstantiator<D>) -> __safeDI_ApiCarrier_Leaf<__safeDI_Built>) {
				            self.leaf = leaf
				        }
				    }

				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier_Leaf<__safeDI_Built> {
				        public let api: () -> __safeDI_Built

				        public init(api: @escaping () -> __safeDI_Built) {
				            self.api = api
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_d d: SendableInstantiator<D>, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let __safeDI_apiBuilder_leaf = __safeDI_apiBuilder.leaf(d)
				        @inline(never) func __safeDI_leaf() -> Leaf {
				            let api: any Api = __safeDI_apiBuilder_leaf.api()
				            return Leaf(api: api, d: d)
				        }
				        let leaf: Leaf = __safeDI_leaf()
				        self.init(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_47FC6CF11998EC83 {}
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(leaf: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				                self.init(d: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(leaf: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				                self.init(d: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				        apiBuilder: (() -> any Api)? = nil,
				        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				            return D.__safeDI_mock(apiBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
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
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(leaf: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				                self.init(d: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				        apiBuilder: (() -> any Api)? = nil,
				        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        Screen.__safeDI_mock(apiBuilder: apiBuilder, apiSendableBuilder: apiSendableBuilder, d: d, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
				        apiSendableBuilder __safeDI_apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        d: SendableInstantiator<D>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
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
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), apiSendableBuilder: __safeDI_apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(screenD: screenD)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_4714DB150E70249B {}
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(leaf: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				                self.init(d: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				        apiBuilder: (() -> any Api)? = nil,
				        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable nonisolated func __safeDI_d() -> D {
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
				            return D.__safeDI_mock(apiBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
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
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(leaf: { _ in .init(__safeDI_noScope: __safeDI_builder) }, d: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        apiBuilder: (() -> any Api)? = nil,
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
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.d)
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
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), d: d, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        @Sendable nonisolated func __safeDI_other() -> Other {
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: SendableInstantiator<Other>? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: SendableInstantiator<Other>?

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
				        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: SendableInstantiator<Other>? = safeDIOverrides.other
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
				            return D.__safeDI_mock(apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), other: other, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: Other? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: Other?

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
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: Other? = safeDIOverrides.other
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
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), other: other, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        other: LazilyInstantiated<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: LazilyInstantiated<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = if let other { other } else { LazilyInstantiated<Other>(__safeDI_other) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_83FFFF301188E543 {}
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: Other? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: Other?

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
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: Other? = safeDIOverrides.other
				        let other_lazilyInstantiated = other.map { instance in LazilyInstantiated<Other> { instance } }
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
				            _ = D.__safeDI_D_mock_83FFFF301188E543.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), other: other_lazilyInstantiated, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        other: SendableLazilyInstantiated<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        other: SendableLazilyInstantiated<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_other__safeDIBuilder = safeDIOverrides.other
				        @Sendable nonisolated func __safeDI_other() -> Other {
				            let __safeDI_apiSendableBuilder_other = __safeDI_apiSendableBuilder.other(SafeDISendableMockScope_Api.other_Values())
				            let api: any Api = __safeDI_apiSendableBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = __safeDI_other__safeDIBuilder { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = if let other { other } else { SendableLazilyInstantiated<Other>(__safeDI_other) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_F62724C96807E5A9 {}
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: Other? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: Other?

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
				        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: Other? = safeDIOverrides.other
				        let other_sendableLazilyInstantiated = other.map { instance in SendableLazilyInstantiated<Other> { instance } }
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
				            _ = D.__safeDI_D_mock_F62724C96807E5A9.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), other: other_sendableLazilyInstantiated, safeDIOverrides: safeDIOverrides.screenD)
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: Other? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: Other?

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
				        liveApi_AnyApiBuilder: (() -> AnyApi)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: Other? = safeDIOverrides.other
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
				            return D.__safeDI_mock(liveApi_AnyApiBuilder: liveApi_AnyApiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_liveApi_AnyApiBuilder_D(), other: other, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_passesTheCalledMockABuilderOfItsPlace_whenPublicMockPromotesAPublicMockOfAModuleBelow() async throws {
		try await expectOutput(
			of: Self.modulesBelow(base: Self.publicMockBelow, feat: Self.promotingPublicMockBelow, app: Self.screenOverModuleBelow + Self.liveApiOverModuleBelow),
			probes: [DifferentialValueProbe("{ let leaf = Screen.mock().screenD.leaf; return (leaf.other, leaf.d.instantiate().leaf.other) }()")],
			expected: [
				"Base": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Other {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct api_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(api: { _ in __safeDI_builder() })
				            }
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api
				    ) -> Other {
				        Other.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Other.SafeDIMockScope_Api.__safeDI_Builder<any Api>
				    ) -> Other {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
				        return Other(api: api)
				    }
				}

				extension Other {
				    public enum __safeDI_Other_mock_98F7041399DB6FFD {}
				}
				#endif
				""",
				"Feat": """
				#if canImport(Base)
				import Base
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct other_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let other: (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((Other, Instantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((Other, Instantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((Other, Instantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((Other, Instantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        d: Instantiator<D>? = nil,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), d: d, other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        d: Instantiator<D>? = nil,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let other = if let other { other } else { Other.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())) }
				        func __safeDI_d() -> D {
				            let d = if let d { d } else { Instantiator<D>(__safeDI_d) }
				            let leaf = if let safeDIBuilder = safeDIOverrides.d.leaf { safeDIBuilder(other, d) } else { Leaf(other: other, d: d) }
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: safeDIOverrides.d.safeDIBuilder)
				        }
				        let d = if let d { d } else { Instantiator<D>(__safeDI_d) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other, d) } else { Leaf(other: other, d: d) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_87A37A5C60473426 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: ((Other, Instantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: ((Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: ((Other, Instantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: ((Other, Instantiator<D>) -> Leaf)?,
				            safeDIBuilder: ((Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: ((Other, Instantiator<D>) -> Leaf)?
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
				#if canImport(Base)
				import Base
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
				            other: ((@escaping () -> any Api) -> Other)? = nil,
				            d: D.SafeDIOverrides = .init(),
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                d: d,
				                screenD: screenD
				            )
				        }

				        var other: ((@escaping () -> any Api) -> Other)? { __safeDI_storage.other }
				        var d: D.SafeDIOverrides { __safeDI_storage.d }
				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((@escaping () -> any Api) -> Other)?,
				                d: D.SafeDIOverrides,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.other = other
				                self.d = d
				                self.screenD = screenD
				            }

				            let other: ((@escaping () -> any Api) -> Other)?
				            let d: D.SafeDIOverrides
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_other() -> Other {
				            func __safeDI_apiBuilder_Other_api() -> any Api {
				                let api: any Api = LiveApi()
				                return api
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in __safeDI_apiBuilder_Other_api() })
				            }
				            _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder({ if let apiBuilder { apiBuilder() } else { __safeDI_apiBuilder_Other_api() } }) } else { Other.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Other()) }
				        }
				        let other: Other = __safeDI_other()
				        func __safeDI_d() -> D {
				            let d = Instantiator<D>(__safeDI_d)
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_Other() })
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_87A37A5C60473426.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), d: d, other: other, safeDIOverrides: safeDIOverrides.d)
				        }
				        let d = Instantiator<D>(__safeDI_d)
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_Other() })
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_87A37A5C60473426.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), d: d, other: other, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_passesTheCalledMockASendableBuilderOfItsPlace_whenPublicMockPromotesASendableInstantiatorOfAPublicMockOfAModuleBelow() async throws {
		try await expectOutput(
			of: Self.modulesBelow(base: Self.sendablePublicMockBelow, feat: Self.promotingSendableInstantiatorOfPublicMockBelow, app: Self.screenOverModuleBelow + Self.sendableLiveApiOverModuleBelow),
			probes: [DifferentialValueProbe("{ let leaf = Screen.mock().screenD.leaf; return (leaf.other.instantiate(), leaf.other.instantiate(), leaf.d.instantiate().leaf.other.instantiate()) }()")],
			expected: [
				"Base": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Other {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct api_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(api: { _ in __safeDI_builder() })
				            }
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api
				    ) -> Other {
				        Other.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Other.SafeDIMockScope_Api.__safeDI_Builder<any Api>
				    ) -> Other {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
				        return Other(api: api)
				    }
				}

				extension Other {
				    public enum __safeDI_Other_mock_98F7041399DB6FFD {}
				}
				#endif
				""",
				"Feat": """
				#if canImport(Base)
				import Base
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDISendableMockScope_Api {
				        nonisolated public struct other_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let other: @Sendable (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping @Sendable (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        d: SendableInstantiator<D>? = nil,
				        other: SendableInstantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiSendableBuilder __safeDI_apiSendableBuilder: D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
				        d: SendableInstantiator<D>? = nil,
				        other: SendableInstantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        @Sendable nonisolated func __safeDI_other() -> Other {
				            Other.__safeDI_mock(apiBuilder: __safeDI_apiSendableBuilder.other(SafeDISendableMockScope_Api.other_Values()))
				        }
				        let other = if let other { other } else { SendableInstantiator<Other>(__safeDI_other) }
				        let __safeDI_d__d_leaf_safeDIBuilder = safeDIOverrides.d.leaf
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d.safeDIBuilder
				        @Sendable nonisolated func __safeDI_d() -> D {
				            let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				            let leaf = if let safeDIBuilder = __safeDI_d__d_leaf_safeDIBuilder { safeDIBuilder(other, d) } else { Leaf(other: other, d: d) }
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: __safeDI_d__safeDIBuilder)
				        }
				        let d = if let d { d } else { SendableInstantiator<D>(__safeDI_d) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other, d) } else { Leaf(other: other, d: d) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_0BFAA54D97F12F84 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: (@Sendable (SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: (@Sendable (Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: (@Sendable (SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: (@Sendable (SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)?,
				            safeDIBuilder: (@Sendable (Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: (@Sendable (SendableInstantiator<Other>, SendableInstantiator<D>) -> Leaf)?
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
				#if canImport(Base)
				import Base
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
				            other: (@Sendable (@escaping () -> any Api) -> Other)? = nil,
				            d: (@Sendable () -> D.SafeDIOverrides)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                d: d,
				                screenD: screenD
				            )
				        }

				        var other: (@Sendable (@escaping () -> any Api) -> Other)? { __safeDI_storage.other }
				        var d: (@Sendable () -> D.SafeDIOverrides)? { __safeDI_storage.d }
				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: (@Sendable (@escaping () -> any Api) -> Other)?,
				                d: (@Sendable () -> D.SafeDIOverrides)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.other = other
				                self.d = d
				                self.screenD = screenD
				            }

				            let other: (@Sendable (@escaping () -> any Api) -> Other)?
				            let d: (@Sendable () -> D.SafeDIOverrides)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_other__safeDIBuilder = safeDIOverrides.other
				        @Sendable nonisolated func __safeDI_other() -> Other {
				            func __safeDI_apiBuilder_Other_api() -> any Api {
				                let api: any Api = LiveApi()
				                return api
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in __safeDI_apiBuilder_Other_api() })
				            }
				            _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return if let safeDIBuilder = __safeDI_other__safeDIBuilder { safeDIBuilder({ if let apiSendableBuilder { apiSendableBuilder() } else { __safeDI_apiBuilder_Other_api() } }) } else { Other.__safeDI_mock(apiBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Other()) }
				        }
				        let other = SendableInstantiator<Other>(__safeDI_other)
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable nonisolated func __safeDI_d() -> D {
				            let d = SendableInstantiator<D>(__safeDI_d)
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_Other() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_0BFAA54D97F12F84.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, other: other, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
				        }
				        let d = SendableInstantiator<D>(__safeDI_d)
				        func __safeDI_screenD() -> D {
				            @Sendable nonisolated func __safeDI_apiSendableBuilder_D() -> D.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_Other() })
				            }
				            @Sendable nonisolated func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_0BFAA54D97F12F84.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_D(), d: d, other: other, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_passesTheCalledMockABuilderOfItsPlace_whenPublicMockPromotesAnInstantiatorOfASeamOfAModuleBelow() async throws {
		try await expectOutput(
			of: Self.modulesBelow(base: Self.seamBelow, feat: Self.promotingInstantiatorOfSeamBelow, app: Self.screenOverModuleBelow + Self.liveApiOverModuleBelow),
			probes: [DifferentialValueProbe("{ let leaf = Screen.mock().screenD.leaf; return (leaf.other.instantiate(), leaf.other.instantiate(), leaf.d.instantiate().leaf.other.instantiate()) }()")],
			expected: [
				"Base": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				extension Other {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let api: () -> __safeDI_Built

				        public init(api: @escaping () -> __safeDI_Built) {
				            self.api = api
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api()
				        self.init(api: api)
				    }
				}

				extension Other {
				    public enum __safeDI_Other_D0DF39ED60BA8025 {}
				}

				#if DEBUG
				extension Other {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct api_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(api: { _ in __safeDI_builder() })
				            }
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api
				    ) -> Other {
				        Other.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Other.SafeDIMockScope_Api.__safeDI_Builder<any Api>
				    ) -> Other {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
				        return Other(api: api)
				    }
				}

				extension Other {
				    public enum __safeDI_Other_mock_98F7041399DB6FFD {}
				}
				#endif
				""",
				"Feat": """
				#if canImport(Base)
				import Base
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct other_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let other: (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            d: __safeDI_Feat_D_MockConfiguration = .init(),
				            leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                d: d,
				                leaf: leaf
				            )
				        }

				        public var d: __safeDI_Feat_D_MockConfiguration { __safeDI_storage.d }
				        public var leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                d: __safeDI_Feat_D_MockConfiguration,
				                leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)?
				            ) {
				                self.d = d
				                self.leaf = leaf
				            }

				            let d: __safeDI_Feat_D_MockConfiguration
				            let leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        d: Instantiator<D>? = nil,
				        other: Instantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), d: d, other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        d: Instantiator<D>? = nil,
				        other: Instantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        func __safeDI_other() -> Other {
				            Other.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values()))
				        }
				        let other = if let other { other } else { Instantiator<Other>(__safeDI_other) }
				        func __safeDI_d() -> D {
				            let d = if let d { d } else { Instantiator<D>(__safeDI_d) }
				            let leaf = if let safeDIBuilder = safeDIOverrides.d.leaf { safeDIBuilder(other, d) } else { Leaf(other: other, d: d) }
				            return D.__safeDI_init(leaf: leaf, safeDIBuilder: safeDIOverrides.d.safeDIBuilder)
				        }
				        let d = if let d { d } else { Instantiator<D>(__safeDI_d) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other, d) } else { Leaf(other: other, d: d) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_17AE6CAF5550B09C {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `D` is constructed within the public mock trees of module `Feat`.
				nonisolated public struct __safeDI_Feat_D_MockConfiguration {
				    public init(
				        leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)? = nil,
				        _ safeDIBuilder: ((Leaf) -> D)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            leaf: leaf,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)? { __safeDI_storage.leaf }
				    /// Overrides how `D` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((Leaf) -> D)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)?,
				            safeDIBuilder: ((Leaf) -> D)?
				        ) {
				            self.leaf = leaf
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let leaf: ((Instantiator<Other>, Instantiator<D>) -> Leaf)?
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
				#if canImport(Base)
				import Base
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
				            other: ((@escaping () -> any Api) -> Other)? = nil,
				            d: D.SafeDIOverrides = .init(),
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                d: d,
				                screenD: screenD
				            )
				        }

				        var other: ((@escaping () -> any Api) -> Other)? { __safeDI_storage.other }
				        var d: D.SafeDIOverrides { __safeDI_storage.d }
				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((@escaping () -> any Api) -> Other)?,
				                d: D.SafeDIOverrides,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.other = other
				                self.d = d
				                self.screenD = screenD
				            }

				            let other: ((@escaping () -> any Api) -> Other)?
				            let d: D.SafeDIOverrides
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    static func mock(
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        func __safeDI_other() -> Other {
				            func __safeDI_apiBuilder_Other_api() -> any Api {
				                let api: any Api = LiveApi()
				                return api
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in __safeDI_apiBuilder_Other_api() })
				            }
				            _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder({ if let apiBuilder { apiBuilder() } else { __safeDI_apiBuilder_Other_api() } }) } else { Other.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Other()) }
				        }
				        let other = Instantiator<Other>(__safeDI_other)
				        func __safeDI_d() -> D {
				            let d = Instantiator<D>(__safeDI_d)
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_Other() })
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_17AE6CAF5550B09C.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), d: d, other: other, safeDIOverrides: safeDIOverrides.d)
				        }
				        let d = Instantiator<D>(__safeDI_d)
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { _ in __safeDI_apiBuilder_Other() })
				            }
				            func __safeDI_apiBuilder_Other() -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_17AE6CAF5550B09C.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), d: d, other: other, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_handsThePlaceAValueTheRootBindsBeforeIt_whenPublicMockPromotesAnotherTypeThatReceivesTheValue() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingOtherReceivingAValueOfTheRoot, caller: .internal, liveApi: Self.liveApiReceivingShared),
			// `App` cannot construct `Other`, so `D`'s public mock builds it, with the `Shared` `D`'s mock binds, where the inline
			// build promotes `Other` to `Screen`'s mock with a `Shared` of its own: the Manual's "A dependency the calling module
			// cannot construct is built by each public mock that builds it". So the probe compares `Other`, whose place's fill
			// receives the `Shared` `Other` receives on both paths, and not `D`'s own `Shared`.
			probes: [DifferentialValueProbe("Screen.mock().screenD.leaf.other")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct other_Values {
				            public let shared: Shared
				        }

				        nonisolated public enum Other_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            shared: (() -> Shared)? = nil,
				            other: ((any Api, Shared) -> Other)? = nil,
				            leaf: ((Other) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                shared: shared,
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var shared: (() -> Shared)? { __safeDI_storage.shared }
				        public var other: ((any Api, Shared) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((Other) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                shared: (() -> Shared)?,
				                other: ((any Api, Shared) -> Other)?,
				                leaf: ((Other) -> Leaf)?
				            ) {
				                self.shared = shared
				                self.other = other
				                self.leaf = leaf
				            }

				            let shared: (() -> Shared)?
				            let other: ((any Api, Shared) -> Other)?
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
				        let shared = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { Shared() }
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values(shared: shared))
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api, shared) } else { Other(api: api, shared: shared) }
				        }
				        let other: Other = if let other { other } else { __safeDI_other() }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf, shared: shared)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_EB540A8EB6036FD1 {}
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: Other? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: Other?

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
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: Other? = safeDIOverrides.other
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { values in __safeDI_apiBuilder_D_Other_Scope(shared: values.shared) })
				            }
				            func __safeDI_apiBuilder_D_Other_Scope(shared: Shared) -> D.SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi(shared: shared)
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_EB540A8EB6036FD1.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), other: other, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_takesAPlainBuilder_whenPublicMockReceivesADependencyItsTreeReceivesLazily() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.receivingOtherItsTreeReceivesLazily, caller: .internal),
			probes: [DifferentialValueProbe("{ let d = Screen.mock().screenD; return (d.other, d.leaf.other.instance) }()")],
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				        other: LazilyInstantiated<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: LazilyInstantiated<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = if let other { other } else { LazilyInstantiated<Other>(__safeDI_other) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(other: other.instance, leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_83FFFF301188E543 {}
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
				            screenD: D.SafeDIOverrides = .init(),
				            other: Other? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.other = other
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let other: Other?

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
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let other: Other? = safeDIOverrides.other
				        let other_lazilyInstantiated = other.map { instance in LazilyInstantiated<Other> { instance } }
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
				            _ = D.__safeDI_D_mock_83FFFF301188E543.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), other: other_lazilyInstantiated, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_ordersThePromotedChildrensCasesAsTheMocksTreeFirstReceivesThem_whenPublicMockPromotesSeveralTypes() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSeveralTypes, caller: .internal),
			probes: [DifferentialValueProbe("{ let d = Screen.mock().screenD; return (d, d.leaf.alpha.instantiate(\"name\")) }()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct own_Values {
				            public let more: More
				            public let zeta: Zeta
				            public let alpha: Instantiator<Alpha>
				            public let leaf: Leaf
				        }

				        nonisolated public struct zeta_Values {
				            public let more: More
				        }

				        nonisolated public struct alpha_Values {
				            public let more: More
				            public let zeta: Zeta
				        }

				        nonisolated public struct more_Values {}

				        nonisolated public enum Own_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        nonisolated public enum Zeta_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        nonisolated public enum Alpha_Scope {
				            nonisolated public struct api_Values {
				                public let name: String
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        nonisolated public enum More_Scope {
				            nonisolated public struct api_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let api: (api_Values) -> __safeDI_Built

				                public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                    self.api = api
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let own: (own_Values) -> SafeDIMockScope_Api.Own_Scope.__safeDI_Builder<__safeDI_Built>
				            public let zeta: (zeta_Values) -> SafeDIMockScope_Api.Zeta_Scope.__safeDI_Builder<__safeDI_Built>
				            public let alpha: (alpha_Values) -> SafeDIMockScope_Api.Alpha_Scope.__safeDI_Builder<__safeDI_Built>
				            public let more: (more_Values) -> SafeDIMockScope_Api.More_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(own: @escaping (own_Values) -> SafeDIMockScope_Api.Own_Scope.__safeDI_Builder<__safeDI_Built>, zeta: @escaping (zeta_Values) -> SafeDIMockScope_Api.Zeta_Scope.__safeDI_Builder<__safeDI_Built>, alpha: @escaping (alpha_Values) -> SafeDIMockScope_Api.Alpha_Scope.__safeDI_Builder<__safeDI_Built>, more: @escaping (more_Values) -> SafeDIMockScope_Api.More_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.own = own
				                self.zeta = zeta
				                self.alpha = alpha
				                self.more = more
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(own: { _ in .init(__safeDI_noScope: __safeDI_builder) }, zeta: { _ in .init(__safeDI_noScope: __safeDI_builder) }, alpha: { _ in .init(__safeDI_noScope: __safeDI_builder) }, more: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            more: ((any Api) -> More)? = nil,
				            zeta: ((any Api, More) -> Zeta)? = nil,
				            alpha: ((any Api, String) -> Alpha)? = nil,
				            leaf: ((Zeta, Instantiator<Alpha>) -> Leaf)? = nil,
				            own: ((any Api) -> Own)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                more: more,
				                zeta: zeta,
				                alpha: alpha,
				                leaf: leaf,
				                own: own
				            )
				        }

				        public var more: ((any Api) -> More)? { __safeDI_storage.more }
				        public var zeta: ((any Api, More) -> Zeta)? { __safeDI_storage.zeta }
				        public var alpha: ((any Api, String) -> Alpha)? { __safeDI_storage.alpha }
				        public var leaf: ((Zeta, Instantiator<Alpha>) -> Leaf)? { __safeDI_storage.leaf }
				        public var own: ((any Api) -> Own)? { __safeDI_storage.own }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                more: ((any Api) -> More)?,
				                zeta: ((any Api, More) -> Zeta)?,
				                alpha: ((any Api, String) -> Alpha)?,
				                leaf: ((Zeta, Instantiator<Alpha>) -> Leaf)?,
				                own: ((any Api) -> Own)?
				            ) {
				                self.more = more
				                self.zeta = zeta
				                self.alpha = alpha
				                self.leaf = leaf
				                self.own = own
				            }

				            let more: ((any Api) -> More)?
				            let zeta: ((any Api, More) -> Zeta)?
				            let alpha: ((any Api, String) -> Alpha)?
				            let leaf: ((Zeta, Instantiator<Alpha>) -> Leaf)?
				            let own: ((any Api) -> Own)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        alpha: Instantiator<Alpha>? = nil,
				        more: More? = nil,
				        zeta: Zeta? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), alpha: alpha, more: more, zeta: zeta, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        alpha: Instantiator<Alpha>? = nil,
				        more: More? = nil,
				        zeta: Zeta? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_more = __safeDI_apiBuilder.more(SafeDIMockScope_Api.more_Values())
				        func __safeDI_more() -> More {
				            let api: any Api = __safeDI_apiBuilder_more.api(SafeDIMockScope_Api.More_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.more { safeDIBuilder(api) } else { More(api: api) }
				        }
				        let more: More = if let more { more } else { __safeDI_more() }
				        let __safeDI_apiBuilder_zeta = __safeDI_apiBuilder.zeta(SafeDIMockScope_Api.zeta_Values(more: more))
				        func __safeDI_zeta() -> Zeta {
				            let api: any Api = __safeDI_apiBuilder_zeta.api(SafeDIMockScope_Api.Zeta_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.zeta { safeDIBuilder(api, more) } else { Zeta(api: api, more: more) }
				        }
				        let zeta: Zeta = if let zeta { zeta } else { __safeDI_zeta() }
				        let __safeDI_apiBuilder_alpha = __safeDI_apiBuilder.alpha(SafeDIMockScope_Api.alpha_Values(more: more, zeta: zeta))
				        func __safeDI_alpha(name: String) -> Alpha {
				            let api: any Api = __safeDI_apiBuilder_alpha.api(SafeDIMockScope_Api.Alpha_Scope.api_Values(name: name))
				            return if let safeDIBuilder = safeDIOverrides.alpha { safeDIBuilder(api, name) } else { Alpha(api: api, name: name) }
				        }
				        let alpha = if let alpha { alpha } else { Instantiator<Alpha> {
				            __safeDI_alpha(name: $0)
				        } }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(zeta, alpha) } else { Leaf(zeta: zeta, alpha: alpha) }
				        let __safeDI_apiBuilder_own = __safeDI_apiBuilder.own(SafeDIMockScope_Api.own_Values(more: more, zeta: zeta, alpha: alpha, leaf: leaf))
				        func __safeDI_own() -> Own {
				            let api: any Api = __safeDI_apiBuilder_own.api(SafeDIMockScope_Api.Own_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.own { safeDIBuilder(api) } else { Own(api: api) }
				        }
				        let own: Own = __safeDI_own()
				        return D(leaf: leaf, own: own)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_B2B010B6059D397F {}
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
				            screenD: D.SafeDIOverrides = .init(),
				            alpha: Instantiator<Alpha>? = nil,
				            more: More? = nil,
				            zeta: Zeta? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				            self.alpha = alpha
				            self.more = more
				            self.zeta = zeta
				        }

				        var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        let alpha: Instantiator<Alpha>?
				        let more: More?
				        let zeta: Zeta?

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
				        apiBuilder: (() -> any Api)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let alpha: Instantiator<Alpha>? = safeDIOverrides.alpha
				        let more: More? = safeDIOverrides.more
				        let zeta: Zeta? = safeDIOverrides.zeta
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_D() -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(own: { _ in __safeDI_apiBuilder_D_Own_Scope() }, zeta: { _ in __safeDI_apiBuilder_D_Zeta_Scope() }, alpha: { _ in __safeDI_apiBuilder_D_Alpha_Scope() }, more: { _ in __safeDI_apiBuilder_D_More_Scope() })
				            }
				            func __safeDI_apiBuilder_D_Own_Scope() -> D.SafeDIMockScope_Api.Own_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            func __safeDI_apiBuilder_D_Zeta_Scope() -> D.SafeDIMockScope_Api.Zeta_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            func __safeDI_apiBuilder_D_Alpha_Scope() -> D.SafeDIMockScope_Api.Alpha_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            func __safeDI_apiBuilder_D_More_Scope() -> D.SafeDIMockScope_Api.More_Scope.__safeDI_Builder<any Api> {
				                .init(api: { _ in
				                    let api: any Api = LiveApi()
				                    return api
				                })
				            }
				            _ = D.__safeDI_D_mock_B2B010B6059D397F.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(), alpha: alpha, more: more, zeta: zeta, safeDIOverrides: safeDIOverrides.screenD)
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
	mutating func generate_handsThePlaceOnlyValuesBoundBeforeIt_whenPublicMockInAnotherPackageBuildsTheTypeTheCalledMockPromotes() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingConstructibleOther, caller: .public, liveApi: Self.stubApi),
			probes: [Self.stubApiProbe],
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct screenD_Values: Sendable {}

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
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let screenD: (screenD_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>
				            public let other: (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(screenD: @escaping (screenD_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>, other: @escaping (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.screenD = screenD
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(screenD: { _ in .init(__safeDI_noScope: __safeDI_builder) }, other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((any Api) -> Other)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                screenD: screenD
				            )
				        }

				        public var other: ((any Api) -> Other)? { __safeDI_storage.other }
				        public var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((any Api) -> Other)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.other = other
				                self.screenD = screenD
				            }

				            let other: ((any Api) -> Other)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        Screen.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Screen.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other: Other = if let other { other } else { __safeDI_other() }
				        _ = D.__safeDI_D_mock_389F8635950AB28C.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let screenD = D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.screenD(SafeDIMockScope_Api.screenD_Values()), other: other, safeDIOverrides: safeDIOverrides.screenD)
				        return Screen(screenD: screenD)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_CAB3C0E3D494A86F {}
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsThePlaceOnlyValuesBoundBeforeIt_whenPublicMockInSamePackageBuildsTheTypeTheCalledMockPromotes() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingConstructibleOther, caller: .public, liveApi: Self.stubApi, appPackageName: "feat"),
			probes: [Self.stubApiProbe],
			expected: [
				"App": """
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct screenD_Values: Sendable {}

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
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let screenD: (screenD_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>
				            public let other: (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(screenD: @escaping (screenD_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>, other: @escaping (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.screenD = screenD
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(screenD: { _ in .init(__safeDI_noScope: __safeDI_builder) }, other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((any Api) -> Other)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                screenD: screenD
				            )
				        }

				        public var other: ((any Api) -> Other)? { __safeDI_storage.other }
				        public var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((any Api) -> Other)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.other = other
				                self.screenD = screenD
				            }

				            let other: ((any Api) -> Other)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        Screen.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Screen.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other: Other = if let other { other } else { __safeDI_other() }
				        _ = D.__safeDI_D_mock_389F8635950AB28C.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let screenD = D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.screenD(SafeDIMockScope_Api.screenD_Values()), other: other, safeDIOverrides: safeDIOverrides.screenD)
				        return Screen(screenD: screenD)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_CAB3C0E3D494A86F {}
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsThePlaceOnlyValuesBoundBeforeIt_whenPublicMockBuildsAnInstantiatorTheCalledMockPromotes() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingConstructibleOtherThroughInstantiator, caller: .public, liveApi: Self.stubApi),
			probes: [Self.stubApiProbe(builderLabels: ["apiBuilder"], reading: ".screenD.leaf.other.instantiate().api, screen.screenD.leaf.other.instantiate().api", sharesOneStubApi: true)],
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
				                    self.init(api: { _ in __safeDI_builder() })
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
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((any Api) -> Other)? = nil,
				            leaf: ((Instantiator<Other>) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                leaf: leaf
				            )
				        }

				        public var other: ((any Api) -> Other)? { __safeDI_storage.other }
				        public var leaf: ((Instantiator<Other>) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((any Api) -> Other)?,
				                leaf: ((Instantiator<Other>) -> Leaf)?
				            ) {
				                self.other = other
				                self.leaf = leaf
				            }

				            let other: ((any Api) -> Other)?
				            let leaf: ((Instantiator<Other>) -> Leaf)?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        other: Instantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: D.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: Instantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = if let other { other } else { Instantiator<Other>(__safeDI_other) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_783127226CA300CE {}
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
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct screenD_Values: Sendable {}

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
				                    self.init(api: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let screenD: (screenD_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>
				            public let other: (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(screenD: @escaping (screenD_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>, other: @escaping (other_Values) -> SafeDIMockScope_Api.Other_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.screenD = screenD
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(screenD: { _ in .init(__safeDI_noScope: __safeDI_builder) }, other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            other: ((any Api) -> Other)? = nil,
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                other: other,
				                screenD: screenD
				            )
				        }

				        public var other: ((any Api) -> Other)? { __safeDI_storage.other }
				        public var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                other: ((any Api) -> Other)?,
				                screenD: D.SafeDIOverrides
				            ) {
				                self.other = other
				                self.screenD = screenD
				            }

				            let other: ((any Api) -> Other)?
				            let screenD: D.SafeDIOverrides
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api,
				        other: Instantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        Screen.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Screen.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
				        other: Instantiator<Other>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_apiBuilder_other = __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())
				        func __safeDI_other() -> Other {
				            let api: any Api = __safeDI_apiBuilder_other.api(SafeDIMockScope_Api.Other_Scope.api_Values())
				            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(api) } else { Other(api: api) }
				        }
				        let other = if let other { other } else { Instantiator<Other>(__safeDI_other) }
				        _ = D.__safeDI_D_mock_783127226CA300CE.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let screenD = D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.screenD(SafeDIMockScope_Api.screenD_Values()), other: other, safeDIOverrides: safeDIOverrides.screenD)
				        return Screen(screenD: screenD)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_CB99228069ED77B9 {}
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoBuilderForTheType_whenPublicMockCallsMockWhoseTreeReceivesItOnlyIfAvailable() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.receivingConstructibleOtherOnlyIfAvailable, caller: .public, liveApi: Self.stubApi),
			probes: [DifferentialValueProbe("Screen.mock()")],
			expected: [
				"Feat": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            leaf: ((Other?) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                leaf: leaf
				            )
				        }

				        public var leaf: ((Other?) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                leaf: ((Other?) -> Leaf)?
				            ) {
				                self.leaf = leaf
				            }

				            let leaf: ((Other?) -> Leaf)?
				        }
				    }

				    public static func mock(
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        D.__safeDI_mock(other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> D {
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_01E07719440659F9 {}
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
				            screenD: D.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                screenD: screenD
				            )
				        }

				        public var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }

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

				    public static func mock(
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        Screen.__safeDI_mock(other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = D.__safeDI_D_mock_01E07719440659F9.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let screenD = D.__safeDI_mock(other: other, safeDIOverrides: safeDIOverrides.screenD)
				        return Screen(screenD: screenD)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_01E07719440659F9 {}
				}
				#endif
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsTheFillOfAPlaceInsideTheTypeOnlyValuesBoundBeforeIt_whenPublicMockBuildsWithACallTheTypeTheCalledMockPromotes() async throws {
		// `Screen`'s mock builds the `Other` `D`'s mock promotes with a call of `Other`'s public mock, whose place `LiveApi`
		// fills, and `LiveApi` holds a place of its own, so the fill's case is handed what `Screen`'s mock binds before
		// `Other`: neither `Other` itself nor `screenD`, which it binds after.
		try await expectOutput(
			of: Self.modulesBelow(base: Self.publicMockWithAPlaceBelow, feat: Self.promotingPublicMockBelowByValue, app: Self.screenBindingValuesAroundTheCall + Self.liveApiWithAPlaceReceivingSession),
			probes: [Self.stubInnerProbe],
			expected: [
				"Base": """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Other {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct api_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(api: { _ in __safeDI_builder() })
				            }
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping () -> any Api
				    ) -> Other {
				        Other.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        apiBuilder __safeDI_apiBuilder: Other.SafeDIMockScope_Api.__safeDI_Builder<any Api>
				    ) -> Other {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values())
				        return Other(api: api)
				    }
				}

				extension Other {
				    public enum __safeDI_Other_mock_98F7041399DB6FFD {}
				}
				#endif
				""",
				"Feat": """
				#if canImport(Base)
				import Base
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension D {
				    nonisolated public enum SafeDIMockScope_Api {
				        nonisolated public struct other_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let other: (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

				            public init(other: @escaping (other_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
				                self.other = other
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(other: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            leaf: ((Other) -> Leaf)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                leaf: leaf
				            )
				        }

				        public var leaf: ((Other) -> Leaf)? { __safeDI_storage.leaf }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                leaf: ((Other) -> Leaf)?
				            ) {
				                self.leaf = leaf
				            }

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
				        _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let other = if let other { other } else { Other.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.other(SafeDIMockScope_Api.other_Values())) }
				        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder(other) } else { Leaf(other: other) }
				        return D(leaf: leaf)
				    }
				}

				extension D {
				    public enum __safeDI_D_mock_C6DE6D2ED52D206F {}
				}
				#endif
				""",
				"App": """
				#if canImport(Base)
				import Base
				#endif
				#if canImport(Feat)
				import Feat
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    nonisolated public enum SafeDIMockScope_Inner {
				        nonisolated public struct screenD_apiBuilder_Values {
				            public let session: Session
				            public let alpha: Alpha
				            public let zed: Zed
				            public let omega: Omega
				            public let other: Other
				        }

				        nonisolated public struct other_apiBuilder_Values {
				            public let session: Session
				            public let alpha: Alpha
				            public let zed: Zed
				            public let omega: Omega
				        }

				        nonisolated public enum LiveApi_Scope {
				            nonisolated public struct inner_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let inner: (inner_Values) -> __safeDI_Built

				                public init(inner: @escaping (inner_Values) -> __safeDI_Built) {
				                    self.inner = inner
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(inner: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let screenD_apiBuilder: (screenD_apiBuilder_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<__safeDI_Built>>
				            public let other_apiBuilder: (other_apiBuilder_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(screenD_apiBuilder: @escaping (screenD_apiBuilder_Values) -> D.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<__safeDI_Built>>, other_apiBuilder: @escaping (other_apiBuilder_Values) -> Other.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.screenD_apiBuilder = screenD_apiBuilder
				                self.other_apiBuilder = other_apiBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(screenD_apiBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, other_apiBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            session: (() -> Session)? = nil,
				            alpha: ((Session) -> Alpha)? = nil,
				            screenD: D.SafeDIOverrides = .init(),
				            zed: (() -> Zed)? = nil,
				            omega: ((Zed) -> Omega)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                session: session,
				                alpha: alpha,
				                screenD: screenD,
				                zed: zed,
				                omega: omega
				            )
				        }

				        public var session: (() -> Session)? { __safeDI_storage.session }
				        public var alpha: ((Session) -> Alpha)? { __safeDI_storage.alpha }
				        public var screenD: D.SafeDIOverrides { __safeDI_storage.screenD }
				        public var zed: (() -> Zed)? { __safeDI_storage.zed }
				        public var omega: ((Zed) -> Omega)? { __safeDI_storage.omega }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                session: (() -> Session)?,
				                alpha: ((Session) -> Alpha)?,
				                screenD: D.SafeDIOverrides,
				                zed: (() -> Zed)?,
				                omega: ((Zed) -> Omega)?
				            ) {
				                self.session = session
				                self.alpha = alpha
				                self.screenD = screenD
				                self.zed = zed
				                self.omega = omega
				            }

				            let session: (() -> Session)?
				            let alpha: ((Session) -> Alpha)?
				            let screenD: D.SafeDIOverrides
				            let zed: (() -> Zed)?
				            let omega: ((Zed) -> Omega)?
				        }
				    }

				    public static func mock(
				        innerBuilder: @escaping () -> any Inner,
				        apiBuilder: (() -> any Api)? = nil,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        Screen.__safeDI_mock(innerBuilder: .init(__safeDI_noScope: innerBuilder), apiBuilder: apiBuilder, other: other, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        innerBuilder __safeDI_innerBuilder: Screen.SafeDIMockScope_Inner.__safeDI_Builder<any Inner>,
				        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
				        other: Other? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
				        let alpha = if let safeDIBuilder = safeDIOverrides.alpha { safeDIBuilder(session) } else { Alpha(session: session) }
				        let zed = if let safeDIBuilder = safeDIOverrides.zed { safeDIBuilder() } else { Zed() }
				        let omega = if let safeDIBuilder = safeDIOverrides.omega { safeDIBuilder(zed) } else { Omega(zed: zed) }
				        let __safeDI_innerBuilder_other_apiBuilder = __safeDI_innerBuilder.other_apiBuilder(SafeDIMockScope_Inner.other_apiBuilder_Values(session: session, alpha: alpha, zed: zed, omega: omega))
				        func __safeDI_other() -> Other {
				            func __safeDI_apiBuilder_Other_api(_ scope: Other.SafeDIMockScope_Api.api_Values, __safeDI_other_apiBuilder: SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<any Inner>) -> any Api {
				                func __safeDI_api() -> LiveApi {
				                    let inner: any Inner = __safeDI_other_apiBuilder.inner(SafeDIMockScope_Inner.LiveApi_Scope.inner_Values())
				                    return LiveApi(inner: inner, session: session)
				                }
				                let api: any Api = __safeDI_api()
				                return api
				            }
				            func __safeDI_apiBuilder_Other(up: Other.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<any Inner>>) -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { scope in __safeDI_apiBuilder_Other_api(scope, __safeDI_other_apiBuilder: up.api(scope)) })
				            }
				            _ = Other.__safeDI_Other_mock_98F7041399DB6FFD.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Other.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Other(up: __safeDI_innerBuilder_other_apiBuilder))
				        }
				        let other: Other = if let other { other } else { __safeDI_other() }
				        let __safeDI_innerBuilder_screenD_apiBuilder = __safeDI_innerBuilder.screenD_apiBuilder(SafeDIMockScope_Inner.screenD_apiBuilder_Values(session: session, alpha: alpha, zed: zed, omega: omega, other: other))
				        func __safeDI_screenD() -> D {
				            func __safeDI_apiBuilder_Other_api(_ scope: Other.SafeDIMockScope_Api.api_Values, __safeDI_screenD_apiBuilder: SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<any Inner>) -> any Api {
				                func __safeDI_api() -> LiveApi {
				                    let inner: any Inner = __safeDI_screenD_apiBuilder.inner(SafeDIMockScope_Inner.LiveApi_Scope.inner_Values())
				                    return LiveApi(inner: inner, session: session)
				                }
				                let api: any Api = __safeDI_api()
				                return api
				            }
				            func __safeDI_apiBuilder_D(up: D.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<any Inner>>) -> D.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(other: { values in __safeDI_apiBuilder_Other(up: up.other(values)) })
				            }
				            func __safeDI_apiBuilder_Other(up: Other.SafeDIMockScope_Api.__safeDI_Builder<SafeDIMockScope_Inner.LiveApi_Scope.__safeDI_Builder<any Inner>>) -> Other.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
				                .init(api: { scope in __safeDI_apiBuilder_Other_api(scope, __safeDI_screenD_apiBuilder: up.api(scope)) })
				            }
				            _ = D.__safeDI_D_mock_C6DE6D2ED52D206F.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return D.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_D(up: __safeDI_innerBuilder_screenD_apiBuilder), other: other, safeDIOverrides: safeDIOverrides.screenD)
				        }
				        let screenD: D = __safeDI_screenD()
				        return Screen(alpha: alpha, screenD: screenD, session: session, zed: zed, omega: omega)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_mock_B44C26F8F906A2AB {}
				}
				#endif
				""",
			],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "This test compares only values, which the value comparator compiles only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTheInlineValues_whenInternalMockBuildsTheTypeTheCalledMockPromotes() async throws {
		// Values only: an internal mock of a type that is not a seam takes a flat value for a place of its own tree, a
		// deliberate gap from its twin (`seamMockBuilders`' call in `ScopeGenerator`), which no test pins.
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingConstructibleOther, caller: .internal, liveApi: Self.stubApi),
			probes: [Self.flatStubApiProbe],
			expected: [:],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "This test compares only values, which the value comparator compiles only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTheInlineValues_whenListedMockBuildsTheTypeTheCalledMockPromotes() async throws {
		// Values only: an internal mock of a type that is not a seam takes a flat value for a place of its own tree, a
		// deliberate gap from its twin (`seamMockBuilders`' call in `ScopeGenerator`), which no test pins.
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingConstructibleOther, caller: .listedInAnotherModule, liveApi: Self.stubApi),
			probes: [Self.flatStubApiProbe],
			expected: [:],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneSendableBuilderForEveryPlace_whenInternalMockPassesUpPlacesOfMockItAlsoBuildsInASendableFunction() async throws {
		try await expectOutput(
			of: Self.callingModules(feat: Self.promotingSendableInstantiatorOfItself, caller: .internal, liveApi: Self.stubApi),
			probes: [Self.stubApiProbe(builderLabels: ["apiSendableBuilder"], reading: Self.adopterShapePlaces, sharesOneStubApi: false)],
			expected: [
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
				        apiSendableBuilder: @escaping @Sendable () -> any Api,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        let __safeDI_apiSendableBuilder = apiSendableBuilder
				        _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let __safeDI_d__safeDIBuilder = safeDIOverrides.d
				        @Sendable nonisolated func __safeDI_d() -> D {
				            let d = SendableInstantiator<D>(__safeDI_d)
				            let apiBuilder: () -> any Api = __safeDI_apiSendableBuilder
				            let apiSendableBuilder: @Sendable () -> any Api = __safeDI_apiSendableBuilder
				            return D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: __safeDI_d__safeDIBuilder?() ?? .init())
				        }
				        let d = SendableInstantiator<D>(__safeDI_d)
				        _ = D.__safeDI_D_mock_9254F2CA9ECAA712.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        func __safeDI_screenD() -> D {
				            let apiBuilder: () -> any Api = __safeDI_apiSendableBuilder
				            let apiSendableBuilder: @Sendable () -> any Api = __safeDI_apiSendableBuilder
				            return D.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), d: d, safeDIOverrides: safeDIOverrides.screenD)
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
				$0.replacingOccurrences(of: "import Base\n", with: "")
					.replacingOccurrences(of: "import Feat\n", with: "")
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

	/// `Feat`, which declares the public mock in `feat`, and `App`, in `appPackageName` (another package unless it is
	/// `feat`), whose `Screen` mock, of the kind `caller` says, calls it, and whose `LiveApi`, `liveApi`, fills every place
	/// of it.
	private static func callingModules(feat: String, caller: CallingMock, liveApi: String = liveApi, appPackageName: String = "app") -> [ModuleFixture] {
		var modules = [
			ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [feat]),
			ModuleFixture(name: "App", packageName: appPackageName, swiftFileContent: [screen.replacingOccurrences(of: "@Instantiable(generateMock: true)", with: caller.attribute), liveApi], dependencies: ["Feat"]),
		]
		if caller == .listedInAnotherModule {
			modules.append(ModuleFixture(
				name: "AppMocks",
				packageName: appPackageName,
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n"],
				dependencies: ["Feat", "App"],
			))
		}
		return modules
	}

	/// `Base`, which declares `Api` and a public mock, in package `base`; `Feat`, which declares the public mock that calls
	/// it, in `feat`; and `App`, another package, whose `Screen` mock calls `Feat`'s.
	private static func modulesBelow(base: String, feat: String, app: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Base", packageName: "base", swiftFileContent: [base]),
			ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [feat], dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app], dependencies: ["Base", "Feat"]),
		]
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

	/// `promotingOtherByValue` with `Other`'s initializer `public`, so a mock in another module that calls `D`'s public mock
	/// builds the `Other` the call takes, with `Other`'s place, as `D`'s mock does.
	private static let promotingConstructibleOther = promotingOtherByValue.replacingOccurrences(of: "    init(api: any Api) {", with: "    public init(api: any Api) {")

	/// `promotingConstructibleOther`, `Leaf` receiving an `Instantiator` of `Other`.
	private static let promotingConstructibleOtherThroughInstantiator = promotingConstructibleOther
		.replacingOccurrences(of: "public init(other: Other) {", with: "public init(other: Instantiator<Other>) {")
		.replacingOccurrences(of: "@Received let other: Other", with: "@Received let other: Instantiator<Other>")

	/// `promotingConstructibleOther`, `Leaf` receiving `Other` only if available, which nothing in `D`'s tree provides, so
	/// `D`'s mock and its callers leave it `nil` and build no `Other`.
	private static let receivingConstructibleOtherOnlyIfAvailable = promotingConstructibleOther
		.replacingOccurrences(of: "public init(other: Other) {", with: "public init(other: Other?) {")
		.replacingOccurrences(of: "@Received let other: Other", with: "@Received(onlyIfAvailable: true) let other: Other?")

	/// `App`'s `StubApi`, which no declaration SafeDI reads fulfills `Api` with, so a mock of `App` passes up every place of
	/// `Api` it builds, and a call of the mock hands it a `StubApi`, a class, so that two builds of it differ by identity.
	private static let stubApi = """
	import Feat

	public final class StubApi: Api, Sendable {
	    public init() {}
	}
	"""

	/// `Screen`'s value, built with a `StubApi` for each place of `Api`: through the builder `Screen`'s mock takes for it,
	/// and inline, where an internal mock of a type that is not a seam takes a flat value for a place of its own tree.
	private static let stubApiProbe = DifferentialValueProbe(
		name: "Screen.mock(apiBuilder:)",
		expression: "Screen.mock(apiBuilder: { StubApi() })",
		knownRightExpression: "Screen.mock(api: StubApi())",
	)

	/// The places of `adopterShape` a probe of `Screen.mock(…)`'s value reads: `D`'s leaf's, and its leaf's again in each of
	/// two builds of `D` through the instantiator `D`'s mock promotes.
	private static let adopterShapePlaces = ".screenD.leaf.api, screen.screenD.leaf.d.instantiate().leaf.api, screen.screenD.leaf.d.instantiate().leaf.api"

	/// `Screen`'s value, built with a `StubApi` for each place of `Api`, `reading` the places listed after `screen`: through
	/// each builder of `builderLabels` that `Screen`'s mock takes, and inline, where an internal mock of a type that is not a
	/// seam takes a flat value for its own tree's places, which it evaluates for each place where it takes it `@autoclosure`,
	/// as for a `Sendable` value. Where `sharesOneStubApi`, each builder returns one `StubApi`, as a flat value that is no
	/// `@autoclosure` is one value for every place.
	private static func stubApiProbe(builderLabels: [String], reading places: String, sharesOneStubApi: Bool) -> DifferentialValueProbe {
		let builders = builderLabels.map { "\($0): { \(sharesOneStubApi ? "api" : "StubApi()") }" }.joined(separator: ", ")
		return DifferentialValueProbe(
			name: "Screen.mock(\(builderLabels.map { "\($0):" }.joined()))",
			expression: "{ \(sharesOneStubApi ? "let api = StubApi(); " : "")let screen = Screen.mock(\(builders)); return [screen\(places)] as [any Api] }()",
			knownRightExpression: "{ let screen = Screen.mock(api: StubApi()); return [screen\(places)] as [any Api] }()",
		)
	}

	/// `Screen`'s value, where its internal mock takes a flat value for the place of the `Other` it builds and a builder for
	/// the place `D`'s mock passes up, which it never calls, since it hands `D`'s mock that `Other`.
	private static let flatStubApiProbe = DifferentialValueProbe(
		name: "Screen.mock(api:)",
		expression: "Screen.mock(apiBuilder: { StubApi() }, api: StubApi())",
		knownRightExpression: "Screen.mock(api: StubApi())",
	)

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

	/// A public mock in a module beneath `Feat`: `Other`, whose initializer is `internal`, so `Feat` calls its public mock
	/// rather than building it, and whose place is `api`.
	private static let publicMockBelow = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class Other: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `D`'s child `Leaf` receives `publicMockBelow`'s `Other`, which `D`'s mock promotes and builds with a call of `Other`'s
	/// public mock, and an `Instantiator` of `D`, which `D`'s mock promotes too.
	private static let promotingPublicMockBelow = """
	import Base
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(other: Other, d: Instantiator<D>) {
	        self.other = other
	        self.d = d
	    }

	    @Received let other: Other
	    @Received let d: Instantiator<D>
	}
	"""

	/// `publicMockBelow` in a `Sendable` graph.
	private static let sendablePublicMockBelow = """
	import SafeDI

	public protocol Api: Sendable {}

	@Instantiable(generateMock: .public)
	public final class Other: Instantiable, Sendable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `promotingPublicMockBelow`, `Leaf` receiving `SendableInstantiator`s of `Other` and of `D`.
	private static let promotingSendableInstantiatorOfPublicMockBelow = """
	import Base
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class D: Instantiable, Sendable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable, Sendable {
	    public init(other: SendableInstantiator<Other>, d: SendableInstantiator<D>) {
	        self.other = other
	        self.d = d
	    }

	    @Received let other: SendableInstantiator<Other>
	    @Received let d: SendableInstantiator<D>
	}
	"""

	/// `publicMockBelow`, `Other` a seam too.
	private static let seamBelow = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateDependencyTree: true, generateMock: .public)
	public final class Other: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}
	"""

	/// `promotingPublicMockBelow`, `Leaf` receiving an `Instantiator` of `Other`.
	private static let promotingInstantiatorOfSeamBelow = """
	import Base
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf) {
	        self.leaf = leaf
	    }

	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(other: Instantiator<Other>, d: Instantiator<D>) {
	        self.other = other
	        self.d = d
	    }

	    @Received let other: Instantiator<Other>
	    @Received let d: Instantiator<D>
	}
	"""

	/// `screen` over `Base` and `Feat`.
	private static let screenOverModuleBelow = """
	import Base
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

	/// `App`'s fulfiller of `Base`'s `Api`.
	private static let liveApiOverModuleBelow = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Api, Instantiable {
	    public init() {}
	}
	"""

	/// `liveApiOverModuleBelow`, `Sendable`.
	private static let sendableLiveApiOverModuleBelow = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Api, Instantiable, Sendable {
	    public init() {}
	}
	"""

	/// A public mock in a module beneath `Feat`, `Other`, whose initializer is `internal`, so a mock in another module
	/// builds it with a call of its public mock, with its place `api`, beside `Session` and `Zed`, which `App`'s `Screen`
	/// instantiates.
	private static let publicMockWithAPlaceBelow = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class Other: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}

	@Instantiable
	public final class Session: Instantiable {
	    public init() {}
	}

	@Instantiable
	public final class Zed: Instantiable {
	    public init() {}
	}
	"""

	/// `D`'s child `Leaf` receives `publicMockWithAPlaceBelow`'s `Other` by value, which `D`'s mock promotes and builds with
	/// a call of `Other`'s public mock.
	private static let promotingPublicMockBelowByValue = """
	import Base
	import SafeDI

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
	"""

	/// A public mock of `App` that instantiates values before and after `D`, so its mock binds some before the `Other` it
	/// promotes for `D`'s tree and some after it.
	private static let screenBindingValuesAroundTheCall = """
	import Base
	import Feat
	import SafeDI

	@Instantiable(generateMock: .public)
	public final class Screen: Instantiable {
	    public init(alpha: Alpha, screenD: D, session: Session, zed: Zed, omega: Omega) {
	        self.alpha = alpha
	        self.screenD = screenD
	        self.session = session
	        self.zed = zed
	        self.omega = omega
	    }

	    @Instantiated let alpha: Alpha
	    @Instantiated let screenD: D
	    @Instantiated let session: Session
	    @Instantiated let zed: Zed
	    @Instantiated let omega: Omega
	}

	@Instantiable
	public final class Alpha: Instantiable {
	    public init(session: Session) {
	        self.session = session
	    }

	    @Received let session: Session
	}

	@Instantiable
	public final class Omega: Instantiable {
	    public init(zed: Zed) {
	        self.zed = zed
	    }

	    @Received let zed: Zed
	}


	"""

	/// `App`'s fulfiller of `Base`'s `Api`, which receives `Session` and holds a place of `Inner`, which no declaration
	/// SafeDI reads fulfills, and `StubInner`, which a call of `Screen`'s mock hands it.
	private static let liveApiWithAPlaceReceivingSession = """
	public protocol Inner {}

	public final class StubInner: Inner, Sendable {
	    public init() {}
	}

	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Api, Instantiable {
	    public init(inner: any Inner, session: Session) {
	        self.inner = inner
	        self.session = session
	    }

	    @Instantiated let inner: any Inner
	    @Received let session: Session
	}
	"""

	/// `Screen`'s value, built with a `StubInner` for each place of `Inner`: through the builder `Screen`'s public mock takes
	/// for it, and inline, where an internal mock of a type that is not a seam takes a flat value for a place of its own tree.
	private static let stubInnerProbe = DifferentialValueProbe(
		name: "Screen.mock(innerBuilder:)",
		expression: "Screen.mock(innerBuilder: { StubInner() })",
		knownRightExpression: "Screen.mock(inner: StubInner())",
	)

	/// `D` instantiates `shared` after `leaf`, whose received `Other` `D`'s mock promotes, and `Other` receives `shared`
	/// beside its place, so the mock's root binds `shared` before the place's level and hands it to the place's builder.
	private static let promotingOtherReceivingAValueOfTheRoot = """
	import SafeDI

	public protocol Api {}

	@Instantiable
	public final class Shared: Instantiable {
	    public init() {}
	}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf, shared: Shared) {
	        self.leaf = leaf
	        self.shared = shared
	    }

	    @Instantiated let leaf: Leaf
	    @Instantiated let shared: Shared
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
	    init(api: any Api, shared: Shared) {
	        self.api = api
	        self.shared = shared
	    }

	    @Instantiated let api: any Api
	    @Received let shared: Shared
	}
	"""

	/// `App`'s fulfiller of `Api`, which receives the `Shared` `D`'s mock binds.
	private static let liveApiReceivingShared = """
	import Feat
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Api, Instantiable {
	    public init(shared: Shared) {
	        self.shared = shared
	    }

	    @Received let shared: Shared
	}
	"""

	/// `D` receives `Other`, which nothing in its tree provides, so `D`'s mock promotes it, and `D`'s child `Leaf` receives
	/// it lazily, so the mock's root builds `Other` under the wrapper's property, which `D` does not declare.
	private static let receivingOtherItsTreeReceivesLazily = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(other: Other, leaf: Leaf) {
	        self.other = other
	        self.leaf = leaf
	    }

	    @Received let other: Other
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

	/// `D`'s child `Leaf` receives `Zeta` and an `Instantiator` of `Alpha`, and `Zeta` receives `More`, which `D`'s mock
	/// promotes in the order its tree first receives them – `zeta`, `alpha`, `more` – and builds in the order they need
	/// each other – `more`, `zeta`, `alpha` – each with a place, as `D`'s own `own` has.
	private static let promotingSeveralTypes = """
	import SafeDI

	public protocol Api {}

	@Instantiable(generateMock: .public)
	public final class D: Instantiable {
	    init(leaf: Leaf, own: Own) {
	        self.leaf = leaf
	        self.own = own
	    }

	    @Instantiated let leaf: Leaf
	    @Instantiated let own: Own
	}

	@Instantiable
	public final class Own: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}

	@Instantiable
	public final class Leaf: Instantiable {
	    public init(zeta: Zeta, alpha: Instantiator<Alpha>) {
	        self.zeta = zeta
	        self.alpha = alpha
	    }

	    @Received let zeta: Zeta
	    @Received let alpha: Instantiator<Alpha>
	}

	@Instantiable
	public final class Zeta: Instantiable {
	    init(api: any Api, more: More) {
	        self.api = api
	        self.more = more
	    }

	    @Instantiated let api: any Api
	    @Received let more: More
	}

	@Instantiable
	public final class More: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated let api: any Api
	}

	@Instantiable
	public final class Alpha: Instantiable {
	    init(api: any Api, name: String) {
	        self.api = api
	        self.name = name
	    }

	    @Instantiated let api: any Api
	    @Forwarded let name: String
	}
	"""
}
