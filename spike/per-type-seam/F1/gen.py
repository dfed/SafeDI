"""F1, calibration: SafeDIToolSeamBuilderParameterTests.generate_declaresOneCaseForOwnerType_whenTreeBuildsHolesOwnerAtTwoSites."""
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

feature = [
    swift_type("Analytics", []),
    swift_type("Session", []),
    swift_type("Theme", []),
    swift_type("Avatar", [("inst", "userService", "any UserService")]),
    swift_type("Home", [("inst", "session", "Session"), ("inst", "avatar", "Avatar")]),
    swift_type("Settings", [("inst", "theme", "Theme"), ("inst", "avatar", "Avatar")]),
    swift_type("Service", [("inst", "analytics", "Analytics"), ("inst", "home", "Home"), ("inst", "settings", "Settings")], seam=True),
]
app = [
    swift_type("DefaultUserService", [("recv", "analytics", "Analytics"), ("opt", "session", "Session?")], fulfills="UserService"),
    swift_type("Root", [("inst", "session", "Session"), ("inst", "service", "Service")], root=True),
]
protocol = "public protocol UserService: AnyObject {}\n\n"
configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
write_module("shared/Feature", ["Harness", "SafeDI"], feature, protocol + configuration)
write_module("shared/App", ["Feature", "Harness", "SafeDI"], app)
inline = [t.replace("(generateDependencyTree: true)", "") for t in feature]
write_module("shared/Inline", ["Harness", "SafeDI"], inline + app, protocol)
