import App
#if canImport(Inner)
import Inner
#endif
#if canImport(Feature)
import Feature
#endif
import Harness

var held: Any? = {
	let root = Root()
	let a1 = root.store.aBuilder.instantiate()
	let side1 = (a1.tBuilder.instantiate().api as! LiveApi).sideBuilder.instantiate()
	let a2 = side1.aBuilder.instantiate()
	let side2 = (a2.tBuilder.instantiate().api as! LiveApi).sideBuilder.instantiate()
	let a3 = side2.aBuilder.instantiate()
	let a0 = root.store.sideBuilder.instantiate().aBuilder.instantiate()
	_ = (a0.tBuilder.instantiate().api as! LiveApi)
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((a1, side1, a2, side2, a0, root)) {}
	return a3
}()
Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
