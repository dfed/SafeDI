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

/// The names the modules SafeDI read declare types by at file scope, each with the modules that declare it.
struct DeclaredTypeNames: Sendable {
	/// - Parameter moduleNamesByTypeName: The modules that declare a type of each name, `nil` for a declaration whose
	///   module SafeDITool does not know.
	init(moduleNamesByTypeName: [String: Set<String?>] = [:]) {
		self.moduleNamesByTypeName = moduleNamesByTypeName
	}

	/// Whether any module declares a type named `name`.
	func contains(_ name: String) -> Bool {
		moduleNamesByTypeName[name] != nil
	}

	/// Whether a module other than the one named `moduleName` declares a type named `name`. A declaration of an unknown
	/// module counts as another's, since it may be.
	func isDeclared(_ name: String, outsideModuleNamed moduleName: String) -> Bool {
		moduleNamesByTypeName[name, default: []].contains { $0 != moduleName }
	}

	private let moduleNamesByTypeName: [String: Set<String?>]
}
