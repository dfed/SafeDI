import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(logger: LazilyInstantiated<Logger>, leftBuilder: Instantiator<LeftSide>, rightBuilder: Instantiator<RightSide>) { self.logger = logger; self.leftBuilder = leftBuilder; self.rightBuilder = rightBuilder }
    @Instantiated let logger: LazilyInstantiated<Logger>
    @Instantiated let leftBuilder: Instantiator<LeftSide>
    @Instantiated let rightBuilder: Instantiator<RightSide>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Logger: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LeftSide: Instantiable {
    public init(logger: LazilyInstantiated<Logger>?, probe: LogProbe) { self.logger = logger; self.probe = probe }
    @Received(onlyIfAvailable: true) let logger: LazilyInstantiated<Logger>?
    @Instantiated let probe: LogProbe
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class RightSide: Instantiable {
    public init(logger: Logger, probe: LogProbe) { self.logger = logger; self.probe = probe }
    @Received let logger: Logger
    @Instantiated let probe: LogProbe
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LogProbe: Instantiable {
    public init(logger: Logger?, tracer: LazilyInstantiated<Logger>?) { self.logger = logger; self.tracer = tracer }
    @Received(onlyIfAvailable: true) let logger: Logger?
    @Received(onlyIfAvailable: true) let tracer: LazilyInstantiated<Logger>?
    let differentialValueCreationStamp = ProbeStamp.next()
}
