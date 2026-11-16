import App
import Harness
#if canImport(Feat)
	import Core
	import Feat
#endif

#if canImport(Glibc)
	import Glibc
#endif

if let iterations = ProcessInfoLite.benchIterations {
	// Timing run: no trace; the median of five rounds, in nanoseconds per walk of three levels of Root.mock().
	tracingEnabled.store(false, ordering: .relaxed)
	var rounds = [Double]()
	for _ in 0..<5 {
		let start = ContinuousClock.now
		for _ in 0..<iterations {
			let root = rootMock()
			let step3 = root.home.screen.stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate()
			withExtendedLifetime((root, step3)) {}
		}
		let elapsed = ContinuousClock.now - start
		rounds.append(Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9)
	}
	FileHandleLite.error("bench ns per walk: \(Int(rounds.sorted()[2] / Double(iterations)))")
	exit(0)
}

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

// Every override set: which override each place reads.
do {
	let root = rootMockWithOverrides()
	let step3 = root.home.screen.stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate()
	print("every override set:")
	Registry.printTrace()
	withExtendedLifetime((root, step3)) {}
}
Registry.printAlive("after dropping everything")
