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

/// Stage D1's lane B: loops of builders (`ReceivedBuilderLoops` in `cycle-generation.md`). Each member's builder function
/// first rebinds the wrappers of the members its tree receives, and the members of one loop, consecutive at their level,
/// are emitted as one unit: every member's locals, then every function, then every binding, since each function names
/// the others'.
extension MockLowering {
	/// The loop of builders a child is a member of, among its level's children.
	struct LoopMembership: Equatable {
		/// The loop, named by the index of its first member among the children.
		let loop: Int
		/// Whether the child's wrapper is read outside its loop, so its level binds it.
		let declaresBinding: Bool
	}

	/// A member of a loop of builders, as the functions of its loop rebind it.
	struct LoopMember {
		/// The member's wrapper type.
		let typeDescription: TypeDescription
		/// The name the member's wrappers made again are bound under.
		let bindingName: String
		/// For a rename the level declares of a member, the rename as it is bound, wrapping the member's function: its
		/// binding name and its own type.
		let rename: Property?
		/// The name of the function every wrapper of the member that its level makes hands: its builder function, or the
		/// `_received` function that calls it where it takes parameters a lazy cycle needs.
		let functionName: String
		/// The name of the member's builder function, or of the function a cycle-closing member closes on.
		let builderFunctionName: String
		/// The `_received` function of a member whose builder function takes parameters a lazy cycle needs.
		let receivedFunctionName: String?
		/// The properties the member's type forwards, in the order its wrapper hands them.
		let forwardedProperties: [Property]
		/// The parameters of the member's builder function that a lazy cycle needs.
		let cycleParameters: [Property]
	}

	/// The lines of the loop of builders being emitted at a level, which the level appends when the loop ends.
	struct LoopUnit {
		let loop: Int
		var prelude = [String]()
		var functions = [String]()
		var bindings = [String]()

		var lines: [String] {
			prelude + functions + bindings
		}
	}

	/// How the lines a loop member appended split: the locals before its function, and the binding after it.
	struct LoopMemberLineCounts {
		let prelude: Int
		let binding: Int
	}

	/// The members of the loops among `generators`, the children of one level, by property, where `loops` holds each
	/// child's loop: the property nodes, whose functions the members' functions rebind. A member whose builder function
	/// takes parameters a lazy cycle needs is wrapped through `__safeDI_<label>_received`, named apart from the level's
	/// builder functions, `namesInScope`, and the builder functions, and their `_received` names, of each member's level,
	/// as the emitter names it (`loopMemberEmissions`).
	///
	/// A rename the level declares of a member (`isLoopBuilder(amongSiblings:)`) is a member too, under its own property,
	/// bound under `bindingNames`' entry, wrapping the member's function, as the emitter declares it.
	static func loopMembers(among generators: [ScopeGenerator], loops: [LoopMembership?], bindingNames: [String?], namesInScope: Set<String>) -> [Property: LoopMember] {
		var reservedNames = namesInScope
		var memberGenerators = [(generator: ScopeGenerator, bindingName: String?)]()
		for (index, (generator, membership)) in zip(generators, loops).enumerated() where membership != nil {
			memberGenerators.append((generator, index < bindingNames.count ? bindingNames[index] : nil))
		}
		for (index, generator) in generators.enumerated() {
			guard case let .property(_, property, _, _, isPropertyCycle, _) = generator.scopeData, !isPropertyCycle else { continue }
			// A node named apart is built by the function its name gives.
			reservedNames.insert(MockLowering.builderFunctionName(boundAs: (index < bindingNames.count ? bindingNames[index] : nil) ?? property.label))
		}
		for (member, _) in memberGenerators {
			for child in member.orderedChildGenerators {
				guard case let .property(_, property, _, _, isPropertyCycle, _) = child.scopeData, !isPropertyCycle else { continue }
				let functionName = ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
				reservedNames.insert(functionName)
				reservedNames.insert(ReservedName.receivedBuilderFunctionName(of: functionName))
			}
		}
		var names = GeneratedNameAllocator(reserving: reservedNames)
		var members = [Property: LoopMember]()
		for (generator, bindingName) in memberGenerators {
			guard case let .property(instantiable, property, _, _, _, _) = generator.scopeData else { continue }
			// A member named apart from a sibling of its label is bound again, and built, under its name.
			let bindingName = bindingName ?? property.label
			let builderFunctionName = MockLowering.builderFunctionName(boundAs: bindingName)
			let receivedFunctionName = generator.cycleParameters.isEmpty ? nil : names.claim(ReservedName.receivedBuilderFunctionName(of: builderFunctionName))
			members[property] = LoopMember(
				typeDescription: property.typeDescription,
				bindingName: bindingName,
				rename: nil,
				functionName: receivedFunctionName ?? builderFunctionName,
				builderFunctionName: builderFunctionName,
				receivedFunctionName: receivedFunctionName,
				forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
				cycleParameters: generator.cycleParameters.map(\.property),
			)
		}
		for (index, generator) in generators.enumerated() where index < loops.count && loops[index] != nil {
			guard case let .alias(property, fulfillingProperty, false, _, _) = generator.scopeData,
			      let member = members[fulfillingProperty]
			else { continue }
			let bindingName = (index < bindingNames.count ? bindingNames[index] : nil) ?? property.label
			members[property] = LoopMember(
				typeDescription: member.typeDescription,
				bindingName: bindingName,
				rename: Property(label: bindingName, typeDescription: property.typeDescription),
				functionName: member.functionName,
				builderFunctionName: member.builderFunctionName,
				receivedFunctionName: nil,
				forwardedProperties: member.forwardedProperties,
				cycleParameters: [],
			)
		}
		return members
	}

