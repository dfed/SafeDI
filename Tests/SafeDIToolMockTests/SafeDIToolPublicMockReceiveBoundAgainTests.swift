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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        apiSendableBuilder: @escaping @Sendable (Hub.SafeDISendableMockScope_Api) -> any Api,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        _ = Hub.\(Self.sendableCycleGuard).self\(Self.comment)
		        let hub = Hub.mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable func __safeDI_apiSendableBuilder_Hub(_ scope: Hub.SafeDISendableMockScope_Api) -> any Api {
		                switch scope {
		                case let .x_Sendable(scope): return __safeDI_apiSendableBuilder_Hub_X_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_apiSendableBuilder_Hub_X_Scope(_ scope: Hub.SafeDISendableMockScope_Api.X_Scope) -> any Api {
		                switch scope {
		                case let .bBuilder(scope): return __safeDI_apiBuilder_Hub_B_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_apiBuilder_Hub_B_Scope(_ scope: Hub.SafeDIMockScope_Api.B_Scope) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                }
		            }
		            _ = Hub.\(Self.sendableCycleGuard).self\(Self.comment)
		            return Hub.mock(user_Draft: user_Draft, apiSendableBuilder: __safeDI_apiSendableBuilder_Hub, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        apiSendableBuilder: @escaping @Sendable (Hub.SafeDISendableMockScope_Api) -> any Api,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        _ = Hub.\(Self.sendableCycleGuard).self\(Self.comment)
		        let hub = Hub.mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            @Sendable func __safeDI_apiSendableBuilder_Hub(_ scope: Hub.SafeDISendableMockScope_Api) -> any Api {
		                switch scope {
		                case let .x_Sendable(scope): return __safeDI_apiSendableBuilder_Hub_X_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_apiSendableBuilder_Hub_X_Scope(_ scope: Hub.SafeDISendableMockScope_Api.X_Scope) -> any Api {
		                switch scope {
		                case let .bBuilder(scope): return __safeDI_apiBuilder_Hub_B_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_apiBuilder_Hub_B_Scope(_ scope: Hub.SafeDIMockScope_Api.B_Scope) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                }
		            }
		            _ = Hub.\(Self.sendableCycleGuard).self\(Self.comment)
		            return Hub.mock(user_Draft: user_Draft, apiSendableBuilder: __safeDI_apiSendableBuilder_Hub, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.sendableNoCycleFeature])
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        apiSendableBuilder: @escaping @Sendable (Hub.SafeDISendableMockScope_Api) -> any Api,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        _ = Hub.\(Self.sendableNoCycleGuard).self\(Self.comment)
		        let hub = Hub.mock(user_Draft: user_Draft, apiSendableBuilder: apiSendableBuilder, bBuilder: nil, user: user, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        _ = Hub.\(Self.plainCycleGuard).self\(Self.comment)
		        let hub = Hub.mock(user_Draft: user_Draft, apiBuilder: apiBuilder, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIMockScope_Api) -> any Api {
		                switch scope {
		                case let .x(_, scope): return __safeDI_apiBuilder_Hub_X_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_X_Scope(_ scope: Hub.SafeDIMockScope_Api.X_Scope) -> any Api {
		                switch scope {
		                case let .bBuilder(_, scope): return __safeDI_apiBuilder_Hub_B_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope(_ scope: Hub.SafeDIMockScope_Api.B_Scope) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                }
		            }
		            _ = Hub.\(Self.plainCycleGuard).self\(Self.comment)
		            return Hub.mock(user_Draft: user_Draft, apiBuilder: __safeDI_apiBuilder_Hub, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        _ = Hub.\(Self.plainNoCycleGuard).self\(Self.comment)
		        let hub = Hub.mock(user_Draft: user_Draft, apiBuilder: apiBuilder, bBuilder: nil, user: user, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        user_Draft: Draft,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIMockScope_Api) -> any Api {
		                switch scope {
		                case let .bBuilder(_, scope): return __safeDI_apiBuilder_Hub_B_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope(_ scope: Hub.SafeDIMockScope_Api.B_Scope) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                }
		            }
		            _ = Hub.\(Self.plainNoCycleGuard).self\(Self.comment)
		            return Hub.mock(user_Draft: user_Draft, apiBuilder: __safeDI_apiBuilder_Hub, bBuilder: nil, user: user, safeDIOverrides: safeDIOverrides.hub)
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
		            hub: Hub.SafeDIOverrides = .init()
		        ) {
		            self.user = user
		            self.hub = hub
		        }

		        let user: (() -> User)?
		        let hub: Hub.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_hub() -> Hub {
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIMockScope_Api) -> any Api {
		                switch scope {
		                case let .x(_, scope): return __safeDI_apiBuilder_Hub_X_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_X_Scope(_ scope: Hub.SafeDIMockScope_Api.X_Scope) -> any Api {
		                switch scope {
		                case let .bBuilder(_, scope): return __safeDI_apiBuilder_Hub_B_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_B_Scope(_ scope: Hub.SafeDIMockScope_Api.B_Scope) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let user = scope.user
		                    let api: any Api = LiveApi(user: user)
		                    return api
		                }
		            }
		            _ = Hub.\(Self.plainCycleOnlyIfAvailableGuard).self\(Self.comment)
		            return Hub.mock(apiBuilder: __safeDI_apiBuilder_Hub, user: user, x: nil, safeDIOverrides: safeDIOverrides.hub)
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

	/// The comment that ends the line that names the guard of `Hub`'s public mock.
	private static let comment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "", declaringModule: "Feature")

	/// The guard enum of `Hub`'s public mock in `sendableCycle`'s tree.
	private static let sendableCycleGuard = "__safeDI_Hub_mock_2D6711958996C05D"

	/// `Feature`'s file for the tree `feature(…)` makes sendableCycle.
	private static let sendableCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    @frozen public enum SafeDIMockScope_Api {
	        @frozen public enum B_Scope {
	            case api(api_Values)

	            public struct api_Values {
	                public let user: Draft
	                public let x: X
	            }
	        }
	    }

	    @frozen public enum SafeDISendableMockScope_Api {
	        case x_Sendable(SafeDISendableMockScope_Api.X_Scope)

	        @frozen public enum X_Scope {
	            case bBuilder(SafeDIMockScope_Api.B_Scope)
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            x: __safeDI_Feature_X_MockConfiguration = .init()
	        ) {
	            self.user = user
	            self.x = x
	        }

	        public let user: (() -> User)?
	        public let x: __safeDI_Feature_X_MockConfiguration
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiSendableBuilder: @escaping @Sendable (Hub.SafeDISendableMockScope_Api) -> any Api,
	        user: User? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let __safeDI_apiSendableBuilder = apiSendableBuilder
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_x__safeDIBuilder = safeDIOverrides.x.safeDIBuilder
	        @Sendable func __safeDI_x() -> X {
	            @Sendable func __safeDI_bBuilder() -> B {
	                let user: Draft = user_Draft
	                let x: X = __safeDI_x()
	                let api: any Api = __safeDI_apiSendableBuilder(.x_Sendable(.bBuilder(.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x)))))
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
	    public enum \(Self.sendableCycleGuard) {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_B_MockConfiguration {
	    public init(
	        x: __safeDI_Feature_X_MockConfiguration = .init(),
	        _ safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)? = nil
	    ) {
	        self.x = x
	        self.safeDIBuilder = safeDIBuilder
	    }

	    public let x: __safeDI_Feature_X_MockConfiguration
	    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: (@Sendable (any Api, X, Draft) -> B)?
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
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
	}

	extension X {
	    static func __safeDI_init(bBuilder: SendableInstantiator<B>, safeDIBuilder: (@Sendable (SendableInstantiator<B>) -> X)?) -> X {
	        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
	    }
	}
	#endif

	"""

	/// The guard enum of `Hub`'s public mock in `sendableNoCycle`'s tree.
	private static let sendableNoCycleGuard = "__safeDI_Hub_mock_AF3A489729B5F092"

	/// `Feature`'s file for the tree `feature(…)` makes sendableNoCycle.
	private static let sendableNoCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    @frozen public enum SafeDIMockScope_Api {
	        @frozen public enum B_Scope {
	            case api(api_Values)

	            public struct api_Values {
	                public let user: Draft
	            }
	        }
	    }

	    @frozen public enum SafeDISendableMockScope_Api {
	        case bBuilder(SafeDIMockScope_Api.B_Scope)
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            bBuilder: (@Sendable (any Api, Draft) -> B)? = nil
	        ) {
	            self.user = user
	            self.bBuilder = bBuilder
	        }

	        public let user: (() -> User)?
	        public let bBuilder: (@Sendable (any Api, Draft) -> B)?
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiSendableBuilder: @escaping @Sendable (Hub.SafeDISendableMockScope_Api) -> any Api,
	        bBuilder: SendableInstantiator<B>? = nil,
	        user: User? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let __safeDI_apiSendableBuilder = apiSendableBuilder
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_bBuilder__safeDIBuilder = safeDIOverrides.bBuilder
	        @Sendable func __safeDI_bBuilder() -> B {
	            let user: Draft = user_Draft
	            let api: any Api = __safeDI_apiSendableBuilder(.bBuilder(.api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))))
	            return if let safeDIBuilder = __safeDI_bBuilder__safeDIBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
	        }
	        let bBuilder = if let bBuilder { bBuilder } else { SendableInstantiator<B>(__safeDI_bBuilder) }
	        return Hub(user: user, bBuilder: bBuilder)
	    }
	}

	extension Hub {
	    public enum \(Self.sendableNoCycleGuard) {}
	}
	#endif
	"""

	/// The guard enum of `Hub`'s public mock in `plainCycle`'s tree.
	private static let plainCycleGuard = "__safeDI_Hub_mock_09EA5B6C21F15CC7"

	/// `Feature`'s file for the tree `feature(…)` makes plainCycle.
	private static let plainCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    @frozen public enum SafeDIMockScope_Api {
	        case x(x_Values, SafeDIMockScope_Api.X_Scope)

	        public struct x_Values {
	            public let user: User
	        }

	        @frozen public enum X_Scope {
	            case bBuilder(bBuilder_Values, SafeDIMockScope_Api.B_Scope)

	            public struct bBuilder_Values {}
	        }

	        @frozen public enum B_Scope {
	            case api(api_Values)

	            public struct api_Values {
	                public let user: Draft
	                public let x: X
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            x: __safeDI_Feature_X_MockConfiguration = .init()
	        ) {
	            self.user = user
	            self.x = x
	        }

	        public let user: (() -> User)?
	        public let x: __safeDI_Feature_X_MockConfiguration
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
	        user: User? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let __safeDI_apiBuilder = apiBuilder
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_apiValues_x = SafeDIMockScope_Api.x_Values(user: user)
	        func __safeDI_x() -> X {
	            let __safeDI_apiValues_bBuilder = SafeDIMockScope_Api.X_Scope.bBuilder_Values()
	            func __safeDI_bBuilder() -> B {
	                let user: Draft = user_Draft
	                let x: X = __safeDI_x()
	                let api: any Api = __safeDI_apiBuilder(.x(__safeDI_apiValues_x, .bBuilder(__safeDI_apiValues_bBuilder, .api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x)))))
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
	    public enum \(Self.plainCycleGuard) {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_B_MockConfiguration {
	    public init(
	        x: __safeDI_Feature_X_MockConfiguration = .init(),
	        _ safeDIBuilder: ((any Api, X, Draft) -> B)? = nil
	    ) {
	        self.x = x
	        self.safeDIBuilder = safeDIBuilder
	    }

	    public let x: __safeDI_Feature_X_MockConfiguration
	    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: ((any Api, X, Draft) -> B)?
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
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: ((Instantiator<B>) -> X)?
	}

	extension X {
	    static func __safeDI_init(bBuilder: Instantiator<B>, safeDIBuilder: ((Instantiator<B>) -> X)?) -> X {
	        if let safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
	    }
	}
	#endif

	"""

	/// The guard enum of `Hub`'s public mock in `plainNoCycle`'s tree.
	private static let plainNoCycleGuard = "__safeDI_Hub_mock_9034726A3AAA829C"

	/// `Feature`'s file for the tree `feature(…)` makes plainNoCycle.
	private static let plainNoCycleFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    @frozen public enum SafeDIMockScope_Api {
	        case bBuilder(bBuilder_Values, SafeDIMockScope_Api.B_Scope)

	        public struct bBuilder_Values {
	            public let user: User
	        }

	        @frozen public enum B_Scope {
	            case api(api_Values)

	            public struct api_Values {
	                public let user: Draft
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            bBuilder: ((any Api, Draft) -> B)? = nil
	        ) {
	            self.user = user
	            self.bBuilder = bBuilder
	        }

	        public let user: (() -> User)?
	        public let bBuilder: ((any Api, Draft) -> B)?
	    }

	    public static func mock(
	        user_Draft: Draft,
	        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
	        bBuilder: Instantiator<B>? = nil,
	        user: User? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let __safeDI_apiBuilder = apiBuilder
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_apiValues_bBuilder = SafeDIMockScope_Api.bBuilder_Values(user: user)
	        func __safeDI_bBuilder() -> B {
	            let user: Draft = user_Draft
	            let api: any Api = __safeDI_apiBuilder(.bBuilder(__safeDI_apiValues_bBuilder, .api(SafeDIMockScope_Api.B_Scope.api_Values(user: user))))
	            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(api, user) } else { B(api: api, user: user) }
	        }
	        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
	        return Hub(user: user, bBuilder: bBuilder)
	    }
	}

	extension Hub {
	    public enum \(Self.plainNoCycleGuard) {}
	}
	#endif
	"""

	/// The guard enum of `Hub`'s public mock in `plainCycleOnlyIfAvailable`'s tree.
	private static let plainCycleOnlyIfAvailableGuard = "__safeDI_Hub_mock_04EB1A90E005ABCA"

	/// `Feature`'s file for the tree `feature(…)` makes plainCycleOnlyIfAvailable.
	private static let plainCycleOnlyIfAvailableFeature = """
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Hub {
	    @frozen public enum SafeDIMockScope_Api {
	        case x(x_Values, SafeDIMockScope_Api.X_Scope)

	        public struct x_Values {
	            public let user: User
	        }

	        @frozen public enum X_Scope {
	            case bBuilder(bBuilder_Values, SafeDIMockScope_Api.B_Scope)

	            public struct bBuilder_Values {}
	        }

	        @frozen public enum B_Scope {
	            case api(api_Values)

	            public struct api_Values {
	                public let user: Draft?
	                public let x: X
	            }
	        }
	    }

	    /// Overrides for the mock dependency tree.
	    nonisolated public struct SafeDIOverrides {
	        public init(
	            user: (() -> User)? = nil,
	            x: __safeDI_Feature_X_MockConfiguration = .init()
	        ) {
	            self.user = user
	            self.x = x
	        }

	        public let user: (() -> User)?
	        public let x: __safeDI_Feature_X_MockConfiguration
	    }

	    public static func mock(
	        apiBuilder: @escaping (Hub.SafeDIMockScope_Api) -> any Api,
	        user: User? = nil,
	        user_Draft: Draft? = nil,
	        x: X? = nil,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Hub {
	        let __safeDI_apiBuilder = apiBuilder
	        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
	        let __safeDI_apiValues_x = SafeDIMockScope_Api.x_Values(user: user)
	        func __safeDI_x() -> X {
	            let __safeDI_apiValues_bBuilder = SafeDIMockScope_Api.X_Scope.bBuilder_Values()
	            func __safeDI_bBuilder() -> B {
	                let user: Draft? = user_Draft
	                let x: X = __safeDI_x()
	                let api: any Api = __safeDI_apiBuilder(.x(__safeDI_apiValues_x, .bBuilder(__safeDI_apiValues_bBuilder, .api(SafeDIMockScope_Api.B_Scope.api_Values(user: user, x: x)))))
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
	    public enum \(Self.plainCycleOnlyIfAvailableGuard) {}
	}
	#endif

	#if DEBUG
	/// Configuration for how `B` is constructed within the public mock trees of module `Feature`.
	nonisolated public struct __safeDI_Feature_B_MockConfiguration {
	    public init(
	        x: __safeDI_Feature_X_MockConfiguration = .init(),
	        _ safeDIBuilder: ((any Api, X, Draft?) -> B)? = nil
	    ) {
	        self.x = x
	        self.safeDIBuilder = safeDIBuilder
	    }

	    public let x: __safeDI_Feature_X_MockConfiguration
	    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: ((any Api, X, Draft?) -> B)?
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
	        self.safeDIBuilder = safeDIBuilder
	    }

	    /// Overrides how `X` is constructed. Parameters match the type’s initializer or custom mock method.
	    public let safeDIBuilder: ((Instantiator<B>) -> X)?
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
