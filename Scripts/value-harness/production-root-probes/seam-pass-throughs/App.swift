// module: FuzzApp
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(prefs: Prefs, flags: Flags, lazyPrefs: LazilyInstantiated<Prefs>, settings: Settings) { self.prefs = prefs; self.flags = flags; self.lazyPrefs = lazyPrefs; self.settings = settings }
    @Instantiated let prefs: Prefs
    @Instantiated let flags: Flags
    @Instantiated let lazyPrefs: LazilyInstantiated<Prefs>
    @Instantiated let settings: Settings
    let differentialValueCreationStamp = ProbeStamp.next()
}
