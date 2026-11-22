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

/// Stage D1's lane B: receives only if available, which a node is passed `nil` where nothing provides them, or the
/// binding in scope that provides them.
extension MockLowering {
	/// Whether a receive only if available of `property` is handed `nil` (`unavailableProperties`) or a binding of `scope`:
	/// the property itself, its non-optional form, or the lazy wrapper whose instance it is.
	static func scope(
		_ scope: Set<Property>,
		provides property: Property,
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
	) -> Bool {
		let unwrappedProperty = property.asUnwrappedProperty
		return unavailableProperties.contains(property)
			|| scope.contains(property)
			|| scope.contains(unwrappedProperty)
			|| lazilyInstantiatedInstanceProperties.contains(unwrappedProperty) && Self.scope(scope, holdsWrapperOfInstance: unwrappedProperty)
	}
}
