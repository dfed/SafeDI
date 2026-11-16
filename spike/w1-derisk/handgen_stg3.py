"""Hand-written W1 form for STG3: stage structs three seams deep. Each level's first call takes stage 0 (what is bound
before the first carrier); a call after a sibling that receives the first call takes stage 1 = stage 0 + that sibling."""
import os
def write(p, t):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(t)
def builder(members, pad):
    out = [f"{pad}nonisolated public struct __safeDI_Builder<Built> {{"]
    for m, v, r in members: out.append(f"{pad}\tpublic let {m}: ({v}) -> {r}")
    out.append("")
    out.append(f"{pad}\tpublic init(" + ", ".join(f"{m}: @escaping ({v}) -> {r}" for m, v, r in members) + ") {")
    for m, _, _ in members: out.append(f"{pad}\t\tself.{m} = {m}")
    out.append(f"{pad}\t}}\n")
    out.append(f"{pad}\tpublic init(__safeDI_noScope builder: @escaping () -> Built) {{")
    for m, _, r in members: out.append(f"{pad}\t\t{m} = {{ _ in {'builder()' if r == 'Built' else '.init(__safeDI_noScope: builder)'} }}")
    out.append(f"{pad}\t}}\n{pad}}}")
    return "\n".join(out)
d = "STG3/base/d"
write(f"{d}/Three/Generated/Three.swift", f"""import Harness
import SafeDI

extension S3 {{
	nonisolated public enum SafeDIScope_Api {{
		nonisolated public struct api_Values {{}}

{builder([("api", "api_Values", "Built")], "		")}
	}}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {{
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {{
		let api: any Api = __safeDI_apiBuilder.api(.init())
		self.init(api: api)
	}}
}}
""")
for k, inner, imports in [(2, "S3", ["Three"]), (1, "S2", ["Three", "Two"])]:
    write(f"{d}/{'Two' if k == 2 else 'One'}/Generated/Level.swift", "".join(f"import {m}\n" for m in ["Harness", "SafeDI"] + imports) + f"""
extension S{k} {{
	nonisolated public enum SafeDIScope_Api {{
		/// Stage 0: what is bound before the first call.
		nonisolated public struct a_Values {{
			public let m{k}: M{k}
		}}

		/// Stage 1: stage 0 plus what was bound since.
		nonisolated public struct b_Values {{
			public let previous: a_Values
			public let badge{k}: Badge{k}
		}}

{builder([("a", "a_Values", f"{inner}.SafeDIScope_Api.__safeDI_Builder<Built>"), ("b", "b_Values", f"{inner}.SafeDIScope_Api.__safeDI_Builder<Built>")], "		")}
	}}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {{
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {{
		let m{k} = M{k}()
		let __safeDI_stage0 = SafeDIScope_Api.a_Values(m{k}: m{k})
		let a = {inner}(__safeDI_apiBuilder: __safeDI_apiBuilder.a(__safeDI_stage0))
		let badge{k} = Badge{k}(a: a)
		let b = {inner}(__safeDI_apiBuilder: __safeDI_apiBuilder.b(.init(previous: __safeDI_stage0, badge{k}: badge{k})))
		self.init(m{k}: m{k}, a: a, badge{k}: badge{k}, b: b)
	}}
}}
""")
write(f"{d}/App/Generated/App.swift", """import Harness
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
""")
