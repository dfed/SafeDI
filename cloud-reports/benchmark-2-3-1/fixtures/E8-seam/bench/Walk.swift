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
}

func walk(_ value: Model4) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walk(_ value: Screen5) {
	built += 1
	walk(value.model5)
}

func walk(_ value: Model5) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walk(_ value: Screen6) {
	built += 1
	walk(value.model6)
}

func walk(_ value: Model6) {
	built += 1
	withExtendedLifetime(value.api) {}
}

func walk(_ value: Screen7) {
	built += 1
	walk(value.model7)
}

func walk(_ value: Model7) {
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
