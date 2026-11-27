import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
    @Instantiated let screenBuilder: Instantiator<Screen>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Screen: Instantiable {
    public init(stepBuilder: Instantiator<Step>, detail: Detail) { self.stepBuilder = stepBuilder; self.detail = detail }
    @Instantiated let stepBuilder: Instantiator<Step>
    @Instantiated let detail: Detail
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Detail: Instantiable {
    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
    @Received let screenBuilder: Instantiator<Screen>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Step: Instantiable {
    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
    @Instantiated let screenBuilder: Instantiator<Screen>
    let differentialValueCreationStamp = ProbeStamp.next()
}
