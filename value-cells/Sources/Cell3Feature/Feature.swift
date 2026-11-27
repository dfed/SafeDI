// module: Cell3Feature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

public protocol Api: AnyObject, Sendable {}
@Instantiable(generateDependencyTree: true)
public final class Home: Instantiable, Sendable {
    public init(panelBuilder: SendableInstantiator<Panel>) { self.panelBuilder = panelBuilder }
    @Instantiated let panelBuilder: SendableInstantiator<Panel>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Panel: Instantiable, Sendable {
    public init(api: any Api) { self.api = api }
    @Instantiated let api: any Api
    let differentialValueCreationStamp = ProbeStamp.next()
}
