"""Authored once: run.sh does not rerun it, since ./CLI/lint.sh formats what it wrote and the formatted files are committed.
Writes F6's hand-written variants. (c): the leak fix's per-path body over both families' structs. (d1): one
`@Sendable nonisolated` function per type, taking the plain level struct both families hand it (for (ii) also the
`@Sendable` family's struct of the type, which its `again` reopens). (d2): one function per (type, family)."""
import os


def builder(members, indent, sendable):
    pad = " " * indent
    attribute = "@Sendable " if sendable else ""
    lines = [f"{pad}nonisolated public struct __safeDI_Builder<Built>{': Sendable' if sendable else ''} {{"]
    for name, values, returned in members:
        lines.append(f"{pad}    public let {name}: {attribute}({values}) -> {returned}")
    lines.append("")
    parameters = ", ".join(f"{name}: @escaping {attribute}({values}) -> {returned}" for name, values, returned in members)
    lines.append(f"{pad}    public init({parameters}) {{")
    for name, _, _ in members:
        lines.append(f"{pad}        self.{name} = {name}")
    lines.append(f"{pad}    }}")
    lines.append("")
    lines.append(f"{pad}    public init(__safeDI_noScope builder: @escaping {attribute}() -> Built) {{")
    for name, _, returned in members:
        body = "builder()" if returned == "Built" else ".init(__safeDI_noScope: builder)"
        lines.append(f"{pad}        {name} = {{ _ in {body} }}")
    lines.append(f"{pad}    }}")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def empty(name, indent):
    return f"{' ' * indent}nonisolated public struct {name}: Sendable {{}}" if name.endswith("Sendable_Values") or name.startswith("tBuilder") or name.startswith("again") else f"{' ' * indent}nonisolated public struct {name} {{}}"


HEADER = "import Harness\nimport SafeDI\n\n"

STRUCTS_I = f"""extension Hub {{
    nonisolated public enum SafeDIScope_Api {{
{empty("t_Values", 8)}

{builder([("t", "t_Values", "T_Scope.__safeDI_Builder<Built>")], 8, False)}

        nonisolated public enum T_Scope {{
{empty("api_Values", 12)}

{builder([("api", "api_Values", "Built")], 12, False)}
        }}
    }}

    nonisolated public enum SafeDISendableScope_Api {{
{empty("tBuilder_Values", 8)}

{builder([("tBuilder", "tBuilder_Values", "SafeDIScope_Api.T_Scope.__safeDI_Builder<Built>")], 8, True)}
    }}

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {{
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
    }}

"""

BODY_I = {
    "c": """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        let __safeDI_apiBuilder_t = __safeDI_apiBuilder.t(.init())
        func __safeDI_t() -> T {
            let api: any Api = __safeDI_apiBuilder_t.api(.init())
            return T(api: api)
        }
        let t: T = __safeDI_t()
        @Sendable nonisolated func __safeDI_tBuilder() -> T {
            let __safeDI_apiBuilder_tBuilder = __safeDI_apiSendableBuilder.tBuilder(.init())
            let api: any Api = __safeDI_apiBuilder_tBuilder.api(.init())
            return T(api: api)
        }
        let tBuilder = SendableInstantiator<T>(__safeDI_tBuilder)
        self.init(t: t, tBuilder: tBuilder)
    }
}
""",
    "d1": """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        @Sendable nonisolated func __safeDI_t(_ __safeDI_apiBuilder: SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api>) -> T {
            let api: any Api = __safeDI_apiBuilder.api(.init())
            return T(api: api)
        }
        let t: T = __safeDI_t(__safeDI_apiBuilder.t(.init()))
        @Sendable nonisolated func __safeDI_tBuilder() -> T {
            __safeDI_t(__safeDI_apiSendableBuilder.tBuilder(.init()))
        }
        let tBuilder = SendableInstantiator<T>(__safeDI_tBuilder)
        self.init(t: t, tBuilder: tBuilder)
    }
}
""",
    "d2": """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        func __safeDI_t(_ __safeDI_apiBuilder: SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api>) -> T {
            let api: any Api = __safeDI_apiBuilder.api(.init())
            return T(api: api)
        }
        @Sendable nonisolated func __safeDI_t_Sendable(_ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) -> T {
            let __safeDI_apiBuilder = __safeDI_apiSendableBuilder.tBuilder(.init())
            let api: any Api = __safeDI_apiBuilder.api(.init())
            return T(api: api)
        }
        let t: T = __safeDI_t(__safeDI_apiBuilder.t(.init()))
        let tBuilder = SendableInstantiator<T> { __safeDI_t_Sendable(__safeDI_apiSendableBuilder) }
        self.init(t: t, tBuilder: tBuilder)
    }
}
""",
}

APP_I = """import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        func __safeDI_hub() -> Hub {
            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIScope_Api.__safeDI_Builder<any Api> {
                .init(t: { _ in __safeDI_apiBuilder_Hub_T_Scope() })
            }
            @Sendable func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api> {
                @Sendable func __safeDI_liveApi() -> any Api {
                    LiveApi()
                }
                return .init(api: { _ in __safeDI_liveApi() })
            }
            func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
                .init(tBuilder: { _ in __safeDI_apiBuilder_Hub_T_Scope() })
            }
            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub())
        }
        let hub: Hub = __safeDI_hub()
        self.init(hub: hub)
    }
}
"""

