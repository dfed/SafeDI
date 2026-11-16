#if canImport(Feature)
import Feature
#endif
import Harness

nonisolated(unsafe) var nextIdentifier = 0
nonisolated(unsafe) var built = 0

func identifier() -> Int {
	nextIdentifier += 1
	return nextIdentifier
}

func walk(_ value: Home) {
	built += 1
	walk(value.screen0Builder.instantiate(identifier()))
	walk(value.screen1Builder.instantiate(identifier()))
	walk(value.screen2Builder.instantiate(identifier()))
	walk(value.screen3Builder.instantiate(identifier()))
}

func walk(_ value: Screen0) {
	built += 1
	walk(value.model0)
	walk(value.screen5Builder.instantiate(identifier()))
	walk(value.screen6Builder.instantiate(identifier()))
	walk(value.screen7Builder.instantiate(identifier()))
}

func walk(_ value: Model0) {
	built += 1
}

func walk(_ value: Screen1) {
	built += 1
	walk(value.model1)
	walk(value.screen4Builder.instantiate(identifier()))
	walk(value.screen6Builder.instantiate(identifier()))
	walk(value.screen7Builder.instantiate(identifier()))
}

func walk(_ value: Model1) {
	built += 1
}

func walk(_ value: Screen2) {
	built += 1
	walk(value.model2)
	walk(value.screen4Builder.instantiate(identifier()))
	walk(value.screen5Builder.instantiate(identifier()))
	walk(value.screen7Builder.instantiate(identifier()))
}

func walk(_ value: Model2) {
	built += 1
}

func walk(_ value: Screen3) {
	built += 1
	walk(value.model3)
	walk(value.screen4Builder.instantiate(identifier()))
	walk(value.screen5Builder.instantiate(identifier()))
	walk(value.screen6Builder.instantiate(identifier()))
}

func walk(_ value: Model3) {
	built += 1
}

func walk(_ value: Screen4) {
	built += 1
	walk(value.model4)
	walk(value.screen9Builder.instantiate(identifier()))
	walk(value.screen10Builder.instantiate(identifier()))
	walk(value.screen11Builder.instantiate(identifier()))
}

func walk(_ value: Model4) {
	built += 1
}

func walk(_ value: Screen5) {
	built += 1
	walk(value.model5)
	walk(value.screen8Builder.instantiate(identifier()))
	walk(value.screen10Builder.instantiate(identifier()))
	walk(value.screen11Builder.instantiate(identifier()))
}

func walk(_ value: Model5) {
	built += 1
}

func walk(_ value: Screen6) {
	built += 1
	walk(value.model6)
	walk(value.screen8Builder.instantiate(identifier()))
	walk(value.screen9Builder.instantiate(identifier()))
	walk(value.screen11Builder.instantiate(identifier()))
}

func walk(_ value: Model6) {
	built += 1
}

func walk(_ value: Screen7) {
	built += 1
	walk(value.model7)
	walk(value.screen8Builder.instantiate(identifier()))
	walk(value.screen9Builder.instantiate(identifier()))
	walk(value.screen10Builder.instantiate(identifier()))
}

func walk(_ value: Model7) {
	built += 1
}

func walk(_ value: Screen8) {
	built += 1
	walk(value.model8)
	walk(value.screen13Builder.instantiate(identifier()))
	walk(value.screen14Builder.instantiate(identifier()))
	walk(value.screen15Builder.instantiate(identifier()))
}

func walk(_ value: Model8) {
	built += 1
}

func walk(_ value: Screen9) {
	built += 1
	walk(value.model9)
	walk(value.screen12Builder.instantiate(identifier()))
	walk(value.screen14Builder.instantiate(identifier()))
	walk(value.screen15Builder.instantiate(identifier()))
}

func walk(_ value: Model9) {
	built += 1
}

func walk(_ value: Screen10) {
	built += 1
	walk(value.model10)
	walk(value.screen12Builder.instantiate(identifier()))
	walk(value.screen13Builder.instantiate(identifier()))
	walk(value.screen15Builder.instantiate(identifier()))
}

func walk(_ value: Model10) {
	built += 1
}

func walk(_ value: Screen11) {
	built += 1
	walk(value.model11)
	walk(value.screen12Builder.instantiate(identifier()))
	walk(value.screen13Builder.instantiate(identifier()))
	walk(value.screen14Builder.instantiate(identifier()))
}

func walk(_ value: Model11) {
	built += 1
}

func walk(_ value: Screen12) {
	built += 1
	walk(value.model12)
	walk(value.screen17Builder.instantiate(identifier()))
	walk(value.screen18Builder.instantiate(identifier()))
	walk(value.screen19Builder.instantiate(identifier()))
}

func walk(_ value: Model12) {
	built += 1
}

func walk(_ value: Screen13) {
	built += 1
	walk(value.model13)
	walk(value.screen16Builder.instantiate(identifier()))
	walk(value.screen18Builder.instantiate(identifier()))
	walk(value.screen19Builder.instantiate(identifier()))
}

func walk(_ value: Model13) {
	built += 1
}

func walk(_ value: Screen14) {
	built += 1
	walk(value.model14)
	walk(value.screen16Builder.instantiate(identifier()))
	walk(value.screen17Builder.instantiate(identifier()))
	walk(value.screen19Builder.instantiate(identifier()))
}

func walk(_ value: Model14) {
	built += 1
}

func walk(_ value: Screen15) {
	built += 1
	walk(value.model15)
	walk(value.screen16Builder.instantiate(identifier()))
	walk(value.screen17Builder.instantiate(identifier()))
	walk(value.screen18Builder.instantiate(identifier()))
}

func walk(_ value: Model15) {
	built += 1
}

func walk(_ value: Screen16) {
	built += 1
	walk(value.model16)
	walk(value.screen21Builder.instantiate(identifier()))
	walk(value.screen22Builder.instantiate(identifier()))
	walk(value.screen23Builder.instantiate(identifier()))
}

func walk(_ value: Model16) {
	built += 1
}

func walk(_ value: Screen17) {
	built += 1
	walk(value.model17)
	walk(value.screen20Builder.instantiate(identifier()))
	walk(value.screen22Builder.instantiate(identifier()))
	walk(value.screen23Builder.instantiate(identifier()))
}

func walk(_ value: Model17) {
	built += 1
}

func walk(_ value: Screen18) {
	built += 1
	walk(value.model18)
	walk(value.screen20Builder.instantiate(identifier()))
	walk(value.screen21Builder.instantiate(identifier()))
	walk(value.screen23Builder.instantiate(identifier()))
}

func walk(_ value: Model18) {
	built += 1
}

func walk(_ value: Screen19) {
	built += 1
	walk(value.model19)
	walk(value.screen20Builder.instantiate(identifier()))
	walk(value.screen21Builder.instantiate(identifier()))
	walk(value.screen22Builder.instantiate(identifier()))
}

func walk(_ value: Model19) {
	built += 1
}

func walk(_ value: Screen20) {
	built += 1
	walk(value.model20)
}

func walk(_ value: Model20) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walk(_ value: Screen21) {
	built += 1
	walk(value.model21)
}

func walk(_ value: Model21) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walk(_ value: Screen22) {
	built += 1
	walk(value.model22)
}

func walk(_ value: Model22) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walk(_ value: Screen23) {
	built += 1
	walk(value.model23)
}

func walk(_ value: Model23) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walkEveryPath(_ root: Root) {
	walk(root.home)
}

func benchmarkIteration() -> Int {
	built = 0
	walkEveryPath(Root())
	return built + 1
}
