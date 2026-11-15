import App
#if canImport(Feature)
import Feature
#endif
import Harness

var deepest: AnyObject? = {
	let root = Root()
	let a1 = root.store.aBuilder.instantiate()
	let i1 = a1.innerBuilder.instantiate()
	let side1 = (i1.api as! LiveApi).sideBuilder.instantiate()
	let a2 = side1.aBuilder.instantiate()
	let i2 = a2.innerBuilder.instantiate()
	let side2 = (i2.api as! LiveApi).sideBuilder.instantiate()
	let a3 = side2.aBuilder.instantiate()
	let i3 = a3.innerBuilder.instantiate()
	let a0 = root.store.sideBuilder.instantiate().aBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((a1, i1, side1, a2, i2, side2, a3, a0, root)) {}
	return i3
}()
Registry.printAlive("holding only the deepest")
withExtendedLifetime(deepest) {}
deepest = nil
Registry.printAlive("after dropping everything")

