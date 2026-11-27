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
		guard !uncoveredDependencies.isEmpty, uncoveredDependencies.allSatisfy({ world.mockRootNames.uncoveredParameterName(of: $0.property) != nil }) else { return [] }
		return [.uncoveredDependency]
	}

	/// The name of the parameter of `mock()` each dependency `declaration`'s type instantiates that its scope does not build
	/// is read by, by the dependency's label, where it is named apart from that label, as the walk passes it
	/// (`MockLowering.argumentValues(of:given:lazilyInstantiatedInstanceProperties:unavailableProperties:bindingNamesPassedByName:uncoveredParameterNames:)`).
	static func uncoveredArgumentNames(of declaration: DeclarationID, in world: some NodeRecordSources) -> [String: String] {
		var names = [String: String]()
		for dependency in world.scope(of: declaration).instantiatedDependenciesNotGenerated {
			guard let name = world.mockRootNames.uncoveredParameterName(of: dependency.property), name != dependency.property.label else { continue }
			names[dependency.property.label] = name
		}
		return names
	}
}
