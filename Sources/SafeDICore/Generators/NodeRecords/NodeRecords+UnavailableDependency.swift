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
	/// The claim of `declaration` as `unavailableDependency` where it stands for a property instantiated only if available
	/// that no declaration fulfills (`ConstructionScope.isUnavailableDependency`): it discharges stage 1's refusal of an
	/// unavailable dependency, and of a type with no initializer, since the node builds nothing. `nil` for any other node,
	/// and for every node of a mock root's world, which reads each node's override.
	static func unavailableDependencyClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard !world.isMockWorld, world.scope(of: declaration).isUnavailableDependency else { return nil }
		return NodeRecordClaim(kind: .unavailableDependency, discharges: [.unavailableOrInlineSeam, .noInitializer])
	}

	/// The record of `declaration`'s place, a node of kind `unavailableDependency`: its property bound to `nil`, which reads
	/// nothing, so the engine copies it as written.
	static func unavailableDependencyRecord(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> AliasPlaceRecord {
		// Never thrown: every node but the root is built as a property, and the root is no unavailable dependency.
		guard let property = world.property(of: declaration) else { throw .noInitializer }
		return AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "let \(property.asSource) = nil", reads: [])
	}
}
