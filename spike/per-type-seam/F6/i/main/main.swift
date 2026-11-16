import App
import Harness
#if canImport(Feature)
	import Feature
#endif

do {
	let root = Root()
	let t2 = root.hub.tBuilder.instantiate()
	let t3 = root.hub.tBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	withExtendedLifetime((root, t2, t3)) {}
}

Registry.printAlive("after dropping everything")
