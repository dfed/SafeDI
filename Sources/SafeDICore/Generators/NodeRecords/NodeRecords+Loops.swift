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
	/// The refusals of `declaration` as a member of a loop of builders, whatever kind claims it: a member two parents'
	/// loops make different members of again, which would need a function per parent where a record is a function of the
	/// node; a member whose loop step 0 finds that makes nothing again, which the stand-in for its loops does not see; a
	/// mock world's member of a shape whose configurations these records do not hand yet
	/// (`mockLoopRefusesNothing(ofMember:in:)`); and a
	/// `@Sendable` member that captures a member's wrapper that is not `Sendable`, which the tree reports.
	static func loopRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		guard !world.loopMembersSharedApart.contains(declaration) else { return [.builderLoopSharedApart] }
		let isUnseenMember = zip(world.edges(from: declaration), world.edgeFacts(from: declaration)).contains { child, edge in
			edge.loop >= 0 && world.madeAgain(from: child).isEmpty && !world.loopMembersSharedApart.contains(child)
		}
		let madeAgain = world.madeAgain(from: declaration)
		let isMockMember = isMockLoopMember(declaration, in: world) && !mockLoopRefusesNothing(ofMember: declaration, in: world)
		// A rebinding names the member's function, so it captures that member's wrapper: a `@Sendable` member that makes a
		// member again that is not `Sendable` captures it, the error the tree reports (`nonSendableWrapperCaptures`).
		let capturesWrapper = world.property(of: declaration)?.propertyType.isSendable == true && madeAgain.contains { member in
			world.property(of: member)?.propertyType.isSendable == false
		}
		return (isUnseenMember || isMockMember ? [.builderLoop] : []) + (capturesWrapper ? [.sendableFunctionCapturesWrapper] : [])
	}

	/// Whether `member`, a member of a loop of builders in a mock root's world, reads its override where the root's body
	/// declares its function and is handed nothing: only the root builds it, it hands no configuration to its children,
	/// and its function is not `@Sendable` (`mockOverrideSlot(of:labeled:typed:in:hasFunction:handsOverridesToChildren:isSendable:)`),
	/// so a rebinding of it inside another member's function calls it as the root's body does.
	static func mockLoopMemberTakesNothing(_ member: DeclarationID, in world: some NodeRecordSources) -> Bool {
		// A `@Sendable` function the root's body declares captures the local its override is read into
		// (`NodeRecords+MockSendable.swift`).
		world.parents(of: member).allSatisfy { $0.parent == 0 }
			&& (world.property(of: member)?.propertyType.isSendable == true || !isConfiguredMockNode(member, in: world))
	}

	/// Whether the loop of builders `member` belongs to, in a mock root's world, is of a shape these records make: every
	/// member at its level is handed nothing (`mockLoopMemberTakesNothing(_:in:)`), or no level that builds a member is on
	/// a cycle, every level that builds one member of the loop builds every member and reads the overrides it hands it
	/// alike, its members are all `@Sendable` or none is (`@Sendable` members take their level's overrides in a `Sendable`
	/// struct, `MockLoopLevels.sendableStructByLevel`), none builds a property nothing fulfills, whose override a member's
	/// function would take beside its own, and none is a call of another module's public mock, whose function takes no
	/// level's configuration.
	static func mockLoopRefusesNothing(ofMember member: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let members = mockLoopMembers(atLevelOf: member, in: world)
		// A member erased to another type is made again of its concrete type's function, whose rebinding these records
		// do not erase yet; and a member promoted for an optional receive is bound non-optional, which its rebinding would
		// annotate optional.
		guard !members.contains(where: { member in
			world.isErased(member) || world.property(of: member).map { $0.asUnwrappedProperty != $0 } == true
		}) else { return false }
		guard !members.allSatisfy({ mockLoopMemberTakesNothing($0, in: world) }) else { return true }
		// A level on a cycle of the mock is entered again with another configuration, which its members' level argument
		// would not follow.
		let level = world.parents(of: member).first?.parent ?? 0
		guard level == 0 || !world.isOnCycle(level) else { return false }
		// A member another level builds too has one function, whose level's argument is typed as the loop's home level's
		// (`MockLoopLevels.homeLevelByMember`), so every level that builds a member hands it the members' fields of its own
		// overrides, and must build each member and read those overrides alike at each. A member that makes only itself
		// again takes no level (`mockLoopLevels(in:)`), so any level builds it. Each loop's members are found once, and
		// each level's edges are one set, both dying with this check, so a level costs its members times their parents.
		// The overrides are compared as the paths each level reads them by, which agree only because every level's
		// function takes its overrides under one name (`ReservedName.mockOverridesParameterName`): a level whose
		// configuration were named apart would be refused here.
		let overrides = mockOverridesOfChildren(of: level, in: world, slots: nil)
		var componentByMember = [DeclarationID: Set<DeclarationID>]()
		var edgesByLevel = [DeclarationID: Set<DeclarationID>]()
		for member in members where world.madeAgain(from: member) != [member] {
			let component: Set<DeclarationID>
			if let found = componentByMember[member] {
				component = found
			} else {
				component = Set(mockLoopComponent(of: member, in: world))
				for componentMember in component {
					componentByMember[componentMember] = component
				}
			}
			for parent in world.parents(of: member) {
				guard parent.parent == 0 || !world.isOnCycle(parent.parent),
				      mockOverridesOfChildren(of: parent.parent, in: world, slots: nil) == overrides
				else { return false }
				let edges = edgesByLevel[parent.parent] ?? Set(world.edges(from: parent.parent))
				edgesByLevel[parent.parent] = edges
				guard component.isSubset(of: edges) else { return false }
			}
		}
		// A loop of `@Sendable` members and members that are not would hand one struct to functions of both kinds.
		let sendableMembers = members.count { world.property(of: $0)?.propertyType.isSendable == true }
		guard sendableMembers == 0 || sendableMembers == members.count else { return false }
		return members.allSatisfy { member in
			world.scope(of: member).publicMockCall == nil
				&& !buildsUnavailableDependency(beneath: member, in: world)
		}
	}

	/// The members of loops of builders in a mock root's world that `member` makes again or is made again by, each in turn,
	/// in declaration order: the members one level's argument passes between, which take one type of it.
	static func mockLoopComponent(of member: DeclarationID, in world: some NodeRecordSources) -> [DeclarationID] {
		var component: Set<DeclarationID> = [member]
		var stack = [member]
		while let next = stack.popLast() {
			var neighbors = Array(world.madeAgain(from: next))
			for parent in world.parents(of: next) {
				neighbors.append(contentsOf: world.edges(from: parent.parent).filter { world.madeAgain(from: $0).contains(next) })
			}
			for neighbor in neighbors where component.insert(neighbor).inserted {
				stack.append(neighbor)
			}
		}
		return component.sorted()
	}

	/// The members of loops of builders at the level that builds `member`, in the order the level builds them.
	static func mockLoopMembers(atLevelOf member: DeclarationID, in world: some NodeRecordSources) -> [DeclarationID] {
		let level = world.parents(of: member).first?.parent ?? 0
		return world.edges(from: level).filter { isMockLoopMember($0, in: world) }
	}

	/// Whether a node in `declaration`'s tree builds a property nothing fulfills, whose override `mock()` hands down as an
	/// argument of its own (`NodeRecords+MockUnavailableDependency.swift`).
	private static func buildsUnavailableDependency(beneath declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		var stack = Array(world.edges(from: declaration))
		var visited = Set<DeclarationID>()
		while let next = stack.popLast() {
			guard visited.insert(next).inserted else { continue }
			guard !world.scope(of: next).isUnavailableDependency else { return true }
			stack.append(contentsOf: world.edges(from: next))
		}
		return false
	}

	/// Which members of a mock root's loops of builders take their level's overrides, and the name each level's argument
	/// is passed under. Computed once per world (`NodeRecords.init`), and holding only declaration IDs and names, for as
	/// long as the world's records are made.
	struct MockLoopLevels: Sendable {
		/// The members whose functions take their level's overrides: each makes again a member that takes its own
		/// overrides or its level's, so that a member that hands nothing keeps the walk's bytes.
		var takingLevel = Set<DeclarationID>()
		/// The level whose overrides' type each member taking its level's overrides takes them as: the first of the levels
		/// that build a member of its loop (`mockLoopComponent(of:in:)`), so that every member of a loop takes one type,
		/// which another level hands a value of made of its own overrides' fields (`mockLoopLevelArgument(of:in:levels:slots:)`).
		var homeLevelByMember = [DeclarationID: DeclarationID]()
		/// The members of each member's loop, for the fields another level hands.
		var componentByMember = [DeclarationID: [DeclarationID]]()
		/// The name each home level's argument is passed under, `__safeDI_<LevelType>_loopConfiguration`, claimed apart
		/// from every builder function name of the world and from the names of the levels claimed before it.
		var parameterNameByLevel = [DeclarationID: String]()
		/// The struct each home level of a loop of `@Sendable` members hands them in its configuration's place, which is
		/// not `Sendable`: one per level, holding each member's override, so that a loop of k members spells k fields.
		var sendableStructByLevel = [DeclarationID: SendableLoopStruct]()
	}

	/// A `Sendable` struct `mock()` declares for a loop of `@Sendable` members: each member's override, a `@Sendable`
	/// closure or a configuration of the `Sendable` form, under the member's label. Every level that builds the members
	/// binds one, made of the locals it reads the members' overrides into (`mockLoopSendableStructBindings(atLevel:in:levels:)`),
	/// and hands it to each member's function, which hands it on.
	struct SendableLoopStruct: Sendable {
		/// The struct's name, claimed apart from every builder function name of the world and every level's argument.
		let typeName: String
		/// The name each level binds it under, and each member's function takes it by: the home level's argument's.
		let parameterName: String
		/// A field for each member whose function takes overrides, in the home level's order.
		let fields: [Field]

		/// A member's override: the member's label and the type of its override.
		struct Field: Sendable {
			let member: DeclarationID
			let label: String
			let type: TypeDescription
		}

		/// The struct's type.
		var type: TypeDescription {
			.simple(name: typeName)
		}

		/// The struct's declaration, its lines unindented.
		var declaration: [String] {
			["nonisolated struct \(typeName): Sendable {"]
				+ fields.map { "\(ScopeGenerator.standardIndent)let \($0.label.spelledAsMemberDeclarationName): \($0.type.asSource)" }
				+ ["}"]
		}
	}

	/// The members of `world`'s loops of builders that take their level's overrides (`MockLoopLevels`), a least fixed
	/// point over the members, and their levels' names, claimed in declaration order.
	static func mockLoopLevels(in world: some NodeRecordSources) -> MockLoopLevels {
		var levels = MockLoopLevels()
		guard world.isMockWorld else { return levels }
		let members = (0..<world.declarationCount).map { DeclarationID($0) }.filter { isMockLoopMember($0, in: world) }
		guard !members.isEmpty else { return levels }
		var changed = true
		while changed {
			changed = false
			// A member that makes again only itself hands its rebinding its own overrides (`loopRebindings(of:in:mockLoopLevels:ownFunctionArguments:enteredSlots:)`),
			// so it takes no level, whichever levels build it.
			for member in members where !levels.takingLevel.contains(member) && world.madeAgain(from: member) != [member] {
				let makesAgainMemberTakingOverrides = world.madeAgain(from: member).contains { madeAgain in
					!mockLoopMemberTakesNothing(madeAgain, in: world) || levels.takingLevel.contains(madeAgain)
				}
				guard makesAgainMemberTakingOverrides else { continue }
				levels.takingLevel.insert(member)
				changed = true
			}
		}
		var names = GeneratedNameAllocator(reserving: Set((0..<world.declarationCount).compactMap { declaration in
			world.property(of: DeclarationID(declaration)).map { ScopeGenerator.functionName(toBuildPropertyNamed: $0.label) }
		}))
		var sendableHomes = [DeclarationID: String]()
		for member in members where levels.takingLevel.contains(member) {
			if levels.homeLevelByMember[member] == nil {
				let component = mockLoopComponent(of: member, in: world)
				let home = component.flatMap { world.parents(of: $0).map(\.parent) }.min() ?? 0
				for componentMember in component {
					levels.homeLevelByMember[componentMember] = home
					levels.componentByMember[componentMember] = component
				}
			}
			guard let level = levels.homeLevelByMember[member], levels.parameterNameByLevel[level] == nil else { continue }
			let typeIdentifier = world.scope(of: level).instantiable.concreteInstantiable.asIdentifier
			let parameterName = names.claim(ReservedName.loopLevelConfigurationParameterName(ofTypeIdentifier: typeIdentifier))
			levels.parameterNameByLevel[level] = parameterName
			// The members at one level are all `@Sendable` or none is (`mockLoopRefusesNothing(ofMember:in:)`).
			if world.property(of: member)?.propertyType.isSendable == true {
				sendableHomes[level] = parameterName
			}
		}
		// Each home level of `@Sendable` members, once every loop's home is known, in declaration order.
		for (level, parameterName) in sendableHomes.sorted(by: { $0.key < $1.key }) {
			let typeIdentifier = world.scope(of: level).instantiable.concreteInstantiable.asIdentifier
			var fields = [SendableLoopStruct.Field]()
			for member in world.edges(from: level) where levels.homeLevelByMember[member] == level {
				if let property = world.property(of: member), let type = mockLoopOverridesType(of: member, in: world) {
					fields.append(SendableLoopStruct.Field(member: member, label: property.label, type: type))
				}
			}
			levels.sendableStructByLevel[level] = SendableLoopStruct(
				typeName: names.claim(ReservedName.sendableLoopOverridesTypeName(ofTypeIdentifier: typeIdentifier)),
				parameterName: parameterName,
				fields: fields,
			)
		}
		return levels
	}

	/// The passed argument under which the function of `member`, a member of a loop of builders in a mock root's world,
	/// takes the overrides of its loop's level, so that it can hand each member it makes again that member's field of them:
	/// the configuration its level's children read, or `mock()`'s own at the root, read where the level builds the member.
	/// `nil` where `member` makes again no member that takes overrides (`MockLoopLevels.takingLevel`), whose function then
	/// reads its override as the root's body does.
	static func mockLoopLevelArgument(of member: DeclarationID, in world: some NodeRecordSources, levels: MockLoopLevels, slots: MockEnteredSlots?) -> PassedArgument? {
		guard levels.takingLevel.contains(member),
		      let home = levels.homeLevelByMember[member],
		      let parameterName = levels.parameterNameByLevel[home]
		else { return nil }
		// `@Sendable` members are handed the struct their level binds (`mockLoopSendableStructBindings(atLevel:in:levels:)`).
		if let sendableStruct = levels.sendableStructByLevel[home] {
			return PassedArgument(parameterName: parameterName, type: sendableStruct.type, value: .read(sendableStructLocal(named: parameterName, typed: sendableStruct.type)), staysOutsideSendableFunctions: false)
		}
		let type = mockLoopLevelType(of: home, in: world)
		let parents = world.parents(of: member)
		// Every level that builds the member reads these overrides alike (`mockLoopRefusesNothing(ofMember:in:)`).
		let overrides = mockOverridesOfChildren(of: parents.first?.parent ?? 0, in: world, slots: slots)
		// One value serves every call of the member's function, and every level builds every member of the loop, so where
		// any level is of another type, the home level too hands the value made of its fields rather than its overrides.
		let value: ValuePath
		if parents.allSatisfy({ mockLoopLevelType(of: $0.parent, in: world) == type }) {
			value = overrides
		} else {
			// A level of another type hands a value of the home level's type made of its own fields for the loop's members,
			// in the home level's order, every other field taking its default: the members' functions read only those.
			let component = Set(levels.componentByMember[member] ?? [])
			let fields = world.edges(from: home).filter { component.contains($0) && mockLoopOverridesType(of: $0, in: world) != nil }.compactMap(world.property(of:))
			// Spelled `.init(<label>: overrides.<label>, …)`.
			var segments: [ValueSegment] = [.text(".init(")]
			for (index, field) in fields.enumerated() {
				segments.append(.text("\(index == 0 ? "" : ", ")\(field.label.spelledAsArgumentLabel): "))
				segments.append(.value(.member(field.label.spelledAsMemberDeclarationName, of: overrides)))
			}
			segments.append(.text(")"))
			value = .spliced(segments)
		}
		return PassedArgument(parameterName: parameterName, type: type, value: value, staysOutsideSendableFunctions: true)
	}

	/// The local a level binds the struct it hands a loop's `@Sendable` members to, named as their functions take it.
	private static func sendableStructLocal(named name: String, typed type: TypeDescription) -> PlaceRead {
		PlaceRead(argumentLabel: name, label: name, property: Property(label: name, typeDescription: type), source: .binding(label: name))
	}

	/// The places `level` binds, after the locals of its loop members' overrides, the struct of each loop of `@Sendable`
	/// members it builds to (`MockLoopLevels.sendableStructByLevel`): `<Struct>(<label>: <the member's local>, …)`, read once
	/// and handed to every member's function, so that the level spells each member's override once.
	static func mockLoopSendableStructBindings(atLevel level: DeclarationID, in world: some NodeRecordSources, levels: MockLoopLevels) -> [BuiltPlaceRecord] {
		var homes = Set<DeclarationID>()
		var structs = [SendableLoopStruct]()
		for member in world.edges(from: level) {
			if let home = levels.homeLevelByMember[member], let sendableStruct = levels.sendableStructByLevel[home], homes.insert(home).inserted {
				structs.append(sendableStruct)
			}
		}
		return structs.map { sendableStruct in
			var segments: [ValueSegment] = [.text("\(sendableStruct.typeName)(")]
			for (index, field) in sendableStruct.fields.enumerated() {
				segments.append(.text("\(index == 0 ? "" : ", ")\(field.label.spelledAsArgumentLabel): "))
				segments.append(.value(.read(mockOverridesLocal(ofNodeLabeled: field.label, typed: field.type, isConfigured: isConfigured(field.member, in: world)))))
			}
			segments.append(.text(")"))
			let local = sendableStructLocal(named: sendableStruct.parameterName, typed: sendableStruct.type)
			var binding = BuiltPlaceRecord(
				property: local.property,
				isErased: false,
				concreteType: sendableStruct.type,
				isExtension: false,
				target: .initializer(sendableStruct.type),
				arguments: [],
				forwardedProperties: [],
				cycleParameters: [],
				callCycleArguments: [],
				functionName: sendableStruct.parameterName,
				isSendable: false,
				typesDeclaredEscaping: [],
				lineEnd: "",
				hasFunction: false,
				children: [],
				node: PlanNode(),
			)
			binding.constructionValue = ConstructionValue(value: .spliced(segments), resultWrapper: nil)
			return binding
		}
	}

	/// The type of the overrides `level` hands the members of its loops of builders: `mock()`'s own at the root, else the
	/// level's configuration.
	private static func mockLoopLevelType(of level: DeclarationID, in world: some NodeRecordSources) -> TypeDescription {
		level == 0 ? .simple(name: ReservedName.mockOverridesTypeName) : mockConfigurationType(of: world.scope(of: level).instantiable)
	}

	/// What a rebinding of `member` inside another member's function hands `member`'s function, where the members take
	/// their level's overrides (`mockLoopLevelArgument(of:in:levels:slots:)`): `member`'s own overrides, its field of the level's,
	/// where its function takes them, then the level's, where its function takes that.
	private static func mockLoopRebindingArguments(of member: DeclarationID, level: PassedArgument, in world: some NodeRecordSources, levels: MockLoopLevels) -> [PassedArgument] {
		var arguments = [PassedArgument]()
		// A level's configuration is not `Sendable`; the struct a loop of `@Sendable` members is handed is.
		let staysOutsideSendableFunctions = level.staysOutsideSendableFunctions
		if let property = world.property(of: member), let type = mockLoopOverridesType(of: member, in: world) {
			arguments.append(PassedArgument(
				parameterName: ReservedName.mockOverridesParameterName,
				type: type,
				value: .member(property.label, of: .passedArgument(level.parameterName)),
				staysOutsideSendableFunctions: staysOutsideSendableFunctions,
			))
		}
		if levels.takingLevel.contains(member) {
			arguments.append(PassedArgument(parameterName: level.parameterName, type: level.type, value: .passedArgument(level.parameterName), staysOutsideSendableFunctions: staysOutsideSendableFunctions))
		}
		return arguments
	}

	/// The type of the overrides the function of `member`, a member of a loop of builders in a mock root's world, takes:
	/// its configuration, or its override closure where it reads no configuration, `@Sendable` for a `@Sendable` member, as
	/// the local its level reads it into is typed (`mockOverrideType(of:usesHandWrittenMock:isConfigured:isSendable:instantiable:)`).
	/// `nil` where its function is handed nothing (`mockLoopMemberTakesNothing(_:in:)`).
	private static func mockLoopOverridesType(of member: DeclarationID, in world: some NodeRecordSources) -> TypeDescription? {
		guard !mockLoopMemberTakesNothing(member, in: world), let property = world.property(of: member) else { return nil }
		let instantiable = world.scope(of: member).instantiable
		let usesHandWrittenMock = world.construction(of: member) == .handWrittenMock && instantiable.mockInitializer != nil
		return isConfigured(member, in: world)
			? mockConfigurationType(of: instantiable)
			: .unknown(text: "(\(property.propertyType.isSendable ? "@Sendable " : "")(\(MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesHandWrittenMock).spelled)) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource))?")
	}

	/// Whether `declaration` is a member of a loop of builders in a mock root's world: its function makes another member
	/// again, or a sibling's function makes it again.
	static func isMockLoopMember(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		guard world.isMockWorld else { return false }
		guard world.madeAgain(from: declaration).isEmpty else { return true }
		return world.parents(of: declaration).contains { parent in
			world.edges(from: parent.parent).contains { world.madeAgain(from: $0).contains(declaration) }
		}
	}

	/// The places `declaration`'s builder function begins with, before every child: a wrapper made again of each member of
	/// its loop it rebinds, in the order it rebinds them, each a call of that member's builder function
	/// (`ClosingPlaceRecord.rebindsLoopMember`). The rebinding names only the member's declaration, its label and type, so
	/// every variant of `declaration` rebinds alike (oracle B, check 32 of the per-type facts' checks).
	/// - Parameter ownFunctionArguments: What a call of `declaration`'s own function hands it, which a member that makes only
	///   itself again hands its rebinding of itself, under the names its function takes them by.
	static func loopRebindings(of declaration: DeclarationID, in world: some NodeRecordSources, mockLoopLevels: MockLoopLevels = MockLoopLevels(), ownFunctionArguments: [PassedArgument] = [], enteredSlots: MockEnteredSlots? = nil) -> [GeneratedCode] {
		// In a mock, each rebinding hands the member's function what the member's level hands it.
		let level = mockLoopLevelArgument(of: declaration, in: world, levels: mockLoopLevels, slots: enteredSlots)
		return world.madeAgain(from: declaration).compactMap { member in
			guard let property = world.property(of: member) else { return nil }
			let instantiable = world.scope(of: member).instantiable
			var closer = ClosingPlaceRecord(
				property: property,
				isErased: world.isErased(member),
				isExtension: instantiable.declarationType.isExtension,
				closedOnFunctionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
				forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
				cycleArguments: [],
				rebindsLoopMember: true,
			)
			if let level {
				closer.passedArguments = mockLoopRebindingArguments(of: member, level: level, in: world, levels: mockLoopLevels)
			} else if member == declaration {
				// A member that makes only itself again hands the rebinding what its own function was handed, under the names
				// the function takes it by, which the walk's copy of the function reads at whichever level built it. A
				// function that captures its overrides takes nothing.
				closer.passedArguments = ownFunctionArguments.map { argument in
					PassedArgument(parameterName: argument.parameterName, type: argument.type, value: .passedArgument(argument.parameterName), staysOutsideSendableFunctions: argument.staysOutsideSendableFunctions)
				}
			}
			return .indented(.place(PlacePlan(code: .empty, record: .closer(closer))), by: ScopeGenerator.standardIndent)
		}
	}
}
