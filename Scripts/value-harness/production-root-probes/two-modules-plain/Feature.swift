// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

@Instantiable
public final class Engine: Instantiable {
    public init(fuel: Fuel) { self.fuel = fuel }
    @Received let fuel: Fuel
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Fuel: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Wheel: Instantiable {
    public init(fuel: Fuel?, bolt: Bolt) { self.fuel = fuel; self.bolt = bolt }
    @Received(onlyIfAvailable: true) let fuel: Fuel?
    @Instantiated let bolt: Bolt
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Bolt: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
