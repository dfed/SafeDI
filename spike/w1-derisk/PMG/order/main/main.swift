import App
import Harness
#if canImport(Feat)
	import Core
	import Feat
#endif

// Each Sub's Live should read Home's meter; `a`'s Live reads no badge and `b`'s reads Home's badge.
do {
	let root = rootMock()
	print("trace:")
	Registry.printTrace()
	Registry.printAlive("holding the root")
	withExtendedLifetime(root) {}
}

Registry.printAlive("after dropping it")
// The meter override must reach both fills.
do {
	let root = rootMockOverridingMeter()
	print("trace with the meter overridden:")
	Registry.printTrace()
	withExtendedLifetime(root) {}
}

Registry.printAlive("after dropping it")
