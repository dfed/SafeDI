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

import SwiftSyntax

extension AttributeListSyntax.Element {
	var instantiableMacro: AttributeSyntax? {
		attributeIfNameEquals(InstantiableVisitor.macroName)
	}

	var instantiatedMacro: AttributeSyntax? {
		attributeIfNameEquals(Dependency.Source.instantiatedRawValue)
	}

	var receivedMacro: AttributeSyntax? {
		attributeIfNameEquals(Dependency.Source.receivedRawValue)
	}

	var forwardedMacro: AttributeSyntax? {
		attributeIfNameEquals(Dependency.Source.forwardedRawValue)
	}

	/// This attribute when it names SafeDI's macro `expectedName`, spelled alone (`@Instantiable`) or qualified by SafeDI's
	/// module name (`@SafeDI.Instantiable`).
	private func attributeIfNameEquals(_ expectedName: String) -> AttributeSyntax? {
		guard case let .attribute(attribute) = self else { return nil }
		let qualifiedName = MemberTypeSyntax(attribute.attributeName).flatMap { $0.baseType.namesSafeDIModule ? $0.name : nil }
		let name = IdentifierTypeSyntax(attribute.attributeName)?.name ?? qualifiedName
		return name?.text == expectedName ? attribute : nil
	}
}

extension TypeSyntax {
	/// Whether this type is the bare name of SafeDI's module, `SafeDI`, as it qualifies one of SafeDI's names.
	var namesSafeDIModule: Bool {
		IdentifierTypeSyntax(self).map { $0.genericArgumentClause == nil && $0.name.text == Dependency.safeDIModuleName } ?? false
	}
}
