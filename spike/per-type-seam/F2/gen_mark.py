"""F2 extended (`mark/`): F2's loop with L = next, where `Screen` also has a hole, `monitor: any Api`, and `Step` binds
`mark` before `next`. `Live` reads `mark` only if available. Inline, the `Live` that fills screen k+1's `monitor` reads
step k's `mark`: a value bound on the route between the root and the reopened level, which tells candidate A (the
reopened level takes its struct from the root member) from candidate B (a member at `next` carries `mark`)."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

feature = [
    swift_type("Cache", []),
    swift_type("Mark", []),
    swift_type("Home", [("inst", "screenBuilder", "Instantiator<Screen>")], seam=True),
    swift_type("Screen", [("inst", "cache", "Cache"), ("inst", "monitor", "any Api"), ("inst", "stepBuilder", "Instantiator<Step>")]),
    swift_type("Step", [("inst", "api", "any Api"), ("inst", "mark", "Mark"), ("inst", "next", "Instantiator<Screen>")]),
]
app = [
    swift_type("Live", [("recv", "cache", "Cache"), ("opt", "mark", "Mark?")], fulfills="Api"),
    swift_type("Root", [("inst", "home", "Home")], root=True),
]
protocol = "public protocol Api: AnyObject {}\n\n"
configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
write_module("mark/shared/Feature", ["Harness", "SafeDI"], feature, protocol + configuration)
write_module("mark/shared/App", ["Feature", "Harness", "SafeDI"], app)
inline = [t.replace("(generateDependencyTree: true)", "") for t in feature]
write_module("mark/shared/Inline", ["Harness", "SafeDI"], inline + app, protocol)
os.makedirs("mark/main", exist_ok=True)
with open("next/main/main.swift") as source, open("mark/main/main.swift", "w") as file:
    file.write(source.read())


def builder(members, indent):
    pad = " " * indent
    lines = [f"{pad}nonisolated public struct __safeDI_Builder<Built> {{"]
    lines += [f"{pad}    public let {name}: ({values}) -> {returned}" for name, values, returned in members]
    lines.append("")
    lines.append(f"{pad}    public init(" + ", ".join(f"{name}: @escaping ({values}) -> {returned}" for name, values, returned in members) + ") {")
    lines += [f"{pad}        self.{name} = {name}" for name, _, _ in members]
    lines.append(f"{pad}    }}")
    lines.append("")
    lines.append(f"{pad}    public init(__safeDI_noScope builder: @escaping () -> Built) {{")
    lines += [f"{pad}        {name} = {{ _ in {'builder()' if returned == 'Built' else '.init(__safeDI_noScope: builder)'} }}" for name, _, returned in members]
    lines.append(f"{pad}    }}")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def values(name, fields, indent):
    pad = " " * indent
    if not fields:
        return f"{pad}nonisolated public struct {name} {{}}"
    return "\n".join([f"{pad}nonisolated public struct {name} {{"] + [f"{pad}    public let {label}: {type_}" for label, type_ in fields] + [f"{pad}}}"])


def feature_code(candidate):
    step_members = [("api", "api_Values", "Built")]
    step_values = [values("api_Values", [("mark", "Mark")], 12)]
    if candidate == "B":
        step_members.append(("next", "next_Values", "Screen_Scope.__safeDI_Builder<Built>"))
        step_values.append(values("next_Values", [("mark", "Mark"), ("api", "any Api")], 12))
        reopen = """            let __safeDI_apiBuilder_next = __safeDI_apiBuilder.next(.init(mark: mark, api: api))
            let next = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_next) }"""
        root_binding = ""
    else:
        reopen = """            // Candidate A: no member at `next`, so the reopened level takes its struct from the root member.
            let next = Instantiator<Screen> { __safeDI_screen(__safeDI_rootBuilder.screenBuilder(.init())) }"""
        root_binding = "        let __safeDI_rootBuilder = __safeDI_apiBuilder\n"
    return f"""import Harness
import SafeDI

