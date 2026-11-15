import Harness
import SafeDI

extension Home {
	nonisolated public enum SafeDIScope_Api {
		nonisolated public struct screenBuilder_Values {}

		nonisolated public struct __safeDI_Builder<Built> {
			public let screenBuilder: (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>

			public init(screenBuilder: @escaping (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
				self.screenBuilder = screenBuilder
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				screenBuilder = { _ in .init(__safeDI_noScope: builder) }
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

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}

	/// Only code SafeDI generates calls this initializer. Main rejects this shape (`declarationBoundOnCycleReentry`), so
	/// the leak fix has no body for it in 2.3.0; the spike compiles the struct and the readable initializer only.
	public convenience init(__safeDI_apiBuilder _: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		fatalError("rejected in 2.3.0")
	}
}
