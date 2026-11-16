import os, sys
sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module
feature = [
    swift_type("Screen", [("inst", "api", "any Api")]),
    swift_type("Home", [("inst", "screenBuilder", "Instantiator<Screen>")], seam=True),
]
app = [
    swift_type("LiveApi", [("recv", "screenBuilder", "Instantiator<Screen>")], fulfills="Api"),
    swift_type("Root", [("inst", "home", "Home")], root=True),
]
p = "public protocol Api: AnyObject {}\n\n"
c = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
d = "W1/base"
write_module(f"{d}/shared/Feature", ["Harness", "SafeDI"], feature, p + c)
write_module(f"{d}/shared/App", ["Feature", "Harness", "SafeDI"], app)
write_module(f"{d}/shared/Inline", ["Harness", "SafeDI"], [t.replace("(generateDependencyTree: true)", "") for t in feature] + app, p)
os.makedirs(f"{d}/main", exist_ok=True)
open(f"{d}/main/main.swift", "w").write("""import App
#if canImport(Feature)
import Feature
#endif
import Harness

var deepest: AnyObject? = {
\tlet root = Root()
\tlet s1 = root.home.screenBuilder.instantiate()
\tlet s2 = (s1.api as! LiveApi).screenBuilder.instantiate()
\tlet s3 = (s2.api as! LiveApi).screenBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((root, s1, s2)) {}
\treturn s3
}()
Registry.printAlive("holding only the deepest")
deepest = nil
Registry.printAlive("after dropping everything")
""")
