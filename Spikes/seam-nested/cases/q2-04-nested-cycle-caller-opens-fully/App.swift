import Feature
import SafeDI

struct Impl: Service { let tag: String }

/// Not Sendable: the plain builder captures it.
final class Counter {
	var count = 0
	init() {}
}

func openA(_ scope: SeamA.SafeDIScope_Service, depth: Int) -> any Service {
	switch scope {
	case let .service(values): Impl(tag: "A\(depth)/\(values.marker.name)")
	case let .bBuilder(scope): openB(scope, depth: depth + 1)
	}
}

func openB(_ scope: SeamB.SafeDIScope_Service, depth: Int) -> any Service {
	switch scope {
	case let .service(values): Impl(tag: "B\(depth)/\(values.marker.name)")
	case let .a(scope): openA(scope, depth: depth + 1)
	}
}

@main
struct Main {
	static func main() {
		let counter = Counter()
		let seam = SeamA(serviceBuilder: { scope in
			counter.count += 1
			return openA(scope, depth: 0)
		})
		print(seam.walk(4))
		print("builder called \(counter.count) times")
	}
}
