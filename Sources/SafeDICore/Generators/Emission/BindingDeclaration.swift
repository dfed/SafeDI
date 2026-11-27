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

/// The `let` with which a body binds a property it builds: `let label`, or `let label: Type` where the value's spelling
/// does not say the property's type. Each form of property has its own rule, kept apart because they differ where a
/// type is declared in an extension (`SafeDIToolBindingAnnotationTests`).
struct BindingDeclaration: Hashable, Sendable {
	/// When the binding spells the property's type.
	enum AnnotationRule: Hashable, Sendable {
		/// A constant is annotated unless its value is erased to the property's type, or the value is constructed in place
		/// (no builder function) as the property's own type, which is not declared in an extension: a builder function's call,
		/// and `instantiate()`, return the concrete type, which may differ from the property's.
		case constant(isErased: Bool, constructedTypeIsPropertyType: Bool, hasBuilderFunction: Bool, isExtension: Bool)
		/// An instantiator is annotated where its type is declared in an extension, or where the wrapper's spelling for
		/// construction differs from the property's type: an optional property, or generic arguments spelled only there.
		case instantiator(isExtension: Bool, constructionSpellsPropertyType: Bool)
		/// A lazily instantiated property is never annotated: its wrapper is always spelled with its generic argument, and an
		/// optional property receives it through optional promotion.
		case lazilyInstantiated

		var annotates: Bool {
			switch self {
			case let .constant(isErased, constructedTypeIsPropertyType, hasBuilderFunction, isExtension):
				!(isErased || (constructedTypeIsPropertyType && !hasBuilderFunction && !isExtension))
			case let .instantiator(isExtension, constructionSpellsPropertyType):
				isExtension || !constructionSpellsPropertyType
			case .lazilyInstantiated:
				false
			}
		}
	}

	let property: Property
	let rule: AnnotationRule

	/// `let label` or `let label: Type`.
	var spelled: String {
		rule.annotates ? "let \(property.asSource)" : "let \(property.label)"
	}
}
