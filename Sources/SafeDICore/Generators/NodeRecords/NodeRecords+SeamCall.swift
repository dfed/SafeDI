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
	/// The claim of `declaration` as `seamCall` where it calls another module's seam (`TypeFactsConstruction.seamCall`), which
	/// discharges stage 1's refusal of a construction other than an initializer, and its refusal of a call that passes
	/// builders where the call passes each builder up from the seam whose tree makes it (`ConstructionScope.HoleArgument.passUp`);
	/// `nil` for any other node, and for every node of a mock root's world, which builds every seam inline. Every other
	/// check of stage 1 still runs on it, so a call that fills a place is still refused as `fill`. A call that forwards values
	/// binds them inside its text, which no record lists yet: refused as `construction`.
	static func seamCallClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard !world.isMockWorld, world.construction(of: declaration) == .seamCall else { return nil }
		let scope = world.scope(of: declaration)
		let forwardsValues = scope.instantiable.dependencies.contains { $0.source == .forwarded }
		let passesEveryBuilderUp = scope.holeArguments.allSatisfy { holeArgument in
			switch holeArgument {
			case .passUp:
				true
			case .fill:
				false
			}
		}
		return NodeRecordClaim(kind: .seamCall, discharges: passesEveryBuilderUp ? [.construction, .fill] : [.construction], refusals: forwardsValues ? [.construction] : [])
	}

	/// The record of `declaration`'s place, a node of kind `seamCall`: `builtByInitializerRecord`'s, with the seam's tier's
	/// initializer as its target (the scope's instantiable is the seam's leaf), a builder function always declared, the
	/// guard line that function begins with (`CallFields.leadingStatement`), and, where the call passes builders up, the
	/// read of the struct it passes each (`SeamCallRoutes`).
	/// - Throws: `NodeRecordRefusal.fill` where the call passes a builder up that `routes` holds no one read for.
	static func seamCallRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		routes: SeamCallRoutes,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let scope = world.scope(of: declaration)
		var record = try builtByInitializerRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: typesDeclaredEscaping, children: children, declaresFunction: true)
		// Never `nil`: the node is of kind `seamCall` (`seamCallClaim(of:in:)`), whose construction is a call of the seam.
		guard let seamCall = scope.seamCall else { return record }
		// A call that passes nothing up passes no builder: the tier's builders take what the seam's tree builds.
		let closureArguments = try scope.holeArguments.isEmpty ? [] : seamCall.calledBuilders.builders.map { builder throws(NodeRecordRefusal) -> ClosureArgumentEntry in
			guard let read = routes.read(passedUpBy: declaration, to: builder) else { throw .fill }
			return ClosureArgumentEntry(label: builder.generatedOnlyArgumentLabel, value: .passedOn(read))
		}
		record.callFields = CallFields(leadingStatement: seamCall.callGuard(for: scope.instantiable.concreteInstantiable), closureArguments: closureArguments)
		return record
	}
}

/// How a seam's own tree passes its builders' structs up to the seams it calls (`SeamSignature.callRoutes`): for each node
/// that calls a seam and each builder of that seam, the read of the struct it passes, where every path from the root to the
/// node passes the same one. Empty for a tree that is no seam's, whose calls pass nothing up.
struct SeamCallRoutes: Sendable {
	init() {
		readsByCall = [:]
	}

	/// The routes of `signature`'s tree, whose world is `world`.
	init(world: some NodeRecordSources, signature: SeamSignature) {
		guard !signature.callRoutes.isEmpty else {
			readsByCall = [:]
			return
		}
		let seamHoles = SeamHoles(seamType: signature.seamType, holes: signature.holes, builders: signature.builders, parameters: signature.parameters, callRoutes: signature.callRoutes, scopeEnums: signature.scopeEnums, holdsLoopPayloadsInBoxes: true)
		var routesByCall = [Call: (read: PassedOnRead?, count: Int)]()
		for callRoute in signature.callRoutes where !callRoute.reentersEnclosingFill {
			// The node at the end of the route's path: each step the child of the step before built as the step's property. A
			// path into a fill names no edge's property, and leaves its call without a read.
			var declaration: DeclarationID = 0
			for property in callRoute.sitePath {
				guard let child = world.edges(from: declaration).first(where: { world.property(of: $0) == property }) else {
					declaration = -1
					break
				}
				declaration = child
			}
			guard declaration > 0,
			      let calledBuilder = world.scope(of: declaration).seamCall?.calledBuilders.builders.first(where: { $0.enumKey == callRoute.innerKey })
			else { continue }
			// A call whose case is nested in another's binds the payloads of the cases on its route before the places that lead
			// to it, which no record of this kind holds; one inside a fill hands the fill's struct. Neither has a read here.
			let writesOnlyTheCall = callRoute.route.isEmpty && !callRoute.handsFillLevelStruct
			let read = !writesOnlyTheCall ? nil : seamHoles.routeCase(at: callRoute.sitePath, innerKey: callRoute.innerKey)?.passedUpStruct.map { passedUpStruct in
				PassedOnRead(calledType: world.scope(of: declaration).instantiable.concreteInstantiable, builderLabel: calledBuilder.label, structType: passedUpStruct.type, caseName: passedUpStruct.caseName, member: passedUpStruct.member)
			}
			let call = Call(declaration: declaration, innerKey: callRoute.innerKey)
			if let (knownRead, count) = routesByCall[call] {
				// Two paths that pass two structs make two records of one node: no one read.
				routesByCall[call] = (knownRead == read ? read : nil, count + 1)
			} else {
				routesByCall[call] = (read, 1)
			}
		}
		// A read stands for the node only where a route reaches it along every path from the root.
		let pathCounts = Self.pathCounts(in: world)
		readsByCall = routesByCall.compactMapValues { route in route.read }.filter { call, _ in
			routesByCall[call]?.count == pathCounts[Int(call.declaration)]
		}
	}

	/// The read of the struct `declaration`'s call passes `builder` of the seam it calls, or `nil` where no one read stands for
	/// every path to the node.
	func read(passedUpBy declaration: DeclarationID, to builder: SeamSignature.Builder) -> PassedOnRead? {
		readsByCall[Call(declaration: declaration, innerKey: builder.enumKey)]
	}

	private struct Call: Hashable {
		let declaration: DeclarationID
		let innerKey: SeamSignature.ScopeEnum.Key
	}

	private let readsByCall: [Call: PassedOnRead]

	/// How many paths reach each declaration from the root, counting each up to `Int.max`: every declaration's parents
	/// are counted before it.
	private static func pathCounts(in world: some NodeRecordSources) -> [Int] {
		var counts = [Int](repeating: 0, count: world.declarationCount)
		var parentsLeft = [Int](repeating: 0, count: world.declarationCount)
		for declaration in 0..<Int32(world.declarationCount) {
			for child in world.edges(from: declaration) {
				parentsLeft[Int(child)] += 1
			}
		}
		counts[0] = 1
		var ready: [DeclarationID] = [0]
		while let declaration = ready.popLast() {
			for child in world.edges(from: declaration) {
				let (sum, overflows) = counts[Int(child)].addingReportingOverflow(counts[Int(declaration)])
				counts[Int(child)] = overflows ? Int.max : sum
				parentsLeft[Int(child)] -= 1
				if parentsLeft[Int(child)] == 0 {
					ready.append(child)
				}
			}
		}
		return counts
	}
}
