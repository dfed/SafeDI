import Feature
import SafeDI

struct Impl: Service { let tag: String }

@main
struct Main {
	static func main() {
		let seam = SeamA(serviceBuilder: { scope in
			switch scope {
			case .service: Impl(tag: "A0")
			case .bBuilder(.service): Impl(tag: "B1")
			case .bBuilder(.a(.service)): Impl(tag: "A2")
			case .bBuilder(.a(.bBuilder)): Impl(tag: "deeper")
			}
		})
		print(seam.walk(4))
	}
}
