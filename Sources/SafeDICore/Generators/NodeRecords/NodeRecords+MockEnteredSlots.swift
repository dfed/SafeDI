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

/// A member of a mock root's entered places: a property of the mock's tree a path can close on, which a step to it
/// returns to the place entered there (the slot form of a mock's cycle).
struct MockEnteredSlot: Hashable, Sendable {
	/// The member of the entered places: the property's label, or a reserved name where an earlier slot already has
	/// that label.
	let name: String
	/// The `T` of `T.SafeDIMockConfiguration`: the concrete type the property builds.
	let configurationType: TypeDescription
	/// The member that holds the nearest place of `configurationType`, set where that type is reached under several
	/// slots: one name per type.
	let nearestOfTypeSlotName: String?
}

extension NodeRecords {
	/// Every property of the mock root's tree a path can close on, a twin once, in declaration order along the tree.
	///
	/// A path closes on a declaration on a cycle: an edge enters it from its own component. Its slot is keyed as cycle
	/// validation keys a cycle (`TypeFactsWorld.cycle(of:)`), so a value and a `LazilyInstantiated` of one label share
	/// one slot, whichever of the two is on the cycle, and a plain and a `@Sendable` builder of one label have two. The
	/// root is built under no property, so no step returns to it.
	static func mockEnteredSlots(in world: some NodeRecordSources) -> [MockEnteredSlot] {
		MockEnteredSlots(world: world).slots
	}

	/// The slot of `declaration`'s function, or nil where no path closes on it.
	static func mockEnteredSlot(of declaration: DeclarationID, in world: some NodeRecordSources) -> MockEnteredSlot? {
		let slots = MockEnteredSlots(world: world)
		let index = slots.slotIndexByDeclaration[Int(declaration)]
		return index < 0 ? nil : slots.slots[Int(index)]
	}

	/// Whether `declaration`'s function is on a cycle, and so takes and hands on `__safeDI_entered`.
	static func takesMockEnteredPlaces(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		world.isOnCycle(declaration)
	}
}

/// A mock root's entered slots and the slot of each declaration, made in one pass over the world's declarations.
///
/// Memory: one entry per declaration and one per slot, for as long as a caller holds it.
struct MockEnteredSlots: Sendable {
	init(world: some NodeRecordSources) {
		let declarations = 0..<Int32(world.declarationCount)
		// The identities a path can close on: of each declaration on a cycle that is built as a property.
		var closableIdentities = Set<CycleID>()
		for declaration in declarations where world.isOnCycle(declaration) && world.property(of: declaration) != nil {
			closableIdentities.insert(world.cycle(of: declaration))
		}
		var slotIndexByIdentity = [CycleID: Int32]()
		var slotIndexByDeclaration = [Int32](repeating: -1, count: world.declarationCount)
		var labelsAndTypes = [(label: String, type: TypeDescription)]()
		for declaration in declarations where closableIdentities.contains(world.cycle(of: declaration)) {
			let identity = world.cycle(of: declaration)
			if let index = slotIndexByIdentity[identity] {
				slotIndexByDeclaration[Int(declaration)] = index
			} else {
				let index = Int32(labelsAndTypes.count)
				slotIndexByIdentity[identity] = index
				slotIndexByDeclaration[Int(declaration)] = index
				// Only a declaration built as a property shares an identity with one on a cycle.
				let label = world.property(of: declaration)?.label ?? ""
				labelsAndTypes.append((label, world.scope(of: declaration).instantiable.concreteInstantiable))
			}
		}
		// A label taken by an earlier slot, and a type reached under several slots, are named by the slot's position,
		// so that no name follows another type's spelling.
		var labelsTaken = Set<String>()
		var slotCountByType = [TypeDescription: Int]()
		for (_, type) in labelsAndTypes {
			slotCountByType[type, default: 0] += 1
		}
		var nearestOfTypeNameByType = [TypeDescription: String]()
		slots = labelsAndTypes.enumerated().map { index, labelAndType in
			let name = labelsTaken.insert(labelAndType.label).inserted ? labelAndType.label : "\(ReservedName.builderFunctionNamePrefix)slot\(index)"
			let nearestOfTypeSlotName: String? = if slotCountByType[labelAndType.type, default: 0] > 1 {
				nearestOfTypeNameByType[labelAndType.type, default: "\(ReservedName.builderFunctionNamePrefix)nearest\(index)"]
			} else {
				nil
			}
			nearestOfTypeNameByType[labelAndType.type] = nearestOfTypeSlotName
			return MockEnteredSlot(name: name, configurationType: labelAndType.type, nearestOfTypeSlotName: nearestOfTypeSlotName)
		}
		self.slotIndexByDeclaration = slotIndexByDeclaration
	}

	/// In declaration order of each slot's first declaration.
	let slots: [MockEnteredSlot]
	/// By declaration: its slot's position in `slots`, -1 where no path closes on it.
	let slotIndexByDeclaration: [Int32]
}
