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

	/// The slot of `declaration`'s function, or nil where no path closes on it, from the slots made once for its world.
	static func mockEnteredSlot(of declaration: DeclarationID, in slots: MockEnteredSlots) -> MockEnteredSlot? {
		let index = slots.slotIndexByDeclaration[Int(declaration)]
		return index < 0 ? nil : slots.slots[Int(index)]
	}

	/// The nearest name of the configuration `declaration` builds, where it is off every cycle and a slot of that
	/// configuration can be reached beneath it, so that its function enters only that place; nil otherwise.
	static func mockNearestOfTypeEntered(by declaration: DeclarationID, in slots: MockEnteredSlots) -> String? {
		slots.nearestEnteredByDeclaration[Int(declaration)]
	}

	/// Whether `declaration`'s function takes and hands on `__safeDI_entered`: it is on a cycle, enters a place, or lies
	/// between a declaration off every cycle that enters one and a slot beneath it. The root never does.
	static func takesMockEnteredPlaces(_ declaration: DeclarationID, in slots: MockEnteredSlots) -> Bool {
		slots.takesEnteredPlacesByDeclaration[Int(declaration)]
	}
}

/// A mock root's entered slots, the slot of each declaration, the nearest place of its type each declaration off every
/// cycle enters, and which declarations hand the entered places on, made once per world: a writer holds it and reads
/// each declaration's from it (`NodeRecords.mockEnteredSlot(of:in:)`).
///
/// A new place on a cycle takes the configuration of the nearest place of its type on the path, which a declaration
/// off every cycle can be (2.4.0's `AncestorOverridePath.own`), so such a declaration enters that place where a slot
/// of its type can be reached beneath it. "Its type" is its configuration: the concrete type, built the same way
/// (the walk takes no nearest place built with a hand-written mock for one built with its initializer, or the other
/// way round).
///
/// Cost: two passes over the declarations, one walk up from the slots, one walk down from the declarations off every
/// cycle that enter a place, and one walk up per configuration that has a nearest name, each visiting a declaration
/// once. Memory: a few entries per declaration and one per slot, for as long as a caller holds it.
struct MockEnteredSlots: Sendable {
	init(world: some NodeRecordSources) {
		let declarations = 0..<Int32(world.declarationCount)
		// The root is built as no property, so no step returns to it: it has no slot, even where its type is on a cycle.
		let declarationsBuiltAsProperties = declarations.lazy.compactMap { declaration in world.property(of: declaration).map { (declaration, $0) } }
		func configurationBuilt(by declaration: DeclarationID) -> Configuration {
			Configuration(type: world.scope(of: declaration).instantiable.concreteInstantiable, isBuiltWithHandWrittenMock: world.construction(of: declaration) == .handWrittenMock)
		}
		// The identities a path can close on: of each declaration on a cycle that is built as a property.
		var closableIdentities = Set<CycleID>()
		for (declaration, _) in declarationsBuiltAsProperties where world.isOnCycle(declaration) {
			closableIdentities.insert(world.cycle(of: declaration))
		}
		var slotIndexByIdentity = [CycleID: Int32]()
		var slotIndexByDeclarationBeingMade = [Int32](repeating: -1, count: world.declarationCount)
		var labelsAndConfigurations = [(label: String, configuration: Configuration)]()
		// The identities that build each configuration, a twin once: where a slot's configuration is built under another,
		// a new place of the slot reads the nearest of them.
		var identitiesByConfiguration = [Configuration: Set<CycleID>]()
		for (declaration, _) in declarationsBuiltAsProperties {
			identitiesByConfiguration[configurationBuilt(by: declaration), default: []].insert(world.cycle(of: declaration))
		}
		for (declaration, property) in declarationsBuiltAsProperties where closableIdentities.contains(world.cycle(of: declaration)) {
			let identity = world.cycle(of: declaration)
			if let index = slotIndexByIdentity[identity] {
				slotIndexByDeclarationBeingMade[Int(declaration)] = index
			} else {
				let index = Int32(labelsAndConfigurations.count)
				slotIndexByIdentity[identity] = index
				slotIndexByDeclarationBeingMade[Int(declaration)] = index
				labelsAndConfigurations.append((property.label, configurationBuilt(by: declaration)))
			}
		}
		// A label taken by an earlier slot, and a configuration's nearest place, are named by a slot's position, so that
		// no name follows another type's spelling.
		var labelsTaken = Set<String>()
		var nearestNameByConfiguration = [Configuration: String]()
		let slotIndexByDeclaration = slotIndexByDeclarationBeingMade
		let slots = labelsAndConfigurations.enumerated().map { index, labelAndConfiguration in
			let name = labelsTaken.insert(labelAndConfiguration.label).inserted ? labelAndConfiguration.label : "\(ReservedName.builderFunctionNamePrefix)slot\(index)"
			let configuration = labelAndConfiguration.configuration
			let nearestOfTypeSlotName: String? = if identitiesByConfiguration[configuration, default: []].count > 1 {
				nearestNameByConfiguration[configuration, default: "\(ReservedName.builderFunctionNamePrefix)nearest\(index)"]
			} else {
				nil
			}
			nearestNameByConfiguration[configuration] = nearestOfTypeSlotName
			return MockEnteredSlot(name: name, configurationType: configuration.type, nearestOfTypeSlotName: nearestOfTypeSlotName)
		}
		// Each declaration off every cycle whose configuration has a nearest name, and beneath which a slot of that
		// configuration can be reached, enters the nearest place of its type.
		var nearestEnteredByDeclaration = [String?](repeating: nil, count: world.declarationCount)
		for (configuration, name) in nearestNameByConfiguration {
			var isAboveASlotOfConfiguration = [Bool](repeating: false, count: world.declarationCount)
			var pending = declarations.filter { slotIndexByDeclaration[Int($0)] >= 0 && slots[Int(slotIndexByDeclaration[Int($0)])].nearestOfTypeSlotName == name }
			while let declaration = pending.popLast() {
				for parent in world.parents(of: declaration) where !isAboveASlotOfConfiguration[Int(parent.parent)] {
					isAboveASlotOfConfiguration[Int(parent.parent)] = true
					pending.append(parent.parent)
				}
			}
			for (declaration, _) in declarationsBuiltAsProperties where isAboveASlotOfConfiguration[Int(declaration)] && slotIndexByDeclaration[Int(declaration)] < 0 && configurationBuilt(by: declaration) == configuration {
				nearestEnteredByDeclaration[Int(declaration)] = name
			}
		}
		// A declaration hands the places on where it is on a cycle or enters a place, or lies between a declaration off
		// every cycle that enters one and a slot beneath it.
		var isAboveASlot = [Bool](repeating: false, count: world.declarationCount)
		var pendingUp = declarations.filter { slotIndexByDeclaration[Int($0)] >= 0 }
		while let declaration = pendingUp.popLast() {
			for parent in world.parents(of: declaration) where !isAboveASlot[Int(parent.parent)] {
				isAboveASlot[Int(parent.parent)] = true
				pendingUp.append(parent.parent)
			}
		}
		var isBeneathAnEntry = [Bool](repeating: false, count: world.declarationCount)
		var pendingDown = declarations.filter { !world.isOnCycle($0) && (slotIndexByDeclaration[Int($0)] >= 0 || nearestEnteredByDeclaration[Int($0)] != nil) }
		while let declaration = pendingDown.popLast() {
			for child in world.edges(from: declaration) where !isBeneathAnEntry[Int(child)] {
				isBeneathAnEntry[Int(child)] = true
				pendingDown.append(child)
			}
		}
		let nearestEntered = nearestEnteredByDeclaration
		takesEnteredPlacesByDeclaration = declarations.map { declaration in
			declaration != 0 && (world.isOnCycle(declaration)
				|| slotIndexByDeclaration[Int(declaration)] >= 0
				|| nearestEntered[Int(declaration)] != nil
				|| isBeneathAnEntry[Int(declaration)] && isAboveASlot[Int(declaration)])
		}
		self.slots = slots
		self.slotIndexByDeclaration = slotIndexByDeclaration
		self.nearestEnteredByDeclaration = nearestEnteredByDeclaration
	}

	/// In declaration order of each slot's first declaration.
	let slots: [MockEnteredSlot]
	/// By declaration: its slot's position in `slots`, -1 where no path closes on it.
	let slotIndexByDeclaration: [Int32]
	/// By declaration: the nearest name of its configuration where it is off every cycle and enters that place alone.
	let nearestEnteredByDeclaration: [String?]
	/// By declaration: whether its function takes and hands on the entered places.
	let takesEnteredPlacesByDeclaration: [Bool]

	/// A configuration a new place may read: a concrete type, built the one way.
	private struct Configuration: Hashable {
		let type: TypeDescription
		let isBuiltWithHandWrittenMock: Bool
	}
}
