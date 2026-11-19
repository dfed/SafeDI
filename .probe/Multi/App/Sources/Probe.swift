#if canImport(Feed)
import Feed
#endif
import SafeDI

@main enum Main { static func main() {
for _ in [false] {
	let root = Root.mock()
	let fill = root.screen.holeBuilder.instantiate(7).value as! Fill
	let rebuilt = fill.screenBuilder.instantiate()
	print("child holds: " + String(fill.child.session === root.session.instance) + "; rebuilt holds: " + (rebuilt.session?.instance == nil ? "nil" : String(rebuilt.session?.instance === root.session.instance)))
}
} }
