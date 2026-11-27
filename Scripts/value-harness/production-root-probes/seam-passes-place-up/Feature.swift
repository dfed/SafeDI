// module: FuzzFeature
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
public final class Outer: Instantiable {
    public init(mark: Mark, innerBuilder: Instantiator<Inner>) { self.mark = mark; self.innerBuilder = innerBuilder }
    @Instantiated let mark: Mark
    @Instantiated let innerBuilder: Instantiator<Inner>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Mark: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(generateDependencyTree: true)
public final class Inner: Instantiable {
    public init(api: any Api, mark: Mark?) { self.api = api; self.mark = mark }
    @Instantiated let api: any Api
    @Received(onlyIfAvailable: true) let mark: Mark?
    let differentialValueCreationStamp = ProbeStamp.next()
}
