#!/usr/bin/env python3
# Writes the value harness's production-root probe graphs (Scripts/value-harness/production-root-probes, or the
# directory given): each a directory of Swift files in one module, or in two (`// module: FuzzFeature` beneath
# `// module: FuzzApp`), whose root is compared by value between two releases. Every class stores each dependency and a
# creation stamp (`DifferentialValueCreationStamp`), so the comparator sees a value at every read.
import os, shutil, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "production-root-probes")
STAMP = "let differentialValueCreationStamp = ProbeStamp.next()"
COUNTER = """public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}
"""

def cls(name, props=(), attr="@Instantiable", conform=(), sendable=False, access="public"):
    """props: (attribute, label, type) or (None, label, type, default) for a plain stored parameter."""
    conformances = ["Instantiable"] + list(conform) + (["Sendable"] if sendable else [])
    parameters, assignments, lines = [], [], []
    for p in props:
        attribute, label, typ = p[0], p[1], p[2]
        escaping = "@escaping " if typ.startswith("(") and "->" in typ else ""
        default = f" = {p[3]}" if len(p) > 3 else ""
        parameters.append(f"{label}: {escaping}{typ}{default}")
        assignments.append(f"self.{label} = {label}")
        lines.append(f"    {attribute + ' ' if attribute else ''}let {label}: {typ}")
    body = "; ".join(assignments)
    init = f"    {access} init({', '.join(parameters)}) {{ {body} }}" if parameters else f"    {access} init() {{}}"
    return "\n".join([attr, f"{access} final class {name}: {', '.join(conformances)} {{", init] + lines + [f"    {STAMP}", "}"]) + "\n"

def root(name, props, **kw):
    return cls(name, props, attr="@Instantiable(isRoot: true)", **kw)

PROBES = {}
def probe(name, files):
    PROBES[name] = files

def one(*decls, extra=""):
    return {"Graph.swift": "import SafeDI\n\n" + "\n".join(decls) + extra, "ProbeStamp.swift": COUNTER}

def two(feature_decls, app_decls, feature_extra="", app_extra="", app_fills=False):
    return {
        "Feature.swift": "// module: FuzzFeature\nimport SafeDI\n\n" + COUNTER + "\n" + feature_extra + "\n".join(feature_decls),
        "App.swift": "// module: FuzzApp" + (", fills a hole" if app_fills else "") + "\nimport FuzzFeature\nimport SafeDI\n\n" + app_extra + "\n".join(app_decls),
    }

I = "@Instantiated"; R = "@Received"; RO = "@Received(onlyIfAvailable: true)"; IO = "@Instantiated(onlyIfAvailable: true)"
def ren(source, typ, opt=False, erased=False):
    return f"@Received(fulfilledByDependencyNamed: \"{source}\", ofType: {typ}.self" + (", erasedToConcreteExistential: true" if erased else "") + (", onlyIfAvailable: true" if opt else "") + ")"

