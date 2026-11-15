import App
import Harness

do {
	let root = Root()
	print("trace Root():")
	Registry.printTrace()
	withExtendedLifetime(root) {}
}
Registry.printAlive("after dropping Root")
