import App
#if canImport(Feature)
import Feature
#endif
import Harness

// Walks three levels: each screen's step builds a `Live` and opens the next screen through `next`.
do {
	let root = Root()
	let screen1 = root.home.screenBuilder.instantiate()
	let step1 = screen1.stepBuilder.instantiate()
	let screen2 = step1.next.instantiate()
	let step2 = screen2.stepBuilder.instantiate()
	let screen3 = step2.next.instantiate()
	let step3 = screen3.stepBuilder.instantiate()
	print("trace of three levels:")
	Registry.printTrace()
	withExtendedLifetime((root, screen1, step1, screen2, step2, screen3, step3)) {}
}
Registry.printAlive("after dropping everything")
// Holds only the second level's step.
do {
	let step2: Step
	do {
		let root = Root()
		step2 = root.home.screenBuilder.instantiate().stepBuilder.instantiate().next.instantiate().stepBuilder.instantiate()
	}
	Registry.printTrace()
	Registry.printAlive("holding only step 2")
	withExtendedLifetime(step2) {}
}
Registry.printAlive("after dropping step 2")
