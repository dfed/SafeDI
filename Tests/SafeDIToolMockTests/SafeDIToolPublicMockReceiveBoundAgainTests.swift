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

/// A public mock binds a receive again, under its label, in the scope that makes it, where the nearest declaration of its
/// label above provides another form (a mock parameter named apart, `user_Draft`). Beneath that scope the binding hides the
/// farther declaration, as a declaration of the scope's type does: the type's level carries the received value, a fill that
/// reads its form is handed it, as inline is, and a fill that reads the hidden form is passed up, never handed the farther
/// value, which inline rejects as hidden.
struct SafeDIToolPublicMockReceiveBoundAgainTests: ~Copyable {
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
	mutating func generate_passesPlaceUp_whenFillReadsLabelThatReceiveInSendableFunctionOnCycleBindsAgainInAnotherForm() async throws {
		// `B`, built in `X`'s `SendableInstantiator<B>` on a cycle, receives `user: Draft`, which `Hub`'s mock binds again from `user_Draft`
		// beneath `Hub`'s `user: User`. `LiveApi`, reading `user: User`, would be handed `Hub`'s, which inline rejects as hidden.
		let modules = Self.modules(feature: Self.feature(wrapper: .sendable, closesCycle: true), liveApiReads: "User")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
			                public let x: X
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
			    }

			    nonisolated public enum SafeDISendableMockScope_Api {
			        nonisolated public struct x_Sendable_Values: Sendable {}

			        nonisolated public enum X_Scope {
			            nonisolated public struct bBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let bBuilder: @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(bBuilder: @escaping @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.bBuilder = bBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let x_Sendable: @Sendable (x_Sendable_Values) -> SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(x_Sendable: @escaping @Sendable (x_Sendable_Values) -> SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.x_Sendable = x_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(x_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            x: __safeDI_Feature_X_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                x: x
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                x: __safeDI_Feature_X_MockConfiguration
			            ) {
			                self.user = user
			                self.x = x
			            }

			            let user: (() -> User)?
			            let x: __safeDI_Feature_X_MockConfiguration
			        }
			    }

			    public static func mock(
			        user_Draft: Draft,
			        apiSendableBuilder: @escaping @Sendable () -> any Api,
			        user: User? = nil,
			        x: X? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), user: user, x: x, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        user_Draft: Draft,
			        apiSendableBuilder __safeDI_apiSendableBuilder: Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
			        user: User? = nil,
			        x: X? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let __safeDI_x__safeDIBuilder = safeDIOverrides.x.safeDIBuilder
			        @Sendable nonisolated func __safeDI_x() -> X {
			            let __safeDI_apiSendableBuilder_x_Sendable = __safeDI_apiSendableBuilder.x_Sendable(SafeDISendableMockScope_Api.x_Sendable_Values())
			            @Sendable nonisolated func __safeDI_bBuilder() -> B {
			                let __safeDI_apiSendableBuilder_bBuilder = __safeDI_apiSendableBuilder_x_Sendable.bBuilder(SafeDISendableMockScope_Api.X_Scope.bBuilder_Values())
			                let user: Draft = user_Draft
			                let x: X = __safeDI_x()
			                let api: any Api = __safeDI_apiSendableBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x))
			                return B.__safeDI_init(api: api, x: x, user: user, safeDIBuilder: nil)
			            }
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return X.__safeDI_init(bBuilder: bBuilder, safeDIBuilder: __safeDI_x__safeDIBuilder)
			        }
			        let x: X = if let x { x } else { __safeDI_x() }
			        return Hub(user: user, x: x)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_BF59370D78E87A91 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_B_MockConfiguration {
			    public init(
			        x: __safeDI_Feature_X_MockConfiguration = .init(),
			        _ safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            x: x,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            x: __safeDI_Feature_X_MockConfiguration,
			            safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
			        ) {
			            self.x = x
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let x: __safeDI_Feature_X_MockConfiguration
			        let safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
			    }
			}

