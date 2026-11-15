import App
#if canImport(Feature)
import Feature
#endif
import Harness

/// Opens `depth` screens, each from the one before, with ids 1 through `depth`, and returns the deepest.
func walk(_ root: Root, depth: Int) -> Screen {
	var screen = root.home.screenBuilder.instantiate(1)
	for id in 2...max(depth, 2) where id <= depth {
		screen = screen.next.instantiate(id)
	}
	return screen
}

do {
	let root = Root()
	let deepest = walk(root, depth: 8)
	print("trace of eight levels:")
	Registry.printTrace()
	withExtendedLifetime((root, deepest)) {}
}
Registry.printAlive("after dropping everything")
for depth in [4, 8] {
	do {
		let deepest: Screen
		do {
			deepest = walk(Root(), depth: depth)
		}
		Registry.printTrace()
		Registry.printAlive("holding only the screen at depth \(depth)")
		withExtendedLifetime(deepest) {}
	}
	Registry.printAlive("after dropping it")
}
