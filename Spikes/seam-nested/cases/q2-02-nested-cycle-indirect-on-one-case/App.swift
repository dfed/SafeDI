import Feature
import SafeDI

struct Impl: Service { let tag: String }

@main struct Main {
	static func main() {
		print(SeamA(serviceBuilder: { _ in Impl(tag: "hand") }).walk(4))
	}
}
