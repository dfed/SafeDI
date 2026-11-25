func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

// What the innermost tree's levels handed the caller when an api was built, by the place's path.
final class Seen {
	var tokens: [String: Token] = [:]
	var marks: [String: Mark] = [:]
	var earlierClients: [String: Client] = [:]
}

func innerCarrier(_ seen: Seen, _ path: String) -> Inner.__safeDI_ApiCarrier<Api> {
	.init(
		client: { mark, token in
			.init(api: {
				seen.tokens["\(path) client"] = token.instance
				seen.marks["\(path) client"] = mark.instance
				return Api(place: "\(path) client")
			})
		},
		clientBuilder: { mark, token, client in
			.init(api: {
				seen.tokens["\(path) built client"] = token.instance
				seen.marks["\(path) built client"] = mark.instance
				seen.earlierClients["\(path) built client"] = client
				return Api(place: "\(path) built client")
			})
		},
	)
}

func sideCarrier(_ seen: Seen, _ path: String) -> Middle.__safeDI_ApiCarrier_Side<Api> {
	.init(inner: innerCarrier(seen, "\(path) inner"), innerBuilder: innerCarrier(seen, "\(path) built inner"))
}

func middleCarrier(_ seen: Seen, _ path: String) -> Middle.__safeDI_ApiCarrier<Api> {
	.init(leftSide: { _ in sideCarrier(seen, "\(path) left") }, rightSideBuilder: { _, _ in sideCarrier(seen, "\(path) right") })
}

func halfCarrier(_ seen: Seen, _ path: String) -> Outer.__safeDI_ApiCarrier_Half<Api> {
	.init(middle: middleCarrier(seen, "\(path) middle"), middleBuilder: middleCarrier(seen, "\(path) built middle"))
}

// Walks one middle tree and reports, for each of its eight api places, what the place was handed.
@MainActor func check(_ seen: Seen, _ path: String, _ middle: Middle, _ token: Token) -> [Mark] {
	var wrong: [String] = []
	var places: [String] = []
	var marks: [Mark] = []
	for (sideName, side) in [("left", middle.leftSide), ("right", middle.rightSideBuilder.instantiate())] {
		marks.append(side.mark)
		for (innerName, inner) in [("inner", side.inner), ("built inner", side.innerBuilder.instantiate())] {
			let innerPath = "\(path) \(sideName) \(innerName)"
			let built = inner.clientBuilder.instantiate()
			for (clientName, client) in [("client", inner.client), ("built client", built)] {
				let place = "\(innerPath) \(clientName)"
				places.append(client.api.place)
				if client.api.place != place { wrong.append("\(place) was handed the api of \(client.api.place)") }
				if client.token !== token { wrong.append("\(place) reads another token") }
				if client.mark !== side.mark { wrong.append("\(place) reads another mark") }
				if seen.tokens[place] !== token { wrong.append("\(place)'s level was handed another token") }
				if seen.marks[place] !== side.mark { wrong.append("\(place)'s level was handed another mark") }
			}
			if seen.earlierClients["\(innerPath) built client"] !== inner.client { wrong.append("\(innerPath) built client's level was handed another client") }
		}
	}
	report("\(path): apis", places)
	report("\(path): wrong values", wrong)
	return marks
}

let seen = Seen()

// One depth: the middle tree called directly, as the outermost tree calls it.
let directToken = Token()
let direct = Middle(__safeDI_token: directToken, __safeDI_apiBuilder: middleCarrier(seen, "direct"))
var marks = check(seen, "direct", direct, directToken)

// Two depths: the outermost tree.
let outer = Outer(__safeDI_apiBuilder: .init(nearHalf: halfCarrier(seen, "near"), farHalfBuilder: { _ in halfCarrier(seen, "far") }))
let far = outer.farHalfBuilder.instantiate()
for (halfName, half) in [("near", outer.nearHalf), ("far", far)] {
	marks += check(seen, "\(halfName) middle", half.middle, half.token)
	marks += check(seen, "\(halfName) built middle", half.middleBuilder.instantiate(), half.token)
}
report("the halves' tokens differ", outer.nearHalf.token !== far.token)
report("distinct marks among the ten sides", Set(marks.map(ObjectIdentifier.init)).count)
report("api places built", seen.tokens.count)
