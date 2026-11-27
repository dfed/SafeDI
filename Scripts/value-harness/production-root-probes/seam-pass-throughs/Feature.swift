// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

@Instantiable(generateDependencyTree: true)
public final class Settings: Instantiable {
    public init(list: SettingsList) { self.list = list }
    @Instantiated let list: SettingsList
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Prefs: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Flags: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Locale2: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class SettingsList: Instantiable {
    public init(prefs: Prefs, flags: Flags?, locale: Locale2?, lazyPrefs: LazilyInstantiated<Prefs>) { self.prefs = prefs; self.flags = flags; self.locale = locale; self.lazyPrefs = lazyPrefs }
    @Received let prefs: Prefs
    @Received(onlyIfAvailable: true) let flags: Flags?
    @Received(onlyIfAvailable: true) let locale: Locale2?
    @Received let lazyPrefs: LazilyInstantiated<Prefs>
    let differentialValueCreationStamp = ProbeStamp.next()
}
