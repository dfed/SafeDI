"""Authored once: run.sh does not rerun it, since ./CLI/lint.sh formats what it wrote and the formatted files are committed.
Writes F2's hand-written variants: (c) the leak fix's per-path body and (d) the per-type body, each over the builder
struct in candidate A (no member at the reopening property) and candidate B (one member per property).

Run: python3 -I handgen.py. Output: <label>/<variant>-<candidate>/… (Swift files formatted afterwards by ./CLI/lint.sh)."""
import os

HEADER = "import Harness\nimport SafeDI\n\n"


def builder(members, indent):
    """members: (name, values type, returned type)."""
    pad = " " * indent
    lines = [f"{pad}nonisolated public struct __safeDI_Builder<Built> {{"]
    for name, values, returned in members:
        lines.append(f"{pad}    public let {name}: ({values}) -> {returned}")
    lines.append("")
    parameters = ", ".join(f"{name}: @escaping ({values}) -> {returned}" for name, values, returned in members)
    lines.append(f"{pad}    public init({parameters}) {{")
    for name, _, _ in members:
        lines.append(f"{pad}        self.{name} = {name}")
    lines.append(f"{pad}    }}")
    lines.append("")
    lines.append(f"{pad}    public init(__safeDI_noScope builder: @escaping () -> Built) {{")
    for name, _, returned in members:
        body = "builder()" if returned == "Built" else ".init(__safeDI_noScope: builder)"
        lines.append(f"{pad}        {name} = {{ _ in {body} }}")
    lines.append(f"{pad}    }}")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def values(name, fields, indent):
    pad = " " * indent
    if not fields:
        return f"{pad}nonisolated public struct {name} {{}}"
    return "\n".join([f"{pad}nonisolated public struct {name} {{"] + [f"{pad}    public let {label}: {type_}" for label, type_ in fields] + [f"{pad}}}"])


def structs(label, candidate):
    step_members = [("api", "api_Values", "Built")]
    api_fields = [("screenBuilder", "Instantiator<Screen>")] if label == "screenBuilder" else []
    step_values = [values("api_Values", api_fields, 12)]
    if candidate == "B":
        # The member at the reopening property returns the reopened level's struct. It carries what `Step` binds
        # before the property: `api` for `next`; nothing for `screenBuilder`, whose wrapper `Step` binds first.
        fields = [("api", "any Api")] if label == "next" else []
        step_members.append((label, f"{label}_Values", "Screen_Scope.__safeDI_Builder<Built>"))
        step_values.append(values(f"{label}_Values", fields, 12))
    return f"""extension Home {{
    nonisolated public enum SafeDIScope_Api {{
{values("screenBuilder_Values", [], 8)}

{builder([("screenBuilder", "screenBuilder_Values", "Screen_Scope.__safeDI_Builder<Built>")], 8)}

        nonisolated public enum Screen_Scope {{
{values("stepBuilder_Values", [("cache", "Cache")], 12)}

{builder([("stepBuilder", "stepBuilder_Values", "Step_Scope.__safeDI_Builder<Built>")], 12)}
        }}

        nonisolated public enum Step_Scope {{
{chr(10).join(step_values)}

{builder(step_members, 12)}
        }}
    }}

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api) {{
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
    }}
"""


def per_path_body(label, candidate):
    """(c): today's per-path body for `screenBuilder`, which main accepts, over the struct."""
    assert label == "screenBuilder"
    if candidate == "A":
        # The loop closes by declaration: `Step`'s `screenBuilder` calls the function `Home`'s builds, which takes its
        # level's struct from the root member again, as today's code re-enters the root case.
        return """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
        func __safeDI_screenBuilder() -> Screen {
            let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
            let cache = Cache()
            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screenBuilder.stepBuilder(.init(cache: cache))
            func __safeDI_stepBuilder() -> Step {
                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
                let api: any Api = __safeDI_apiBuilder_stepBuilder.api(.init(screenBuilder: screenBuilder))
                return Step(api: api, screenBuilder: screenBuilder)
            }
            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
            return Screen(cache: cache, stepBuilder: stepBuilder)
        }
        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
        self.init(screenBuilder: screenBuilder)
    }
}
"""
    # Candidate B: the per-path body must hand the closing call the struct `Step`'s member returns, so the function the
    # loop closes on takes its level's struct, as inline's cycle function takes its cycle parameters.
    return """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
        func __safeDI_screenBuilder(_ __safeDI_apiBuilder_screenBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {
            let cache = Cache()
            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screenBuilder.stepBuilder(.init(cache: cache))
            func __safeDI_stepBuilder() -> Step {
                let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder_stepBuilder.screenBuilder(.init())
                let screenBuilder = Instantiator<Screen> { __safeDI_screenBuilder(__safeDI_apiBuilder_screenBuilder) }
                let api: any Api = __safeDI_apiBuilder_stepBuilder.api(.init(screenBuilder: screenBuilder))
                return Step(api: api, screenBuilder: screenBuilder)
            }
            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
            return Screen(cache: cache, stepBuilder: stepBuilder)
        }
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let screenBuilder = Instantiator<Screen> { __safeDI_screenBuilder(__safeDI_apiBuilder_screenBuilder) }
        self.init(screenBuilder: screenBuilder)
    }
}
"""


