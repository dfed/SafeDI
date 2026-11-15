import App
import Harness
#if canImport(Feat)
	import Core
	import Feat
#endif

// Walks three levels of Root.mock(): each step's Live should receive its own screen's cache.
do {
	let root = rootMock()
	let step1 = root.home.screen.stepBuilder.instantiate()
	let screen2 = step1.screenBuilder.instantiate()
	let step2 = screen2.stepBuilder.instantiate()
	let screen3 = step2.screenBuilder.instantiate()
	let step3 = screen3.stepBuilder.instantiate()
	print("trace of three levels:")
	Registry.printTrace()
	withExtendedLifetime((root, step1, screen2, step2, screen3, step3)) {}
}

Registry.printAlive("after dropping everything")
// Holds only screen 2's step: inline frees screen 1's cache.
do {
	let step2: Step
	do {
		let root = rootMock()
		step2 = root.home.screen.stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate()
	}
	Registry.printTrace()
	Registry.printAlive("holding only screen 2's step")
	withExtendedLifetime(step2) {}
}

Registry.printAlive("after dropping it")