			extension B {
			    static func __safeDI_init(api: any Api, x: X, user: Draft, safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(api, x, user) } else { B(api: api, x: x, user: user) }
			    }
			}

			/// Configuration for how `X` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_X_MockConfiguration {
			    public init(
			        _ safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			    }
			}

			extension X {
			    static func __safeDI_init(bBuilder: SendableInstantiator<B>, safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?) -> X {
			        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			    }
			}
			#endif

			""",
		])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x_Sendable: { _ in __safeDI_apiSendableBuilder_Hub_X_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_X_Scope() -> Hub.SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_BF59370D78E87A91.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithReceivedValue_whenFillReadsFormThatReceiveInSendableFunctionOnCycleBindsAgain() async throws {
		// `LiveApi` reads `user: Draft`, the value `B` receives, which `B`'s level carries, as inline hands it `user_Draft`.
		let modules = Self.modules(feature: Self.feature(wrapper: .sendable, closesCycle: true), liveApiReads: "Draft")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.sendableCycleFeature])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x_Sendable: { _ in __safeDI_apiSendableBuilder_Hub_X_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_X_Scope() -> Hub.SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_BF59370D78E87A91.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock(user_Draft: Draft())")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUp_whenFillReadsOnlyIfAvailableLabelThatReceiveInSendableFunctionOnCycleBindsAgainInAnotherForm() async throws {
		// `LiveApi` reads `user: User?` only if available: `B`'s `user: Draft` hides `Hub`'s `user: User`, so the fill is not handed it.
		let modules = Self.modules(feature: Self.feature(wrapper: .sendable, closesCycle: true), liveApiReads: "User?")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
			                public let x: X
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
			    }

			    nonisolated public enum SafeDISendableMockScope_Api {
			        nonisolated public struct x_Sendable_Values: Sendable {}

			        nonisolated public enum X_Scope {
			            nonisolated public struct bBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let bBuilder: @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(bBuilder: @escaping @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.bBuilder = bBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let x_Sendable: @Sendable (x_Sendable_Values) -> SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(x_Sendable: @escaping @Sendable (x_Sendable_Values) -> SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.x_Sendable = x_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(x_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            x: __safeDI_Feature_X_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                x: x
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                x: __safeDI_Feature_X_MockConfiguration
			            ) {
			                self.user = user
			                self.x = x
			            }

			            let user: (() -> User)?
			            let x: __safeDI_Feature_X_MockConfiguration
			        }
			    }

			    public static func mock(
			        user_Draft: Draft,
			        apiSendableBuilder: @escaping @Sendable () -> any Api,
			        user: User? = nil,
			        x: X? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), user: user, x: x, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        user_Draft: Draft,
			        apiSendableBuilder __safeDI_apiSendableBuilder: Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
			        user: User? = nil,
			        x: X? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let __safeDI_x__safeDIBuilder = safeDIOverrides.x.safeDIBuilder
			        @Sendable nonisolated func __safeDI_x() -> X {
			            let __safeDI_apiSendableBuilder_x_Sendable = __safeDI_apiSendableBuilder.x_Sendable(SafeDISendableMockScope_Api.x_Sendable_Values())
			            @Sendable nonisolated func __safeDI_bBuilder() -> B {
			                let __safeDI_apiSendableBuilder_bBuilder = __safeDI_apiSendableBuilder_x_Sendable.bBuilder(SafeDISendableMockScope_Api.X_Scope.bBuilder_Values())
			                let user: Draft = user_Draft
			                let x: X = __safeDI_x()
			                let api: any Api = __safeDI_apiSendableBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x))
			                return B.__safeDI_init(api: api, x: x, user: user, safeDIBuilder: nil)
			            }
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return X.__safeDI_init(bBuilder: bBuilder, safeDIBuilder: __safeDI_x__safeDIBuilder)
			        }
			        let x: X = if let x { x } else { __safeDI_x() }
			        return Hub(user: user, x: x)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_BF59370D78E87A91 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_B_MockConfiguration {
			    public init(
			        x: __safeDI_Feature_X_MockConfiguration = .init(),
			        _ safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            x: x,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            x: __safeDI_Feature_X_MockConfiguration,
			            safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
			        ) {
			            self.x = x
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let x: __safeDI_Feature_X_MockConfiguration
			        let safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
			    }
			}

			extension B {
			    static func __safeDI_init(api: any Api, x: X, user: Draft, safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(api, x, user) } else { B(api: api, x: x, user: user) }
			    }
			}

			/// Configuration for how `X` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_X_MockConfiguration {
			    public init(
			        _ safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			    }
			}

			extension X {
			    static func __safeDI_init(bBuilder: SendableInstantiator<B>, safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?) -> X {
			        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			    }
			}
			#endif

			""",
		])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x_Sendable: { _ in __safeDI_apiSendableBuilder_Hub_X_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_X_Scope() -> Hub.SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(user: nil)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_BF59370D78E87A91.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithReceivedValue_whenFillReadsOnlyIfAvailableFormThatReceiveInSendableFunctionOnCycleBindsAgain() async throws {
		// `LiveApi` reads `user: Draft?` only if available, which `B`'s `user: Draft` provides.
		let modules = Self.modules(feature: Self.feature(wrapper: .sendable, closesCycle: true), liveApiReads: "Draft?")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.sendableCycleFeature])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x_Sendable: { _ in __safeDI_apiSendableBuilder_Hub_X_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_X_Scope() -> Hub.SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_BF59370D78E87A91.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock(user_Draft: Draft())")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUp_whenFillReadsLabelThatReceiveInSendableInstantiatorBindsAgainInAnotherForm() async throws {
		// No cycle: `Hub` receives `SendableInstantiator<B>` itself, and `B` receives `user: Draft` beneath `Hub`'s `user: User`.
		let modules = Self.modules(feature: Self.feature(wrapper: .sendable, closesCycle: false), liveApiReads: "User")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
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
			    }

			    nonisolated public enum SafeDISendableMockScope_Api {
			        nonisolated public struct bBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let bBuilder: @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(bBuilder: @escaping @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.bBuilder = bBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            bBuilder: (@Sendable (any Api, Draft) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                bBuilder: bBuilder
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var bBuilder: (@Sendable (any Api, Draft) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                bBuilder: (@Sendable (any Api, Draft) -> B)?
			            ) {
			                self.user = user
			                self.bBuilder = bBuilder
			            }

			            let user: (() -> User)?
			            let bBuilder: (@Sendable (any Api, Draft) -> B)?
			        }
			    }

			    public static func mock(
			        user_Draft: Draft,
			        apiSendableBuilder: @escaping @Sendable () -> any Api,
			        bBuilder: SendableInstantiator<B>? = nil,
			        user: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), bBuilder: bBuilder, user: user, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        user_Draft: Draft,
			        apiSendableBuilder __safeDI_apiSendableBuilder: Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
			        bBuilder: SendableInstantiator<B>? = nil,
			        user: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let __safeDI_bBuilder__safeDIBuilder = safeDIOverrides.bBuilder
			        @Sendable nonisolated func __safeDI_bBuilder() -> B {
			            let __safeDI_apiSendableBuilder_bBuilder = __safeDI_apiSendableBuilder.bBuilder(SafeDISendableMockScope_Api.bBuilder_Values())
			            let user: Draft = user_Draft
			            let api: any Api = __safeDI_apiSendableBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))
			            return if let safeDIBuilder = __safeDI_bBuilder__safeDIBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
			        }
			        let bBuilder = if let bBuilder { bBuilder } else { SendableInstantiator<B>(__safeDI_bBuilder) }
			        return Hub(user: user, bBuilder: bBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_F3FC3EE051794EEE {}
			}
			#endif
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            bBuilder: SendableInstantiator<B>? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.bBuilder = bBuilder
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let bBuilder: SendableInstantiator<B>?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let bBuilder: SendableInstantiator<B>? = safeDIOverrides.bBuilder
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_F3FC3EE051794EEE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_Hub(), bBuilder: bBuilder, user: user, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUp_whenFillReadsLabelThatReceiveInInstantiatorOnCycleBindsAgainInAnotherForm() async throws {
		// In plain code `Hub`'s level carries `user: User`; `B`'s `user: Draft`, bound again beneath it, hides it, so the fill that reads
		// `user: User` is passed up rather than handed `Hub`'s, which inline rejects as hidden.
		let modules = Self.modules(feature: Self.feature(wrapper: .plain, closesCycle: true), liveApiReads: "User")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct x_Values {
			            public let user: User
			        }

			        nonisolated public enum X_Scope {
			            nonisolated public struct bBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.bBuilder = bBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
			                public let x: X
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

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let x: (x_Values) -> SafeDIMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(x: @escaping (x_Values) -> SafeDIMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.x = x
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(x: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            x: __safeDI_Feature_X_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                x: x
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                x: __safeDI_Feature_X_MockConfiguration
			            ) {
			                self.user = user
			                self.x = x
			            }

			            let user: (() -> User)?
			            let x: __safeDI_Feature_X_MockConfiguration
			        }
			    }

			    public static func mock(
			        user_Draft: Draft,
			        apiBuilder: @escaping () -> any Api,
			        user: User? = nil,
			        x: X? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: .init(__safeDI_noScope: apiBuilder), user: user, x: x, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        user_Draft: Draft,
			        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        user: User? = nil,
			        x: X? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let __safeDI_apiBuilder_x = __safeDI_apiBuilder.x(SafeDIMockScope_Api.x_Values(user: user))
			        func __safeDI_x() -> X {
			            let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder_x.bBuilder(SafeDIMockScope_Api.X_Scope.bBuilder_Values())
			            func __safeDI_bBuilder() -> B {
			                let user: Draft = user_Draft
			                let x: X = __safeDI_x()
			                let api: any Api = __safeDI_apiBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x))
			                return B.__safeDI_init(api: api, x: x, user: user, safeDIBuilder: nil)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return X.__safeDI_init(bBuilder: bBuilder, safeDIBuilder: safeDIOverrides.x.safeDIBuilder)
			        }
			        let x: X = if let x { x } else { __safeDI_x() }
			        return Hub(user: user, x: x)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_C92FAC1B9AC96ECD {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_B_MockConfiguration {
			    public init(
			        x: __safeDI_Feature_X_MockConfiguration = .init(),
			        _ safeDIBuilder: ((any Api, X, Draft) -> B)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            x: x,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((any Api, X, Draft) -> B)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            x: __safeDI_Feature_X_MockConfiguration,
			            safeDIBuilder: ((any Api, X, Draft) -> B)?
			        ) {
			            self.x = x
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let x: __safeDI_Feature_X_MockConfiguration
			        let safeDIBuilder: ((any Api, X, Draft) -> B)?
			    }
			}

			extension B {
			    static func __safeDI_init(api: any Api, x: X, user: Draft, safeDIBuilder: ((any Api, X, Draft) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(api, x, user) } else { B(api: api, x: x, user: user) }
			    }
			}

			/// Configuration for how `X` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_X_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((Instantiator<B>) -> X)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<B>) -> X)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: ((Instantiator<B>) -> X)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: ((Instantiator<B>) -> X)?
			    }
			}

			extension X {
			    static func __safeDI_init(bBuilder: Instantiator<B>, safeDIBuilder: ((Instantiator<B>) -> X)?) -> X {
			        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			    }
			}
			#endif

			""",
		])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x: { _ in __safeDI_apiBuilder_Hub_X_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_X_Scope() -> Hub.SafeDIMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_C92FAC1B9AC96ECD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithReceivedValue_whenFillReadsFormThatReceiveInInstantiatorOnCycleBindsAgain() async throws {
		// `LiveApi` reads `user: Draft`, which `B`'s level carries from the binding the mock makes again.
		let modules = Self.modules(feature: Self.feature(wrapper: .plain, closesCycle: true), liveApiReads: "Draft")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.plainCycleFeature])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x: { _ in __safeDI_apiBuilder_Hub_X_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_X_Scope() -> Hub.SafeDIMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_C92FAC1B9AC96ECD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock(user_Draft: Draft())")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUp_whenFillReadsLabelThatReceiveInInstantiatorBindsAgainInAnotherForm() async throws {
		// No cycle: `Hub` receives `Instantiator<B>` itself, and `B` receives `user: Draft` beneath `Hub`'s `user: User`.
		let modules = Self.modules(feature: Self.feature(wrapper: .plain, closesCycle: false), liveApiReads: "User")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Hub {
			    nonisolated public enum SafeDIMockScope_Api {
			        nonisolated public struct bBuilder_Values {
			            public let user: User
			        }

			        nonisolated public enum B_Scope {
			            nonisolated public struct api_Values {
			                public let user: Draft
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

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.bBuilder = bBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            user: (() -> User)? = nil,
			            bBuilder: ((any Api, Draft) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                user: user,
			                bBuilder: bBuilder
			            )
			        }

			        public var user: (() -> User)? { __safeDI_storage.user }
			        public var bBuilder: ((any Api, Draft) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                user: (() -> User)?,
			                bBuilder: ((any Api, Draft) -> B)?
			            ) {
			                self.user = user
			                self.bBuilder = bBuilder
			            }

			            let user: (() -> User)?
			            let bBuilder: ((any Api, Draft) -> B)?
			        }
			    }

			    public static func mock(
			        user_Draft: Draft,
			        apiBuilder: @escaping () -> any Api,
			        bBuilder: Instantiator<B>? = nil,
			        user: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: .init(__safeDI_noScope: apiBuilder), bBuilder: bBuilder, user: user, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        user_Draft: Draft,
			        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			        bBuilder: Instantiator<B>? = nil,
			        user: User? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
			        let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder.bBuilder(SafeDIMockScope_Api.bBuilder_Values(user: user))
			        func __safeDI_bBuilder() -> B {
			            let user: Draft = user_Draft
			            let api: any Api = __safeDI_apiBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
			        }
			        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			        return Hub(user: user, bBuilder: bBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_mock_AC7AE65B2B9A4A12 {}
			}
			#endif
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            bBuilder: Instantiator<B>? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.bBuilder = bBuilder
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let bBuilder: Instantiator<B>?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let bBuilder: Instantiator<B>? = safeDIOverrides.bBuilder
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_AC7AE65B2B9A4A12.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), bBuilder: bBuilder, user: user, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithReceivedValue_whenFillReadsFormThatReceiveInInstantiatorBindsAgain() async throws {
		// No cycle: `LiveApi` reads the `user: Draft` that `B` receives.
		let modules = Self.modules(feature: Self.feature(wrapper: .plain, closesCycle: false), liveApiReads: "Draft")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.plainNoCycleFeature])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            bBuilder: Instantiator<B>? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.bBuilder = bBuilder
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let bBuilder: Instantiator<B>?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let bBuilder: Instantiator<B>? = safeDIOverrides.bBuilder
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_AC7AE65B2B9A4A12.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), bBuilder: bBuilder, user: user, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock(user_Draft: Draft())")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithReceivedValue_whenReceiveThatBindsLabelAgainIsOnlyIfAvailable() async throws {
		// `B` receives `user: Draft?` only if available, which the mock binds again from its override beneath `Hub`'s `user: User`.
		let modules = Self.modules(feature: Self.feature(wrapper: .plain, closesCycle: true, receivesDraftOnlyIfAvailable: true), liveApiReads: "Draft?")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.plainCycleOnlyIfAvailableFeature])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            hub: Hub.SafeDIOverrides = .init(),
		            x: X? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                hub: hub
		            )
		            self.x = x
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var hub: Hub.SafeDIOverrides { __safeDI_storage.hub }
		        let x: X?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                hub: Hub.SafeDIOverrides
		            ) {
		                self.user = user
		                self.hub = hub
		            }

		            let user: (() -> User)?
		            let hub: Hub.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x: X? = safeDIOverrides.x
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(x: { _ in __safeDI_apiBuilder_Hub_X_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_X_Scope() -> Hub.SafeDIMockScope_Api.X_Scope.__safeDI_Builder<any Api> {
		                .init(bBuilder: { _ in __safeDI_apiBuilder_Hub_B_Scope() })
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.SafeDIMockScope_Api.B_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                })
		            }
		            _ = Hub.__safeDI_Hub_mock_06EB73166E9429F2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Hub.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Hub(), user: user, x: x, safeDIOverrides: safeDIOverrides.hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        return Screen(hub: hub)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The wrapper `B` is built in.
	private enum Wrapper: String {
		case sendable = "SendableInstantiator"
		case plain = "Instantiator"
	}

	/// `Feature`'s file: `Hub`'s public mock receives `user: User`, and `B`, built in `wrapper`, has the hole `api` and
	/// receives `user: Draft`, which no declaration in `Feature` provides. When `closesCycle`, `Hub` receives `X`, which
	/// holds `wrapper<B>`, and `B` builds `X` again; otherwise `Hub` receives `wrapper<B>`. `X` or `B` has a `package`
	/// initializer, so a module of another package calls `Hub`'s public mock.
	private static func feature(wrapper: Wrapper, closesCycle: Bool, receivesDraftOnlyIfAvailable: Bool = false) -> String {
		let sendable = wrapper == .sendable ? ", Sendable" : ""
		let draft = receivesDraftOnlyIfAvailable ? "Draft?" : "Draft"
		let receive = receivesDraftOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var content = """
		import SafeDI

		public protocol Api: Sendable {}

		public final class Draft: Sendable {
		    public init() {}
		}

		@Instantiable
		public final class User: Instantiable, Sendable {
		    public init() {}
		}

		"""
		if closesCycle {
			content += """
			@Instantiable(generateMock: .public)
			public struct Hub: Instantiable\(sendable) {
			    public init(user: User, x: X) {
			        self.user = user
			        self.x = x
			    }

			    @Received public let user: User
			    @Received public let x: X
			}

			@Instantiable
			public struct X: Instantiable\(sendable) {
			    package init(bBuilder: \(wrapper.rawValue)<B>) {
			        self.bBuilder = bBuilder
			    }

			    @Instantiated public let bBuilder: \(wrapper.rawValue)<B>
			}

			@Instantiable
			public struct B: Instantiable\(sendable) {
			    public init(api: any Api, x: X, user: \(draft)) {
			        self.api = api
			        self.x = x
			        self.user = user
			    }

			    @Instantiated public let api: any Api
			    @Instantiated public let x: X
			    \(receive) public let user: \(draft)
			}
			"""
		} else {
			content += """
			@Instantiable(generateMock: .public)
			public struct Hub: Instantiable\(sendable) {
			    public init(user: User, bBuilder: \(wrapper.rawValue)<B>) {
			        self.user = user
			        self.bBuilder = bBuilder
			    }

			    @Received public let user: User
			    @Received public let bBuilder: \(wrapper.rawValue)<B>
			}

			@Instantiable
			public struct B: Instantiable\(sendable) {
			    package init(api: any Api, user: \(draft)) {
			        self.api = api
			        self.user = user
			    }

			    @Instantiated public let api: any Api
			    \(receive) public let user: \(draft)
			}
			"""
		}
		return content
	}

	/// `Feature` with `feature`, and `App`, another package, whose `Screen` instantiates `Hub` and whose `LiveApi` fills
	/// `api`, receiving `user` as `liveApiReads`, only if available when it is optional.
	private static func modules(feature: String, liveApiReads: String) -> [ModuleFixture] {
		let receive = liveApiReads.hasSuffix("?") ? "@Received(onlyIfAvailable: true)" : "@Received"
		return [
			ModuleFixture(name: "Feature", packageName: "feature", swiftFileContent: [feature]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Feature
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(user: \(liveApiReads)) {
				        self.user = user
				    }

				    \(receive) public let user: \(liveApiReads)
				}
				""",
				"""
				import Feature
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(hub: Hub) {
				        self.hub = hub
				    }

				    @Instantiated public let hub: Hub
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// `Feature`'s file for the tree `feature(…)` makes sendableCycle.
	private static let sendableCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    nonisolated public enum SafeDIMockScope_Api {
	        nonisolated public enum B_Scope {
	            nonisolated public struct api_Values {
	                public let user: Draft
	                public let x: X
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
	    }

	    nonisolated public enum SafeDISendableMockScope_Api {
	        nonisolated public struct x_Sendable_Values: Sendable {}

	        nonisolated public enum X_Scope {
	            nonisolated public struct bBuilder_Values: Sendable {}

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
	                public let bBuilder: @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

	                public init(bBuilder: @escaping @Sendable (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
	                    self.bBuilder = bBuilder
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
	                    self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	                }
	            }
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
	            public let x_Sendable: @Sendable (x_Sendable_Values) -> SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(x_Sendable: @escaping @Sendable (x_Sendable_Values) -> SafeDISendableMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.x_Sendable = x_Sendable
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
	                self.init(x_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            x: __safeDI_Feature_X_MockConfiguration = .init()
	        ) {
	            __safeDI_storage = __safeDI_Storage(
	                user: user,
	                x: x
	            )
	        }

	        public var user: (() -> User)? { __safeDI_storage.user }
	        public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }

	        private let __safeDI_storage: __safeDI_Storage

	        private final class __safeDI_Storage {
	            init(
	                user: (() -> User)?,
	                x: __safeDI_Feature_X_MockConfiguration
	            ) {
	                self.user = user
	                self.x = x
	            }

	            let user: (() -> User)?
	            let x: __safeDI_Feature_X_MockConfiguration
	        }
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiSendableBuilder: @escaping @Sendable () -> any Api,
	        user: User? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        Hub.__safeDI_mock(user_Draft: user_Draft, apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), user: user, x: x, safeDIOverrides: safeDIOverrides)
	    }

	    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
	    public static func __safeDI_mock(
	        user_Draft: Draft,
	        apiSendableBuilder __safeDI_apiSendableBuilder: Hub.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
	        user: User? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_x__safeDIBuilder = safeDIOverrides.x.safeDIBuilder
	        @Sendable nonisolated func __safeDI_x() -> X {
	            let __safeDI_apiSendableBuilder_x_Sendable = __safeDI_apiSendableBuilder.x_Sendable(SafeDISendableMockScope_Api.x_Sendable_Values())
	            @Sendable nonisolated func __safeDI_bBuilder() -> B {
	                let __safeDI_apiSendableBuilder_bBuilder = __safeDI_apiSendableBuilder_x_Sendable.bBuilder(SafeDISendableMockScope_Api.X_Scope.bBuilder_Values())
	                let user: Draft = user_Draft
	                let x: X = __safeDI_x()
	                let api: any Api = __safeDI_apiSendableBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x))
	                return B.__safeDI_init(api: api, x: x, user: user, safeDIBuilder: nil)
	            }
	            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
	            return X.__safeDI_init(bBuilder: bBuilder, safeDIBuilder: __safeDI_x__safeDIBuilder)
	        }
	        let x: X = if let x { x } else { __safeDI_x() }
	        return Hub(user: user, x: x)
	    }
	}

	extension Hub {
	    public enum __safeDI_Hub_mock_BF59370D78E87A91 {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_B_MockConfiguration {
	    public init(
	        x: __safeDI_Feature_X_MockConfiguration = .init(),
	        _ safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? = nil
	    ) {
	        __safeDI_storage = __safeDI_Storage(
	            x: x,
	            safeDIBuilder: safeDIBuilder
	        )
	    }

	    public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }
	    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
	    public var safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? { __safeDI_storage.safeDIBuilder }

	    private let __safeDI_storage: __safeDI_Storage

	    private final class __safeDI_Storage {
	        init(
	            x: __safeDI_Feature_X_MockConfiguration,
	            safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
	        ) {
	            self.x = x
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let x: __safeDI_Feature_X_MockConfiguration
	        let safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
	    }
	}

	extension B {
	    static func __safeDI_init(api: any Api, x: X, user: Draft, safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?) -> B {
	        if let safeDIBuilder { safeDIBuilder(api, x, user) } else { B(api: api, x: x, user: user) }
	    }
	}

	/// Configuration for how `X` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_X_MockConfiguration {
	    public init(
	        _ safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)? = nil
	    ) {
	        __safeDI_storage = __safeDI_Storage(
	            safeDIBuilder: safeDIBuilder
	        )
	    }

	    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
	    public var safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)? { __safeDI_storage.safeDIBuilder }

	    private let __safeDI_storage: __safeDI_Storage

	    private final class __safeDI_Storage {
	        init(
	            safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
	        ) {
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
	    }
	}

	extension X {
	    static func __safeDI_init(bBuilder: SendableInstantiator<B>, safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?) -> X {
	        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
	    }
	}
	#endif

	"""

	/// `Feature`'s file for the tree `feature(…)` makes plainCycle.
	private static let plainCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    nonisolated public enum SafeDIMockScope_Api {
	        nonisolated public struct x_Values {
	            public let user: User
	        }

	        nonisolated public enum X_Scope {
	            nonisolated public struct bBuilder_Values {}

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	                public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

	                public init(bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
	                    self.bBuilder = bBuilder
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                    self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	                }
	            }
	        }

	        nonisolated public enum B_Scope {
	            nonisolated public struct api_Values {
	                public let user: Draft
	                public let x: X
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

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let x: (x_Values) -> SafeDIMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(x: @escaping (x_Values) -> SafeDIMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.x = x
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.init(x: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            x: __safeDI_Feature_X_MockConfiguration = .init()
	        ) {
	            __safeDI_storage = __safeDI_Storage(
	                user: user,
	                x: x
	            )
	        }

	        public var user: (() -> User)? { __safeDI_storage.user }
	        public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }

	        private let __safeDI_storage: __safeDI_Storage

	        private final class __safeDI_Storage {
	            init(
	                user: (() -> User)?,
	                x: __safeDI_Feature_X_MockConfiguration
	            ) {
	                self.user = user
	                self.x = x
	            }

	            let user: (() -> User)?
	            let x: __safeDI_Feature_X_MockConfiguration
	        }
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiBuilder: @escaping () -> any Api,
	        user: User? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: .init(__safeDI_noScope: apiBuilder), user: user, x: x, safeDIOverrides: safeDIOverrides)
	    }

	    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
	    public static func __safeDI_mock(
	        user_Draft: Draft,
	        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
	        user: User? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_apiBuilder_x = __safeDI_apiBuilder.x(SafeDIMockScope_Api.x_Values(user: user))
	        func __safeDI_x() -> X {
	            let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder_x.bBuilder(SafeDIMockScope_Api.X_Scope.bBuilder_Values())
	            func __safeDI_bBuilder() -> B {
	                let user: Draft = user_Draft
	                let x: X = __safeDI_x()
	                let api: any Api = __safeDI_apiBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x))
	                return B.__safeDI_init(api: api, x: x, user: user, safeDIBuilder: nil)
	            }
	            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
	            return X.__safeDI_init(bBuilder: bBuilder, safeDIBuilder: safeDIOverrides.x.safeDIBuilder)
	        }
	        let x: X = if let x { x } else { __safeDI_x() }
	        return Hub(user: user, x: x)
	    }
	}

	extension Hub {
	    public enum __safeDI_Hub_mock_C92FAC1B9AC96ECD {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_B_MockConfiguration {
	    public init(
	        x: __safeDI_Feature_X_MockConfiguration = .init(),
	        _ safeDIBuilder: ((any Api, X, Draft) -> B)? = nil
	    ) {
	        __safeDI_storage = __safeDI_Storage(
	            x: x,
	            safeDIBuilder: safeDIBuilder
	        )
	    }

	    public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }
	    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
	    public var safeDIBuilder: ((any Api, X, Draft) -> B)? { __safeDI_storage.safeDIBuilder }

	    private let __safeDI_storage: __safeDI_Storage

	    private final class __safeDI_Storage {
	        init(
	            x: __safeDI_Feature_X_MockConfiguration,
	            safeDIBuilder: ((any Api, X, Draft) -> B)?
	        ) {
	            self.x = x
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let x: __safeDI_Feature_X_MockConfiguration
	        let safeDIBuilder: ((any Api, X, Draft) -> B)?
	    }
	}

	extension B {
	    static func __safeDI_init(api: any Api, x: X, user: Draft, safeDIBuilder: ((any Api, X, Draft) -> B)?) -> B {
	        if let safeDIBuilder { safeDIBuilder(api, x, user) } else { B(api: api, x: x, user: user) }
	    }
	}

	/// Configuration for how `X` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_X_MockConfiguration {
	    public init(
	        _ safeDIBuilder: ((Instantiator<B>) -> X)? = nil
	    ) {
	        __safeDI_storage = __safeDI_Storage(
	            safeDIBuilder: safeDIBuilder
	        )
	    }

	    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
	    public var safeDIBuilder: ((Instantiator<B>) -> X)? { __safeDI_storage.safeDIBuilder }

	    private let __safeDI_storage: __safeDI_Storage

	    private final class __safeDI_Storage {
	        init(
	            safeDIBuilder: ((Instantiator<B>) -> X)?
	        ) {
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let safeDIBuilder: ((Instantiator<B>) -> X)?
	    }
	}

	extension X {
	    static func __safeDI_init(bBuilder: Instantiator<B>, safeDIBuilder: ((Instantiator<B>) -> X)?) -> X {
	        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
	    }
	}
	#endif

	"""

	/// `Feature`'s file for the tree `feature(…)` makes plainNoCycle.
	private static let plainNoCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    nonisolated public enum SafeDIMockScope_Api {
	        nonisolated public struct bBuilder_Values {
	            public let user: User
	        }

	        nonisolated public enum B_Scope {
	            nonisolated public struct api_Values {
	                public let user: Draft
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

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.bBuilder = bBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            bBuilder: ((any Api, Draft) -> B)? = nil
	        ) {
	            __safeDI_storage = __safeDI_Storage(
	                user: user,
	                bBuilder: bBuilder
	            )
	        }

	        public var user: (() -> User)? { __safeDI_storage.user }
	        public var bBuilder: ((any Api, Draft) -> B)? { __safeDI_storage.bBuilder }

	        private let __safeDI_storage: __safeDI_Storage

	        private final class __safeDI_Storage {
	            init(
	                user: (() -> User)?,
	                bBuilder: ((any Api, Draft) -> B)?
	            ) {
	                self.user = user
	                self.bBuilder = bBuilder
	            }

	            let user: (() -> User)?
	            let bBuilder: ((any Api, Draft) -> B)?
	        }
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiBuilder: @escaping () -> any Api,
	        bBuilder: Instantiator<B>? = nil,
	        user: User? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        Hub.__safeDI_mock(user_Draft: user_Draft, apiBuilder: .init(__safeDI_noScope: apiBuilder), bBuilder: bBuilder, user: user, safeDIOverrides: safeDIOverrides)
	    }

	    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
	    public static func __safeDI_mock(
	        user_Draft: Draft,
	        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
	        bBuilder: Instantiator<B>? = nil,
	        user: User? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder.bBuilder(SafeDIMockScope_Api.bBuilder_Values(user: user))
	        func __safeDI_bBuilder() -> B {
	            let user: Draft = user_Draft
	            let api: any Api = __safeDI_apiBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))
	            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
	        }
	        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
	        return Hub(user: user, bBuilder: bBuilder)
	    }
	}

	extension Hub {
	    public enum __safeDI_Hub_mock_AC7AE65B2B9A4A12 {}
	}
	#endif
	"""

	/// `Feature`'s file for the tree `feature(…)` makes plainCycleOnlyIfAvailable.
	private static let plainCycleOnlyIfAvailableFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    nonisolated public enum SafeDIMockScope_Api {
	        nonisolated public struct x_Values {
	            public let user: User
	        }

	        nonisolated public enum X_Scope {
	            nonisolated public struct bBuilder_Values {}

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	                public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>

	                public init(bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Api.B_Scope.__safeDI_Builder<__safeDI_Built>) {
	                    self.bBuilder = bBuilder
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                    self.init(bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	                }
	            }
	        }

	        nonisolated public enum B_Scope {
	            nonisolated public struct api_Values {
	                public let user: Draft?
	                public let x: X
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

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let x: (x_Values) -> SafeDIMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(x: @escaping (x_Values) -> SafeDIMockScope_Api.X_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.x = x
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.init(x: { _ in .init(__safeDI_noScope: __safeDI_builder) })
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            x: __safeDI_Feature_X_MockConfiguration = .init()
	        ) {
	            __safeDI_storage = __safeDI_Storage(
	                user: user,
	                x: x
	            )
	        }

	        public var user: (() -> User)? { __safeDI_storage.user }
	        public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }

	        private let __safeDI_storage: __safeDI_Storage

	        private final class __safeDI_Storage {
	            init(
	                user: (() -> User)?,
	                x: __safeDI_Feature_X_MockConfiguration
	            ) {
	                self.user = user
	                self.x = x
	            }

	            let user: (() -> User)?
	            let x: __safeDI_Feature_X_MockConfiguration
	        }
	    }

	    public static func mock(
	        apiBuilder: @escaping () -> any Api,
	        user: User? = nil,
	        user_Draft: Draft? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        Hub.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), user: user, user_Draft: user_Draft, x: x, safeDIOverrides: safeDIOverrides)
	    }

	    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
	    public static func __safeDI_mock(
	        apiBuilder __safeDI_apiBuilder: Hub.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
	        user: User? = nil,
	        user_Draft: Draft? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_apiBuilder_x = __safeDI_apiBuilder.x(SafeDIMockScope_Api.x_Values(user: user))
	        func __safeDI_x() -> X {
	            let __safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder_x.bBuilder(SafeDIMockScope_Api.X_Scope.bBuilder_Values())
	            func __safeDI_bBuilder() -> B {
	                let user: Draft? = user_Draft
	                let x: X = __safeDI_x()
	                let api: any Api = __safeDI_apiBuilder_bBuilder.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x))
	                return B.__safeDI_init(api: api, x: x, user: user, safeDIBuilder: nil)
	            }
	            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
	            return X.__safeDI_init(bBuilder: bBuilder, safeDIBuilder: safeDIOverrides.x.safeDIBuilder)
	        }
	        let x: X = if let x { x } else { __safeDI_x() }
	        return Hub(user: user, x: x)
	    }
	}

	extension Hub {
	    public enum __safeDI_Hub_mock_06EB73166E9429F2 {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_B_MockConfiguration {
	    public init(
	        x: __safeDI_Feature_X_MockConfiguration = .init(),
	        _ safeDIBuilder: ((any Api, X, Draft?) -> B)? = nil
	    ) {
	        __safeDI_storage = __safeDI_Storage(
	            x: x,
	            safeDIBuilder: safeDIBuilder
	        )
	    }

	    public var x: __safeDI_Feature_X_MockConfiguration { __safeDI_storage.x }
	    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
	    public var safeDIBuilder: ((any Api, X, Draft?) -> B)? { __safeDI_storage.safeDIBuilder }

	    private let __safeDI_storage: __safeDI_Storage

	    private final class __safeDI_Storage {
	        init(
	            x: __safeDI_Feature_X_MockConfiguration,
	            safeDIBuilder: ((any Api, X, Draft?) -> B)?
	        ) {
	            self.x = x
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let x: __safeDI_Feature_X_MockConfiguration
	        let safeDIBuilder: ((any Api, X, Draft?) -> B)?
	    }
	}

	extension B {
	    static func __safeDI_init(api: any Api, x: X, user: Draft?, safeDIBuilder: ((any Api, X, Draft?) -> B)?) -> B {
	        if let safeDIBuilder { safeDIBuilder(api, x, user) } else { B(api: api, x: x, user: user) }
	    }
	}

	/// Configuration for how `X` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_X_MockConfiguration {
	    public init(
	        _ safeDIBuilder: ((Instantiator<B>) -> X)? = nil
	    ) {
	        __safeDI_storage = __safeDI_Storage(
	            safeDIBuilder: safeDIBuilder
	        )
	    }

	    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
	    public var safeDIBuilder: ((Instantiator<B>) -> X)? { __safeDI_storage.safeDIBuilder }

	    private let __safeDI_storage: __safeDI_Storage

	    private final class __safeDI_Storage {
	        init(
	            safeDIBuilder: ((Instantiator<B>) -> X)?
	        ) {
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let safeDIBuilder: ((Instantiator<B>) -> X)?
	    }
	}

	extension X {
	    static func __safeDI_init(bBuilder: Instantiator<B>, safeDIBuilder: ((Instantiator<B>) -> X)?) -> X {
	        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
	    }
	}
	#endif

	"""

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				var fixtureFiles = module.swiftFileContentByFilePath
				for (index, content) in module.swiftFileContent.enumerated() {
					fixtureFiles["File\(index).swift"] = content
				}
				return try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: fixtureFiles,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try await expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
