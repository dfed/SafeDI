import Harness
import SafeDI

extension A {
	nonisolated public enum SafeDIScope_Api {
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

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		let api: any Api = __safeDI_apiBuilder.api(.init())
		self.init(api: api)
	}
}
