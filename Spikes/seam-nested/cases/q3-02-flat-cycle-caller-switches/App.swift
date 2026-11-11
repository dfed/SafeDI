import Feature
import SafeDI

struct Impl: Service { let tag: String }

@main
struct Main {
	static func main() {
		let seam = SeamA(serviceBuilder: { scope in
			switch scope {
			case let .service(values): Impl(tag: "own-A/\(values.marker.name)")
			case let .SeamB_service(values): Impl(tag: "other-B/\(values.marker.name)")
			}
		})
		print(seam.walk(4))
	}
}
