import SafeDI

@Instantiable public final class Service: Instantiable { public init() {} }
public protocol Api {}

@Instantiable(generateMock: true)
public final class Screen0: Instantiable {
    public init(id: Int, service: Service, model0: Model0, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>, screen7Builder: Instantiator<Screen7>) {
        self.id = id
        self.service = service
        self.model0 = model0
        self.screen5Builder = screen5Builder
        self.screen6Builder = screen6Builder
        self.screen7Builder = screen7Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model0: Model0
    @Instantiated let screen5Builder: Instantiator<Screen5>
    @Instantiated let screen6Builder: Instantiator<Screen6>
    @Instantiated let screen7Builder: Instantiator<Screen7>
}

@Instantiable
public final class Model0: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen1: Instantiable {
    public init(id: Int, service: Service, model1: Model1, screen4Builder: Instantiator<Screen4>, screen6Builder: Instantiator<Screen6>, screen7Builder: Instantiator<Screen7>) {
        self.id = id
        self.service = service
        self.model1 = model1
        self.screen4Builder = screen4Builder
        self.screen6Builder = screen6Builder
        self.screen7Builder = screen7Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model1: Model1
    @Instantiated let screen4Builder: Instantiator<Screen4>
    @Instantiated let screen6Builder: Instantiator<Screen6>
    @Instantiated let screen7Builder: Instantiator<Screen7>
}

@Instantiable
public final class Model1: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen2: Instantiable {
    public init(id: Int, service: Service, model2: Model2, screen4Builder: Instantiator<Screen4>, screen5Builder: Instantiator<Screen5>, screen7Builder: Instantiator<Screen7>) {
        self.id = id
        self.service = service
        self.model2 = model2
        self.screen4Builder = screen4Builder
        self.screen5Builder = screen5Builder
        self.screen7Builder = screen7Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model2: Model2
    @Instantiated let screen4Builder: Instantiator<Screen4>
    @Instantiated let screen5Builder: Instantiator<Screen5>
    @Instantiated let screen7Builder: Instantiator<Screen7>
}

@Instantiable
public final class Model2: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen3: Instantiable {
    public init(id: Int, service: Service, model3: Model3, screen4Builder: Instantiator<Screen4>, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>) {
        self.id = id
        self.service = service
        self.model3 = model3
        self.screen4Builder = screen4Builder
        self.screen5Builder = screen5Builder
        self.screen6Builder = screen6Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model3: Model3
    @Instantiated let screen4Builder: Instantiator<Screen4>
    @Instantiated let screen5Builder: Instantiator<Screen5>
    @Instantiated let screen6Builder: Instantiator<Screen6>
}

@Instantiable
public final class Model3: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen4: Instantiable {
    public init(id: Int, service: Service, model4: Model4, screen9Builder: Instantiator<Screen9>, screen10Builder: Instantiator<Screen10>, screen11Builder: Instantiator<Screen11>) {
        self.id = id
        self.service = service
        self.model4 = model4
        self.screen9Builder = screen9Builder
        self.screen10Builder = screen10Builder
        self.screen11Builder = screen11Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model4: Model4
    @Instantiated let screen9Builder: Instantiator<Screen9>
    @Instantiated let screen10Builder: Instantiator<Screen10>
    @Instantiated let screen11Builder: Instantiator<Screen11>
}

@Instantiable
public final class Model4: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen5: Instantiable {
    public init(id: Int, service: Service, model5: Model5, screen8Builder: Instantiator<Screen8>, screen10Builder: Instantiator<Screen10>, screen11Builder: Instantiator<Screen11>) {
        self.id = id
        self.service = service
        self.model5 = model5
        self.screen8Builder = screen8Builder
        self.screen10Builder = screen10Builder
        self.screen11Builder = screen11Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model5: Model5
    @Instantiated let screen8Builder: Instantiator<Screen8>
    @Instantiated let screen10Builder: Instantiator<Screen10>
    @Instantiated let screen11Builder: Instantiator<Screen11>
}

@Instantiable
public final class Model5: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen6: Instantiable {
    public init(id: Int, service: Service, model6: Model6, screen8Builder: Instantiator<Screen8>, screen9Builder: Instantiator<Screen9>, screen11Builder: Instantiator<Screen11>) {
        self.id = id
        self.service = service
        self.model6 = model6
        self.screen8Builder = screen8Builder
        self.screen9Builder = screen9Builder
        self.screen11Builder = screen11Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model6: Model6
    @Instantiated let screen8Builder: Instantiator<Screen8>
    @Instantiated let screen9Builder: Instantiator<Screen9>
    @Instantiated let screen11Builder: Instantiator<Screen11>
}

@Instantiable
public final class Model6: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen7: Instantiable {
    public init(id: Int, service: Service, model7: Model7, screen8Builder: Instantiator<Screen8>, screen9Builder: Instantiator<Screen9>, screen10Builder: Instantiator<Screen10>) {
        self.id = id
        self.service = service
        self.model7 = model7
        self.screen8Builder = screen8Builder
        self.screen9Builder = screen9Builder
        self.screen10Builder = screen10Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model7: Model7
    @Instantiated let screen8Builder: Instantiator<Screen8>
    @Instantiated let screen9Builder: Instantiator<Screen9>
    @Instantiated let screen10Builder: Instantiator<Screen10>
}

@Instantiable
public final class Model7: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen8: Instantiable {
    public init(id: Int, service: Service, model8: Model8, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) {
        self.id = id
        self.service = service
        self.model8 = model8
        self.screen13Builder = screen13Builder
        self.screen14Builder = screen14Builder
        self.screen15Builder = screen15Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model8: Model8
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen14Builder: Instantiator<Screen14>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}

@Instantiable
public final class Model8: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen9: Instantiable {
    public init(id: Int, service: Service, model9: Model9, screen12Builder: Instantiator<Screen12>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) {
        self.id = id
        self.service = service
        self.model9 = model9
        self.screen12Builder = screen12Builder
        self.screen14Builder = screen14Builder
        self.screen15Builder = screen15Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model9: Model9
    @Instantiated let screen12Builder: Instantiator<Screen12>
    @Instantiated let screen14Builder: Instantiator<Screen14>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}

@Instantiable
public final class Model9: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen10: Instantiable {
    public init(id: Int, service: Service, model10: Model10, screen12Builder: Instantiator<Screen12>, screen13Builder: Instantiator<Screen13>, screen15Builder: Instantiator<Screen15>) {
        self.id = id
        self.service = service
        self.model10 = model10
        self.screen12Builder = screen12Builder
        self.screen13Builder = screen13Builder
        self.screen15Builder = screen15Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model10: Model10
    @Instantiated let screen12Builder: Instantiator<Screen12>
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}

@Instantiable
public final class Model10: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen11: Instantiable {
    public init(id: Int, service: Service, model11: Model11, screen12Builder: Instantiator<Screen12>, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>) {
        self.id = id
        self.service = service
        self.model11 = model11
        self.screen12Builder = screen12Builder
        self.screen13Builder = screen13Builder
        self.screen14Builder = screen14Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model11: Model11
    @Instantiated let screen12Builder: Instantiator<Screen12>
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen14Builder: Instantiator<Screen14>
}

@Instantiable
public final class Model11: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen12: Instantiable {
    public init(id: Int, service: Service, model12: Model12, screen17Builder: Instantiator<Screen17>, screen18Builder: Instantiator<Screen18>, screen19Builder: Instantiator<Screen19>) {
        self.id = id
        self.service = service
        self.model12 = model12
        self.screen17Builder = screen17Builder
        self.screen18Builder = screen18Builder
        self.screen19Builder = screen19Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model12: Model12
    @Instantiated let screen17Builder: Instantiator<Screen17>
    @Instantiated let screen18Builder: Instantiator<Screen18>
    @Instantiated let screen19Builder: Instantiator<Screen19>
}

@Instantiable
public final class Model12: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen13: Instantiable {
    public init(id: Int, service: Service, model13: Model13, screen16Builder: Instantiator<Screen16>, screen18Builder: Instantiator<Screen18>, screen19Builder: Instantiator<Screen19>) {
        self.id = id
        self.service = service
        self.model13 = model13
        self.screen16Builder = screen16Builder
        self.screen18Builder = screen18Builder
        self.screen19Builder = screen19Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model13: Model13
    @Instantiated let screen16Builder: Instantiator<Screen16>
    @Instantiated let screen18Builder: Instantiator<Screen18>
    @Instantiated let screen19Builder: Instantiator<Screen19>
}

@Instantiable
public final class Model13: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen14: Instantiable {
    public init(id: Int, service: Service, model14: Model14, screen16Builder: Instantiator<Screen16>, screen17Builder: Instantiator<Screen17>, screen19Builder: Instantiator<Screen19>) {
        self.id = id
        self.service = service
        self.model14 = model14
        self.screen16Builder = screen16Builder
        self.screen17Builder = screen17Builder
        self.screen19Builder = screen19Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model14: Model14
    @Instantiated let screen16Builder: Instantiator<Screen16>
    @Instantiated let screen17Builder: Instantiator<Screen17>
    @Instantiated let screen19Builder: Instantiator<Screen19>
}

@Instantiable
public final class Model14: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen15: Instantiable {
    public init(id: Int, service: Service, model15: Model15, screen16Builder: Instantiator<Screen16>, screen17Builder: Instantiator<Screen17>, screen18Builder: Instantiator<Screen18>) {
        self.id = id
        self.service = service
        self.model15 = model15
        self.screen16Builder = screen16Builder
        self.screen17Builder = screen17Builder
        self.screen18Builder = screen18Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model15: Model15
    @Instantiated let screen16Builder: Instantiator<Screen16>
    @Instantiated let screen17Builder: Instantiator<Screen17>
    @Instantiated let screen18Builder: Instantiator<Screen18>
}

@Instantiable
public final class Model15: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen16: Instantiable {
    public init(id: Int, service: Service, model16: Model16, screen21Builder: Instantiator<Screen21>, screen22Builder: Instantiator<Screen22>, screen23Builder: Instantiator<Screen23>) {
        self.id = id
        self.service = service
        self.model16 = model16
        self.screen21Builder = screen21Builder
        self.screen22Builder = screen22Builder
        self.screen23Builder = screen23Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model16: Model16
    @Instantiated let screen21Builder: Instantiator<Screen21>
    @Instantiated let screen22Builder: Instantiator<Screen22>
    @Instantiated let screen23Builder: Instantiator<Screen23>
}

@Instantiable
public final class Model16: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen17: Instantiable {
    public init(id: Int, service: Service, model17: Model17, screen20Builder: Instantiator<Screen20>, screen22Builder: Instantiator<Screen22>, screen23Builder: Instantiator<Screen23>) {
        self.id = id
        self.service = service
        self.model17 = model17
        self.screen20Builder = screen20Builder
        self.screen22Builder = screen22Builder
        self.screen23Builder = screen23Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model17: Model17
    @Instantiated let screen20Builder: Instantiator<Screen20>
    @Instantiated let screen22Builder: Instantiator<Screen22>
    @Instantiated let screen23Builder: Instantiator<Screen23>
}

@Instantiable
public final class Model17: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen18: Instantiable {
    public init(id: Int, service: Service, model18: Model18, screen20Builder: Instantiator<Screen20>, screen21Builder: Instantiator<Screen21>, screen23Builder: Instantiator<Screen23>) {
        self.id = id
        self.service = service
        self.model18 = model18
        self.screen20Builder = screen20Builder
        self.screen21Builder = screen21Builder
        self.screen23Builder = screen23Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model18: Model18
    @Instantiated let screen20Builder: Instantiator<Screen20>
    @Instantiated let screen21Builder: Instantiator<Screen21>
    @Instantiated let screen23Builder: Instantiator<Screen23>
}

@Instantiable
public final class Model18: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen19: Instantiable {
    public init(id: Int, service: Service, model19: Model19, screen20Builder: Instantiator<Screen20>, screen21Builder: Instantiator<Screen21>, screen22Builder: Instantiator<Screen22>) {
        self.id = id
        self.service = service
        self.model19 = model19
        self.screen20Builder = screen20Builder
        self.screen21Builder = screen21Builder
        self.screen22Builder = screen22Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model19: Model19
    @Instantiated let screen20Builder: Instantiator<Screen20>
    @Instantiated let screen21Builder: Instantiator<Screen21>
    @Instantiated let screen22Builder: Instantiator<Screen22>
}

@Instantiable
public final class Model19: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen20: Instantiable {
    public init(id: Int, service: Service, model20: Model20, screen25Builder: Instantiator<Screen25>, screen26Builder: Instantiator<Screen26>, screen27Builder: Instantiator<Screen27>) {
        self.id = id
        self.service = service
        self.model20 = model20
        self.screen25Builder = screen25Builder
        self.screen26Builder = screen26Builder
        self.screen27Builder = screen27Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model20: Model20
    @Instantiated let screen25Builder: Instantiator<Screen25>
    @Instantiated let screen26Builder: Instantiator<Screen26>
    @Instantiated let screen27Builder: Instantiator<Screen27>
}

@Instantiable
public final class Model20: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen21: Instantiable {
    public init(id: Int, service: Service, model21: Model21, screen24Builder: Instantiator<Screen24>, screen26Builder: Instantiator<Screen26>, screen27Builder: Instantiator<Screen27>) {
        self.id = id
        self.service = service
        self.model21 = model21
        self.screen24Builder = screen24Builder
        self.screen26Builder = screen26Builder
        self.screen27Builder = screen27Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model21: Model21
    @Instantiated let screen24Builder: Instantiator<Screen24>
    @Instantiated let screen26Builder: Instantiator<Screen26>
    @Instantiated let screen27Builder: Instantiator<Screen27>
}

@Instantiable
public final class Model21: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen22: Instantiable {
    public init(id: Int, service: Service, model22: Model22, screen24Builder: Instantiator<Screen24>, screen25Builder: Instantiator<Screen25>, screen27Builder: Instantiator<Screen27>) {
        self.id = id
        self.service = service
        self.model22 = model22
        self.screen24Builder = screen24Builder
        self.screen25Builder = screen25Builder
        self.screen27Builder = screen27Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model22: Model22
    @Instantiated let screen24Builder: Instantiator<Screen24>
    @Instantiated let screen25Builder: Instantiator<Screen25>
    @Instantiated let screen27Builder: Instantiator<Screen27>
}

@Instantiable
public final class Model22: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen23: Instantiable {
    public init(id: Int, service: Service, model23: Model23, screen24Builder: Instantiator<Screen24>, screen25Builder: Instantiator<Screen25>, screen26Builder: Instantiator<Screen26>) {
        self.id = id
        self.service = service
        self.model23 = model23
        self.screen24Builder = screen24Builder
        self.screen25Builder = screen25Builder
        self.screen26Builder = screen26Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model23: Model23
    @Instantiated let screen24Builder: Instantiator<Screen24>
    @Instantiated let screen25Builder: Instantiator<Screen25>
    @Instantiated let screen26Builder: Instantiator<Screen26>
}

@Instantiable
public final class Model23: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen24: Instantiable {
    public init(id: Int, service: Service, model24: Model24, screen29Builder: Instantiator<Screen29>, screen30Builder: Instantiator<Screen30>, screen31Builder: Instantiator<Screen31>) {
        self.id = id
        self.service = service
        self.model24 = model24
        self.screen29Builder = screen29Builder
        self.screen30Builder = screen30Builder
        self.screen31Builder = screen31Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model24: Model24
    @Instantiated let screen29Builder: Instantiator<Screen29>
    @Instantiated let screen30Builder: Instantiator<Screen30>
    @Instantiated let screen31Builder: Instantiator<Screen31>
}

@Instantiable
public final class Model24: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen25: Instantiable {
    public init(id: Int, service: Service, model25: Model25, screen28Builder: Instantiator<Screen28>, screen30Builder: Instantiator<Screen30>, screen31Builder: Instantiator<Screen31>) {
        self.id = id
        self.service = service
        self.model25 = model25
        self.screen28Builder = screen28Builder
        self.screen30Builder = screen30Builder
        self.screen31Builder = screen31Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model25: Model25
    @Instantiated let screen28Builder: Instantiator<Screen28>
    @Instantiated let screen30Builder: Instantiator<Screen30>
    @Instantiated let screen31Builder: Instantiator<Screen31>
}

@Instantiable
public final class Model25: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen26: Instantiable {
    public init(id: Int, service: Service, model26: Model26, screen28Builder: Instantiator<Screen28>, screen29Builder: Instantiator<Screen29>, screen31Builder: Instantiator<Screen31>) {
        self.id = id
        self.service = service
        self.model26 = model26
        self.screen28Builder = screen28Builder
        self.screen29Builder = screen29Builder
        self.screen31Builder = screen31Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model26: Model26
    @Instantiated let screen28Builder: Instantiator<Screen28>
    @Instantiated let screen29Builder: Instantiator<Screen29>
    @Instantiated let screen31Builder: Instantiator<Screen31>
}

@Instantiable
public final class Model26: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen27: Instantiable {
    public init(id: Int, service: Service, model27: Model27, screen28Builder: Instantiator<Screen28>, screen29Builder: Instantiator<Screen29>, screen30Builder: Instantiator<Screen30>) {
        self.id = id
        self.service = service
        self.model27 = model27
        self.screen28Builder = screen28Builder
        self.screen29Builder = screen29Builder
        self.screen30Builder = screen30Builder
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model27: Model27
    @Instantiated let screen28Builder: Instantiator<Screen28>
    @Instantiated let screen29Builder: Instantiator<Screen29>
    @Instantiated let screen30Builder: Instantiator<Screen30>
}

@Instantiable
public final class Model27: Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(generateMock: true)
public final class Screen28: Instantiable {
    public init(id: Int, service: Service, model28: Model28) {
        self.id = id
        self.service = service
        self.model28 = model28
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model28: Model28
}

@Instantiable
public final class Model28: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
    }

