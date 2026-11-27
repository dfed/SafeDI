// module: FuzzApp
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(fuel: Fuel, engine: Engine, wheelBuilder: Instantiator<Wheel>) { self.fuel = fuel; self.engine = engine; self.wheelBuilder = wheelBuilder }
    @Instantiated let fuel: Fuel
    @Instantiated let engine: Engine
    @Instantiated let wheelBuilder: Instantiator<Wheel>
    let differentialValueCreationStamp = ProbeStamp.next()
}