	/// The lines, at `indent`, that bind `member`'s wrapper again, handing `functionName` called with its forwarded
	/// properties and `cycleParameterArguments`: under its binding name, or, for a rename, as the rename's own type.
	static func memberBindingLines(of member: LoopMember, handing functionName: String, cycleParameterArguments: [String] = [], indent: String) -> [String] {
		wrapperBindingLines(
			of: member.typeDescription,
			named: member.bindingName,
			declaredAs: member.rename,
			handing: functionName,
			forwardedProperties: member.forwardedProperties,
			cycleParameterArguments: cycleParameterArguments,
			indent: indent,
		)
	}

	/// The lines that begin a loop member's builder function, at `indent`: a binding of each of `reboundProperties`, the
	/// members of `members` its tree receives, wrapping that member's function, the member `ownProperty` names its own
	/// builder function with its own cycle parameters.
	static func rebindingLines(of reboundProperties: [Property], among members: [Property: LoopMember], ownProperty: Property, indent: String) -> [String] {
		var lines = [String]()
		for (property, member) in reboundProperties.compactMap({ property in members[property].map { (property, $0) } }) {
			let isOwnWithCycleParameters = property == ownProperty && member.receivedFunctionName != nil
			lines.append(contentsOf: memberBindingLines(
				of: member,
				handing: isOwnWithCycleParameters ? member.builderFunctionName : member.functionName,
				cycleParameterArguments: isOwnWithCycleParameters ? member.cycleParameters.map { "\($0.label.spelledAsArgumentLabel): \($0.label)" } : [],
				indent: indent,
			))
		}
		return lines
	}

	/// The `_received` function of `member`, the member `property` names, declared at `indent`: it takes the member's
	/// forwarded properties and calls its builder function with them and `cycleParameterArguments`, wrapping again each
	/// member of `members` that an argument names, which it passes instead.
	static func receivedFunctionLines(
		of member: LoopMember,
		property: Property,
		cycleParameterArguments: [String],
		among members: [Property: LoopMember],
		typesDeclaredEscaping: Set<TypeDescription>,
		isSendable: Bool,
		indent: String,
	) -> [String] {
		guard let receivedFunctionName = member.receivedFunctionName else { return [] }
		let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
		var memberLines = [String]()
		let cycleArguments = zip(member.cycleParameters, cycleParameterArguments).map { parameter, argument in
			// A level declares each label once, so at most one of the two forms is a member.
			let unwrappedProperty = parameter.asUnwrappedProperty
			let memberProperty = members[unwrappedProperty] != nil ? unwrappedProperty : unwrappedProperty.asOptionalProperty
			guard let argumentMember = members[memberProperty] else { return argument }
			memberLines.append(contentsOf: memberBindingLines(of: argumentMember, handing: argumentMember.functionName, indent: bodyIndent))
			return "\(parameter.label.spelledAsArgumentLabel): \(argumentMember.bindingName)"
		}
		let parameters = member.forwardedProperties.isEmpty ? "" : member.forwardedProperties.initializerFunctionParametersSource(amongTypesDeclaredEscaping: typesDeclaredEscaping)
		let callArguments = member.forwardedProperties.map { "\($0.label.spelledAsArgumentLabel): \($0.label)" } + cycleArguments
		let decorator = ScopeGenerator.localFunctionPrefix(isSendable: isSendable)
		var lines = ["\(indent)\(decorator)func \(receivedFunctionName)(\(parameters)) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource) {"]
		lines.append(contentsOf: memberLines)
		lines.append("\(bodyIndent)\(memberLines.isEmpty ? "" : "return ")\(member.builderFunctionName)(\(callArguments.joined(separator: ", ")))")
		lines.append("\(indent)}")
		return lines
	}
}