    @Received let id: Int
    @Received let service: Service
    @Instantiated let api: any Api
}

@Instantiable(generateMock: true)
public final class Screen29: Instantiable {
    public init(id: Int, service: Service, model29: Model29) {
        self.id = id
        self.service = service
        self.model29 = model29
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model29: Model29
}

@Instantiable
public final class Model29: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
    }

    @Received let id: Int
    @Received let service: Service
    @Instantiated let api: any Api
}

@Instantiable(generateMock: true)
public final class Screen30: Instantiable {
    public init(id: Int, service: Service, model30: Model30) {
        self.id = id
        self.service = service
        self.model30 = model30
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model30: Model30
}

@Instantiable
public final class Model30: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
    }

    @Received let id: Int
    @Received let service: Service
    @Instantiated let api: any Api
}

@Instantiable(generateMock: true)
public final class Screen31: Instantiable {
    public init(id: Int, service: Service, model31: Model31) {
        self.id = id
        self.service = service
        self.model31 = model31
    }

    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model31: Model31
}

@Instantiable
public final class Model31: Instantiable {
    public init(id: Int, service: Service, api: any Api) {
        self.id = id
        self.service = service
        self.api = api
    }

    @Received let id: Int
    @Received let service: Service
    @Instantiated let api: any Api
}

@Instantiable(generateMock: true)
public final class Home: Instantiable {
    public init(screen0Builder: Instantiator<Screen0>, screen1Builder: Instantiator<Screen1>, screen2Builder: Instantiator<Screen2>, screen3Builder: Instantiator<Screen3>) {
        self.screen0Builder = screen0Builder
        self.screen1Builder = screen1Builder
        self.screen2Builder = screen2Builder
        self.screen3Builder = screen3Builder
    }

    @Instantiated let screen0Builder: Instantiator<Screen0>
    @Instantiated let screen1Builder: Instantiator<Screen1>
    @Instantiated let screen2Builder: Instantiator<Screen2>
    @Instantiated let screen3Builder: Instantiator<Screen3>
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class LiveApi: Api, Instantiable {
    public init(id: Int, service: Service) {
        self.id = id
        self.service = service
    }

    @Received let id: Int
    @Received let service: Service
}

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(service: Service, home: Home) {
        self.service = service
        self.home = home
    }

    @Instantiated let service: Service
    @Instantiated let home: Home
}
