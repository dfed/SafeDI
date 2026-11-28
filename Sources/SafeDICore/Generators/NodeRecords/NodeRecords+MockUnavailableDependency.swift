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
	/// The claim of `declaration`, a node of a mock root's world, as `mockUnavailableDependency` where it stands for a property
	/// instantiated only if available that no declaration fulfills (`ConstructionScope.isUnavailableDependency`): as
	/// production's kind does, it discharges stage 1's refusal of an unavailable dependency, and of a type with no
	/// initializer, since the node builds nothing. `nil` for any other node.
	static func mockUnavailableDependencyClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.scope(of: declaration).isUnavailableDependency else { return nil }
		return NodeRecordClaim(kind: .mockUnavailableDependency, discharges: [.unavailableOrInlineSeam, .noInitializer])
	}

	/// The record of `declaration`'s place, a node of kind `mockUnavailableDependency`: production's record of an
	/// unavailable dependency (`unavailableDependencyRecord(of:in:)`), bound to the override `mock()` takes of the
	/// property where production writes `nil`. `mock()` binds the override before its nodes, under the override's name
	/// (`MockLowering.lowerMockRootWithTree`'s binding lines), so the record reads that name as any value received from
	/// above is read, by capture, wherever the type that declares the property is built. Where the name is the
	/// property's label the record is no place (`isBoundBeforeMockNodes(_:in:)`). Where the override is named apart, the
	/// record binds the label to that name. Where `mock()` takes no override, as of a property declared only inside
	/// `@Sendable` functions, the property is bound to `nil`.
	static func mockUnavailableDependencyRecord(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> AliasPlaceRecord {
		let record = try unavailableDependencyRecord(of: declaration, in: world)
		guard let name = world.mockRootNames.unavailableDependencyOverrideName(of: record.property) else { return record }
		guard name != record.property.label else {
			return AliasPlaceRecord(property: record.property, fulfillingProperty: nil, text: "", reads: [])
		}
		let override = Property(label: name, typeDescription: record.property.typeDescription)
		// The walk binds the property to `nil` inside a `@Sendable` function. No record does: `mock()` takes an override only
		// where a type outside every `@Sendable` function declares the property, the declaration is every declaring type's
		// child, and a node built in a `@Sendable` function shares no child (`mockSendableRefusals(of:in:)`), but one on a
		// cycle, whose world is refused where such a node is built in a `@Sendable` function or beneath one
		// (`checkMockCycles(in:slots:)`). The read is marked, so that the engine refuses the layout should either refusal be
		// lifted.
		var read = PlaceRead(argumentLabel: record.property.label, label: name, property: override, source: .binding(label: name))
		read.staysOutsideSendableFunctions = true
		return AliasPlaceRecord(property: record.property, fulfillingProperty: nil, text: "let \(record.property.asSource) = \(name)", reads: [read])
	}

	/// Whether `declaration`, a node of a mock root's world, is a property nothing fulfills whose override `mock()` binds
	/// before its nodes under the property's own label. That binding is the declaration every type that declares the
	/// property reads, the root among them, so the node is no place of any body: a line that bound the label again would
	/// declare it twice in `mock()`'s body.
	static func isBoundBeforeMockNodes(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		guard world.isMockWorld, world.scope(of: declaration).isUnavailableDependency, let property = world.property(of: declaration) else { return false }
		return world.mockRootNames.unavailableDependencyOverrideName(of: property) == property.label
	}
}
