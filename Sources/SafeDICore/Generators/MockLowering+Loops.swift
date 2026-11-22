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
		/// The name of the member's builder function.
		let functionName: String
		/// The properties the member's type forwards, in the order its wrapper hands them.
		let forwardedProperties: [Property]
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
	/// child's loop: the property nodes, whose functions the members' functions rebind.
	static func loopMembers(among generators: [ScopeGenerator], loops: [LoopMembership?]) -> [Property: LoopMember] {
		var members = [Property: LoopMember]()
		for (generator, membership) in zip(generators, loops) where membership != nil {
			guard case let .property(instantiable, property, _, _, _, _) = generator.scopeData else { continue }
			members[property] = LoopMember(
				typeDescription: property.typeDescription,
				functionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
				forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			)
		}
		return members
	}

	/// The lines that begin a loop member's builder function, at `indent`: a binding of each of `reboundProperties`, the
	/// members of `members` its tree receives, wrapping that member's function; or `nil` where one is no property node.
	static func rebindingLines(of reboundProperties: [Property], among members: [Property: LoopMember], indent: String) -> [String]? {
		var lines = [String]()
		for property in reboundProperties {
			guard let member = members[property] else { return nil }
			lines.append(contentsOf: wrapperBindingLines(
				of: member.typeDescription,
				named: property.label,
				handing: member.functionName,
				forwardedProperties: member.forwardedProperties,
				indent: indent,
			))
		}
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
