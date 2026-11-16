import App
import Harness
#if canImport(Feature)
	import Feature
#endif

var deepest: AnyObject? = {
	let root = Root()
	let a1 = root.store.aBuilder.instantiate()
	let side1 = (a1.api as! LiveApi).sideBuilder.instantiate()
	let a2 = side1.aBuilder.instantiate()
	let side2 = (a2.api as! LiveApi).sideBuilder.instantiate()
	let a3 = side2.aBuilder.instantiate()
	let a0 = root.store.sideBuilder.instantiate().aBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((a1, side1, a2, side2, a0, root)) {}
	return a3
}()

Registry.printAlive("holding only the deepest")
withExtendedLifetime(deepest) {}
deepest = nil
Registry.printAlive("after dropping everything")
