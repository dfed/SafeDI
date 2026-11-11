import Feature
import SafeDI

/// Repeats the hole's property: a cycle that closes on the fill's builder function.
final class Impl: Service {
	let name: String
	let maker: ErasedInstantiator<String, any Service>
	init(name: String, maker: ErasedInstantiator<String, any Service>) {
		self.name = name; self.maker = maker
	}

	var tag: String {
		name.count < 3 ? maker.instantiate(name + "!").tag : "Impl(\(name))"
	}
}

struct PairImpl: Service { let name: String; let count: Int; var tag: String {
	"Pair(\(name),\(count))"
} }
struct PlainImpl: Service { let tag: String }
nonisolated(unsafe) var lazyBuilds = 0

@main
struct App {
	static func main() {
		// The generated caller: each fill is the place's builder function as today, called instead of wrapped.
		func __safeDI_serviceBuilder_Feature_maker(_: Feature.SafeDIScope_Service.maker_Values, _ __safeDI_forwarded: String) -> any Service {
			func __safeDI_maker(name: String) -> Impl {
				let maker = ErasedInstantiator<String, any Service> {
					__safeDI_maker(name: $0)
				}
				return Impl(name: name, maker: maker)
			}
			return __safeDI_maker(name: __safeDI_forwarded)
		}
		func __safeDI_serviceBuilder_Feature_pairMaker(_: Feature.SafeDIScope_Service.pairMaker_Values, _ __safeDI_forwarded: (name: String, count: Int)) -> any Service {
			func __safeDI_pairMaker(name: String, count: Int) -> PairImpl {
				PairImpl(name: name, count: count)
			}
			return __safeDI_pairMaker(name: __safeDI_forwarded.name, count: __safeDI_forwarded.count)
		}
		func __safeDI_serviceBuilder_Feature_plainMaker(_: Feature.SafeDIScope_Service.plainMaker_Values) -> any Service {
			func __safeDI_plainMaker() -> PlainImpl {
				PlainImpl(tag: "plain")
			}
			return __safeDI_plainMaker()
		}
		func __safeDI_serviceBuilder_Feature_lazy(_: Feature.SafeDIScope_Service.lazy_Values) -> any Service {
			func __safeDI_lazy() -> PlainImpl {
				lazyBuilds += 1
				return PlainImpl(tag: "lazy")
			}
			return __safeDI_lazy()
		}
		func __safeDI_serviceBuilder_Feature(_ scope: Feature.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .maker(scope, __safeDI_forwarded): __safeDI_serviceBuilder_Feature_maker(scope, __safeDI_forwarded)
			case let .pairMaker(scope, __safeDI_forwarded): __safeDI_serviceBuilder_Feature_pairMaker(scope, __safeDI_forwarded)
			case let .plainMaker(scope): __safeDI_serviceBuilder_Feature_plainMaker(scope)
			case let .lazy(scope): __safeDI_serviceBuilder_Feature_lazy(scope)
			}
		}
		let feature = Feature(serviceBuilder: __safeDI_serviceBuilder_Feature)
		print(feature.maker.instantiate("a").tag, feature.pairMaker.instantiate((name: "p", count: 2)).tag, feature.plainMaker.instantiate().tag, feature.lazy.instance.tag, feature.lazy.instance.tag, "lazy builds:", lazyBuilds)
		// A person's call.
		let hand = Feature(serviceBuilder: { scope in
			switch scope {
			case let .maker(_, name): PlainImpl(tag: "hand-\(name)")
			case let .pairMaker(values, pair): PlainImpl(tag: "hand-\(pair.name)-\(values.maker.instantiate("x").tag)")
			case .plainMaker, .lazy: PlainImpl(tag: "hand")
			}
		})
		print(hand.maker.instantiate("a").tag, hand.pairMaker.instantiate((name: "p", count: 2)).tag, hand.plainMaker.instantiate().tag)
	}
}
