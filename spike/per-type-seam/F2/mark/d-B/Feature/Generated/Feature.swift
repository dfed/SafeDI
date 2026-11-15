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
			nonisolated public struct monitor_Values {
				public let cache: Cache
			}

			nonisolated public struct stepBuilder_Values {
				public let cache: Cache
				public let monitor: any Api
			}

			nonisolated public struct __safeDI_Builder<Built> {
				public let monitor: (monitor_Values) -> Built
				public let stepBuilder: (stepBuilder_Values) -> Step_Scope.__safeDI_Builder<Built>

				public init(monitor: @escaping (monitor_Values) -> Built, stepBuilder: @escaping (stepBuilder_Values) -> Step_Scope.__safeDI_Builder<Built>) {
					self.monitor = monitor
					self.stepBuilder = stepBuilder
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					monitor = { _ in builder() }
					stepBuilder = { _ in .init(__safeDI_noScope: builder) }
				}
			}
		}

		nonisolated public enum Step_Scope {
			nonisolated public struct api_Values {
				public let mark: Mark
			}

			nonisolated public struct next_Values {
				public let mark: Mark
				public let api: any Api
			}

			nonisolated public struct __safeDI_Builder<Built> {
				public let api: (api_Values) -> Built
				public let next: (next_Values) -> Screen_Scope.__safeDI_Builder<Built>

				public init(api: @escaping (api_Values) -> Built, next: @escaping (next_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
					self.api = api
					self.next = next
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					api = { _ in builder() }
					next = { _ in .init(__safeDI_noScope: builder) }
				}
			}
		}
	}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}

	/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		func __safeDI_step(_ __safeDI_apiBuilder: SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {
			let mark = Mark()
			let api: any Api = __safeDI_apiBuilder.api(.init(mark: mark))
			let __safeDI_apiBuilder_next = __safeDI_apiBuilder.next(.init(mark: mark, api: api))
			let next = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_next) }
			return Step(api: api, mark: mark, next: next)
		}
		func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {
			let cache = Cache()
			let monitor: any Api = __safeDI_apiBuilder.monitor(.init(cache: cache))
			let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder.stepBuilder(.init(cache: cache, monitor: monitor))
			let stepBuilder = Instantiator<Step> { __safeDI_step(__safeDI_apiBuilder_stepBuilder) }
			return Screen(cache: cache, monitor: monitor, stepBuilder: stepBuilder)
		}
		let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
		let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder) }
		self.init(screenBuilder: screenBuilder)
	}
}
