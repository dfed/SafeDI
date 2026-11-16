import App
import Harness
#if canImport(Inner)
	import Inner
#endif
#if canImport(Feature)
	import Feature
#endif

var held: Any? = {
	let root = Root()
	let a1 = root.store.aBuilder.instantiate()
	let a2 = root.store.aBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	_ = root.store.a; withExtendedLifetime((root, a1)) {}
	return a2
}()

Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
