import Core
import Harness
import SafeDI

#if DEBUG
	extension Store {
		nonisolated public enum SafeDIMockScope_Api {
			/// `aBuilder`'s call reads `sideBuilder`, an instantiator the body rebuilds at the call from its sibling's function.
			nonisolated public struct aBuilder_Values {
				public let sideBuilder: Instantiator<Side>
			}

			nonisolated public struct __safeDI_Builder<Built> {
				public let aBuilder: (aBuilder_Values) -> A_Scope.__safeDI_Builder<Built>

				public init(aBuilder: @escaping (aBuilder_Values) -> A_Scope.__safeDI_Builder<Built>) {
					self.aBuilder = aBuilder
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					aBuilder = { _ in .init(__safeDI_noScope: builder) }
				}
			}

			nonisolated public enum A_Scope {
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
				aBuilder: ((any Api) -> A)? = nil,
				sideBuilder: ((Instantiator<A>) -> Side)? = nil,
			) {
				self.aBuilder = aBuilder
				self.sideBuilder = sideBuilder
			}

			public let aBuilder: ((any Api) -> A)?
			public let sideBuilder: ((Instantiator<A>) -> Side)?
		}

		/// For code you write.
		public static func mock(
			apiBuilder: @escaping () -> any Api,
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Store {
			__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
		}

		/// Only code SafeDI generates calls this mock. The two functions are mutually recursive local functions, as in
		/// today's inline mock; nothing is boxed or deferred.
		public static func __safeDI_mock(
			apiBuilder __safeDI_apiBuilder: SafeDIMockScope_Api.__safeDI_Builder<any Api>,
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Store {
			func __safeDI_aBuilder() -> A {
				let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
				let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(.init(sideBuilder: sideBuilder))
				let api: any Api = __safeDI_apiBuilder_aBuilder.api(.init())
				return if let safeDIBuilder = safeDIOverrides.aBuilder {
					safeDIBuilder(api)
				} else {
					A(api: api)
				}
			}
			let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			func __safeDI_sideBuilder() -> Side {
				let aBuilder = Instantiator<A>(__safeDI_aBuilder)
				return if let safeDIBuilder = safeDIOverrides.sideBuilder {
					safeDIBuilder(aBuilder)
				} else {
					Side(aBuilder: aBuilder)
				}
			}
			let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
			return Store(aBuilder: aBuilder, sideBuilder: sideBuilder)
		}
	}
#endif
