import Harness
import SafeDI
import Three

extension S2 {
	nonisolated public enum SafeDIScope_Api {
		/// Stage 0: what is bound before the first call.
		nonisolated public struct a_Values {
			public let m2: M2
		}

		/// Stage 1: stage 0 plus what was bound since.
		nonisolated public struct b_Values {
			public let previous: a_Values
			public let badge2: Badge2
		}

		nonisolated public struct __safeDI_Builder<Built> {
			public let a: (a_Values) -> S3.SafeDIScope_Api.__safeDI_Builder<Built>
			public let b: (b_Values) -> S3.SafeDIScope_Api.__safeDI_Builder<Built>

			public init(a: @escaping (a_Values) -> S3.SafeDIScope_Api.__safeDI_Builder<Built>, b: @escaping (b_Values) -> S3.SafeDIScope_Api.__safeDI_Builder<Built>) {
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
		let m2 = M2()
		let __safeDI_stage0 = SafeDIScope_Api.a_Values(m2: m2)
		let a = S3(__safeDI_apiBuilder: __safeDI_apiBuilder.a(__safeDI_stage0))
		let badge2 = Badge2(a: a)
		let b = S3(__safeDI_apiBuilder: __safeDI_apiBuilder.b(.init(previous: __safeDI_stage0, badge2: badge2)))
		self.init(m2: m2, a: a, badge2: badge2, b: b)
	}
}
