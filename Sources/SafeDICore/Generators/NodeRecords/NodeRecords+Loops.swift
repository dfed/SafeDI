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
	/// The refusals of `declaration` as a member of a loop of builders, whatever kind claims it: a member whose loop step 0
	/// finds that makes nothing again, which the stand-in for its loops does not see; a mock world's member, whose
	/// rebindings hand the mock's configurations, which these records do not yet, a member two parents' loops make
	/// different members of again included; and a `@Sendable` member that captures a member's wrapper that is not
	/// `Sendable`, which the tree reports.
	static func loopRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		let isSharedApart = world.loopMembersSharedApart.contains(declaration)
		let isUnseenMember = zip(world.edges(from: declaration), world.edgeFacts(from: declaration)).contains { child, edge in
			edge.loop >= 0 && world.madeAgain(from: child).isEmpty && !world.loopMembersSharedApart.contains(child)
		}
		let madeAgain = world.madeAgain(from: declaration)
		let isMockMember = world.isMockWorld && (!madeAgain.isEmpty || isSharedApart)
		// A rebinding names the member's function, so it captures that member's wrapper: a `@Sendable` member that makes a
		// member again that is not `Sendable` captures it, the error the tree reports (`nonSendableWrapperCaptures`).
		let capturesWrapper = world.property(of: declaration)?.propertyType.isSendable == true && madeAgain.contains { member in
			world.property(of: member)?.propertyType.isSendable == false
		}
		return (isUnseenMember || isMockMember ? [.builderLoop] : []) + (capturesWrapper ? [.sendableFunctionCapturesWrapper] : [])
	}

	/// The places `variant`'s builder function begins with, before every child: a wrapper made again of each member of
	/// its loop it rebinds, in the order it rebinds them, each a call of that member's builder function, or of the
	/// `__safeDI_<label>_received` function its parent's body declares for it (`receivedFunctionNames`, by the member's
	/// declaration) (`ClosingPlaceRecord.rebindsLoopMember`), but for a member whose label a parameter of the function names
	/// (`hiddenLabels`: its forwarded properties and the parameters a lazy cycle closing on it passes), which is the nearest
	/// declaration there. Its own property, where the function takes `cycleParameters`, is wrapped again with them. The
	/// members are the variant's (`madeAgain(of:)`): a node two parents build can make one set again under one and
	/// another, or none, under the other, and each parent's body calls its own variant.
	static func loopRebindings(
		of variant: VariantID,
		functionName: String?,
		cycleParameters: [Property],
		hiddenLabels: Set<String>,
		receivedFunctionNames: [DeclarationID: String],
		in world: some NodeRecordSources,
	) -> [GeneratedCode] {
		let declaration = world.declaration(of: variant)
		return world.madeAgain(of: variant).compactMap { member in
			guard let property = world.property(of: member), !hiddenLabels.contains(property.label) else { return nil }
			let rebindsOwnFunction = member == declaration && !cycleParameters.isEmpty
			let closedOnFunctionName = if rebindsOwnFunction {
				functionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
			} else {
				receivedFunctionNames[member] ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
			}
			return .indented(rebinding(
				of: member,
				property: property,
				closedOnFunctionName: closedOnFunctionName,
				cycleArguments: rebindsOwnFunction ? cycleParameters.map { PlaceRead(argumentLabel: $0.label, label: $0.label, property: $0, source: .binding(label: $0.label)) } : [],
				in: world,
			), by: ScopeGenerator.standardIndent)
		}
	}

	/// The place that makes `member`'s wrapper, built as `property`, again around the function named
	/// `closedOnFunctionName`, passing it `cycleArguments`.
	static func rebinding(of member: DeclarationID, property: Property, closedOnFunctionName: String, cycleArguments: [PlaceRead], in world: some NodeRecordSources) -> GeneratedCode {
		let instantiable = world.scope(of: member).instantiable
		return .place(PlacePlan(code: .empty, record: .closer(ClosingPlaceRecord(
			property: property,
			isErased: world.isErased(member),
			isExtension: instantiable.declarationType.isExtension,
			closedOnFunctionName: closedOnFunctionName,
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleArguments: cycleArguments,
			rebindsLoopMember: true,
		))))
	}

	/// The statement that binds `property`, the wrapper of a loop member built by the function named `functionName`, through
	/// the member's `__safeDI_<label>_received` function, `name`, which the statement declares (`ScopeGenerator`'s loop
	/// rebindings): after the member's place in its parent's body, or in place of a call that closes a cycle from a loop
	/// member. The function makes again each member of the loop of `declaration` in the body of `parent` whose label one
	/// of `parameters` names, and returns a call of `functionName` that passes those by their labels and every other
	/// parameter `arguments`, what the body around it holds.
	static func receivedFunctionPlace(
		of declaration: DeclarationID,
		property: Property,
		named name: String,
		callingFunctionNamed functionName: String,
		parameters: [Property],
		arguments: [PlaceRead],
		isSendable: Bool,
		typesDeclaredEscaping: Set<TypeDescription>,
		receivedFunctionNames: [DeclarationID: String],
		inBodyOf parent: DeclarationID,
		in world: some NodeRecordSources,
	) -> GeneratedCode {
		let edges = world.edgeFacts(from: parent)
		let loop = edges.first { $0.child == declaration && $0.loop >= 0 }?.loop
		let mates = edges.filter { $0.loop == loop }.map(\.child)
		var statements = [GeneratedCode]()
		var callReads = [PlaceRead]()
		var readsOutsideFunction = [PlaceRead]()
		for (parameter, argument) in zip(parameters, arguments) {
			// A body declares each label once, so at most one of the two forms is a member.
			let unwrappedProperty = parameter.asUnwrappedProperty
			let mate = mates.lazy.compactMap { mate in world.property(of: mate).map { (mate, $0) } }.first { _, mateProperty in
				mateProperty == unwrappedProperty || mateProperty == unwrappedProperty.asOptionalProperty
			}
			if let (mate, mateProperty) = mate {
				statements.append(.indented(rebinding(
					of: mate,
					property: mateProperty,
					closedOnFunctionName: receivedFunctionNames[mate] ?? ScopeGenerator.functionName(toBuildPropertyNamed: mateProperty.label),
					cycleArguments: [],
					in: world,
				), by: ScopeGenerator.standardIndent))
				callReads.append(PlaceRead(argumentLabel: parameter.label, label: parameter.label, property: parameter, source: .binding(label: parameter.label)))
			} else {
				callReads.append(argument)
				readsOutsideFunction.append(argument)
			}
		}
		let instantiable = world.scope(of: declaration).instantiable
		let forwardedProperties = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted()
		var record = AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "", reads: readsOutsideFunction)
		record.declaredFunctionNames = [name]
		record.function = CallingFunction(
			name: name,
			isSendable: isSendable,
			parameters: forwardedProperties,
			typesDeclaredEscaping: typesDeclaredEscaping,
			returnType: instantiable.concreteInstantiable,
			statements: statements,
			returnedCall: ClosingPlaceRecord(
				property: property,
				isErased: false,
				isExtension: instantiable.declarationType.isExtension,
				closedOnFunctionName: functionName,
				forwardedProperties: forwardedProperties,
				cycleArguments: callReads,
			),
		)
		return .place(PlacePlan(code: .text(""), record: .alias(record)))
	}
}
