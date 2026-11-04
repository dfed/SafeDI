// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// The source of a public `@Instantiable` type named `name` for a seam test's fixture, with `declarations` and an
/// initializer taking each, conforming to `Instantiable` and to the `conformances` that follow it: a struct, or a
/// final class where a value type would contain itself.
func seamFixtureType(
	named name: String,
	isSeam: Bool = false,
	isRoot: Bool = false,
	isFinalClass: Bool = false,
	declarations: [String],
	conformances: String = "",
) -> String {
	let properties = declarations.map { declaration -> (label: String, type: String) in
		let property = declaration[declaration.range(of: " let ")!.upperBound...]
		return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
	}
	let parameters = properties.map { "\($0.label): \(GraphFuzzerSpelling.isFunctionType($0.type) ? "@escaping " : "")\($0.type)" }.joined(separator: ", ")
	let body = properties.isEmpty ? "public init() {}" : "public init(\(parameters)) {\n" + properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n") + "\n    }\n\n" + declarations.map { "    \($0)" }.joined(separator: "\n")
	return """
	@Instantiable\(isSeam ? "(generateDependencyTree: true)" : isRoot ? "(isRoot: true)" : "")
	public \(isFinalClass ? "final class" : "struct") \(name): Instantiable\(conformances) {
	    \(body)
	}
	"""
}

/// `files` with no type declared as a seam, so every tree is built inline.
func inlineFixture(_ files: [String]) -> [String] {
	files.map { $0.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable") }
}

/// `Hubs`, in package `Shop`, whose `@Instantiable` `Hub` a fixture declares `Hub.Theme` in an extension of
/// (`hubTheme(declarations:)`).
let hubsModule = ModuleFixture(name: "Hubs", packageName: "Shop", swiftFileContent: ["@Instantiable\npublic struct Hub: Instantiable {\n    public init() {}\n}"])

/// `Hub.Theme`, or `Hub.<name>`, a `public` `@Instantiable` final class with `declarations`, in an unspelled extension of
/// `hubsModule`'s `Hub`,
/// in a file that imports `Hubs`. SafeDI bounds a type in an extension of another module's type by that extension, which
/// counts as `internal`, and raises it only by the mentions in its module or in one whose declaration receives it, so a
/// module in another package can name it while SafeDI proves it narrower: what a type in a clause the conditions select
/// could be before SafeDI read such a type's declaration exactly.
func hubTheme(named name: String = "Theme", declarations: [String] = []) -> String {
	let theme = seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
		.split(separator: "\n", omittingEmptySubsequences: false)
		.map { $0.isEmpty ? "" : "    \($0)" }
		.joined(separator: "\n")
	return "import Hubs\n\nextension Hub {\n\(theme)\n}"
}

/// `declaration`, of a type that is not `@Instantiable`, inside `#if canImport(Foundation)`, which SafeDI records from
/// every clause: a platform condition is one only the compiler decides, so the type counts as the narrowest level any
/// clause declares it at, here the one `declaration` spells.
func platformConditionedDeclaration(_ declaration: String) -> String {
	"#if canImport(Foundation)\n\(declaration)\n#endif"
}
