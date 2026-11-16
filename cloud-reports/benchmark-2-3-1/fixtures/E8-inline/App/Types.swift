import Harness
import SafeDI

public protocol Api: AnyObject {}

@Instantiable
public final class Service: Instantiable {
    public init() {
        #if SPIKE_TRACE
        Registry.created(self, [:])
        #endif
    }

    #if SPIKE_TRACE
    public let tracker = Tracker("Service")
    #endif
}

#if SPIKE_TRACE
extension Service: Traced {}
#endif

@Instantiable
public final class Home: Instantiable {
    public init(screen0Builder: Instantiator<Screen0>, screen1Builder: Instantiator<Screen1>, screen2Builder: Instantiator<Screen2>, screen3Builder: Instantiator<Screen3>) {
        self.screen0Builder = screen0Builder
        self.screen1Builder = screen1Builder
        self.screen2Builder = screen2Builder
        self.screen3Builder = screen3Builder
        #if SPIKE_TRACE
        Registry.created(self, ["screen0Builder": screen0Builder, "screen1Builder": screen1Builder, "screen2Builder": screen2Builder, "screen3Builder": screen3Builder])
        #endif
    }

    @Instantiated public let screen0Builder: Instantiator<Screen0>
    @Instantiated public let screen1Builder: Instantiator<Screen1>
    @Instantiated public let screen2Builder: Instantiator<Screen2>
    @Instantiated public let screen3Builder: Instantiator<Screen3>
    #if SPIKE_TRACE
    public let tracker = Tracker("Home")
    #endif
}

#if SPIKE_TRACE
extension Home: Traced {}
#endif

@Instantiable
public final class Screen0: Instantiable {
    public init(id: Int, service: Service, model0: Model0, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>, screen7Builder: Instantiator<Screen7>) {
        self.id = id
        self.service = service
        self.model0 = model0
        self.screen5Builder = screen5Builder
        self.screen6Builder = screen6Builder
        self.screen7Builder = screen7Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model0": model0, "screen5Builder": screen5Builder, "screen6Builder": screen6Builder, "screen7Builder": screen7Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model0: Model0
    @Instantiated public let screen5Builder: Instantiator<Screen5>
    @Instantiated public let screen6Builder: Instantiator<Screen6>
    @Instantiated public let screen7Builder: Instantiator<Screen7>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen0")
    #endif
}

#if SPIKE_TRACE
extension Screen0: Traced {}
#endif

@Instantiable
public final class Model0: Instantiable {
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
    public let tracker = Tracker("Model0")
    #endif
}

#if SPIKE_TRACE
extension Model0: Traced {}
#endif

@Instantiable
public final class Screen1: Instantiable {
    public init(id: Int, service: Service, model1: Model1, screen4Builder: Instantiator<Screen4>, screen6Builder: Instantiator<Screen6>, screen7Builder: Instantiator<Screen7>) {
        self.id = id
        self.service = service
        self.model1 = model1
        self.screen4Builder = screen4Builder
        self.screen6Builder = screen6Builder
        self.screen7Builder = screen7Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model1": model1, "screen4Builder": screen4Builder, "screen6Builder": screen6Builder, "screen7Builder": screen7Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model1: Model1
    @Instantiated public let screen4Builder: Instantiator<Screen4>
    @Instantiated public let screen6Builder: Instantiator<Screen6>
    @Instantiated public let screen7Builder: Instantiator<Screen7>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen1")
    #endif
}

#if SPIKE_TRACE
extension Screen1: Traced {}
#endif

@Instantiable
public final class Model1: Instantiable {
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
    public let tracker = Tracker("Model1")
    #endif
}

#if SPIKE_TRACE
extension Model1: Traced {}
#endif

@Instantiable
public final class Screen2: Instantiable {
    public init(id: Int, service: Service, model2: Model2, screen4Builder: Instantiator<Screen4>, screen5Builder: Instantiator<Screen5>, screen7Builder: Instantiator<Screen7>) {
        self.id = id
        self.service = service
        self.model2 = model2
        self.screen4Builder = screen4Builder
        self.screen5Builder = screen5Builder
        self.screen7Builder = screen7Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model2": model2, "screen4Builder": screen4Builder, "screen5Builder": screen5Builder, "screen7Builder": screen7Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model2: Model2
    @Instantiated public let screen4Builder: Instantiator<Screen4>
    @Instantiated public let screen5Builder: Instantiator<Screen5>
    @Instantiated public let screen7Builder: Instantiator<Screen7>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen2")
    #endif
}

#if SPIKE_TRACE
extension Screen2: Traced {}
#endif

@Instantiable
public final class Model2: Instantiable {
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
    public let tracker = Tracker("Model2")
    #endif
}

#if SPIKE_TRACE
extension Model2: Traced {}
#endif

@Instantiable
public final class Screen3: Instantiable {
    public init(id: Int, service: Service, model3: Model3, screen4Builder: Instantiator<Screen4>, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>) {
        self.id = id
        self.service = service
        self.model3 = model3
        self.screen4Builder = screen4Builder
        self.screen5Builder = screen5Builder
        self.screen6Builder = screen6Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model3": model3, "screen4Builder": screen4Builder, "screen5Builder": screen5Builder, "screen6Builder": screen6Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model3: Model3
    @Instantiated public let screen4Builder: Instantiator<Screen4>
    @Instantiated public let screen5Builder: Instantiator<Screen5>
    @Instantiated public let screen6Builder: Instantiator<Screen6>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen3")
    #endif
}

#if SPIKE_TRACE
extension Screen3: Traced {}
#endif

@Instantiable
public final class Model3: Instantiable {
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
    public let tracker = Tracker("Model3")
    #endif
}

#if SPIKE_TRACE
extension Model3: Traced {}
#endif

@Instantiable
public final class Screen4: Instantiable {
    public init(id: Int, service: Service, model4: Model4) {
        self.id = id
        self.service = service
        self.model4 = model4
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model4": model4])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model4: Model4
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen4")
    #endif
}

#if SPIKE_TRACE
extension Screen4: Traced {}
#endif

@Instantiable
public final class Model4: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "api": api])
        #endif
    }

