import SafeDI
import Lib

/// Holds `Feature`, whose public mock is called from this module's mock, so a configuration here nests `Feature`'s `SafeDIOverrides`.
@Instantiable(generateMock: true) final class Screen: Instantiable {
    init(service: Service, feature: Feature) { self.service = service; self.feature = feature }
    @Instantiated let service: Service
    @Instantiated let feature: Feature
}

@Instantiable(generateMock: true) final class Shell: Instantiable {
    init(screen: Screen) { self.screen = screen }
    @Instantiated let screen: Screen
}

func probeUse() {
    _ = Feature.mock(service: Service(), safeDIOverrides: .init(leaf: .init(count: 4), pane: .init(leaf2: .init(name: "x"))))
    _ = Shell.mock(safeDIOverrides: .init(screen: .init(feature: .init(leaf: .init(count: 5)))))
}

// Sendable inference: a configuration a `SendableInstantiator` reaches is `@Sendable`-typed, so it is `Sendable` with `let`
// fields. These must stay `Sendable` with the configurations nested in them stored behind one reference.
@Instantiable(generateMock: true) final class Hub: Instantiable, Sendable {
    init(cardBuilder: SendableInstantiator<Card>) { self.cardBuilder = cardBuilder }
    @Instantiated let cardBuilder: SendableInstantiator<Card>
}

@Instantiable final class Card: Instantiable, Sendable {
    init(badge: Badge) { self.badge = badge }
    @Instantiated let badge: Badge
}

@Instantiable final class Badge: Instantiable, Sendable {
    init(text: String = "badge") { self.text = text }
    let text: String
}

func requireSendable<T: Sendable>(_: T.Type) {}
func sendableProbe() {
    requireSendable(Card.SafeDIMockConfiguration.self)
    requireSendable(Hub.SafeDIOverrides.self)
}

/// What storage changes that code outside the generated initializers can observe.
func observableProbe() -> [String] {
    var lines = [String]()
    lines.append("MemoryLayout<Shell.SafeDIOverrides>.size \(MemoryLayout<Shell.SafeDIOverrides>.size)")
    lines.append("MemoryLayout<Screen.SafeDIMockConfiguration>.size \(MemoryLayout<Screen.SafeDIMockConfiguration>.size)")
    lines.append("MemoryLayout<Hub.SafeDIOverrides>.size \(MemoryLayout<Hub.SafeDIOverrides>.size)")
    lines.append("MemoryLayout<Card.SafeDIMockConfiguration>.size \(MemoryLayout<Card.SafeDIMockConfiguration>.size)")
    lines.append("MemoryLayout<Feature.SafeDIOverrides>.size \(MemoryLayout<Feature.SafeDIOverrides>.size)")
    let keyPath: AnyKeyPath = \Shell.SafeDIOverrides.screen
    lines.append("screen key path is WritableKeyPath: \(keyPath is WritableKeyPath<Shell.SafeDIOverrides, Screen.SafeDIMockConfiguration>)")
    let featureKeyPath: AnyKeyPath = \Feature.SafeDIOverrides.leaf
    lines.append("public leaf key path is WritableKeyPath: \(featureKeyPath is WritableKeyPath<Feature.SafeDIOverrides, __safeDI_Lib_Leaf_MockConfiguration>)")
    lines.append("Mirror(Shell.SafeDIOverrides) labels: \(Mirror(reflecting: Shell.SafeDIOverrides()).children.map { $0.label ?? "_" })")
    lines.append("Mirror(Screen.SafeDIMockConfiguration) labels: \(Mirror(reflecting: Screen.SafeDIMockConfiguration()).children.map { $0.label ?? "_" })")
    lines.append("Mirror(Feature.SafeDIOverrides) labels: \(Mirror(reflecting: Feature.SafeDIOverrides()).children.map { $0.label ?? "_" })")
    lines.append("nested read: \(Shell.SafeDIOverrides(screen: .init(feature: .init(leaf: .init(count: 7)))).screen.feature.leaf.count.map { "\($0)" } ?? "nil")")
    return lines
}

@main enum ProbeMain {
    static func main() {
        probeUse()
        sendableProbe()
        print(observableProbe().joined(separator: "\n"))
    }
}
