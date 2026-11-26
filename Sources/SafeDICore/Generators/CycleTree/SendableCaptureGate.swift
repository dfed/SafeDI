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

/// Lets a test compare, for each production root, whether the scopes it reaches name both kinds of wrapper
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

	/// Whether the tree a production root builds can hold a capture of a non-`Sendable` wrapper: whether the scopes it
	/// reaches through the properties they instantiate name both kinds of wrapper (`nameBothWrapperKinds(_:)`). Read from
	/// the scopes alone, before any tree is built, so that a root whose answer is `false` needs no tree of today's for the
	/// walk. Each scope is visited once, from an explicit stack, however many paths reach it.
	static func treeMayCaptureNonSendableWrapper(rootedAt rootScope: Scope) -> Bool {
		var visited: Set<ObjectIdentifier> = [ObjectIdentifier(rootScope)]
		var scopesToVisit = [rootScope]
		var dependencies = [Dependency]()
		while let scope = scopesToVisit.popLast() {
			dependencies.append(contentsOf: scope.instantiable.dependencies)
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate where visited.insert(ObjectIdentifier(childScope)).inserted {
				scopesToVisit.append(childScope)
			}
		}
		return nameBothWrapperKinds(dependencies)
	}
}
