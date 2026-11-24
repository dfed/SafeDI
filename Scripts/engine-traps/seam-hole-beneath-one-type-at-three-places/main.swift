import Synchronization

func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

// What each place's levels handed the caller, by the side the level belongs to.
// The probe runs on one thread, so the lock only satisfies the compiler; identities stand in for the objects.
final class Seen: Sendable {
	let tokens = Mutex<[String: [ObjectIdentifier]]>([:])
	let pairs = Mutex<[String: [ObjectIdentifier]]>([:])
	let inners = Mutex<[String: [ObjectIdentifier]]>([:])
	let nodeIDs = Mutex<[String: [String]]>([:])
}

func sideCarrier(_ seen: Seen, _ side: String) -> Feature.__safeDI_ServiceCarrier_Side<Service> {
	.init(
		inner: { token in
			seen.tokens.withLock { $0["\(side) inner", default: []].append(ObjectIdentifier(token)) }
			return .init(
				pair: .init(service: { Service(place: "\(side) pair") }),
				pairBuilder: { pair in
					seen.pairs.withLock { $0[side, default: []].append(ObjectIdentifier(pair)) }
					return .init(service: { Service(place: "\(side) built pair") })
				},
			)
		},
		nodeBuilder: { token, inner in
			seen.tokens.withLock { $0["\(side) node", default: []].append(ObjectIdentifier(token)) }
			seen.inners.withLock { $0[side, default: []].append(ObjectIdentifier(inner)) }
			return .init(service: { id, _ in
				seen.nodeIDs.withLock { $0[side, default: []].append(id) }
				return Service(place: "\(side) node \(id)")
			})
		},
	)
}

let seen = Seen()
let feature = Feature(
	__safeDI_serviceBuilder: .init(leftSide: sideCarrier(seen, "left"), rightSideBuilder: { _ in sideCarrier(seen, "right") }),
	__safeDI_serviceSendableBuilder: .init(sendableSideBuilder: { [seen] in sideCarrier(seen, "sendable") }),
)
let sides = [("left", feature.leftSide), ("right", feature.rightSideBuilder.instantiate()), ("sendable", feature.sendableSideBuilder.instantiate())]
for (name, side) in sides {
	let built = side.inner.pairBuilder.instantiate()
	report("\(name): services", [side.inner.pair.service.place, built.service.place])
	report("\(name): pairs read \(name)'s token", side.inner.pair.token === side.token && built.token === side.token)
	report("\(name): levels were handed \(name)'s token", seen.tokens.withLock { ($0["\(name) inner"] ?? []).last == ObjectIdentifier(side.token) && ($0["\(name) node"] ?? []).last == ObjectIdentifier(side.token) })
	report("\(name): the built pair's level was handed \(name)'s pair", seen.pairs.withLock { ($0[name] ?? []).last == ObjectIdentifier(side.inner.pair) })
	report("\(name): the node's level was handed \(name)'s inner", seen.inners.withLock { ($0[name] ?? []).last == ObjectIdentifier(side.inner) })
	let node1 = side.nodeBuilder.instantiate("\(name) 1")
	let node2 = node1.nodeBuilder.instantiate("\(name) 2")
	let node3 = node2.nodeBuilder.instantiate("\(name) 3")
	report("\(name): node services by lap", [node1.service.place, node2.service.place, node3.service.place])
	report("\(name): nodes read \(name)'s token and their own id", [node1, node2, node3].allSatisfy { $0.token === side.token } && [node1.id, node2.id, node3.id] == ["\(name) 1", "\(name) 2", "\(name) 3"])
}
report("the three tokens differ", sides[0].1.token !== sides[1].1.token && sides[1].1.token !== sides[2].1.token && sides[0].1.token !== sides[2].1.token)
let secondRight = feature.rightSideBuilder.instantiate()
report("a second right: services", [secondRight.inner.pair.service.place, secondRight.inner.pairBuilder.instantiate().service.place, secondRight.nodeBuilder.instantiate("again").service.place])
report("a second right: its levels were handed its own token and pair", seen.tokens.withLock { $0["right inner"]?.last == ObjectIdentifier(secondRight.token) && $0["right node"]?.last == ObjectIdentifier(secondRight.token) } && seen.pairs.withLock { $0["right"]?.last == ObjectIdentifier(secondRight.inner.pair) })
report("levels handed out by side", seen.tokens.withLock { tokens in tokens.keys.sorted().map { "\($0) \(tokens[$0]?.count ?? 0)" } })