extension Home {{
    nonisolated public enum SafeDIScope_Api {{
{values("screenBuilder_Values", [], 8)}

{builder([("screenBuilder", "screenBuilder_Values", "Screen_Scope.__safeDI_Builder<Built>")], 8)}

        nonisolated public enum Screen_Scope {{
{values("monitor_Values", [("cache", "Cache")], 12)}

{values("stepBuilder_Values", [("cache", "Cache"), ("monitor", "any Api")], 12)}

{builder([("monitor", "monitor_Values", "Built"), ("stepBuilder", "stepBuilder_Values", "Step_Scope.__safeDI_Builder<Built>")], 12)}
        }}

        nonisolated public enum Step_Scope {{
{(chr(10) + chr(10)).join(step_values)}

{builder(step_members, 12)}
        }}
    }}

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api) {{
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
    }}

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {{
{root_binding}        func __safeDI_step(_ __safeDI_apiBuilder: SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {{
            let mark = Mark()
            let api: any Api = __safeDI_apiBuilder.api(.init(mark: mark))
{reopen}
            return Step(api: api, mark: mark, next: next)
        }}
        func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {{
            let cache = Cache()
            let monitor: any Api = __safeDI_apiBuilder.monitor(.init(cache: cache))
            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder.stepBuilder(.init(cache: cache, monitor: monitor))
            let stepBuilder = Instantiator<Step> {{ __safeDI_step(__safeDI_apiBuilder_stepBuilder) }}
            return Screen(cache: cache, monitor: monitor, stepBuilder: stepBuilder)
        }}
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let screenBuilder = Instantiator<Screen> {{ __safeDI_screen(__safeDI_apiBuilder_screenBuilder) }}
        self.init(screenBuilder: screenBuilder)
    }}
}}
"""


def app_code(candidate):
    next_member = ",\n                    next: { values in __safeDI_apiBuilder_Home_Screen_Scope(mark: values.mark) }" if candidate == "B" else ""
    return f"""import Feature
import Harness
import SafeDI

extension Root {{
    public convenience init() {{
        func __safeDI_home() -> Home {{
            func __safeDI_live(cache: Cache, mark: Mark?) -> any Api {{
                Live(cache: cache, mark: mark)
            }}
            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {{
                .init(screenBuilder: {{ _ in __safeDI_apiBuilder_Home_Screen_Scope(mark: nil) }})
            }}
            func __safeDI_apiBuilder_Home_Screen_Scope(mark: Mark?) -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {{
                .init(
                    monitor: {{ values in __safeDI_live(cache: values.cache, mark: mark) }},
                    stepBuilder: {{ values in __safeDI_apiBuilder_Home_Step_Scope(cache: values.cache) }}
                )
            }}
            func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api> {{
                .init(
                    api: {{ values in __safeDI_live(cache: cache, mark: values.mark) }}{next_member}
                )
            }}
            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
        }}
        let home: Home = __safeDI_home()
        self.init(home: home)
    }}
}}
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


for candidate in ["A", "B"]:
    directory = f"mark/d-{candidate}"
    write(f"{directory}/modules.txt", "Harness plain\nFeature hand Harness\nApp hand Feature Harness\nMain plain App Harness\n")
    write(f"{directory}/Harness/shared", "../../common\n")
    write(f"{directory}/Feature/shared", "shared/Feature\n")
    write(f"{directory}/App/shared", "shared/App\n")
    write(f"{directory}/Main/shared", "main\n")
    write(f"{directory}/Feature/Generated/Feature.swift", feature_code(candidate))
    write(f"{directory}/App/Generated/App.swift", app_code(candidate))
for variant, mode in [("a", None), ("b", "tool")]:
    directory = f"mark/{variant}"
    write(f"{directory}/Harness/shared", "../../common\n")
    write(f"{directory}/Main/shared", "main\n")
    if mode is None:
        write(f"{directory}/modules.txt", "Harness plain\nApp tool Harness\nMain plain App Harness\n")
        write(f"{directory}/App/shared", "shared/Inline\n")
    else:
        write(f"{directory}/modules.txt", "Harness plain\nFeature tool Harness\nApp tool Feature Harness\nMain plain App Harness\n")
        write(f"{directory}/Feature/shared", "shared/Feature\n")
        write(f"{directory}/App/shared", "shared/App\n")
