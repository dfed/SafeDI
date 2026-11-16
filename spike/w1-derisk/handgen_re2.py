"""Hand-written W1 form for RE2: re-entry through a second seam (req, opt) and through a plain type (one)."""
import os
def write(p, t):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(t)

def builder(members, indent):
    pad = indent
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

HEAD = "import Harness\nimport SafeDI\n\n"
two_seams = HEAD + f"""extension Service {{
	nonisolated public enum SafeDIScope_Gadget {{
		nonisolated public struct gadget_Values {{}}

		nonisolated public struct xBuilder_Values {{}}

{builder([("gadget", "gadget_Values", "Built"), ("xBuilder", "xBuilder_Values", "X.SafeDIScope_Gadget.__safeDI_Builder<Built>")], "		")}
	}}

	/// For code you write.
	public convenience init(gadgetBuilder: @escaping () -> any Gadget) {{
		self.init(__safeDI_gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {{
		let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(.init())
		func __safeDI_xBuilder() -> X {{
			X(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder.xBuilder(.init()))
		}}
		let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		self.init(gadget: gadget, xBuilder: xBuilder)
	}}
}}

extension X {{
	nonisolated public enum SafeDIScope_Gadget {{
		nonisolated public struct serviceBuilder_Values {{
			public let logger: Logger
		}}

{builder([("serviceBuilder", "serviceBuilder_Values", "Service.SafeDIScope_Gadget.__safeDI_Builder<Built>")], "		")}
	}}

	/// For code you write.
	public convenience init(gadgetBuilder: @escaping () -> any Gadget) {{
		self.init(__safeDI_gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {{
		let logger = Logger()
		func __safeDI_serviceBuilder() -> Service {{
			Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder.serviceBuilder(.init(logger: logger)))
		}}
		let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		self.init(logger: logger, serviceBuilder: serviceBuilder)
	}}
}}
"""
one_seam = HEAD + f"""extension Service {{
	nonisolated public enum SafeDIScope_Gadget {{
		nonisolated public struct gadget_Values {{}}

		nonisolated public struct xBuilder_Values {{}}

{builder([("gadget", "gadget_Values", "Built"), ("xBuilder", "xBuilder_Values", "X_Scope.__safeDI_Builder<Built>")], "		")}

		nonisolated public enum X_Scope {{
			nonisolated public struct serviceBuilder_Values {{
				public let logger: Logger
			}}

{builder([("serviceBuilder", "serviceBuilder_Values", "SafeDIScope_Gadget.__safeDI_Builder<Built>")], "			")}
		}}
	}}

	/// For code you write.
	public convenience init(gadgetBuilder: @escaping () -> any Gadget) {{
		self.init(__safeDI_gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder))
	}}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {{
		// Per-type: X's function takes X's level struct; the re-entering call hands Service the struct X's member
		// returns (candidate B), which carries X's logger.
		func __safeDI_x(_ __safeDI_gadgetBuilder: SafeDIScope_Gadget.X_Scope.__safeDI_Builder<any Gadget>) -> X {{
			let logger = Logger()
			func __safeDI_serviceBuilder() -> Service {{
				Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder.serviceBuilder(.init(logger: logger)))
			}}
			let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			return X(logger: logger, serviceBuilder: serviceBuilder)
		}}
		let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(.init())
		func __safeDI_xBuilder() -> X {{
			__safeDI_x(__safeDI_gadgetBuilder.xBuilder(.init()))
		}}
		let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		self.init(gadget: gadget, xBuilder: xBuilder)
	}}
}}
"""
for shape in ["req", "opt", "one"]:
    T = "Logger?" if shape == "opt" else "Logger"
    xscope = "X.SafeDIScope_Gadget" if shape != "one" else "Service.SafeDIScope_Gadget.X_Scope"
    root_logger = "" if shape == "opt" else "\t\tlet logger = Logger()\n"
    root_arg = "nil" if shape == "opt" else "logger"
    init_args = "service: service" if shape == "opt" else "logger: logger, service: service"
    app = f"""import Feature
import Harness
import SafeDI

extension Root {{
	public convenience init() {{
{root_logger}		// The dispatcher fixed point: the root level function takes the value its fill reads; the root passes its own
		// ({root_arg}), the re-entry from X's level passes X's.
		func __safeDI_gadgetBuilder_Service(logger: {T}) -> Service.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {{
			.init(
				gadget: {{ _ in LiveGadget(logger: logger) }},
				xBuilder: {{ _ in __safeDI_gadgetBuilder_Service_X() }},
			)
		}}
		func __safeDI_gadgetBuilder_Service_X() -> {xscope}.__safeDI_Builder<any Gadget> {{
			.init(serviceBuilder: {{ values in __safeDI_gadgetBuilder_Service(logger: values.logger) }})
		}}
		let service = Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Service(logger: {root_arg}))
		self.init({init_args})
	}}
}}
"""
    write(f"RE2/{shape}/d/Feature/Generated/Feature.swift", one_seam if shape == "one" else two_seams)
    write(f"RE2/{shape}/d/App/Generated/App.swift", app)
