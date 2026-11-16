import Core
import Harness
import SafeDI

#if DEBUG
	extension Home {
		nonisolated public enum SafeDIMockScope_Api {
			/// Stage 0: what `a`'s call reads. `meter` is built before the call although Home declares it after `a` (gap 1).
			nonisolated public struct a_Values {
				public let meter: Meter
			}

			/// Stage 1: `b`'s call adds `badge`, which receives `a` and so is built after `a`'s call (gap 2).
			nonisolated public struct b_Values {
				public let previous: a_Values
				public let badge: Badge
			}

			nonisolated public struct __safeDI_Builder<Built> {
				public let a: (a_Values) -> Sub_Scope.__safeDI_Builder<Built>
				public let b: (b_Values) -> Sub_Scope.__safeDI_Builder<Built>

				public init(a: @escaping (a_Values) -> Sub_Scope.__safeDI_Builder<Built>, b: @escaping (b_Values) -> Sub_Scope.__safeDI_Builder<Built>) {
					self.a = a
					self.b = b
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					a = { _ in .init(__safeDI_noScope: builder) }
					b = { _ in .init(__safeDI_noScope: builder) }
				}
			}

			nonisolated public enum Sub_Scope {
				nonisolated public struct api_Values {}

				nonisolated public struct __safeDI_Builder<Built> {
					public let api: (api_Values) -> Built

					public init(api: @escaping (api_Values) -> Built) {
						self.api = api
					}

					public init(__safeDI_noScope builder: @escaping () -> Built) {
						api = { _ in builder() }
					}
				}
			}
		}

		/// Overrides for the mock dependency tree.
		nonisolated public struct SafeDIOverrides {
			public init(
				meter: (() -> Meter)? = nil,
				a: ((any Api) -> Sub)? = nil,
				badge: ((Sub) -> Badge)? = nil,
				b: ((any Api) -> Sub)? = nil,
			) {
				self.meter = meter
				self.a = a
				self.badge = badge
				self.b = b
			}

			public let meter: (() -> Meter)?
			public let a: ((any Api) -> Sub)?
			public let badge: ((Sub) -> Badge)?
			public let b: ((any Api) -> Sub)?
		}

		/// For code you write.
		public static func mock(
			apiBuilder: @escaping () -> any Api,
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Home {
			__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		}

		/// Only code SafeDI generates calls this mock. A per-path body: each call is handed the values its own path bound.
		public static func __safeDI_mock(
			apiBuilder __safeDI_apiBuilder: SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Home {
			let meter = if let safeDIBuilder = safeDIOverrides.meter {
				safeDIBuilder()
			} else {
				Meter()
			}
			let __safeDI_stage0 = SafeDIMockScope_Api.a_Values(meter: meter)
			func __safeDI_a() -> Sub {
				let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(__safeDI_stage0)
				let api: any Api = __safeDI_apiBuilder_a.api(.init())
				return if let safeDIBuilder = safeDIOverrides.a {
					safeDIBuilder(api)
				} else {
					Sub(api: api)
				}
			}
			let a: Sub = __safeDI_a()
			let badge = if let safeDIBuilder = safeDIOverrides.badge {
				safeDIBuilder(a)
			} else {
				Badge(a: a)
			}
			func __safeDI_b() -> Sub {
				let __safeDI_apiBuilder_b = __safeDI_apiBuilder.b(.init(previous: __safeDI_stage0, badge: badge))
				let api: any Api = __safeDI_apiBuilder_b.api(.init())
				return if let safeDIBuilder = safeDIOverrides.b {
					safeDIBuilder(api)
				} else {
					Sub(api: api)
				}
			}
			let b: Sub = __safeDI_b()
			return Home(a: a, meter: meter, badge: badge, b: b)
		}
	}
#endif
