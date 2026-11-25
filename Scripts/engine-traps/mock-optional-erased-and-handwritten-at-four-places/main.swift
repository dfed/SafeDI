func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@MainActor func describe(_ name: String, _ root: Root, rightExtra: Extra?) {
	let places: [(String, Holder, Token, Extra?)] = [
		("left", root.left.holder, root.left.token, root.left.extra),
		("left built", root.left.holderBuilder.instantiate(), root.left.token, root.left.extra),
		("right", root.right.holder, root.right.token, rightExtra),
		("right built", root.right.holderBuilder.instantiate(), root.right.token, rightExtra),
	]
	for (place, holder, token, extra) in places {
		let leaf = holder.lazyLeaf.instance
		report("\(name): \(place): services (holder, widget, leaf)", [holder.service.side, holder.widget.service.side, leaf.service.side])
		report("\(name): \(place): names (widget, leaf)", [holder.widget.name, leaf.name])
		report("\(name): \(place): holder, widget and leaf read the side's token", holder.token === token && holder.widget.token === token && leaf.token === token)
		report("\(name): \(place): holder and leaf read the side's extra", "\(holder.extra === extra && leaf.extra === extra), which is \(extra == nil ? "nothing" : "an extra")")
	}
}

describe("no overrides", Root.mock(), rightExtra: nil)

let rootExtra = Extra()
describe("an extra for whoever lacks one", Root.mock(safeDIOverrides: .init(extra: rootExtra)), rightExtra: rootExtra)

let leftExtra = Extra()
describe("names and values at each place", Root.mock(safeDIOverrides: .init(
	left: .init(
		extra: { leftExtra },
		holder: .init(widget: .init(name: "left widget"), lazyLeaf: .init(name: "left leaf")),
		holderBuilder: .init(widget: .init(name: "left built widget"), lazyLeaf: .init(name: "left built leaf")),
	),
	right: .init(
		service: { LeftService() },
		holder: .init(widget: .init(name: "right widget"), lazyLeaf: .init(name: "right leaf")),
		holderBuilder: .init(widget: .init(name: "right built widget"), lazyLeaf: .init(name: "right built leaf")),
	),
	extra: rootExtra,
)), rightExtra: rootExtra)

describe("builders at two places", Root.mock(safeDIOverrides: .init(
	left: .init(holderBuilder: .init(lazyLeaf: .init { token, extra, service, _ in Leaf(token: token, extra: extra, service: service, name: "left built leaf from a builder") })),
	right: .init(holder: .init(widget: .init { token, service, _ in Widget(token: token, service: service, name: "right widget from a builder") })),
)), rightExtra: nil)

let production = Root()
for (place, holder, token) in [("left", production.left.holder, production.left.token), ("left built", production.left.holderBuilder.instantiate(), production.left.token), ("right", production.right.holder, production.right.token), ("right built", production.right.holderBuilder.instantiate(), production.right.token)] {
	report("production: \(place)", "\(holder.service.side) \(holder.widget.name) \(holder.lazyLeaf.instance.name) \(holder.token === token) \(holder.extra == nil)")
}
