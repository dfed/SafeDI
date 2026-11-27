import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(lit: LitPanel, dark: DarkPanel) { self.lit = lit; self.dark = dark }
    @Instantiated let lit: LitPanel
    @Instantiated let dark: DarkPanel
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Theme: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LitPanel: Instantiable {
    public init(theme: Theme, badge: ThemeBadge) { self.theme = theme; self.badge = badge }
    @Instantiated let theme: Theme
    @Instantiated let badge: ThemeBadge
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class DarkPanel: Instantiable {
    public init(badgeBuilder: Instantiator<ThemeBadge>) { self.badgeBuilder = badgeBuilder }
    @Instantiated let badgeBuilder: Instantiator<ThemeBadge>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class ThemeBadge: Instantiable {
    public init(theme: Theme?, accent: Accent?) { self.theme = theme; self.accent = accent }
    @Received(onlyIfAvailable: true) let theme: Theme?
    @Received(onlyIfAvailable: true) let accent: Accent?
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Accent: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