# --- Cycles with renames ---------------------------------------------------------------------------------------
probe("cycle-rename-session", one(
    root("Root", [(I, "session", "Session"), (I, "homeBuilder", "Instantiator<Home>")]),
    cls("Session"),
    cls("Home", [(ren("session", "Session"), "currentSession", "Session"), (I, "profileBuilder", "Instantiator<Profile>")]),
    cls("Profile", [(R, "currentSession", "Session"), (R, "session", "Session"), (I, "homeBuilder", "Instantiator<Home>")]),
))
probe("cycle-redeclared-label", one(
    root("Root", [(I, "tag", "Tag"), (I, "homeBuilder", "Instantiator<Home>")]),
    cls("Tag"),
    cls("Home", [(I, "reader", "Reader"), (I, "profileBuilder", "Instantiator<Profile>")]),
    cls("Reader", [(R, "tag", "Tag")]),
    cls("Profile", [(I, "tag", "Tag"), (I, "homeBuilder", "Instantiator<Home>")]),
))
probe("cycle-renamed-back-builder", one(
    root("Root", [(I, "homeBuilder", "Instantiator<Home>")]),
    cls("Home", [(I, "profileBuilder", "Instantiator<Profile>"), (I, "badge", "Badge")]),
    cls("Badge"),
    cls("Profile", [(ren("homeBuilder", "Instantiator<Home>"), "backBuilder", "Instantiator<Home>"), (R, "badge", "Badge")]),
))
probe("cycle-three-types-renamed-owner", one(
    root("Root", [(I, "user", "User"), (I, "aBuilder", "Instantiator<StepA>")]),
    cls("User"),
    cls("StepA", [(I, "reader", "OwnerReader"), (I, "bBuilder", "Instantiator<StepB>")]),
    cls("OwnerReader", [(RO, "owner", "User?"), (R, "user", "User")]),
    cls("StepB", [(ren("user", "User"), "owner", "User"), (I, "cBuilder", "Instantiator<StepC>")]),
    cls("StepC", [(R, "owner", "User"), (I, "user", "User"), (I, "aBuilder", "Instantiator<StepA>")]),
))
probe("cycle-only-if-available-rename", one(
    root("Root", [(I, "token", "Token"), (I, "aBuilder", "Instantiator<Gate>")]),
    cls("Token"),
    cls("Gate", [(ren("token", "Token", opt=True), "maybeToken", "Token?"), (I, "bBuilder", "Instantiator<Door>")]),
    cls("Door", [(RO, "maybeToken", "Token?"), (I, "token", "Token"), (I, "aBuilder", "Instantiator<Gate>")]),
))
probe("cycle-erased-rename", one(
    root("Root", [(I, "store", "Store"), (I, "listBuilder", "Instantiator<ListScreen>")]),
    "public protocol Storing: AnyObject {}\npublic struct AnyStoring { public let base: any Storing; public init(_ base: any Storing) { self.base = base } }\n",
    cls("Store", conform=["Storing"]),
    cls("ListScreen", [(ren("store", "Store", erased=True), "storing", "AnyStoring"), (I, "detailBuilder", "Instantiator<DetailScreen>")]),
    cls("DetailScreen", [(R, "storing", "AnyStoring"), (I, "listBuilder", "Instantiator<ListScreen>"), (I, "store", "Store")]),
))
probe("cycle-same-label-retyped", one(
    root("Root", [(I, "manager", "Manager"), (I, "aBuilder", "Instantiator<Shelf>")]),
    "public protocol Vending: AnyObject {}\n",
    cls("Manager", conform=["Vending"]),
    cls("Shelf", [(ren("manager", "Manager"), "vendor", "any Vending"), (I, "bBuilder", "Instantiator<Bin>")]),
    cls("Bin", [(R, "vendor", "any Vending"), (R, "manager", "Manager"), (I, "aBuilder", "Instantiator<Shelf>")]),
))
# --- Only if available -----------------------------------------------------------------------------------------
probe("only-if-available-two-parents", one(
    root("Root", [(I, "lit", "LitPanel"), (I, "dark", "DarkPanel")]),
    cls("Theme"),
    cls("LitPanel", [(I, "theme", "Theme"), (I, "badge", "ThemeBadge")]),
    cls("DarkPanel", [(I, "badgeBuilder", "Instantiator<ThemeBadge>")]),
    cls("ThemeBadge", [(RO, "theme", "Theme?"), (RO, "accent", "Accent?")]),
    cls("Accent"),
))
probe("instantiated-only-if-available", one(
    root("Root", [(I, "checkout", "Checkout")]),
    "public protocol FraudCheck: AnyObject {}\npublic protocol Coupons: AnyObject {}\n",
    cls("Checkout", [(IO, "fraud", "(any FraudCheck)?"), (IO, "coupons", "(any Coupons)?"), (I, "summary", "Summary")]),
    cls("FraudCheckImpl", attr="@Instantiable(fulfillingAdditionalTypes: [FraudCheck.self])", conform=["FraudCheck"]),
    cls("Summary", [(R, "fraud", "(any FraudCheck)?"), (RO, "coupons", "(any Coupons)?")]),
))
probe("only-if-available-inside-instantiator", one(
    root("Root", [(I, "outerBuilder", "Instantiator<Outer>"), (I, "clock", "Ticker")]),
    cls("Ticker"),
    cls("Outer", [(I, "ledger", "Ledger"), (I, "innerBuilder", "Instantiator<Inner>")]),
    cls("Ledger"),
    cls("Inner", [(RO, "clock", "Ticker?"), (RO, "ledger", "Ledger?"), (RO, "missing", "Ledger?"), (I, "note", "Note")]),
    cls("Note", [(RO, "ledger", "Ledger?"), (R, "clock", "Ticker")]),
))
probe("only-if-available-alias", one(
    root("Root", [(I, "account", "Account"), (I, "pane", "AccountPane"), (I, "otherBuilder", "Instantiator<OtherPane>")]),
    cls("Account"),
    cls("AccountPane", [(ren("account", "Account", opt=True), "maybeAccount", "Account?"), (I, "row", "AccountRow")]),
    cls("AccountRow", [(RO, "maybeAccount", "Account?"), (R, "account", "Account")]),
    cls("OtherPane", [(ren("missingAccount", "Account", opt=True), "maybeOther", "Account?")]),
))
probe("only-if-available-optional-form", one(
    root("Root", [(I, "profile", "Profile"), (I, "screen", "ProfileScreen")]),
    cls("Profile"),
    cls("ProfileScreen", [(ren("profile", "Profile?", opt=True), "optionalProfile", "Profile?"), (I, "cell", "ProfileCell")]),
    cls("ProfileCell", [(RO, "optionalProfile", "Profile?"), (RO, "profile", "Profile?")]),
))
# --- Lazy and Sendable wrappers --------------------------------------------------------------------------------
probe("lazy-wrapper-forms", one(
    root("Root", [(I, "cache", "LazilyInstantiated<Cache>"), (I, "feed", "Feed"), (I, "panelBuilder", "Instantiator<Panel>")]),
    cls("Cache"),
    cls("Feed", [(R, "cache", "LazilyInstantiated<Cache>")]),
    cls("Panel", [(R, "cache", "Cache"), (I, "rowBuilder", "Instantiator<Row>")]),
    cls("Row", [(RO, "cache", "LazilyInstantiated<Cache>?"), (R, "feed", "Feed")]),
))
probe("sendable-wrappers", one(
    root("Root", [(I, "client", "SendableLazilyInstantiated<Client>"), (I, "workerBuilder", "SendableInstantiator<Worker>"), (I, "monitor", "Monitor")], sendable=True),
    cls("Client", sendable=True),
    cls("Worker", [(R, "client", "Client"), (I, "jobBuilder", "SendableInstantiator<Job>")], sendable=True),
    cls("Job", [(R, "client", "SendableLazilyInstantiated<Client>"), (RO, "monitor", "Monitor?")], sendable=True),
    cls("Monitor", sendable=True),
))
probe("sendable-lazy-cycle", one(
    root("Root", [(I, "source", "Source"), (I, "aBuilder", "SendableInstantiator<Ping>")], sendable=True),
    cls("Source", sendable=True),
    cls("Ping", [(R, "source", "Source"), (I, "bBuilder", "SendableInstantiator<Pong>")], sendable=True),
    cls("Pong", [(I, "aBuilder", "SendableInstantiator<Ping>"), (ren("source", "Source"), "origin", "Source")], sendable=True),
))
probe("lazy-only-if-available-wrapper", one(
    root("Root", [(I, "logger", "LazilyInstantiated<Logger>"), (I, "leftBuilder", "Instantiator<LeftSide>"), (I, "rightBuilder", "Instantiator<RightSide>")]),
    cls("Logger"),
    cls("LeftSide", [(RO, "logger", "LazilyInstantiated<Logger>?"), (I, "probe", "LogProbe")]),
    cls("RightSide", [(R, "logger", "Logger"), (I, "probe", "LogProbe")]),
    cls("LogProbe", [(RO, "logger", "Logger?"), (RO, "tracer", "LazilyInstantiated<Logger>?")]),
))
probe("erased-constant-and-lazy", one(
    root("Root", [(I, "player", "LazilyInstantiated<Player>"), ('@Instantiated(fulfilledByType: "Song", erasedToConcreteExistential: true)', "track", "AnyTrack"), (I, "deckBuilder", "Instantiator<Deck>")]),
    "public protocol Track: AnyObject {}\npublic struct AnyTrack { public let base: any Track; public init(_ base: any Track) { self.base = base } }\n",
    cls("Player"),
    cls("Song", [(R, "player", "LazilyInstantiated<Player>")], conform=["Track"]),
    cls("Deck", [(R, "track", "AnyTrack"), (R, "player", "LazilyInstantiated<Player>")]),
))
# --- Seams with fills (two modules) ----------------------------------------------------------------------------
API = "public protocol Api: AnyObject {}\n"
probe("seam-fill-reads-seam-value", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Screen", [(I, "analytics", "Analytics"), (I, "profileBuilder", "Instantiator<ProfileView>")], attr="").lstrip("\n"),
    cls("Analytics"),
    cls("ProfileView", [(I, "api", "any Api"), (R, "analytics", "Analytics")]),
], [
    root("AppRoot", [(I, "screen", "Screen")]),
    cls("ApiImpl", [(R, "analytics", "Analytics")], attr="@Instantiable(fulfillingAdditionalTypes: [Api.self])", conform=["Api"]),
], feature_extra=API, app_fills=True))
probe("seam-fill-in-instantiator", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Inbox", [(R, "user", "User"), (I, "threadBuilder", "Instantiator<ThreadView>")], attr="").lstrip("\n"),
    cls("User"),
    cls("ThreadView", [(I, "api", "any Api"), (R, "user", "User")]),
], [
    root("AppRoot", [(I, "user", "User"), (I, "inbox", "Inbox"), (I, "session", "AppSession")]),
    cls("AppSession"),
    cls("ApiImpl", [(R, "user", "User"), (R, "session", "AppSession")], attr="@Instantiable(fulfillingAdditionalTypes: [Api.self])", conform=["Api"]),
], feature_extra=API, app_fills=True))
probe("seam-pass-throughs", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Settings", [(I, "list", "SettingsList")], attr="").lstrip("\n"),
    cls("Prefs"), cls("Flags"), cls("Locale2"),
    cls("SettingsList", [(R, "prefs", "Prefs"), (RO, "flags", "Flags?"), (RO, "locale", "Locale2?"), (R, "lazyPrefs", "LazilyInstantiated<Prefs>")]),
], [
    root("AppRoot", [(I, "prefs", "Prefs"), (I, "flags", "Flags"), (I, "lazyPrefs", "LazilyInstantiated<Prefs>"), (I, "settings", "Settings")]),
]))
probe("seam-cycle-with-fill", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Browser", [(I, "tag", "Tag"), (I, "pageBuilder", "Instantiator<Page>")], attr="").lstrip("\n"),
    cls("Tag"),
    cls("Page", [(I, "api", "any Api"), (I, "linkBuilder", "Instantiator<Link>"), (R, "tag", "Tag")]),
    cls("Link", [(I, "tag", "Tag"), (I, "pageBuilder", "Instantiator<Page>")]),
], [
    root("AppRoot", [(I, "browser", "Browser")]),
    cls("ApiImpl", [(R, "tag", "Tag")], attr="@Instantiable(fulfillingAdditionalTypes: [Api.self])", conform=["Api"]),
], feature_extra=API, app_fills=True))
probe("seam-optional-place", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Cart", [(IO, "promo", "(any Promo)?"), (IO, "tax", "(any Tax)?"), (I, "total", "Total")], attr="").lstrip("\n"),
    cls("Total", [(R, "promo", "(any Promo)?")]),
], [
    root("AppRoot", [(I, "cart", "Cart")]),
    cls("PromoImpl", attr="@Instantiable(fulfillingAdditionalTypes: [Promo.self])", conform=["Promo"]),
], feature_extra="public protocol Promo: AnyObject {}\npublic protocol Tax: AnyObject {}\n", app_fills=True))
probe("seam-passes-place-up", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Outer", [(I, "mark", "Mark"), (I, "innerBuilder", "Instantiator<Inner>")], attr="").lstrip("\n"),
    cls("Mark"),
    "@Instantiable(generateDependencyTree: true)\n" + cls("Inner", [(I, "api", "any Api"), (RO, "mark", "Mark?")], attr="").lstrip("\n"),
], [
    root("AppRoot", [(I, "outer", "Outer")]),
    cls("ApiImpl", [(RO, "mark", "Mark?")], attr="@Instantiable(fulfillingAdditionalTypes: [Api.self])", conform=["Api"]),
], feature_extra=API, app_fills=True))
probe("seam-lazy-place-and-received-wrapper", two([
    "@Instantiable(generateDependencyTree: true)\n" + cls("Gallery", [(I, "api", "LazilyInstantiated<any Api>"), (R, "store", "LazilyInstantiated<Store>"), (I, "gridBuilder", "Instantiator<Grid>")], attr="").lstrip("\n"),
    cls("Store"),
    cls("Grid", [(R, "store", "Store"), (R, "api", "any Api")]),
], [
    root("AppRoot", [(I, "store", "LazilyInstantiated<Store>"), (I, "gallery", "Gallery")]),
    cls("ApiImpl", [(R, "store", "Store")], attr="@Instantiable(fulfillingAdditionalTypes: [Api.self])", conform=["Api"]),
], feature_extra=API, app_fills=True))
# --- Two modules without seams ---------------------------------------------------------------------------------
probe("two-modules-plain", two([
    cls("Engine", [(R, "fuel", "Fuel")]), cls("Fuel"),
    cls("Wheel", [(RO, "fuel", "Fuel?"), (I, "bolt", "Bolt")]), cls("Bolt"),
], [
    root("AppRoot", [(I, "fuel", "Fuel"), (I, "engine", "Engine"), (I, "wheelBuilder", "Instantiator<Wheel>")]),
]))
probe("two-modules-rename-and-lazy", two([
    cls("Database"),
    cls("Repo", [(ren("database", "Database"), "storage", "Database"), (I, "query", "Query")]),
    cls("Query", [(R, "storage", "Database"), (R, "database", "LazilyInstantiated<Database>")]),
], [
    root("AppRoot", [(I, "database", "LazilyInstantiated<Database>"), (I, "repoBuilder", "Instantiator<Repo>")]),
]))
probe("two-modules-cycle", two([
    cls("Feed", [(I, "postBuilder", "Instantiator<Post>"), (R, "viewer", "Viewer")]),
    cls("Post", [(I, "feedBuilder", "Instantiator<Feed>"), (I, "viewer", "Viewer")]),
    cls("Viewer"),
], [
    root("AppRoot", [(I, "viewer", "Viewer"), (I, "feedBuilder", "Instantiator<Feed>"), (I, "local", "LocalReader")]),
    cls("LocalReader", [(R, "viewer", "Viewer")]),
]))
# --- Cycles node records lay out, or will (shapes of SafeDIToolNodeRecordsCycleTests) ----------------------------
probe("records-two-types-instantiate-each-other", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Alpha", [(I, "bBuilder", "Instantiator<Beta>")]),
    cls("Beta", [(I, "aBuilder", "Instantiator<Alpha>")]),
))
probe("records-value-declared-after-builder", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Alpha", [(I, "bBuilder", "Instantiator<Beta>"), (I, "model", "Model")]),
    cls("Beta", [(R, "model", "Model"), (I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Model"),
))
probe("records-cycle-closes-through-constant", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Alpha", [(I, "b", "Beta")]),
    cls("Beta", [(I, "aBuilder", "Instantiator<Alpha>")]),
))
probe("records-two-branches-close-on-one-place", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Alpha", [(I, "bBuilder", "Instantiator<Beta>"), (I, "cBuilder", "Instantiator<Gamma>")]),
    cls("Beta", [(I, "cBuilder", "Instantiator<Gamma>")]),
    cls("Gamma", [(I, "aBuilder", "Instantiator<Alpha>")]),
))
probe("records-member-closes-on-another-place", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Alpha", [(I, "bBuilder", "Instantiator<Beta>"), (I, "cBuilder", "Instantiator<Gamma>")]),
    cls("Beta", [(I, "cBuilder", "Instantiator<Gamma>")]),
    cls("Gamma", [(I, "bBuilder", "Instantiator<Beta>"), (I, "aBuilder", "Instantiator<Alpha>")]),
))
probe("records-type-receives-builder-of-cycle", one(
    root("Root", [(I, "screenBuilder", "Instantiator<Screen>")]),
    cls("Screen", [(I, "stepBuilder", "Instantiator<Step>"), (I, "detail", "Detail")]),
    cls("Detail", [(R, "screenBuilder", "Instantiator<Screen>")]),
    cls("Step", [(I, "screenBuilder", "Instantiator<Screen>")]),
))
probe("records-member-receives-only-if-available", one(
    root("Root", [(I, "session", "Session"), (I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Session"),
    cls("Alpha", [(I, "bBuilder", "Instantiator<Beta>")]),
    cls("Beta", [(RO, "session", "Session?"), (I, "aBuilder", "Instantiator<Alpha>")]),
))
probe("records-builder-name-shared-by-another-type", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>"), (I, "other", "Other")]),
    cls("Alpha", [(I, "bBuilder", "Instantiator<Beta>")]),
    cls("Beta", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Other", [(I, "aBuilder", "Instantiator<Leaf>")]),
    cls("Leaf"),
))
probe("records-builder-name-shared-by-two-cycles", one(
    root("Root", [(I, "left", "LeftHub"), (I, "right", "RightHub")]),
    cls("LeftHub", [(I, "aBuilder", "Instantiator<LeftA>")]),
    cls("LeftA", [(I, "bBuilder", "Instantiator<LeftB>")]),
    cls("LeftB", [(I, "aBuilder", "Instantiator<LeftA>")]),
    cls("RightHub", [(I, "aBuilder", "Instantiator<RightA>")]),
    cls("RightA", [(I, "bBuilder", "Instantiator<RightB>"), (I, "mark", "Mark")]),
    cls("RightB", [(I, "aBuilder", "Instantiator<RightA>"), (R, "mark", "Mark")]),
    cls("Mark"),
))
probe("records-sendable-closing", one(
    root("Root", [(I, "session", "Session"), (I, "aBuilder", "SendableInstantiator<Alpha>")], sendable=True),
    cls("Session", sendable=True),
    cls("Alpha", [(I, "bBuilder", "SendableInstantiator<Beta>")], sendable=True),
    cls("Beta", [(R, "session", "Session"), (I, "aBuilder", "SendableInstantiator<Alpha>")], sendable=True),
))
probe("records-sendable-closing-beneath-plain-builder", one(
    root("Root", [(I, "session", "Session"), (I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Session", sendable=True),
    cls("Alpha", [(I, "bBuilder", "SendableInstantiator<Beta>"), (I, "tag", "Tag")], sendable=True),
    cls("Tag", sendable=True),
    cls("Beta", [(R, "tag", "Tag"), (RO, "session", "Session?"), (I, "aBuilder", "SendableInstantiator<Alpha>")], sendable=True),
))
probe("records-sendable-closing-beside-shared-name", one(
    root("Root", [(I, "aBuilder", "SendableInstantiator<Alpha>"), (I, "other", "Other")]),
    cls("Alpha", [(I, "bBuilder", "SendableInstantiator<Beta>")], sendable=True),
    cls("Beta", [(I, "aBuilder", "SendableInstantiator<Alpha>")], sendable=True),
    cls("Other", [(I, "aBuilder", "Instantiator<Leaf>")]),
    cls("Leaf"),
))
probe("records-sendable-and-plain-closings", one(
    root("Root", [(I, "aBuilder", "Instantiator<Alpha>")]),
    cls("Alpha", [(I, "bBuilder", "SendableInstantiator<Beta>"), (I, "cBuilder", "Instantiator<Gamma>")]),
    cls("Beta", [(I, "token", "Token")], sendable=True),
    cls("Token", sendable=True),
    cls("Gamma", [(I, "aBuilder", "Instantiator<Alpha>"), (I, "bBuilder", "SendableInstantiator<Beta>")]),
))

if os.path.exists(OUT):
    shutil.rmtree(OUT)
for name, files in PROBES.items():
    os.makedirs(f"{OUT}/{name}")
    for fname, content in files.items():
        open(f"{OUT}/{name}/{fname}", "w").write(content)
print(len(PROBES), "probes")
print(":".join(f"{OUT}/{n}" for n in PROBES))
