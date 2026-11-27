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
	/// The world of per-type facts of the roots one validation call is about to walk, built from their scopes before any
	/// is validated, as a report for a test. The scopes are read frozen, as generation reads them once they are validated:
	/// a scope map is complete before its walk, so its records hold before the walk what they hold after it, whether or
	/// not the walk then rejects a tree. Each root is frozen against the map's table, since a mock root's scope is in no
	/// map. A frame is given what the walk makes receivable at its root from outside the tree: what a mock root binds
	/// and what a generated seam's initializer takes.
	///
	/// Only a test asks for it (`ValidationWalkObservation.unvalidatedWorld`): the freeze here is one more than the run
	/// makes, so the tables' observer is not told of it, and what the world interns beyond the records is counted as
	/// `ConstructionInternerMiss.internedForTypeFacts`.
	func unvalidatedWorldReport(ofRootScopes rootScopes: [ValidatedRootScope], typeDescriptionToScopeMap: [TypeDescription: Scope]) -> TypeFactsRootsReport? {
		let frozenScopeMap = ScopeTableObservation.$observer.withValue(nil) {
			FrozenScopeMap(freezing: typeDescriptionToScopeMap.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace)
		}
		let roots = rootScopes.map { rootScope in
			let (table, record) = frozenScopeMap.freezing(rootScope: rootScope.scope)
			return TypeFactsRoot(scope: ConstructionScope(table: table, record: record), givenProperties: rootScope.boundProperties.union(rootScope.receivedFromOutside).sorted())
		}
		let internedCountBefore = internerSpace.internedCount
		let graph = internerSpace.interning(countingMissesIn: .internedForTypeFacts) {
			TypeFactsGraph(roots: roots, intern: internerSpace.intern)
		}
		return graph.map { TypeFactsRootsReport($0, internedCountBefore: internedCountBefore, internedCountAfter: internerSpace.internedCount) }
	}
}
