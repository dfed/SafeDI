func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@MainActor func describe(_ name: String, _ root: Root) {
	let places: [(String, Holder, Session)] = [
		("left", root.left.holder, root.first),
		("left built", root.left.holderBuilder.instantiate(), root.first),
		("right", root.right.holder, root.second),
		("right built", root.right.holderBuilder.instantiate(), root.second),
		("top built", root.holderBuilder.instantiate(), root.session),
	]
	for (place, holder, session) in places {
		report("\(name): \(place): session, wrapped, leaf's session, leaf's wrapped, leaf", [holder.session.name, holder.wrapped.session.name, holder.leaf.session.name, holder.leaf.wrapped.session.name, holder.leaf.name])
		report("\(name): \(place): all four are the place's session", [holder.session, holder.wrapped.session, holder.leaf.session, holder.leaf.wrapped.session].allSatisfy { $0 === session })
	}
	report("\(name): the sides hold the renamed sessions", root.left.session === root.first && root.right.session === root.second)
}

describe("no overrides", Root.mock())
describe("a name at each place", Root.mock(safeDIOverrides: .init(
	first: .init(name: "first"),
	second: .init(name: "second"),
	session: .init(name: "session"),
	left: .init(holder: .init(leaf: .init(name: "left leaf")), holderBuilder: .init(leaf: .init(name: "left built leaf"))),
	right: .init(holder: .init(leaf: .init(name: "right leaf")), holderBuilder: .init(leaf: .init(name: "right built leaf"))),
	holderBuilder: .init(leaf: .init(name: "top built leaf")),
)))
describe("builders at two places", Root.mock(safeDIOverrides: .init(
	second: .init { _ in Session(name: "second from a builder") },
	left: .init(holderBuilder: .init { session, wrapped, _ in Holder(session: session, wrapped: wrapped, leaf: Leaf(session: session, wrapped: wrapped, name: "left built holder from a builder")) }),
	right: .init(holder: .init(leaf: .init { session, wrapped, _ in Leaf(session: session, wrapped: wrapped, name: "right leaf from a builder") })),
)))
describe("production", Root())
