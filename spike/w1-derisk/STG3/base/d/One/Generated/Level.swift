import Harness
import SafeDI
import Three
import Two

extension S1 {
	nonisolated public enum SafeDIScope_Api {
		/// Stage 0: what is bound before the first call.
		nonisolated public struct a_Values {
			public let m1: M1
		}

		/// Stage 1: stage 0 plus what was bound since.
		nonisolated public struct b_Values {
			public let previous: a_Values
			public let badge1: Badge1
		}

		nonisolated public struct __safeDI_Builder<Built> {
			public let a: (a_Values) -> S2.SafeDIScope_Api.__safeDI_Builder<Built>
			public let b: (b_Values) -> S2.SafeDIScope_Api.__safeDI_Builder<Built>

			public init(a: @escaping (a_Values) -> S2.SafeDIScope_Api.__safeDI_Builder<Built>, b: @escaping (b_Values) -> S2.SafeDIScope_Api.__safeDI_Builder<Built>) {
				self.a = a
				self.b = b
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				a = { _ in .init(__safeDI_noScope: builder) }
				b = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		let m1 = M1()
		let __safeDI_stage0 = SafeDIScope_Api.a_Values(m1: m1)
		let a = S2(__safeDI_apiBuilder: __safeDI_apiBuilder.a(__safeDI_stage0))
		let badge1 = Badge1(a: a)
		let b = S2(__safeDI_apiBuilder: __safeDI_apiBuilder.b(.init(previous: __safeDI_stage0, badge1: badge1)))
		self.init(m1: m1, a: a, badge1: badge1, b: b)
	}
}
