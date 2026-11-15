import App
import Harness
#if canImport(Feature)
	import Feature
#endif

var held: Any? = {
	let root = Root()
	_ = root
	let top = rootUnderTest()
	let x1 = top.service.xBuilder.instantiate()
	let s2 = x1.serviceBuilder.instantiate()
	let x2 = s2.xBuilder.instantiate()
	let s3 = x2.serviceBuilder.instantiate()
	let x3 = s3.xBuilder.instantiate()
	let s4 = x3.serviceBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((top, x1, s2, x2, s3, x3)) {}
	return s4
}()

Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
