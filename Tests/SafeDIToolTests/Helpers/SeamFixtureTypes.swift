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

/// `declaration`, of a type that is not `@Instantiable`, inside an `#if` block, where SafeDI records no declaration of
/// the type (`PlainTypeDeclaration`): only the members that mention it then prove its access, as they prove the access
/// of a type of a module SafeDI does not read, such as a framework's.
func unrecordedTypeDeclaration(_ declaration: String) -> String {
	"#if canImport(Foundation)\n\(declaration)\n#endif"
}
