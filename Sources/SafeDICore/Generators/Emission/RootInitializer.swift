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

/// The `init()` a root's dependency tree is generated as, in an extension of the root: facts of the root, decided before
/// the tree's body is written.
struct RootInitializer: Hashable, Sendable {
	/// The root's concrete type, which the extension extends.
	let extendedType: TypeDescription
	/// The attributes `generatedInitializerAttributes` spells, which precede the initializer's modifiers on its line, as
	/// `mockAttributes` precede a mock's.
	let attributes: String
	/// Whether the root is a class, whose initializer that calls another is `convenience`.
	let isConvenience: Bool
	/// What the initializer passes the root's own initializer.
	let argumentList: String

	/// The initializer generated for `instantiable`, a root, which passes `argumentList` to the root's own initializer;
	/// `nil` for a root without dependencies, which has nothing to build, and for which nothing is generated.
	init?(of instantiable: Instantiable, argumentList: String) {
		guard !instantiable.dependencies.isEmpty else { return nil }
		extendedType = instantiable.concreteInstantiable
		attributes = instantiable.generatedInitializerAttributes
		isConvenience = instantiable.declarationType == .classType
		self.argumentList = argumentList
	}

	/// The extension declaring the initializer, whose body writes `statements` before it calls the root's own initializer.
	func spelled(writing statements: [String]) -> String {
		let attributesPrefix = attributes.isEmpty ? "" : "\(attributes) "
		return """
		extension \(extendedType.asSource) {
		    \(attributesPrefix)public \(isConvenience ? "convenience " : "")init() {
		\(statements.joined(separator: "\n"))
		        self.init(\(argumentList))
		    }
		}
		"""
	}
}
