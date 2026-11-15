import App
#if canImport(Three)
import Three
#endif
#if canImport(Two)
import Two
#endif
#if canImport(One)
import One
#endif
import Harness

var held: Any? = {
	let root = Root()
	var all: [AnyObject] = []
	for s2 in [root.s1.a, root.s1.b] {
		all.append(s2)
		for s3 in [s2.a, s2.b] { all.append(s3) }
	}
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding everything")
	withExtendedLifetime((root, all)) {}
	return all[2]
}()
Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
