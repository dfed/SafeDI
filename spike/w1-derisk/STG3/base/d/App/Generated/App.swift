import Harness
import One
import SafeDI
import Three
import Two

extension Root {
	public convenience init() {
		// Per-type level functions; each takes what the levels above bound for its fills (the fixed point).
		func __safeDI_apiBuilder_S1() -> S1.SafeDIScope_Api.__safeDI_Builder<any Api> {
			.init(
				a: { values in __safeDI_apiBuilder_S2(m1: values.m1, badge1: nil) },
				b: { values in __safeDI_apiBuilder_S2(m1: values.previous.m1, badge1: values.badge1) },
			)
		}
		func __safeDI_apiBuilder_S2(m1: M1, badge1: Badge1?) -> S2.SafeDIScope_Api.__safeDI_Builder<any Api> {
			.init(
				a: { values in __safeDI_apiBuilder_S3(m1: m1, badge1: badge1, m2: values.m2, badge2: nil) },
				b: { values in __safeDI_apiBuilder_S3(m1: m1, badge1: badge1, m2: values.previous.m2, badge2: values.badge2) },
			)
		}
		func __safeDI_apiBuilder_S3(m1: M1, badge1: Badge1?, m2: M2, badge2: Badge2?) -> S3.SafeDIScope_Api.__safeDI_Builder<any Api> {
			.init(api: { _ in LiveApi(m1: m1, badge1: badge1, m2: m2, badge2: badge2) })
		}
		let s1 = S1(__safeDI_apiBuilder: __safeDI_apiBuilder_S1())
		self.init(s1: s1)
	}
}
