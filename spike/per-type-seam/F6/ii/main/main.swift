import App
import Harness
#if canImport(Feature)
	import Feature
#endif

do {
	let root = Root()
	let screen1 = root.home.screenBuilder.instantiate()
	let screen2 = screen1.again.instantiate()
	let screen3 = screen2.again.instantiate()
	print("trace:")
	Registry.printTrace()
	withExtendedLifetime((root, screen1, screen2, screen3)) {}
}

Registry.printAlive("after dropping everything")
