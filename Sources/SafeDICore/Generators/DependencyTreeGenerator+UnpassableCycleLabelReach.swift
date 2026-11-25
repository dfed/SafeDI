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

extension DependencyTreeGenerator {
	/// Whether the tree `rootScope` roots can hold a label no one parameter of a builder function a lazy cycle closes on
	/// can pass (`UnpassableCycleLabel`), read from the scopes alone, once per scope, whatever the number of paths
	/// through them.
	///
	/// `CycleParameter.parameters` finds a label unpassable only among the labels a scope between the function and one
	/// of its cycle-closing scopes declares, and only where the function's body receives the label in two or more
	/// forms: one form is always the parameter's, or the form the parameter was made optional from. Both the declaring
	/// scope and every receiver are scopes of the tree, so a tree none of whose declared labels its scopes receive in
	/// two forms holds no such label, and its generators, which a tree with a dense lazy cycle builds once per path,
	/// need not be built to learn that. An alias receives the property it is fulfilled by, as `ScopeGenerator.receives`
	/// counts it. The answer may be `true` for a tree that holds none: where no cycle
	/// closes around the declaration, or the forms are received on different branches.
	static func canHoldUnpassableCycleLabel(inTreeRootedAt rootScope: Scope) -> Bool {
		var declaredLabels = Set<String>()
		var receivedFormsByLabel = [String: Set<Property>]()
		var visitedScopes: Set<Scope> = [rootScope]
		var scopesToVisit = [rootScope]
		while let scope = scopesToVisit.popLast() {
			declaredLabels.formUnion(scope.declaredLabels)
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case .received:
					receivedFormsByLabel[dependency.property.label, default: []].insert(dependency.property)
				case let .aliased(fulfillingProperty, _, _):
					receivedFormsByLabel[fulfillingProperty.label, default: []].insert(fulfillingProperty)
				case .instantiated,
				     .forwarded:
					break
				}
			}
			for builtScope in scope.propertiesToGenerate.compactMap(\.builtScope) where visitedScopes.insert(builtScope).inserted {
				scopesToVisit.append(builtScope)
			}
		}
		return declaredLabels.contains { (receivedFormsByLabel[$0]?.count ?? 0) > 1 }
	}
}
