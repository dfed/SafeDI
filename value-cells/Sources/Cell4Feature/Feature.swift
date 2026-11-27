// module: Cell4Feature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

public protocol Api: AnyObject {}
@Instantiable(generateDependencyTree: true)
public final class Home: Instantiable {
    public init(api: any Api) { self.api = api }
    @Instantiated let api: any Api
    let differentialValueCreationStamp = ProbeStamp.next()
}
