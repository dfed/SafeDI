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
extension NodeRecords {
	/// The refusals of stage 1 a node of a mock root's world discharges where its type instantiates dependencies its scope
	/// does not build (`Scope.instantiatedDependenciesNotGenerated`): `uncoveredDependency` where `mock()` takes each as a
	/// plain value (`MockRootNames.uncoveredParameterName(of:)`), which the node's construction reads by the parameter's
	/// name (`uncoveredArgumentNames(of:in:)`) and every receive beneath reads as the walk routes it
	/// (`mockReceivesBoundAgain(in:)`). A dependency `mock()` takes as a `@Sendable` autoclosure, which the node binds
	/// from it at the top of its function, keeps the refusal, as does a place a seam's own mock builds from its builder.
	static func mockUncoveredDependencyDischarges(of declaration: DeclarationID, in world: some NodeRecordSources) -> Set<NodeRecordRefusal> {
		let uncoveredDependencies = world.scope(of: declaration).instantiatedDependenciesNotGenerated
		guard !uncoveredDependencies.isEmpty else { return [] }
		let placeBindings = mockPlaceBuilderBindings(of: declaration, in: world)
		guard uncoveredDependencies.allSatisfy({ dependency in
			world.mockRootNames.uncoveredParameterName(of: dependency.property) != nil
				|| placeBindings.contains { $0.dependency == dependency.property }
				|| isPlaceMockBindsBeforeItsNodes(dependency, of: declaration, in: world)
		}) else { return [] }
		return [.uncoveredDependency]
	}

	/// The binding of each place of a seam's own mock `declaration`'s type instantiates, from the builder `mock()` takes
	/// for it, in the order the type declares them: the first statements of the node's function, after the receives it
	/// binds again, as the walk writes them (`MockLowering.ConstantNode.receiverBindingLines(indent:)`). None for the
	/// mocked type itself, whose places `mock()` binds before its nodes, and none in a world that builds a node in a
	/// `@Sendable` function, where the builder is `@Sendable` and a record would have to keep its call inside the function.
	static func mockPlaceBuilderBindings(of declaration: DeclarationID, in world: some NodeRecordSources) -> [MockPlaceBuilderBinding] {
		guard world.isMockWorld, declaration != 0 else { return [] }
		let bindings = world.scope(of: declaration).instantiatedDependenciesNotGenerated.compactMap { world.mockRootNames.placeBuilderBinding(of: $0.property) }
		guard !bindings.isEmpty, !worldBuildsNodeInSendableFunction(world) else { return [] }
		return bindings
	}

	/// Whether `dependency` is a place of a seam's own mock that the mocked type itself instantiates, which `mock()` binds
	/// from its builder before its nodes, as a declaration the nodes read. One held in a wrapper is served only where the
	/// mock builds no node, since a node's read of the wrapper's instance is no read of a declaration the records hold.
	private static func isPlaceMockBindsBeforeItsNodes(_ dependency: Dependency, of declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		declaration == 0
			&& world.mockRootNames.placeBuilderBinding(of: dependency.property) != nil
			&& (dependency.property.propertyType.isConstant || world.declarationCount == 1)
	}

	/// Whether `world` builds any node in a `@Sendable` function of its own.
	private static func worldBuildsNodeInSendableFunction(_ world: some NodeRecordSources) -> Bool {
		(0..<Int32(world.declarationCount)).contains { declaration in
			switch world.kind(of: declaration) {
			case .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
				true
			case .constant, .instantiator, .erasedInstantiator, .lazy, .alias, .hole:
				false
			}
		}
	}

	/// The name of the parameter of `mock()` each dependency `declaration`'s type instantiates that its scope does not build
	/// is read by, by the dependency's label, where it is named apart from that label, as the walk passes it
	/// (`MockLowering.argumentValues(of:given:lazilyInstantiatedInstanceProperties:unavailableProperties:bindingNamesPassedByName:uncoveredParameterNames:)`).
	static func uncoveredArgumentNames(of declaration: DeclarationID, in world: some NodeRecordSources) -> [String: String] {
		var names = [String: String]()
		for dependency in world.scope(of: declaration).instantiatedDependenciesNotGenerated {
			let name = world.mockRootNames.uncoveredParameterName(of: dependency.property) ?? world.mockRootNames.placeBuilderBinding(of: dependency.property)?.property.label
			guard let name, name != dependency.property.label else { continue }
			names[dependency.property.label] = name
		}
		return names
	}
}
