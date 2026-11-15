import Harness
import Inner
import SafeDI

extension Store {
	nonisolated public enum SafeDIScope_Api {
		nonisolated public struct a_Values {
			public let db: Db
		}

		nonisolated public struct __safeDI_Builder<Built> {
			public let a: (a_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>

			public init(a: @escaping (a_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>) {
				self.a = a
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				a = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	nonisolated public enum SafeDISendableScope_Api {
		nonisolated public struct aBuilder_Values: Sendable {
			public let db: Db
		}

		nonisolated public struct __safeDI_Builder<Built>: Sendable {
			public let aBuilder: @Sendable (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>

			public init(aBuilder: @escaping @Sendable (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>) {
				self.aBuilder = aBuilder
			}

			public init(__safeDI_noScope builder: @escaping @Sendable () -> Built) {
				aBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		let db = Db()
		let a = A(__safeDI_apiBuilder: __safeDI_apiBuilder.a(.init(db: db)))
		@Sendable func __safeDI_aBuilder() -> A {
			A(__safeDI_apiBuilder: __safeDI_apiSendableBuilder.aBuilder(.init(db: db)))
		}
		let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
		self.init(db: db, a: a, aBuilder: aBuilder)
	}
}