CALLERS_I = """import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Hub] {
    [
        Hub(apiBuilder: { LiveApi() }, apiSendableBuilder: { LiveApi() }),
        Hub(apiBuilder: LiveApi.init, apiSendableBuilder: LiveApi.init),
    ]
}
"""

STRUCTS_II = f"""extension Home {{
    nonisolated public enum SafeDIScope_Api {{
{empty("screenBuilder_Values", 8)}

{builder([("screenBuilder", "screenBuilder_Values", "Screen_Scope.__safeDI_Builder<Built>")], 8, False)}

        nonisolated public enum Screen_Scope {{
{empty("api_Values", 12)}

{builder([("api", "api_Values", "Built")], 12, False)}
        }}
    }}

    nonisolated public enum SafeDISendableScope_Api {{
{empty("screenBuilder_Sendable_Values", 8)}

{builder([("screenBuilder_Sendable", "screenBuilder_Sendable_Values", "Screen_Scope.__safeDI_Builder<Built>")], 8, True)}

        nonisolated public enum Screen_Scope {{
{empty("again_Values", 12)}

{builder([("again", "again_Values", "SafeDIScope_Api.Screen_Scope.__safeDI_Builder<Built>")], 12, True)}
        }}
    }}

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {{
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
    }}

"""

BODY_II = {
    "c": """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        func __safeDI_screenBuilder() -> Screen {
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init())
            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder_Sendable(.init())
            @Sendable nonisolated func __safeDI_again() -> Screen {
                let __safeDI_apiBuilder_again = __safeDI_apiSendableBuilder_screenBuilder.again(.init())
                let api: any Api = __safeDI_apiBuilder_again.api(.init())
                let again = SendableInstantiator<Screen>(__safeDI_again)
                return Screen(api: api, again: again)
            }
            let again = SendableInstantiator<Screen>(__safeDI_again)
            return Screen(api: api, again: again)
        }
        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    "d1": """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        @Sendable nonisolated func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>, _ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {
            let api: any Api = __safeDI_apiBuilder.api(.init())
            let again = SendableInstantiator<Screen> { __safeDI_screen(__safeDI_apiSendableBuilder.again(.init()), __safeDI_apiSendableBuilder) }
            return Screen(api: api, again: again)
        }
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder_Sendable(.init())
        let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, __safeDI_apiSendableBuilder_screenBuilder) }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
    "d2": """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        @Sendable nonisolated func __safeDI_screen_Sendable(_ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {
            let __safeDI_apiBuilder = __safeDI_apiSendableBuilder.again(.init())
            let api: any Api = __safeDI_apiBuilder.api(.init())
            let again = SendableInstantiator<Screen> { __safeDI_screen_Sendable(__safeDI_apiSendableBuilder) }
            return Screen(api: api, again: again)
        }
        func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>, _ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {
            let api: any Api = __safeDI_apiBuilder.api(.init())
            let again = SendableInstantiator<Screen> { __safeDI_screen_Sendable(__safeDI_apiSendableBuilder) }
            return Screen(api: api, again: again)
        }
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder_Sendable(.init())
        let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, __safeDI_apiSendableBuilder_screenBuilder) }
        self.init(screenBuilder: screenBuilder)
    }
}
""",
}

APP_II = """import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        func __safeDI_home() -> Home {
            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
                .init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            @Sendable func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                @Sendable func __safeDI_liveApi() -> any Api {
                    LiveApi()
                }
                return .init(api: { _ in __safeDI_liveApi() })
            }
            func __safeDI_apiSendableBuilder_Home() -> Home.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
                .init(screenBuilder_Sendable: { _ in __safeDI_apiSendableBuilder_Home_Screen_Scope() })
            }
            @Sendable func __safeDI_apiSendableBuilder_Home_Screen_Scope() -> Home.SafeDISendableScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                .init(again: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
        }
        let home: Home = __safeDI_home()
        self.init(home: home)
    }
}
"""

CALLERS_II = CALLERS_I.replace("[Hub]", "[Home]").replace("Hub(", "Home(")


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


for shape, structs, bodies, app, callers in [("i", STRUCTS_I, BODY_I, APP_I, CALLERS_I), ("ii", STRUCTS_II, BODY_II, APP_II, CALLERS_II)]:
    for variant, body in bodies.items():
        directory = f"{shape}/{variant}"
        write(f"{directory}/modules.txt", "Harness plain\nFeature hand Harness\nApp hand Feature Harness\nMain plain App Harness\n")
        write(f"{directory}/Harness/shared", "../../common\n")
        write(f"{directory}/Feature/shared", "shared/Feature\n")
        write(f"{directory}/App/shared", "shared/App\n")
        write(f"{directory}/Main/shared", "main\n")
        write(f"{directory}/Feature/Generated/Feature.swift", HEADER + structs + body)
        write(f"{directory}/App/Generated/App.swift", app)
        write(f"{directory}/App/Generated/Callers.swift", callers)
