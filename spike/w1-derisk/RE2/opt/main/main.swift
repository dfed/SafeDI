import App
import Harness
#if canImport(Feature)
	import Feature
#endif

var held: Any? = {
	let root = Root()
	let x1 = root.service.xBuilder.instantiate()
	let s2 = x1.serviceBuilder.instantiate()
	let x2 = s2.xBuilder.instantiate()
	let s3 = x2.serviceBuilder.instantiate()
	let x2b = s2.xBuilder.instantiate()
	let s3b = x2b.serviceBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((root, x1, s2, x2, x2b, s3b)) {}
	return s3
}()

Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
