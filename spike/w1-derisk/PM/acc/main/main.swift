import App
#if canImport(Feature)
import Feature
#endif
import Harness

var held: Any? = {
	let root = Root()
	let mocked = Root.mock()
	let x1 = mocked.service.xBuilder.instantiate()
	let s2 = x1.serviceBuilder.instantiate()
	let x2 = s2.xBuilder.instantiate()
	let s3 = x2.serviceBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((root, mocked, x1, s2, x2)) {}
	return s3
}()
Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
