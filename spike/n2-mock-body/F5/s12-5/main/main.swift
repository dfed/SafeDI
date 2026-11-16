import App
import Harness
#if canImport(Glibc)
	import Glibc
#endif

if let iterations = ProcessInfoLite.benchIterations {
	// Timing run: no trace; prints the median of five rounds, in nanoseconds per call of the fixture's walk.
	tracingEnabled.store(false, ordering: .relaxed)
	var rounds = [Double]()
	for _ in 0..<5 {
		let start = ContinuousClock.now
		for _ in 0..<iterations {
			runPlain()
		}
		let elapsed = ContinuousClock.now - start
		rounds.append(Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9)
	}
	let median = rounds.sorted()[2] / Double(iterations)
	FileHandleLite.error("bench ns per walk: \(Int(median))")
} else {
	runFixture()
}