def per_type_body(label, candidate):
    """(d): one function per type; each takes its own level's struct."""
    if candidate == "A":
        # No member at the reopening property: `Step` takes `Screen`'s struct from the root member, the only member
        # that returns it.
        reopen_binding = ""
        reopen_struct = "__safeDI_apiBuilder.screenBuilder(.init())"
    else:
        args = ".init(api: api)" if label == "next" else ".init()"
        reopen_binding = f"__safeDI_apiBuilder.{label}({args})"
        reopen_struct = f"__safeDI_apiBuilder_{label}"
    if label == "next":
        step = f"""        func __safeDI_step(_ __safeDI_apiBuilder: SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {{
            let api: any Api = __safeDI_apiBuilder.api(.init())
{"            let __safeDI_apiBuilder_next = " + reopen_binding + chr(10) if reopen_binding else ""}            let next = Instantiator<Screen> {{ __safeDI_screen({reopen_struct}) }}
            return Step(api: api, next: next)
        }}"""
    else:
        step = f"""        func __safeDI_step(_ __safeDI_apiBuilder: SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {{
{"            let __safeDI_apiBuilder_screenBuilder = " + reopen_binding + chr(10) if reopen_binding else ""}            let screenBuilder = Instantiator<Screen> {{ __safeDI_screen({reopen_struct}) }}
            let api: any Api = __safeDI_apiBuilder.api(.init(screenBuilder: screenBuilder))
            return Step(api: api, screenBuilder: screenBuilder)
        }}"""
    if candidate == "A":
        # The function for `Step` reads the root struct: a declaration the same at every call is captured.
        step = step.replace(f"__safeDI_screen({reopen_struct})", "__safeDI_screen(__safeDI_rootBuilder.screenBuilder(.init()))")
    return f"""    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {{
{"        let __safeDI_rootBuilder = __safeDI_apiBuilder" + chr(10) if candidate == "A" else ""}{step}
        func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {{
            let cache = Cache()
            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder.stepBuilder(.init(cache: cache))
            let stepBuilder = Instantiator<Step> {{ __safeDI_step(__safeDI_apiBuilder_stepBuilder) }}
            return Screen(cache: cache, stepBuilder: stepBuilder)
        }}
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let screenBuilder = Instantiator<Screen> {{ __safeDI_screen(__safeDI_apiBuilder_screenBuilder) }}
        self.init(screenBuilder: screenBuilder)
    }}
}}
"""


def rejected_body():
    return """    /// Only code SafeDI generates calls this initializer. Main rejects this shape (`declarationBoundOnCycleReentry`), so
    /// the leak fix has no body for it in 2.3.0; the spike compiles the struct and the readable initializer only.
    public convenience init(__safeDI_apiBuilder _: SafeDIScope_Api.__safeDI_Builder<any Api>) {
        fatalError("rejected in 2.3.0")
    }
}
"""


def app_code(label, candidate):
    """The calling module's level functions, shared by (c) and (d) of a candidate."""
    reopen = f",\n                    {label}: {{ _ in __safeDI_apiBuilder_Home_Screen_Scope() }}" if candidate == "B" else ""
    return f"""import Feature
import Harness
import SafeDI

extension Root {{
    public convenience init() {{
        func __safeDI_home() -> Home {{
            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {{
                .init(screenBuilder: {{ _ in __safeDI_apiBuilder_Home_Screen_Scope() }})
            }}
            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {{
                .init(stepBuilder: {{ values in __safeDI_apiBuilder_Home_Step_Scope(cache: values.cache) }})
            }}
            func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api> {{
                func __safeDI_live() -> any Api {{
                    Live(cache: cache)
                }}
                return .init(
                    api: {{ _ in __safeDI_live() }}{reopen}
                )
            }}
            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
        }}
        let home: Home = __safeDI_home()
        self.init(home: home)
    }}
}}
"""


CALLERS = """import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Home] {
    [
        Home { Live(cache: Cache()) },
        Home(apiBuilder: { Live(cache: Cache()) }),
    ]
}
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


def layout(variant_directory, feature_mode="hand"):
    write(f"{variant_directory}/modules.txt", f"Harness plain\nFeature {feature_mode} Harness\nApp hand Feature Harness\nMain plain App Harness\n")
    write(f"{variant_directory}/Harness/shared", "../../common\n")
    write(f"{variant_directory}/Feature/shared", "shared/Feature\n")
    write(f"{variant_directory}/App/shared", "shared/App\n")
    write(f"{variant_directory}/Main/shared", "main\n")


for label in ["next", "screenBuilder"]:
    for candidate in ["A", "B"]:
        c = f"{label}/c-{candidate}"
        d = f"{label}/d-{candidate}"
        if label == "next":
            # Main rejects the shape: (c) is the struct and the readable initializer, compiled with the callers and a
            # main that builds nothing.
            write(f"{c}/modules.txt", "Harness plain\nFeature hand Harness\nMain plain Feature Harness\n")
            write(f"{c}/Harness/shared", "../../common\n")
            write(f"{c}/Feature/shared", "shared/Feature\n")
            write(f"{c}/Feature/Generated/Feature.swift", HEADER + structs(label, candidate) + "\n" + rejected_body())
            write(f"{c}/Main/Sources/main.swift", CALLERS.replace("func handWrittenCallers", "@MainActor func handWrittenCallers").replace("Live(cache: Cache())", "Cache() as AnyObject as! any Api") + '\nprint("rejected in 2.3.0: the struct and the readable initializer compile")\n')
        else:
            layout(c)
            write(f"{c}/Feature/Generated/Feature.swift", HEADER + structs(label, candidate) + "\n" + per_path_body(label, candidate))
            write(f"{c}/App/Generated/App.swift", app_code(label, candidate))
            write(f"{c}/App/Generated/Callers.swift", CALLERS)
        layout(d)
        write(f"{d}/Feature/Generated/Feature.swift", HEADER + structs(label, candidate) + "\n" + per_type_body(label, candidate))
        write(f"{d}/App/Generated/App.swift", app_code(label, candidate))
        write(f"{d}/App/Generated/Callers.swift", CALLERS)
