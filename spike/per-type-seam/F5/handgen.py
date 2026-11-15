"""Authored once: run.sh does not rerun it, since ./CLI/lint.sh formats what it wrote and the formatted files are committed.
Writes F5's hand-written variants. For L = next, main's enum already has a case at `next` (`Screen_Scope.next` holds
`Screen_Scope`), so candidates A and B have the same struct and differ only in the body: (c) is today's per-path body,
whose closing call reuses the struct the first `next` returned; (d) calls each screen's own member. For L =
screenBuilder, candidate A has no member at `Screen.screenBuilder` (the loop closes on `Home.screenBuilder`, through the
root member) and candidate B has one that returns `Screen_Scope`'s struct."""
import os


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


def structs(label, candidate):
    if label == "next":
        screen_values = [values("api_Values", [("id", "Int")], 12), values("next_Values", [("id", "Int"), ("api", "any Api")], 12)]
        screen_members = [("api", "api_Values", "Built"), ("next", "next_Values", "Screen_Scope.__safeDI_Builder<Built>")]
    else:
        screen_values = [values("api_Values", [("id", "Int"), ("screenBuilder", "Instantiator<Screen>")], 12)]
        screen_members = [("api", "api_Values", "Built")]
        if candidate == "B":
            screen_values.append(values("screenBuilder_Values", [("id", "Int")], 12))
            screen_members.append(("screenBuilder", "screenBuilder_Values", "Screen_Scope.__safeDI_Builder<Built>"))
    return f"""import Harness
import SafeDI

extension Home {{
    nonisolated public enum SafeDIScope_Api {{
{values("screenBuilder_Values", [], 8)}

{builder([("screenBuilder", "screenBuilder_Values", "Screen_Scope.__safeDI_Builder<Built>")], 8)}

        nonisolated public enum Screen_Scope {{
{(chr(10) + chr(10)).join(screen_values)}

{builder(screen_members, 12)}
        }}
    }}

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api) {{
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
    }}

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {{
"""


BODIES = {
    ("next", "c"): """        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        func __safeDI_screenBuilder(id: Int) -> Screen {
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init(id: id))
            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_screenBuilder.next(.init(id: id, api: api))
            func __safeDI_next(id: Int) -> Screen {
                let api: any Api = __safeDI_apiBuilder_next.api(.init(id: id))
                let next = Instantiator<Screen> {
                    __safeDI_next(id: $0)
                }
                return Screen(id: id, api: api, next: next)
            }
            let next = Instantiator<Screen> {
                __safeDI_next(id: $0)
            }
            return Screen(id: id, api: api, next: next)
        }
        let screenBuilder = Instantiator<Screen> {
            __safeDI_screenBuilder(id: $0)
        }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    ("next", "d"): """        func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>, id: Int) -> Screen {
            let api: any Api = __safeDI_apiBuilder.api(.init(id: id))
            let __safeDI_apiBuilder_next = __safeDI_apiBuilder.next(.init(id: id, api: api))
            let next = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_next, id: $0) }
            return Screen(id: id, api: api, next: next)
        }
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, id: $0) }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    ("screenBuilder", "c-A"): """        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        func __safeDI_screenBuilder(id: Int) -> Screen {
            let screenBuilder = Instantiator<Screen> {
                __safeDI_screenBuilder(id: $0)
            }
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init(id: id, screenBuilder: screenBuilder))
            return Screen(id: id, api: api, screenBuilder: screenBuilder)
        }
        let screenBuilder = Instantiator<Screen> {
            __safeDI_screenBuilder(id: $0)
        }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    ("screenBuilder", "c-B"): """        func __safeDI_screenBuilder(_ __safeDI_apiBuilder_screenBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>, id: Int) -> Screen {
            let __safeDI_apiBuilder_screenBuilder_again = __safeDI_apiBuilder_screenBuilder.screenBuilder(.init(id: id))
            let screenBuilder = Instantiator<Screen> {
                __safeDI_screenBuilder(__safeDI_apiBuilder_screenBuilder_again, id: $0)
            }
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init(id: id, screenBuilder: screenBuilder))
            return Screen(id: id, api: api, screenBuilder: screenBuilder)
        }
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let screenBuilder = Instantiator<Screen> {
            __safeDI_screenBuilder(__safeDI_apiBuilder_screenBuilder, id: $0)
        }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    ("screenBuilder", "d-A"): """        // Candidate A: every `Screen` takes its struct from the root member, the same declaration at every call, so the
        // function captures it instead of taking it as a parameter.
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        func __safeDI_screen(id: Int) -> Screen {
            let screenBuilder = Instantiator<Screen> { __safeDI_screen(id: $0) }
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init(id: id, screenBuilder: screenBuilder))
            return Screen(id: id, api: api, screenBuilder: screenBuilder)
        }
        let screenBuilder = Instantiator<Screen> { __safeDI_screen(id: $0) }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    ("screenBuilder", "d-B"): """        func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>, id: Int) -> Screen {
            let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init(id: id))
            let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, id: $0) }
            let api: any Api = __safeDI_apiBuilder.api(.init(id: id, screenBuilder: screenBuilder))
            return Screen(id: id, api: api, screenBuilder: screenBuilder)
        }
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, id: $0) }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
}


def app(label, candidate):
    reopen = ""
    if label == "next":
        reopen = ",\n                    next: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }"
    elif candidate == "B":
        reopen = ",\n                    screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }"
    return f"""import Feature
import Harness
import SafeDI

extension Root {{
    public convenience init() {{
        func __safeDI_home() -> Home {{
            func __safeDI_live(id: Int) -> any Api {{
                Live(id: id)
            }}
            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {{
                .init(screenBuilder: {{ _ in __safeDI_apiBuilder_Home_Screen_Scope() }})
            }}
            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {{
                .init(
                    api: {{ values in __safeDI_live(id: values.id) }}{reopen}
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
        Home { Live(id: 0) },
        Home(apiBuilder: { Live(id: 1) }),
    ]
}
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


for (label, variant), body in BODIES.items():
    candidate = variant[-1] if "-" in variant else "A"
    directory = f"{label}/{variant}"
    write(f"{directory}/modules.txt", "Harness plain\nFeature hand Harness\nApp hand Feature Harness\nMain plain App Harness\n")
    write(f"{directory}/Harness/shared", "../../common\n")
    write(f"{directory}/Feature/shared", "shared/Feature\n")
    write(f"{directory}/App/shared", "shared/App\n")
    write(f"{directory}/Main/shared", "main\n")
    write(f"{directory}/Feature/Generated/Feature.swift", structs(label, candidate) + body)
    write(f"{directory}/App/Generated/App.swift", app(label, candidate))
    write(f"{directory}/App/Generated/Callers.swift", CALLERS)
