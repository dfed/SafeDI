import Core
import Harness
import SafeDI

#if DEBUG
	extension Home {
		nonisolated public enum SafeDIMockScope_Api {
			nonisolated public struct screen_Values {}

			nonisolated public struct __safeDI_Builder<Built> {
				public let screen: (screen_Values) -> Screen_Scope.__safeDI_Builder<Built>

				public init(screen: @escaping (screen_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
					self.screen = screen
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					screen = { _ in .init(__safeDI_noScope: builder) }
				}
			}

			nonisolated public enum Screen_Scope {
				nonisolated public struct stepBuilder_Values {
					public let cache: Cache
				}

				nonisolated public struct __safeDI_Builder<Built> {
					public let stepBuilder: (stepBuilder_Values) -> Step_Scope.__safeDI_Builder<Built>

					public init(stepBuilder: @escaping (stepBuilder_Values) -> Step_Scope.__safeDI_Builder<Built>) {
						self.stepBuilder = stepBuilder
					}

					public init(__safeDI_noScope builder: @escaping () -> Built) {
						stepBuilder = { _ in .init(__safeDI_noScope: builder) }
					}
				}
			}

			nonisolated public enum Step_Scope {
				nonisolated public struct api_Values {
					public let screenBuilder: Instantiator<Screen>
				}

				nonisolated public struct screenBuilder_Values {}

				nonisolated public struct __safeDI_Builder<Built> {
					public let api: (api_Values) -> Built
					public let screenBuilder: (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>

					public init(api: @escaping (api_Values) -> Built, screenBuilder: @escaping (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
						self.api = api
						self.screenBuilder = screenBuilder
					}

					public init(__safeDI_noScope builder: @escaping () -> Built) {
						api = { _ in builder() }
						screenBuilder = { _ in .init(__safeDI_noScope: builder) }
					}
				}
			}
		}

		/// Overrides for the mock dependency tree.
		nonisolated public struct SafeDIOverrides {
			public init(
				screen: __safeDI_Feat_Screen_MockConfiguration = .init(),
			) {
				self.screen = screen
			}

			public let screen: __safeDI_Feat_Screen_MockConfiguration
		}

		/// For code you write.
		public static func mock(
			apiBuilder: @escaping () -> any Api,
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Home {
			__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		}

		/// Only code SafeDI generates calls this mock. Main rejects this shape (`declarationBoundOnCycleReentry`), so the
		/// leak fix has no body for it in 2.3.0; the spike compiles the struct and the readable mock only.
		public static func __safeDI_mock(
			apiBuilder __safeDI_apiBuilder: SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Home {
			// One function per key. Screen's places read different configurations (the first `screen`, a reopened one none)
			// and different level structs, so both are parameters. Every Step reads `screen.stepBuilder`, so Step captures it;
			// its level struct differs by place, so Step takes it (W1's cycle parameter, variant h).
			func __safeDI_screen(
				_ __safeDI_apiBuilder_screen: SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api>,
				safeDIOverrides __safeDI_overrides: __safeDI_Feat_Screen_MockConfiguration?,
			) -> Screen {
				let cache = if let safeDIBuilder = __safeDI_overrides?.cache {
					safeDIBuilder()
				} else {
					Cache()
				}
				let __safeDI_apiBuilder_step = __safeDI_apiBuilder_screen.stepBuilder(.init(cache: cache))
				let stepBuilder = Instantiator<Step> { __safeDI_stepBuilder(__safeDI_apiBuilder_step) }
				return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: __safeDI_overrides?.safeDIBuilder)
			}
			func __safeDI_stepBuilder(_ __safeDI_apiBuilder_step: SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {
				let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_step.screenBuilder(.init()), safeDIOverrides: nil) }
				let api: any Api = __safeDI_apiBuilder_step.api(.init(screenBuilder: screenBuilder))
				return Step.__safeDI_init(api: api, screenBuilder: screenBuilder, safeDIBuilder: safeDIOverrides.screen.stepBuilder.safeDIBuilder)
			}
			let screen = __safeDI_screen(__safeDI_apiBuilder.screen(.init()), safeDIOverrides: safeDIOverrides.screen)
			return Home(screen: screen)
		}
	}
#endif

#if DEBUG
	/// Configuration for how `Step` is constructed within the public mock trees of module `Feat`.
	nonisolated public struct __safeDI_Feat_Step_MockConfiguration {
		public init(
			_ safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)? = nil,
		) {
			self.safeDIBuilder = safeDIBuilder
		}

		/// Overrides how `Step` is constructed. Parameters match the type’s initializer or custom mock method.
		public let safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?
	}

	extension Step {
		static func __safeDI_init(api: any Api, screenBuilder: Instantiator<Screen>, safeDIBuilder: ((any Api, Instantiator<Screen>) -> Step)?) -> Step {
			if let safeDIBuilder {
				safeDIBuilder(api, screenBuilder)
			} else {
				Step(api: api, screenBuilder: screenBuilder)
			}
		}
	}

	/// Configuration for how `Screen` is constructed within the public mock trees of module `Feat`.
	nonisolated public struct __safeDI_Feat_Screen_MockConfiguration {
		public init(
			cache: (() -> Cache)? = nil,
			stepBuilder: __safeDI_Feat_Step_MockConfiguration = .init(),
			_ safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)? = nil,
		) {
			self.cache = cache
			self.stepBuilder = stepBuilder
			self.safeDIBuilder = safeDIBuilder
		}

		public let cache: (() -> Cache)?
		public let stepBuilder: __safeDI_Feat_Step_MockConfiguration
		/// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
		public let safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?
	}

	extension Screen {
		static func __safeDI_init(cache: Cache, stepBuilder: Instantiator<Step>, safeDIBuilder: ((Cache, Instantiator<Step>) -> Screen)?) -> Screen {
			if let safeDIBuilder {
				safeDIBuilder(cache, stepBuilder)
			} else {
				Screen(cache: cache, stepBuilder: stepBuilder)
			}
		}
	}
#endif