extension MockLowering.Walk {
	/// Appends `memberLines`, the lines of a member of the loop `membership` names, to the loop being emitted, after
	/// appending the loop before it, if another, to `lines`.
	mutating func append(_ memberLines: [String], ofMemberOf membership: MockLowering.LoopMembership, to lines: inout [String]) {
		if let loopUnit, loopUnit.loop != membership.loop {
			endLoopUnit(appendingTo: &lines)
		}
		var unit = loopUnit ?? MockLowering.LoopUnit(loop: membership.loop)
		let counts = lastLoopMemberLineCounts ?? MockLowering.LoopMemberLineCounts(prelude: 0, binding: 0)
		unit.prelude.append(contentsOf: memberLines.prefix(counts.prelude))
		unit.functions.append(contentsOf: memberLines.dropFirst(counts.prelude).dropLast(counts.binding))
		unit.bindings.append(contentsOf: memberLines.suffix(counts.binding))
		loopUnit = unit
		lastLoopMemberLineCounts = nil
	}

	/// The lines of a call of another module's public mock that is a member, `property`, of the loop being lowered, at
	/// `indent`, of `loopMembership`: its builder function, declared by `functionDeclaration`, which first rebinds the
	/// members its tree receives, then holds `bodyLines` and returns `call`; then its wrapper's binding where its level
	/// binds it.
	mutating func loopMemberCallLines(of generator: ScopeGenerator, property: Property, in loopMembership: MockLowering.LoopMembership, functionDeclaration: String, bodyLines: [String], call: String, indent: String) -> [String] {
		let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
		let rebindingLines = MockLowering.rebindingLines(of: generator.reboundProperties, among: loopMembers, ownProperty: property, indent: bodyIndent)
		let statements = rebindingLines + bodyLines.map { "\(bodyIndent)\($0)" }
		var lines = [functionDeclaration] + statements
		lines.append("\(bodyIndent)\(statements.isEmpty ? "" : "return ")\(call)")
		lines.append("\(indent)}")
		let bindingLines = loopMembership.declaresBinding ? loopMembers[property].map { MockLowering.memberBindingLines(of: $0, handing: $0.functionName, indent: indent) } ?? [] : []
		lines.append(contentsOf: bindingLines)
		lastLoopMemberLineCounts = MockLowering.LoopMemberLineCounts(prelude: 0, binding: bindingLines.count)
		return lines
	}

	/// Appends the loop being emitted, if any, to `lines`.
	mutating func endLoopUnit(appendingTo lines: inout [String]) {
		if let loopUnit {
			lines.append(contentsOf: loopUnit.lines)
		}
		loopUnit = nil
	}
}

extension ScopeGenerator {
	/// The loop of builders each of this scope's children, in generation order, is a member of (see `ReceivedBuilderLoops`).
	nonisolated var mockLoweringLoopMemberships: [MockLowering.LoopMembership?] {
		let loopByChildIndex = receivedBuilderLoops.loopByChildIndex
		guard !loopByChildIndex.isEmpty else { return [] }
		let membersReadOnlyInsideTheirLoop = mockLoweringLoopMembersReadOnlyInsideTheirLoop
		return orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map { child in
			loopByChildIndex[child.index].map { MockLowering.LoopMembership(loop: $0, declaresBinding: !membersReadOnlyInsideTheirLoop.contains(child.index)) }
		}
	}
}
