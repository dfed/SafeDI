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
	/// The record of `declaration`'s place where its call of another module's public mock fills a builder of the mock it calls
	/// (`PublicMockFilledCallRecords`): a call the engine spells where its place is written (`InPlaceCall`), as the walk writes
	/// it (`MockLowering.Walk.publicMockCallNode`): its function holds each fill that declares a function, then the call's
	/// level functions, each member that holds a fill's body holding it, then the mock's guard line, then the rebindings of
	/// what it receives named apart, and returns the call, which hands each builder it fills the call of its root level
	/// function, or the builder `mock()` takes for the places its fills build, where it is set
	/// (`MockRootNames.filledCallBuilders`). A fill's body is its place laid out by the engine with what the fill binds and
	/// takes declared around it, as a seam call's fill is (`filledSeamCallRecord`).
	/// - Parameters:
	///   - childPlaces: The declaration and place of each of the node's children, in the order its body builds them.
	///   - typesDeclaredEscapingOf: The types a node's tree declares `@escaping`.
	/// - Throws: `NodeRecordRefusal.publicMockCallFills` where the records do not make the call, and
	///   `NodeRecordRefusal.notLaidOut` where the engine cannot lay a fill's body out.
	static func publicMockFilledCallRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		receivesBoundAgain: [MockReceiveBoundAgain],
		typesDeclaredEscaping: Set<TypeDescription>,
		childPlaces: [(declaration: DeclarationID, place: GeneratedCode)],
		typesDeclaredEscapingOf: (DeclarationID) -> Set<TypeDescription>,
	) throws -> AliasPlaceRecord {
		let scope = world.scope(of: declaration)
		guard let call = scope.publicMockCall, case let .success(records) = world.publicMockFilledCallRecords(of: declaration) else { throw NodeRecordRefusal.publicMockCallFills }
		// What the call hands each builder it fills: the struct its root level function returns, unless `mock()` takes a
		// builder for the places of the builder's family, which a test passes in place of the fills.
		var filledBuilderValues = [String: String]()
		for (label, rootCall) in records.rootCallsByLabel {
			let family = call.builders.first { $0.label == label }.map { MockFilledCallBuilder.Family(holeType: $0.enumKey.holeType, isSendable: $0.enumKey.isSendable) }
			filledBuilderValues[label] = family.flatMap { world.mockRootNames.filledCallBuilders[$0] }?.structValue(fillsStruct: rootCall) ?? rootCall
		}
		var record = try publicMockCallRecord(of: declaration, variant: variant, in: world, receivesBoundAgain: [], typesDeclaredEscaping: typesDeclaredEscaping, children: [], filledBuilderValues: filledBuilderValues, isSpelledInPlace: true)
		let calledType = record.concreteType
		let indent = ScopeGenerator.standardIndent
		// The names a fill's body sees where the call declares it, which a function laid out inside it is named apart from:
		// the call's function, its level functions and its fills.
		let namesInScope = Set([record.functionName] + records.levelFunctions.functionNames + records.fills.map(\.functionName))
		let fillsByDeclaration = Dictionary(grouping: records.fills, by: \.facts.declaration)
		var statements = [GeneratedCode]()
		var inlinedFillBodies = [String: [String]]()
		for child in childPlaces {
			for fill in fillsByDeclaration[child.declaration] ?? [] {
				let typesEscaping = typesDeclaredEscapingOf(fill.facts.declaration)
				if records.inlinedFillKeys.contains(fill.facts.key),
				   let inlinedFill = try ScopeGenerator.FillDispatcher.InlinedFill(hole: fill.facts.hole, carrierUse: fill.facts.carrierUse, builtProperty: world.property(of: fill.facts.declaration), code: fill.functionLines(place: child.place, typesDeclaredEscaping: typesEscaping, namesInScope: namesInScope).map { indent + $0 }.joined(separator: "\n"), leadingMemberWhitespace: indent)
				{
					inlinedFillBodies[fill.facts.key] = inlinedFill.body
				} else {
					try statements.append(.indented(fill.functionCode(place: child.place, typesDeclaredEscaping: typesEscaping, namesInScope: namesInScope), by: indent))
				}
			}
		}
		statements += records.levelFunctions.declarations(indent: indent, inlinedFillBodies: inlinedFillBodies).map(GeneratedCode.text)
		// The call names the mock's guard after its fills.
		record.callFields = CallFields(leadingStatement: .callGuard(CallGuard(calledType: calledType, guardTypeName: call.guardTypeName, comment: call.comment)), closureArguments: [])
		// What the call reads of the caller's scope, which its function captures; a builder's value reads nothing of it.
		let reads = record.arguments.filter { argument in
			guard case .spelledArgument = argument.source else { return true }
			return false
		}
		var alias = AliasPlaceRecord(property: record.property, fulfillingProperty: nil, text: "", reads: reads)
		alias.declaredFunctionNames = [record.functionName]
		alias.call = InPlaceCall(record: record, statementsBeforeLeadingStatement: statements, statementsAfterLeadingStatement: receivesBoundAgain.map { .indented($0.place, by: indent) })
		return alias
	}
}
