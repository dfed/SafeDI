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

/// The two forms in which places of one node can read a label that no parameter carries, so the only differences a
/// variant may still split on: a parameter has one type and one form. Every other difference between two places' answers
/// (`nil` or a value, a value still being built or not, what a mock root pins) is one a parameter carries, and keys no
/// variant, since a variant per difference grows as two to the power of the labels that differ. A world whose variants
/// split on one of these forms holds that debt, which the roadmap's row of superlinear debt names by this type; a test
/// counts the worlds that hold each (`TypeFactsGraph.formDebts`).
enum TypeFactsFormDebt: String, CaseIterable, Sendable {
	/// The declarations answering a read differ in wrapper kind (`Property.PropertyType`): a value beside a lazy wrapper, or
	/// two kinds of wrapper.
	case wrapperKind
	/// The declarations answering a read are of one kind and differ in type.
	case type
}

extension TypeFactsGraph {
	/// The form debts the world's variants split on: for each node, the reads whose keys differ between two of its
	/// variants in a form no parameter carries. Only a test reads it, once per world; it compares each node's variants'
	/// keys read by read, so it costs what the variants' keys hold.
	var formDebts: Set<TypeFactsFormDebt> {
		var keysByNodeAndRead = [DeclarationID: [Set<AnswerID>]]()
		for variant in 0..<VariantID(variantCount) {
			let node = declaration(of: variant)
			let keys = keys(of: variant)
			var keysByRead = keysByNodeAndRead[node] ?? [Set<AnswerID>](repeating: [], count: keys.count)
			for (read, key) in keys.enumerated() {
				keysByRead[read].insert(key)
			}
			keysByNodeAndRead[node] = keysByRead
		}
		var debts = Set<TypeFactsFormDebt>()
		for keysByRead in keysByNodeAndRead.values {
			for keys in keysByRead where keys.count > 1 {
				let keys = keys.sorted()
				for (index, key) in keys.enumerated() {
					for other in keys[(index + 1)...] {
						if let debt = formDebt(between: key, and: other) {
							debts.insert(debt)
						}
					}
				}
			}
		}
		return debts
	}

	/// The form debt that tells two keys of one read apart, or `nil` where a parameter carries their difference or a
	/// difference of another kind (a family, a carrier) keys them.
	private func formDebt(between key: AnswerID, and other: AnswerID) -> TypeFactsFormDebt? {
		let optionalKeys: Set = [Self.optionalParameterKey, Self.optionalLazilyInstantiatedParameterKey, Self.optionalSendableLazilyInstantiatedParameterKey]
		if optionalKeys.contains(key), optionalKeys.contains(other) {
			// Rule 1's keys are one per wrapper kind of the answer: a value or `nil`, and each kind of lazy wrapper.
			return .wrapperKind
		} else if key >= 0, other >= 0, answerProperties[Int(key)] >= 0, answerProperties[Int(other)] >= 0 {
			let property = propertyTable[Int(answerProperties[Int(key)])]
			let otherProperty = propertyTable[Int(answerProperties[Int(other)])]
			if property.propertyType != otherProperty.propertyType {
				return .wrapperKind
			} else if property.typeDescription != otherProperty.typeDescription {
				return .type
			} else {
				return nil
			}
		} else {
			return nil
		}
	}
}
