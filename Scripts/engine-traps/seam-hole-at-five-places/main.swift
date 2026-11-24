func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

// What each place's levels handed the caller: the token the place can read, and the pair built before it.
final class Seen {
	var tokens: [String: Token] = [:]
	var earlierPairs: [String: Pair] = [:]
	var topTokenWasRead = false
}

let seen = Seen()
var created = 0
@MainActor func makeToken() -> Token {
	created += 1
	return Token()
}

func pairCarrier(_ place: String) -> Feature.__safeDI_ServiceCarrier_Pair<Service> {
	.init(service: { Service(place: place) })
}

func sideCarrier<Carrier>(_ seen: Seen, _ side: String, _ make: (@escaping (Token) -> Feature.__safeDI_ServiceCarrier_Pair<Service>, @escaping (Token, Pair) -> Feature.__safeDI_ServiceCarrier_Pair<Service>) -> Carrier) -> Carrier {
	make(
		{ token in
			seen.tokens["\(side) pair"] = token
			return pairCarrier("\(side) pair")
		},
		{ token, pair in
			seen.tokens["\(side) built pair"] = token
			seen.earlierPairs[side] = pair
			return pairCarrier("\(side) built pair")
		},
	)
}

let feature = Feature(
	__safeDI_token: makeToken(),
	__safeDI_serviceBuilder: .init(
		left: { _ in sideCarrier(seen, "left") { .init(pair: $0, pairBuilder: $1) } },
		rightBuilder: { _, _ in sideCarrier(seen, "right") { .init(pair: $0, pairBuilder: $1) } },
		pairBuilder: { _, _, _ in pairCarrier("top built pair") },
	),
)
report("tokens created once the tree is built", created)
let left = feature.left
let right = feature.rightBuilder.instantiate()
for (side, token, pair, pairBuilder) in [("left", left.token, left.pair, left.pairBuilder), ("right", right.token, right.pair, right.pairBuilder)] {
	let built = pairBuilder.instantiate()
	report("\(side): services", [pair.service.place, built.service.place])
	report("\(side): pairs read \(side)'s token", pair.token === token && built.token === token)
	report("\(side): levels were handed \(side)'s token", seen.tokens["\(side) pair"] === token && seen.tokens["\(side) built pair"] === token)
	report("\(side): the built pair's level was handed \(side)'s pair", seen.earlierPairs[side] === pair)
}
report("the sides' tokens differ", left.token !== right.token)
report("tokens created before the top pair", created)
let top = feature.pairBuilder.instantiate()
report("top: service", top.service.place)
report("top: token is neither side's", top.token !== left.token && top.token !== right.token)
report("a second right has its own token and services", { () -> String in
	let second = feature.rightBuilder.instantiate()
	return "\(second.token !== right.token) \(second.pair.service.place) \(second.pairBuilder.instantiate().service.place) \(seen.tokens["right built pair"] === second.token)"
}())
report("tokens created at the end", created)
