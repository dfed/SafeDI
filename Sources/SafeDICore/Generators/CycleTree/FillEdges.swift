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

/// The edges a plan's declaration has to the fills of the call its scope makes, and the labels the call reads of the
/// scope enclosing it for those fills (`Scope.fillUnderConstruction` and the reads `construction-memo-calls.md` lists).
/// A fill builds the hole's property with the type that fulfills it, beneath the call, and reads what the call does not
/// bind from the declarations enclosing the call, so its declaration is a target of the call's, as a child's is.
///
/// What it says a fill binds is a subset of what any build of the call binds, and what it says the call reads is a
/// superset, so a plan built with it lacks no label a place reads from above: a field a build may read from the caller's
/// scope instead (a deferred parameter's, a label some route to the place does not carry, every label of a call of
/// another module's public mock, whose caller's own values are decided per build) is not bound, and a call that re-enters
/// a fill an enclosing call declares keeps its edge to the fill, which its build reuses by name.
///
/// Read once per declaration as the plan's walk first reaches it; it holds one entry per fill of the call and its labels,
/// for as long as the plan keeps it.
struct FillEdges: Sendable {
	/// One fill of the call: the declaration the fill builds, the labels the fill binds from its place's struct, which
	/// hide the caller's declarations of them from the fill's tree, and the fields it binds them from, in field order.
	struct Edge: Sendable {
		let target: Declaration
		let boundLabels: Set<String>
		let boundFields: [SeamSignature.Hole.Field]
	}

	init(of record: ScopeRecord, in table: ScopeTable) {
		var fills = [(hole: SeamSignature.Hole, scopeID: ScopeID, context: ScopeRecord.FillContext)]()
		for case let .fill(hole, scopeID, context) in record.holeArguments {
			fills.append((hole, scopeID, context))
		}
		guard !fills.isEmpty else {
			edges = []
			labelsReadOfCaller = []
			return
		}
		let isPublicMockCall = record.publicMockCall != nil
		// Every place of a case nested by type is filled by one function, which binds what every route to the case can hand
		// it (`ScopeGenerator.caseFields(of:)`); another place's fill, which a re-entering call may stand in for, binds its own
		// place's fields. A label either binds from a level counts as bound only where both do.
		var placesByCaseKey = [String: [SeamSignature.Hole]]()
		for fill in fills where fill.hole.enumPlace != nil {
			placesByCaseKey[ScopeGenerator.fillCaseKey(of: fill.hole), default: []].append(fill.hole)
		}
		let innerScopeReaders = record.calledBuilders.map { InnerScopeReaders(enumsByKey: $0.enumsByKey) }
		var labelsBoundByCaseKey = [String: Set<String>]()
		for (caseKey, places) in placesByCaseKey {
			let caseFields = ScopeGenerator.caseFields(of: places)
			var bound = Set(caseFields.fields.filter { !$0.isDeferredParameter }.map(\.property.label))
			bound.subtract(caseFields.callerReadLabels)
			if let innerScopeReaders {
				for place in places {
					bound.subtract(innerScopeReaders.labelsSomeInnerRouteLacks(of: place))
				}
			}
			labelsBoundByCaseKey[caseKey] = bound
		}
		// A level of the called seam that binds a label from a deferred parameter of a seam it calls hands a fill the memo of
		// what that call passed, which the call reads of its caller's declaration of the label where the memo is `@Sendable`
		// (`Scope.callerReads(of:child:labelsHandedToReenteredFunctions:log:)`).
		var deferredLabelsOfCalledLevels = Set<String>()
		for scopeEnum in record.calledBuilders?.scopeEnums ?? [] {
			for scopeCase in scopeEnum.cases {
				for field in scopeCase.values?.fields ?? [] where field.isDeferredParameter {
					deferredLabelsOfCalledLevels.insert(field.property.label)
				}
			}
		}
		var edges = [Edge]()
		var labelsReadOfCaller = [String]()
		var labelsReadOfCallerSet = Set<String>()
		func readOfCaller(_ label: String) {
			if labelsReadOfCallerSet.insert(label).inserted {
				labelsReadOfCaller.append(label)
			}
		}
		for fill in fills {
			let hole = fill.hole
			var boundLabels = Set<String>()
			if !isPublicMockCall {
				boundLabels = Set(hole.fields.filter { !$0.isDeferredParameter }.map(\.property.label))
				if hole.enumPlace != nil {
					boundLabels.formIntersection(labelsBoundByCaseKey[ScopeGenerator.fillCaseKey(of: hole)] ?? [])
				}
			}
			var boundFields = [SeamSignature.Hole.Field]()
			var boundFieldLabels = Set<String>()
			for field in hole.fields where boundLabels.contains(field.property.label) && boundFieldLabels.insert(field.property.label).inserted {
				boundFields.append(field)
			}
			edges.append(Edge(
				target: Declaration(
					record: table[fill.scopeID],
					built: Declaration.Built(property: hole.property, id: fill.context.propertyID, erasedToConcreteExistential: hole.erasedToConcreteExistential),
				),
				boundLabels: boundLabels,
				boundFields: boundFields,
			))
			// The fill's place reads its own property's declaration, to mark it as being built, of the declarations enclosing
			// the call, which no scope between declares.
			readOfCaller(hole.property.label)
			let payloadLabels = Set(hole.enumPlace?.values.map(\.property.label) ?? [])
			for field in hole.fields {
				let label = field.property.label
				// A call of another module's public mock reads the caller's declaration of a label its case's fields hold, to
				// find the caller's own values (`Scope.callersOwnLabels`); a seam's call reads the caller's declaration of a label
				// a level hands a fill as a `@Sendable` memo.
				if isPublicMockCall || (!field.isDeferredParameter && !payloadLabels.contains(label) && deferredLabelsOfCalledLevels.contains(label)) {
					readOfCaller(label)
				}
			}
			// A value the called public mock binds at its root from the call's argument, outside the `@Sendable` function that
			// builds the place, is read of the caller's declaration (`Scope.fillUnderConstruction`).
			for declaration in hole.uncarriedDeclarations where declaration.isBoundFromCallersArgument {
				readOfCaller(declaration.property.label)
			}
		}
		self.edges = edges
		self.labelsReadOfCaller = labelsReadOfCaller
	}

	/// One edge per fill the call passes, in the order of the call's hole arguments.
	let edges: [Edge]
	/// The labels the call reads of the declarations enclosing it for its fills, in the order its fills first read them.
	let labelsReadOfCaller: [String]
}
