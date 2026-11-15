import App
#if canImport(Feature)
import Feature
#endif
import Harness

var deepest: AnyObject? = {
	let root = Root()
	let s1 = root.home.screenBuilder.instantiate()
	let s2 = (s1.api as! LiveApi).screenBuilder.instantiate()
	let s3 = (s2.api as! LiveApi).screenBuilder.instantiate()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((root, s1, s2)) {}
	return s3
}()
Registry.printAlive("holding only the deepest")
deepest = nil
Registry.printAlive("after dropping everything")
