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
    public init(id: Int, service: Service, model4: Model4, screen9Builder: Instantiator<Screen9>, screen10Builder: Instantiator<Screen10>, screen11Builder: Instantiator<Screen11>) {
        self.id = id
        self.service = service
        self.model4 = model4
        self.screen9Builder = screen9Builder
        self.screen10Builder = screen10Builder
        self.screen11Builder = screen11Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model4": model4, "screen9Builder": screen9Builder, "screen10Builder": screen10Builder, "screen11Builder": screen11Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model4: Model4
    @Instantiated public let screen9Builder: Instantiator<Screen9>
    @Instantiated public let screen10Builder: Instantiator<Screen10>
    @Instantiated public let screen11Builder: Instantiator<Screen11>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen4")
    #endif
}

#if SPIKE_TRACE
extension Screen4: Traced {}
#endif

@Instantiable
public final class Model4: Instantiable {
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
    public let tracker = Tracker("Model4")
    #endif
}

#if SPIKE_TRACE
extension Model4: Traced {}
#endif

@Instantiable
public final class Screen5: Instantiable {
    public init(id: Int, service: Service, model5: Model5, screen8Builder: Instantiator<Screen8>, screen10Builder: Instantiator<Screen10>, screen11Builder: Instantiator<Screen11>) {
        self.id = id
        self.service = service
        self.model5 = model5
        self.screen8Builder = screen8Builder
        self.screen10Builder = screen10Builder
        self.screen11Builder = screen11Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model5": model5, "screen8Builder": screen8Builder, "screen10Builder": screen10Builder, "screen11Builder": screen11Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model5: Model5
    @Instantiated public let screen8Builder: Instantiator<Screen8>
    @Instantiated public let screen10Builder: Instantiator<Screen10>
    @Instantiated public let screen11Builder: Instantiator<Screen11>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen5")
    #endif
}

#if SPIKE_TRACE
extension Screen5: Traced {}
#endif

@Instantiable
public final class Model5: Instantiable {
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
    public let tracker = Tracker("Model5")
    #endif
}

#if SPIKE_TRACE
extension Model5: Traced {}
#endif

@Instantiable
public final class Screen6: Instantiable {
    public init(id: Int, service: Service, model6: Model6, screen8Builder: Instantiator<Screen8>, screen9Builder: Instantiator<Screen9>, screen11Builder: Instantiator<Screen11>) {
        self.id = id
        self.service = service
        self.model6 = model6
        self.screen8Builder = screen8Builder
        self.screen9Builder = screen9Builder
        self.screen11Builder = screen11Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model6": model6, "screen8Builder": screen8Builder, "screen9Builder": screen9Builder, "screen11Builder": screen11Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model6: Model6
    @Instantiated public let screen8Builder: Instantiator<Screen8>
    @Instantiated public let screen9Builder: Instantiator<Screen9>
    @Instantiated public let screen11Builder: Instantiator<Screen11>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen6")
    #endif
}

#if SPIKE_TRACE
extension Screen6: Traced {}
#endif

@Instantiable
public final class Model6: Instantiable {
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
    public let tracker = Tracker("Model6")
    #endif
}

#if SPIKE_TRACE
extension Model6: Traced {}
#endif

@Instantiable
public final class Screen7: Instantiable {
    public init(id: Int, service: Service, model7: Model7, screen8Builder: Instantiator<Screen8>, screen9Builder: Instantiator<Screen9>, screen10Builder: Instantiator<Screen10>) {
        self.id = id
        self.service = service
        self.model7 = model7
        self.screen8Builder = screen8Builder
        self.screen9Builder = screen9Builder
        self.screen10Builder = screen10Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model7": model7, "screen8Builder": screen8Builder, "screen9Builder": screen9Builder, "screen10Builder": screen10Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model7: Model7
    @Instantiated public let screen8Builder: Instantiator<Screen8>
    @Instantiated public let screen9Builder: Instantiator<Screen9>
    @Instantiated public let screen10Builder: Instantiator<Screen10>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen7")
    #endif
}

#if SPIKE_TRACE
extension Screen7: Traced {}
#endif

@Instantiable
public final class Model7: Instantiable {
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
    public let tracker = Tracker("Model7")
    #endif
}

#if SPIKE_TRACE
extension Model7: Traced {}
#endif

@Instantiable
public final class Screen8: Instantiable {
    public init(id: Int, service: Service, model8: Model8, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) {
        self.id = id
        self.service = service
        self.model8 = model8
        self.screen13Builder = screen13Builder
        self.screen14Builder = screen14Builder
        self.screen15Builder = screen15Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model8": model8, "screen13Builder": screen13Builder, "screen14Builder": screen14Builder, "screen15Builder": screen15Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model8: Model8
    @Instantiated public let screen13Builder: Instantiator<Screen13>
    @Instantiated public let screen14Builder: Instantiator<Screen14>
    @Instantiated public let screen15Builder: Instantiator<Screen15>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen8")
    #endif
}

#if SPIKE_TRACE
extension Screen8: Traced {}
#endif

@Instantiable
public final class Model8: Instantiable {
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
    public let tracker = Tracker("Model8")
    #endif
}

#if SPIKE_TRACE
extension Model8: Traced {}
#endif

@Instantiable
public final class Screen9: Instantiable {
    public init(id: Int, service: Service, model9: Model9, screen12Builder: Instantiator<Screen12>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) {
        self.id = id
        self.service = service
        self.model9 = model9
        self.screen12Builder = screen12Builder
        self.screen14Builder = screen14Builder
        self.screen15Builder = screen15Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model9": model9, "screen12Builder": screen12Builder, "screen14Builder": screen14Builder, "screen15Builder": screen15Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model9: Model9
    @Instantiated public let screen12Builder: Instantiator<Screen12>
    @Instantiated public let screen14Builder: Instantiator<Screen14>
    @Instantiated public let screen15Builder: Instantiator<Screen15>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen9")
    #endif
}

#if SPIKE_TRACE
extension Screen9: Traced {}
#endif

@Instantiable
public final class Model9: Instantiable {
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
    public let tracker = Tracker("Model9")
    #endif
}

#if SPIKE_TRACE
extension Model9: Traced {}
#endif

@Instantiable
public final class Screen10: Instantiable {
    public init(id: Int, service: Service, model10: Model10, screen12Builder: Instantiator<Screen12>, screen13Builder: Instantiator<Screen13>, screen15Builder: Instantiator<Screen15>) {
        self.id = id
        self.service = service
        self.model10 = model10
        self.screen12Builder = screen12Builder
        self.screen13Builder = screen13Builder
        self.screen15Builder = screen15Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model10": model10, "screen12Builder": screen12Builder, "screen13Builder": screen13Builder, "screen15Builder": screen15Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model10: Model10
    @Instantiated public let screen12Builder: Instantiator<Screen12>
    @Instantiated public let screen13Builder: Instantiator<Screen13>
    @Instantiated public let screen15Builder: Instantiator<Screen15>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen10")
    #endif
}

#if SPIKE_TRACE
extension Screen10: Traced {}
#endif

@Instantiable
public final class Model10: Instantiable {
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
    public let tracker = Tracker("Model10")
    #endif
}

#if SPIKE_TRACE
extension Model10: Traced {}
#endif

@Instantiable
public final class Screen11: Instantiable {
    public init(id: Int, service: Service, model11: Model11, screen12Builder: Instantiator<Screen12>, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>) {
        self.id = id
        self.service = service
        self.model11 = model11
        self.screen12Builder = screen12Builder
        self.screen13Builder = screen13Builder
        self.screen14Builder = screen14Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model11": model11, "screen12Builder": screen12Builder, "screen13Builder": screen13Builder, "screen14Builder": screen14Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model11: Model11
    @Instantiated public let screen12Builder: Instantiator<Screen12>
    @Instantiated public let screen13Builder: Instantiator<Screen13>
    @Instantiated public let screen14Builder: Instantiator<Screen14>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen11")
    #endif
}

#if SPIKE_TRACE
extension Screen11: Traced {}
#endif

@Instantiable
public final class Model11: Instantiable {
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
    public let tracker = Tracker("Model11")
    #endif
}

#if SPIKE_TRACE
extension Model11: Traced {}
#endif

@Instantiable
public final class Screen12: Instantiable {
    public init(id: Int, service: Service, model12: Model12, screen17Builder: Instantiator<Screen17>, screen18Builder: Instantiator<Screen18>, screen19Builder: Instantiator<Screen19>) {
        self.id = id
        self.service = service
        self.model12 = model12
        self.screen17Builder = screen17Builder
        self.screen18Builder = screen18Builder
        self.screen19Builder = screen19Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model12": model12, "screen17Builder": screen17Builder, "screen18Builder": screen18Builder, "screen19Builder": screen19Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model12: Model12
    @Instantiated public let screen17Builder: Instantiator<Screen17>
    @Instantiated public let screen18Builder: Instantiator<Screen18>
    @Instantiated public let screen19Builder: Instantiator<Screen19>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen12")
    #endif
}

#if SPIKE_TRACE
extension Screen12: Traced {}
#endif

@Instantiable
public final class Model12: Instantiable {
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
    public let tracker = Tracker("Model12")
    #endif
}

#if SPIKE_TRACE
extension Model12: Traced {}
#endif

@Instantiable
public final class Screen13: Instantiable {
    public init(id: Int, service: Service, model13: Model13, screen16Builder: Instantiator<Screen16>, screen18Builder: Instantiator<Screen18>, screen19Builder: Instantiator<Screen19>) {
        self.id = id
        self.service = service
        self.model13 = model13
        self.screen16Builder = screen16Builder
        self.screen18Builder = screen18Builder
        self.screen19Builder = screen19Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model13": model13, "screen16Builder": screen16Builder, "screen18Builder": screen18Builder, "screen19Builder": screen19Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model13: Model13
    @Instantiated public let screen16Builder: Instantiator<Screen16>
    @Instantiated public let screen18Builder: Instantiator<Screen18>
    @Instantiated public let screen19Builder: Instantiator<Screen19>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen13")
    #endif
}

#if SPIKE_TRACE
extension Screen13: Traced {}
#endif

@Instantiable
public final class Model13: Instantiable {
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
    public let tracker = Tracker("Model13")
    #endif
}

#if SPIKE_TRACE
extension Model13: Traced {}
#endif

@Instantiable
public final class Screen14: Instantiable {
    public init(id: Int, service: Service, model14: Model14, screen16Builder: Instantiator<Screen16>, screen17Builder: Instantiator<Screen17>, screen19Builder: Instantiator<Screen19>) {
        self.id = id
        self.service = service
        self.model14 = model14
        self.screen16Builder = screen16Builder
        self.screen17Builder = screen17Builder
        self.screen19Builder = screen19Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model14": model14, "screen16Builder": screen16Builder, "screen17Builder": screen17Builder, "screen19Builder": screen19Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model14: Model14
    @Instantiated public let screen16Builder: Instantiator<Screen16>
    @Instantiated public let screen17Builder: Instantiator<Screen17>
    @Instantiated public let screen19Builder: Instantiator<Screen19>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen14")
    #endif
}

#if SPIKE_TRACE
extension Screen14: Traced {}
#endif

@Instantiable
public final class Model14: Instantiable {
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
    public let tracker = Tracker("Model14")
    #endif
}

#if SPIKE_TRACE
extension Model14: Traced {}
#endif

@Instantiable
public final class Screen15: Instantiable {
    public init(id: Int, service: Service, model15: Model15, screen16Builder: Instantiator<Screen16>, screen17Builder: Instantiator<Screen17>, screen18Builder: Instantiator<Screen18>) {
        self.id = id
        self.service = service
        self.model15 = model15
        self.screen16Builder = screen16Builder
        self.screen17Builder = screen17Builder
        self.screen18Builder = screen18Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model15": model15, "screen16Builder": screen16Builder, "screen17Builder": screen17Builder, "screen18Builder": screen18Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model15: Model15
    @Instantiated public let screen16Builder: Instantiator<Screen16>
    @Instantiated public let screen17Builder: Instantiator<Screen17>
    @Instantiated public let screen18Builder: Instantiator<Screen18>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen15")
    #endif
}

#if SPIKE_TRACE
extension Screen15: Traced {}
#endif

@Instantiable
public final class Model15: Instantiable {
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
    public let tracker = Tracker("Model15")
    #endif
}

#if SPIKE_TRACE
extension Model15: Traced {}
#endif

@Instantiable
public final class Screen16: Instantiable {
    public init(id: Int, service: Service, model16: Model16, screen21Builder: Instantiator<Screen21>, screen22Builder: Instantiator<Screen22>, screen23Builder: Instantiator<Screen23>) {
        self.id = id
        self.service = service
        self.model16 = model16
        self.screen21Builder = screen21Builder
        self.screen22Builder = screen22Builder
        self.screen23Builder = screen23Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model16": model16, "screen21Builder": screen21Builder, "screen22Builder": screen22Builder, "screen23Builder": screen23Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model16: Model16
    @Instantiated public let screen21Builder: Instantiator<Screen21>
    @Instantiated public let screen22Builder: Instantiator<Screen22>
    @Instantiated public let screen23Builder: Instantiator<Screen23>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen16")
    #endif
}

#if SPIKE_TRACE
extension Screen16: Traced {}
#endif

@Instantiable
public final class Model16: Instantiable {
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
    public let tracker = Tracker("Model16")
    #endif
}

#if SPIKE_TRACE
extension Model16: Traced {}
#endif

@Instantiable
public final class Screen17: Instantiable {
    public init(id: Int, service: Service, model17: Model17, screen20Builder: Instantiator<Screen20>, screen22Builder: Instantiator<Screen22>, screen23Builder: Instantiator<Screen23>) {
        self.id = id
        self.service = service
        self.model17 = model17
        self.screen20Builder = screen20Builder
        self.screen22Builder = screen22Builder
        self.screen23Builder = screen23Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model17": model17, "screen20Builder": screen20Builder, "screen22Builder": screen22Builder, "screen23Builder": screen23Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model17: Model17
    @Instantiated public let screen20Builder: Instantiator<Screen20>
    @Instantiated public let screen22Builder: Instantiator<Screen22>
    @Instantiated public let screen23Builder: Instantiator<Screen23>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen17")
    #endif
}

#if SPIKE_TRACE
extension Screen17: Traced {}
#endif

@Instantiable
public final class Model17: Instantiable {
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
    public let tracker = Tracker("Model17")
    #endif
}

#if SPIKE_TRACE
extension Model17: Traced {}
#endif

@Instantiable
public final class Screen18: Instantiable {
    public init(id: Int, service: Service, model18: Model18, screen20Builder: Instantiator<Screen20>, screen21Builder: Instantiator<Screen21>, screen23Builder: Instantiator<Screen23>) {
        self.id = id
        self.service = service
        self.model18 = model18
        self.screen20Builder = screen20Builder
        self.screen21Builder = screen21Builder
        self.screen23Builder = screen23Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model18": model18, "screen20Builder": screen20Builder, "screen21Builder": screen21Builder, "screen23Builder": screen23Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model18: Model18
    @Instantiated public let screen20Builder: Instantiator<Screen20>
    @Instantiated public let screen21Builder: Instantiator<Screen21>
    @Instantiated public let screen23Builder: Instantiator<Screen23>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen18")
    #endif
}

#if SPIKE_TRACE
extension Screen18: Traced {}
#endif

@Instantiable
public final class Model18: Instantiable {
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
    public let tracker = Tracker("Model18")
    #endif
}

#if SPIKE_TRACE
extension Model18: Traced {}
#endif

@Instantiable
public final class Screen19: Instantiable {
    public init(id: Int, service: Service, model19: Model19, screen20Builder: Instantiator<Screen20>, screen21Builder: Instantiator<Screen21>, screen22Builder: Instantiator<Screen22>) {
        self.id = id
        self.service = service
        self.model19 = model19
        self.screen20Builder = screen20Builder
        self.screen21Builder = screen21Builder
        self.screen22Builder = screen22Builder
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model19": model19, "screen20Builder": screen20Builder, "screen21Builder": screen21Builder, "screen22Builder": screen22Builder])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model19: Model19
    @Instantiated public let screen20Builder: Instantiator<Screen20>
    @Instantiated public let screen21Builder: Instantiator<Screen21>
    @Instantiated public let screen22Builder: Instantiator<Screen22>
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen19")
    #endif
}

#if SPIKE_TRACE
extension Screen19: Traced {}
#endif

@Instantiable
public final class Model19: Instantiable {
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
    public let tracker = Tracker("Model19")
    #endif
}

#if SPIKE_TRACE
extension Model19: Traced {}
#endif

@Instantiable
public final class Screen20: Instantiable {
    public init(id: Int, service: Service, model20: Model20) {
        self.id = id
        self.service = service
        self.model20 = model20
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model20": model20])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model20: Model20
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen20")
    #endif
}

#if SPIKE_TRACE
extension Screen20: Traced {}
#endif

@Instantiable
public final class Model20: Instantiable {
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
    public let tracker = Tracker("Model20")
    #endif
}

#if SPIKE_TRACE
extension Model20: Traced {}
#endif

@Instantiable
public final class Screen21: Instantiable {
    public init(id: Int, service: Service, model21: Model21) {
        self.id = id
        self.service = service
        self.model21 = model21
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model21": model21])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model21: Model21
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen21")
    #endif
}

#if SPIKE_TRACE
extension Screen21: Traced {}
#endif

@Instantiable
public final class Model21: Instantiable {
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
    public let tracker = Tracker("Model21")
    #endif
}

#if SPIKE_TRACE
extension Model21: Traced {}
#endif

@Instantiable
public final class Screen22: Instantiable {
    public init(id: Int, service: Service, model22: Model22) {
        self.id = id
        self.service = service
        self.model22 = model22
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model22": model22])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model22: Model22
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen22")
    #endif
}

#if SPIKE_TRACE
extension Screen22: Traced {}
#endif

@Instantiable
public final class Model22: Instantiable {
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
    public let tracker = Tracker("Model22")
    #endif
}

#if SPIKE_TRACE
extension Model22: Traced {}
#endif

@Instantiable
public final class Screen23: Instantiable {
    public init(id: Int, service: Service, model23: Model23) {
        self.id = id
        self.service = service
        self.model23 = model23
        #if SPIKE_TRACE
        Registry.created(self, ["id": id, "service": service, "model23": model23])
        #endif
    }

    @Forwarded public let id: Int
    @Received public let service: Service
    @Instantiated public let model23: Model23
    #if SPIKE_TRACE
    public let tracker = Tracker("Screen23")
    #endif
}

#if SPIKE_TRACE
extension Screen23: Traced {}
#endif

@Instantiable
public final class Model23: Instantiable {
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
    public let tracker = Tracker("Model23")
    #endif
}

#if SPIKE_TRACE
extension Model23: Traced {}
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

