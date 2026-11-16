"""Hand-written W1 form (leak-fix builder struct, per-type body) for G2L's three shapes, variant d."""
import os

def struct(name_values, fields, members, sendable, indent="\t\t"):
    """members: [(member, values, returned)]"""
    s = ": Sendable" if sendable else ""
    at = "@Sendable " if sendable else ""
    out = []
    for values, fs in name_values:
        body = "".join(f"\n{indent}\tpublic let {l}: {t}" for l, t in fs)
        out.append(f"{indent}nonisolated public struct {values}{s} {{{body}{chr(10) + indent if fs else ''}}}\n")
    out.append(f"{indent}nonisolated public struct __safeDI_Builder<Built>{s} {{")
    for m, v, r in members:
        out.append(f"{indent}\tpublic let {m}: {at}({v}) -> {r}")
    params = ", ".join(f"{m}: @escaping {at}({v}) -> {r}" for m, v, r in members)
    out.append(f"\n{indent}\tpublic init({params}) {{")
    for m, _, _ in members:
        out.append(f"{indent}\t\tself.{m} = {m}")
    out.append(f"{indent}\t}}\n\n{indent}\tpublic init(__safeDI_noScope builder: @escaping {at}() -> Built) {{")
    for m, _, r in members:
        out.append(f"{indent}\t\t{m} = {{ _ in {'builder()' if r == 'Built' else '.init(__safeDI_noScope: builder)'} }}")
    out.append(f"{indent}\t}}\n{indent}}}")
    return "\n".join(out)

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)

for shape in ["plain", "scall", "sfam"]:
    S = shape != "plain"
    I = "SendableInstantiator" if S else "Instantiator"
    at = "@Sendable " if S else ""
    d = f"G2L/{shape}/d"
    # Inner
    if shape == "sfam":
        inner = f"""import Harness
import SafeDI

extension A {{
	nonisolated public enum SafeDIScope_Api {{
		nonisolated public enum InnerT_Scope {{
{struct([("api_Values", [])], None, [("api", "api_Values", "Built")], False, "			")}
		}}
	}}

	nonisolated public enum SafeDISendableScope_Api {{
{struct([("tBuilder_Values", [])], None, [("tBuilder", "tBuilder_Values", "SafeDIScope_Api.InnerT_Scope.__safeDI_Builder<Built>")], True)}
	}}

	/// For code you write.
	public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {{
		self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {{
		@Sendable
		nonisolated func __safeDI_innerT_Sendable(_ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) -> InnerT {{
			let __safeDI_apiBuilder = __safeDI_apiSendableBuilder.tBuilder(.init())
			let api: any Api = __safeDI_apiBuilder.api(.init())
			return InnerT(api: api)
		}}
		let tBuilder = SendableInstantiator<InnerT> {{ __safeDI_innerT_Sendable(__safeDI_apiSendableBuilder) }}
		self.init(tBuilder: tBuilder)
	}}
}}
"""
        a_struct = "A.SafeDISendableScope_Api.__safeDI_Builder<Built>"
        a_label = "__safeDI_apiSendableBuilder"
    else:
        inner = f"""import Harness
import SafeDI

extension A {{
	nonisolated public enum SafeDIScope_Api {{
{struct([("api_Values", [])], None, [("api", "api_Values", "Built")], False)}
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
"""
        a_struct = "A.SafeDIScope_Api.__safeDI_Builder<Built>"
        a_label = "__safeDI_apiBuilder"
    write(f"{d}/Inner/Generated/Inner.swift", inner)
    # Feature: Store's family is @Sendable when its call of A sits in a @Sendable function.
    fam = "SafeDISendableScope_Api" if S else "SafeDIScope_Api"
    label = "apiSendableBuilder" if S else "apiBuilder"
    feature = f"""import Harness
import Inner
import SafeDI

extension Store {{
	nonisolated public enum {fam} {{
{struct([("aBuilder_Values", [("sideBuilder", f"{I}<Side>")])], None, [("aBuilder", "aBuilder_Values", a_struct)], S)}
	}}

	/// For code you write.
	public convenience init({label}: @escaping {at}() -> any Api) {{
		self.init(__safeDI_{label}: .init(__safeDI_noScope: {label}))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_{label}: {fam}.__safeDI_Builder<any Api>) {{
		{at}func __safeDI_aBuilder() -> A {{
			let sideBuilder = {I}<Side>(__safeDI_sideBuilder)
			return A({a_label}: __safeDI_{label}.aBuilder(.init(sideBuilder: sideBuilder)))
		}}
		let aBuilder = {I}<A>(__safeDI_aBuilder)
		{at}func __safeDI_sideBuilder() -> Side {{
			let aBuilder = {I}<A>(__safeDI_aBuilder)
			return Side(aBuilder: aBuilder)
		}}
		let sideBuilder = {I}<Side>(__safeDI_sideBuilder)
		self.init(aBuilder: aBuilder, sideBuilder: sideBuilder)
	}}
}}
"""
    write(f"{d}/Feature/Generated/Feature.swift", feature)
    if shape == "sfam":
        a_level = """				@Sendable func __safeDI_apiBuilder_A_InnerT_Scope(sideBuilder: SendableInstantiator<Side>) -> A.SafeDIScope_Api.InnerT_Scope.__safeDI_Builder<any Api> {
					.init(api: { _ in __safeDI_liveApi(sideBuilder: sideBuilder) })
				}
				return .init(aBuilder: { values in .init(tBuilder: { _ in __safeDI_apiBuilder_A_InnerT_Scope(sideBuilder: values.sideBuilder) }) })"""
    else:
        a_level = f"""				return .init(aBuilder: {{ values in .init(api: {{ _ in __safeDI_liveApi(sideBuilder: values.sideBuilder) }}) }})"""
    app = f"""import Feature
import Harness
import Inner
import SafeDI

extension Root {{
	public convenience init() {{
		func __safeDI_store() -> Store {{
			func __safeDI_{label}_Store() -> Store.{fam}.__safeDI_Builder<any Api> {{
				{at}func __safeDI_liveApi(sideBuilder: {I}<Side>) -> any Api {{
					LiveApi(sideBuilder: sideBuilder)
				}}
{a_level}
			}}
			return Store(__safeDI_{label}: __safeDI_{label}_Store())
		}}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}}
}}
"""
    write(f"{d}/App/Generated/App.swift", app)
