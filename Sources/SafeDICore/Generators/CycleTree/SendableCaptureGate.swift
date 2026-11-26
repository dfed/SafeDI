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

/// Lets a test compare, for each production root, whether the scopes it reaches let the capture walk run
/// (`DependencyTreeGenerator.treeMayCaptureNonSendableWrapper(rootedAt:)`) with whether the capture walk of today's tree
/// finds anything (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`). Test only.
public enum SendableCaptureGateObservation {
	/// Called with the root's type, whether the gate lets the walk run, and whether today's walk finds a capture.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ gateLetsWalkRun: Bool, _ todaysWalkFindsCapture: Bool) -> Void)?
}

extension DependencyTreeGenerator {
	/// Whether `dependencies` name both a wrapper no `@Sendable` function can capture (`Instantiator`,
	/// `ErasedInstantiator`, `LazilyInstantiated`) and a `Sendable` one. Where they do not, no tree built of the types
	/// that declare them holds a capture `ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)` reports: every
	/// `@Sendable` builder function starts at a property held in a `Sendable` wrapper (one a scope closing a cycle makes
	/// `@Sendable`, `buildsInSendableFunction`, is referred to from inside such a function), and every capture names a
	/// declaration whose property is a wrapper of the other kind, which is some type's dependency.
	static func nameBothWrapperKinds(_ dependencies: some Sequence<Dependency>) -> Bool {
		var namesNonSendableWrapper = false
		var namesSendableWrapper = false
		for dependency in dependencies {
			let propertyType = dependency.property.propertyType
			if propertyType.isSendable {
				namesSendableWrapper = true
			} else if !propertyType.isConstant {
				namesNonSendableWrapper = true
			}
			if namesNonSendableWrapper, namesSendableWrapper {
				return true
			}
		}
		return false
	}

	/// Whether the tree a production root builds can hold a capture of a non-`Sendable` wrapper. Read from the scopes
	/// alone, before any tree is built, so that a root whose answer is `false` needs no tree of today's for the walk
	/// (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`), and whose answer is `true` keeps today's tree.
	///
	/// A capture is a receive inside a `@Sendable` builder function whose label resolves to a non-`Sendable` wrapper
	/// declared outside it: the wrapper itself, or the instance of a `LazilyInstantiated`, both under the wrapper's
	/// label. So the answer is `true` only where a scope that can be built inside a `@Sendable` function receives a label
	/// (directly, or as the property an alias renames) that some dependency of a scope the root reaches has a
	/// non-`Sendable` wrapper type under. A dependency of any source counts, a receive included, since the parameter of a
	/// builder function a lazy cycle closes on is typed by a form its body receives and can be read where every call
	/// passes `nil`. A scope can be built inside a `@Sendable` function only beneath a property held in a `Sendable`
	/// wrapper: a builder function a scope closing a cycle makes `@Sendable` (`buildsInSendableFunction`) is the
	/// function of the scope the closer repeats, which the closer reaches, and the closer is beneath such a property; and
	/// what a call of such a function reads is what its body receives (`CycleParameter`). Each scope is visited once per
	/// walk, from an explicit stack, however many paths reach it.
	static func treeMayCaptureNonSendableWrapper(rootedAt rootScope: Scope) -> Bool {
		var nonSendableWrapperLabels = Set<String>()
		var scopesBuiltInSendableWrappers = [Scope]()
		var visited: Set<ObjectIdentifier> = [ObjectIdentifier(rootScope)]
		var scopesToVisit = [rootScope]
		while let scope = scopesToVisit.popLast() {
			for dependency in scope.instantiable.dependencies {
				let propertyType = dependency.property.propertyType
				if !propertyType.isConstant, !propertyType.isSendable {
					nonSendableWrapperLabels.insert(dependency.property.label)
				}
			}
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
				if property.propertyType.isSendable {
					scopesBuiltInSendableWrappers.append(childScope)
				}
				if visited.insert(ObjectIdentifier(childScope)).inserted {
					scopesToVisit.append(childScope)
				}
			}
		}
		guard !nonSendableWrapperLabels.isEmpty else { return false }
		var visitedInSendableFunction = Set<ObjectIdentifier>()
		scopesToVisit = scopesBuiltInSendableWrappers.filter { visitedInSendableFunction.insert(ObjectIdentifier($0)).inserted }
		while let scope = scopesToVisit.popLast() {
			for dependency in scope.instantiable.dependencies {
				let readLabel: String? = switch dependency.source {
				case .received:
					dependency.property.label
				case let .aliased(fulfillingProperty, _, _):
					fulfillingProperty.label
				case .instantiated, .forwarded:
					nil
				}
				if let readLabel, nonSendableWrapperLabels.contains(readLabel) {
					return true
				}
			}
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate where visitedInSendableFunction.insert(ObjectIdentifier(childScope)).inserted {
				scopesToVisit.append(childScope)
			}
		}
		return false
	}
}