    @Received public let id: Int
    @Received public let service: Service
    @Instantiated public let api: any Api
    #if SPIKE_TRACE
    public let tracker = Tracker("Model4")
    #endif
}

#if SPIKE_TRACE
extension Model4: Traced {}
#endif

@Instantiable
public final class Screen5: Instantiable {
    public init(id: Int, service: Service, model5: Model5) {
        self.id = id
        self.service = service
        self.model5 = model5
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model5": model5])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model5: Model5
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen5")
    #endif
}

#if SPIKE_TRACE
extension Screen5: Traced {}
#endif

@Instantiable
public final class Model5: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "api": api])
        #endif
    }

    @Received public let id: Int
    @Received public let service: Service
    @Instantiated public let api: any Api
    #if SPIKE_TRACE
    public let tracker = Tracker("Model5")
    #endif
}

#if SPIKE_TRACE
extension Model5: Traced {}
#endif

@Instantiable
public final class Screen6: Instantiable {
    public init(id: Int, service: Service, model6: Model6) {
        self.id = id
        self.service = service
        self.model6 = model6
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model6": model6])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model6: Model6
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen6")
    #endif
}

#if SPIKE_TRACE
extension Screen6: Traced {}
#endif

@Instantiable
public final class Model6: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "api": api])
        #endif
    }

    @Received public let id: Int
    @Received public let service: Service
    @Instantiated public let api: any Api
    #if SPIKE_TRACE
    public let tracker = Tracker("Model6")
    #endif
}

#if SPIKE_TRACE
extension Model6: Traced {}
#endif

@Instantiable
public final class Screen7: Instantiable {
    public init(id: Int, service: Service, model7: Model7) {
        self.id = id
        self.service = service
        self.model7 = model7
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model7": model7])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model7: Model7
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen7")
    #endif
}

#if SPIKE_TRACE
extension Screen7: Traced {}
#endif

@Instantiable
public final class Model7: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "api": api])
        #endif
    }

    @Received public let id: Int
    @Received public let service: Service
    @Instantiated public let api: any Api
    #if SPIKE_TRACE
    public let tracker = Tracker("Model7")
    #endif
}

#if SPIKE_TRACE
extension Model7: Traced {}
#endif

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

