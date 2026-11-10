import Feature
import SafeDI

struct Impl: Service { let tag: String }

/// Not Sendable: the plain builder captures it.
final class Counter {
	var count = 0
	init() {}
}

@main struct Main {
	static func main() {
		let counter = Counter()
		let seam = SeamA(serviceBuilder: { _ in
			counter.count += 1
			return Impl(tag: "hand")
		})
		print(seam.walk(4))
		print("builder called \(counter.count) times")
	}
}
