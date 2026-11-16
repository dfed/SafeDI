import Feature
import Harness
import SafeDI

@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
public final class LiveApi: Instantiable, Api {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service])
        #endif
    }

    @Received public let id: Int
    @Received public let service: Service
    #if SPIKE_TRACE
    public let tracker = Tracker("LiveApi")
    #endif
}

#if SPIKE_TRACE
extension LiveApi: Traced {}
#endif

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(service: Service, home: Home) {
        self.service = service
        self.home = home
        #if SPIKE_TRACE
        Registry.created(self, ["service": service, "home": home])
        #endif
    }

    @Instantiated public let service: Service
    @Instantiated public let home: Home
    #if SPIKE_TRACE
    public let tracker = Tracker("Root")
    #endif
}

#if SPIKE_TRACE
extension Root: Traced {}
#endif

