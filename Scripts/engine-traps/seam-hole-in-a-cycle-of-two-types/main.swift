func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

// What each place's levels handed the caller: the last value by the place the level belongs to.
final class Seen {
	var tokens: [String: Token] = [:]
	var services: [String: Service] = [:]
	var leaves: [String: Leaf] = [:]
	var calls: [String] = []
}

func leafCarrier(_ place: String) -> Feature.__safeDI_ServiceCarrier_Leaf<Service> {
	.init(service: { Service(place: place) })
}

func sideCarrier(_ seen: Seen, _ side: String) -> Feature.__safeDI_ServiceCarrier_Side<Service> {
	.init(
		next: { token in
			seen.tokens["\(side) A"] = token
			return .init(
				service: { Service(place: "\(side) A") },
				leaf: { service in
					seen.services["\(side) A leaf"] = service
					return leafCarrier("\(side) A leaf")
				},
				next: { service, leaf in
					seen.services["\(side) B"] = service
					seen.leaves["\(side) B"] = leaf
					return .init(
						service: { _ in Service(place: "\(side) B") },
						leaf: { _, service in
							seen.services["\(side) B leaf"] = service
							return leafCarrier("\(side) B leaf")
						},
					)
				},
			)
		},
		leaf: { token, _ in
			seen.tokens["\(side) leaf"] = token
			return leafCarrier("\(side) leaf")
		},
	)
}

let seen = Seen()
let feature = Feature(__safeDI_serviceBuilder: .init(leftSide: sideCarrier(seen, "left"), rightSideBuilder: { _ in sideCarrier(seen, "right") }))
let sides = [("left", feature.leftSide), ("right", feature.rightSideBuilder.instantiate())]
for (name, side) in sides {
	report("\(name): the side's leaf", side.leaf.service.place)
	report("\(name): levels were handed \(name)'s token", seen.tokens["\(name) A"] === side.token && seen.tokens["\(name) leaf"] === side.token)
	let a1 = side.next.instantiate()
	report("\(name): first A's leaf level was handed that A's service", seen.services["\(name) A leaf"] === a1.service)
	report("\(name): first A's next level was handed that A's service and leaf", seen.services["\(name) B"] === a1.service && seen.leaves["\(name) B"] === a1.leaf)
	let b1 = a1.next.instantiate()
	report("\(name): first B's leaf level was handed that B's service", seen.services["\(name) B leaf"] === b1.service)
	let a2 = b1.next.instantiate()
	report("\(name): second A's leaf level was handed that A's service", seen.services["\(name) A leaf"] === a2.service && a2.service !== a1.service)
	let b2 = a2.next.instantiate()
	report("\(name): second B's leaf level was handed that B's service", seen.services["\(name) B leaf"] === b2.service && b2.service !== b1.service)
	report("\(name): services by lap (A, its leaf, B, its leaf, A, its leaf, B, its leaf)", [a1.service, a1.leaf.service, b1.service, b1.leaf.service, a2.service, a2.leaf.service, b2.service, b2.leaf.service].map(\.place))
	report("\(name): every leaf reads \(name)'s token", [side.leaf, a1.leaf, b1.leaf, a2.leaf, b2.leaf].allSatisfy { $0.token === side.token })
}
report("the two tokens differ", sides[0].1.token !== sides[1].1.token)
