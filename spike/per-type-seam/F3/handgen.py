"""Authored once: run.sh does not rerun it, since ./CLI/lint.sh formats what it wrote and the formatted files are committed.
Writes F3's hand-written variants over candidate B's struct, under `SafeDIMockScope_Api`. (c) is the readable mock and
the struct only, since main rejects the shape; (d) is `__safeDI_mock` with one function per type. `safeDIOverrides` is
read as today's path reads it: the first `Screen` reads `safeDIOverrides.screen`, a reopened `Screen` reads no
override, and every `Step` reads `safeDIOverrides.screen.stepBuilder`. No configuration is passed as a parameter (that
is the deferred mock-overrides storage change), so the first `Screen` keeps its own text and the reopened ones share one
function: the key is the type plus the override outcome."""
import os

accepted = open("accepted/b/stored/Feat.swift.txt").read()
configurations = accepted[accepted.index("/// Configuration for how `Step`"):]
configurations = "#if DEBUG\n" + configurations


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


STRUCTS = f"""import Core
import Harness
import SafeDI

#if DEBUG
extension Home {{
    nonisolated public enum SafeDIMockScope_Api {{
{values("screen_Values", [], 8)}

{builder([("screen", "screen_Values", "Screen_Scope.__safeDI_Builder<Built>")], 8)}

        nonisolated public enum Screen_Scope {{
{values("stepBuilder_Values", [("cache", "Cache")], 12)}

{builder([("stepBuilder", "stepBuilder_Values", "Step_Scope.__safeDI_Builder<Built>")], 12)}
        }}

        nonisolated public enum Step_Scope {{
{values("api_Values", [("screenBuilder", "Instantiator<Screen>")], 12)}

{values("screenBuilder_Values", [], 12)}

{builder([("api", "api_Values", "Built"), ("screenBuilder", "screenBuilder_Values", "Screen_Scope.__safeDI_Builder<Built>")], 12)}
        }}
    }}

    /// Overrides for the mock dependency tree.
    nonisolated public struct SafeDIOverrides {{
        public init(
            screen: __safeDI_Feat_Screen_MockConfiguration = .init()
        ) {{
            self.screen = screen
        }}

        public let screen: __safeDI_Feat_Screen_MockConfiguration
    }}

    /// For code you write.
    public static func mock(
        apiBuilder: @escaping () -> any Api,
        safeDIOverrides: SafeDIOverrides = .init()
    ) -> Home {{
        __safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides)
    }}

"""

REJECTED = """    /// Only code SafeDI generates calls this mock. Main rejects this shape (`declarationBoundOnCycleReentry`), so the
    /// leak fix has no body for it in 2.3.0; the spike compiles the struct and the readable mock only.
    public static func __safeDI_mock(
        apiBuilder _: SafeDIMockScope_Api.__safeDI_Builder<any Api>,
        safeDIOverrides _: SafeDIOverrides = .init()
    ) -> Home {
        fatalError("rejected in 2.3.0")
    }
}
#endif

"""

PER_TYPE = """    /// Only code SafeDI generates calls this mock, and its shape can change in any release of SafeDI.
    public static func __safeDI_mock(
        apiBuilder __safeDI_apiBuilder: SafeDIMockScope_Api.__safeDI_Builder<any Api>,
        safeDIOverrides: SafeDIOverrides = .init()
    ) -> Home {
        func __safeDI_step(_ __safeDI_apiBuilder: SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {
            let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
            let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder) }
            let api: any Api = __safeDI_apiBuilder.api(.init(screenBuilder: screenBuilder))
            return Step.__safeDI_init(api: api, screenBuilder: screenBuilder, safeDIBuilder: safeDIOverrides.screen.stepBuilder.safeDIBuilder)
        }
        // A reopened `Screen`: today's path reads no override for it.
        func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api>) -> Screen {
            let cache = Cache()
            let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder.stepBuilder(.init(cache: cache))
            let stepBuilder = Instantiator<Step> { __safeDI_step(__safeDI_apiBuilder_stepBuilder) }
            return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: nil)
        }
        // The first `Screen` reads `safeDIOverrides.screen`, so it keeps its own text.
        let __safeDI_apiBuilder_screen = __safeDI_apiBuilder.screen(.init())
        let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
        let __safeDI_apiBuilder_stepBuilder = __safeDI_apiBuilder_screen.stepBuilder(.init(cache: cache))
        let stepBuilder = Instantiator<Step> { __safeDI_step(__safeDI_apiBuilder_stepBuilder) }
        let screen = Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
        return Home(screen: screen)
    }
}
#endif

"""

APP = """import Core
import Feat
import Harness
import SafeDI

#if DEBUG
extension Root {
    /// Overrides for the mock dependency tree.
    struct SafeDIOverrides {
        init(
            home: Home.SafeDIOverrides = .init()
        ) {
            self.home = home
        }

        let home: Home.SafeDIOverrides
    }

    static func mock(
        safeDIOverrides: SafeDIOverrides = .init()
    ) -> Root {
        func __safeDI_home() -> Home {
            func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
                .init(screen: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                .init(stepBuilder: { values in __safeDI_apiBuilder_Home_Step_Scope(cache: values.cache) })
            }
            func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api> {
                func __safeDI_live() -> any Api {
                    Live(cache: cache)
                }
                return .init(
                    api: { _ in __safeDI_live() },
                    screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }
                )
            }
            return Home.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
        }
        let home: Home = __safeDI_home()
        return Root(home: home)
    }
}
#endif
"""

CALLERS = """import Core
import Feat
import Harness
import SafeDI

#if DEBUG
// Hand-written callers of the readable mock; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Home] {
    [
        Home.mock(apiBuilder: { Live(cache: Cache()) }),
        Home.mock { Live(cache: Cache()) },
    ]
}
#endif
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


for variant, body in [("c", REJECTED), ("d", PER_TYPE)]:
    directory = f"stale/{variant}"
    write(f"{directory}/modules.txt", "Harness plain\nCore tool Harness\nFeat hand Core Harness\nApp hand Core Feat Harness\nMain plain App Harness\n")
    for module, shared in [("Harness", "../../common"), ("Core", "shared/Core"), ("Feat", "shared/Feat"), ("App", "shared/App"), ("Main", "main")]:
        write(f"{directory}/{module}/shared", shared + "\n")
    for module, package in [("Core", "Shop"), ("Feat", "Shop"), ("App", "App")]:
        write(f"{directory}/{module}/package", package + "\n")
    write(f"{directory}/Feat/Generated/Feat.swift", STRUCTS + body + configurations)
    write(f"{directory}/App/Generated/App.swift", APP)
    write(f"{directory}/App/Generated/Callers.swift", CALLERS)
