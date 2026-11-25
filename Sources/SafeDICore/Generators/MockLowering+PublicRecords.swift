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

// The records of a public mock's places, which nothing reads yet: a configured built place calls its type's construction
// function handed the builder its override reads, and a hole's site binds its property from the builder's level.

extension MockLowering {
	/// What a public mock's configured built place calls in place of its type's construction: the type's construction
	/// function (`PublicConstructionRecord.functionName`), handed the place's construction arguments under their inner
	/// labels and, last, the builder its override reads.
	struct PublicConstructionInputs {
		let construction: PublicConstructionRecord
		/// The override the builder argument reads, or `nil` where the place has none and passes `nil`.
		let builderRead: String?
		/// The call the walk writes, unerased, which the record's call is checked against.
		let writtenCall: String
	}

	/// The record of a public mock's configured built place: `record`, the record production's record function made of the
	/// place, calling the type's construction function instead of its construction, or `nil` where its arguments are not
	/// the construction function's, which it then leaves unrecorded.
	static func publicConstructionRecord(of record: BuiltPlaceRecord, inputs: PublicConstructionInputs) -> BuiltPlaceRecord? {
		let construction = inputs.construction
		guard record.arguments.count == construction.arguments.count,
		      zip(record.arguments, construction.arguments).allSatisfy({ $0.argumentLabel == $1.label })
		else { return nil }
		let builderLabel = ReservedName.configurationBuilderPropertyName
		let builderType = TypeDescription.optional(.closure(arguments: construction.builderParameterTypes, isAsync: false, doesThrow: false, returnType: construction.concreteType))
		let builderRead = PlaceRead(
			argumentLabel: builderLabel,
			label: inputs.builderRead ?? builderLabel,
			property: Property(label: builderLabel, typeDescription: builderType),
			source: inputs.builderRead.map { .spelledArgument($0) } ?? .nil,
		)
		let arguments = zip(record.arguments, construction.arguments).map { read, argument in
			PlaceRead(argumentLabel: argument.innerLabel, label: read.label, property: read.property, source: read.source, staysOutsideSendableFunctions: read.staysOutsideSendableFunctions)
		}
		var publicRecord = BuiltPlaceRecord(
			property: record.property,
			isErased: record.isErased,
			concreteType: record.concreteType,
			isExtension: record.isExtension,
			target: .mock(construction.concreteType, name: construction.functionName),
			arguments: arguments + [builderRead],
			forwardedProperties: record.forwardedProperties,
			cycleParameters: record.cycleParameters,
			callCycleArguments: record.callCycleArguments,
			functionName: record.functionName,
			isSendable: record.isSendable,
			typesDeclaredEscaping: record.typesDeclaredEscaping,
			lineEnd: record.lineEnd,
			hasFunction: record.hasFunction,
			children: record.children,
			node: record.node,
		)
		// The builder is an argument of the call, never an alternative the place tries first.
		publicRecord.passedArguments = record.passedArguments
		publicRecord.constructionValue = record.constructionValue
		publicRecord.argumentValues = record.argumentValues
		return publicRecord
	}
}

extension MockLowering {
	/// `record`'s call, spelled from its target and each argument's label and source: what the type key would write.
	static func spelledCall(of record: BuiltPlaceRecord) -> String {
		let arguments = record.arguments.map { "\($0.argumentLabel.spelledAsArgumentLabel): \($0.source.spelled)" }
		return "\(record.target.callee)(\(arguments.joined(separator: ", ")))"
	}
}

extension MockLowering.Walk {
	/// What the public mock's records hold, by kind, for the spike shadow's count line.
	struct PublicRecordCounts {
		var builtPlaces = 0
		var builtPlacesInWrappers = 0
		var constructionFunctionCalls = 0
		var holeSites = 0
		var holeSitesInWrappers = 0
		/// The hole sites whose reads the record cannot name, as a fill's own level, which stay one per path.
		var holeSitesWithoutReads = 0
		var unrecordedConstructionFunctionCalls = 0
		/// The construction function calls whose record, spelled, is the call the walk writes.
		var constructionFunctionCallsSpelledAsWritten = 0

		var reportField: String {
			"built=\(builtPlaces)\tbuiltInWrappers=\(builtPlacesInWrappers)\tconstructionFunctionCalls=\(constructionFunctionCalls)\tholeSites=\(holeSites)\tholeSitesInWrappers=\(holeSitesInWrappers)\tholeSitesWithoutReads=\(holeSitesWithoutReads)\tunrecordedConstructionFunctionCalls=\(unrecordedConstructionFunctionCalls)\tspelledAsWritten=\(constructionFunctionCallsSpelledAsWritten)"
		}
	}

	/// Keeps, for the built place the walk is lowering in a public mock, the construction function its configured node calls
	/// and the override its builder argument reads, so that `recordBuiltPlace` records that call.
	mutating func recordPublicConstruction(of node: MockLowering.ConstantNode, children: [MockLowering.TreeNode], builderRead: String?) {
		guard buildsPublicMock, node.hasConfiguration, builtPlaceInputs[childIndexPath] != nil else { return }
		let construction = MockLowering.PublicConstructionRecord(of: node, children: children)
		builtPlaceInputs[childIndexPath]?.publicConstruction = MockLowering.PublicConstructionInputs(
			construction: construction,
			builderRead: builderRead,
			writtenCall: MockLowering.publicConstructionCall(of: construction, arguments: node.arguments.map(\.value), builderRead: builderRead, erasedTo: nil),
		)
	}

	/// The record of a public mock's place production's record function made, `record`, as the public mock writes it.
	mutating func publicRecord(of record: PlaceRecord, inputs: MockLowering.BuiltPlaceInputs) -> PlaceRecord? {
		guard buildsPublicMock, case let .built(builtRecord) = record else { return record }
		guard let publicConstruction = inputs.publicConstruction else {
			countPublicBuiltPlace(builtRecord)
			return record
		}
		guard let publicRecord = MockLowering.publicConstructionRecord(of: builtRecord, inputs: publicConstruction) else {
			publicRecordCounts.unrecordedConstructionFunctionCalls += 1
			return nil
		}
		publicRecordCounts.constructionFunctionCalls += 1
		if MockLowering.spelledCall(of: publicRecord) == publicConstruction.writtenCall {
			publicRecordCounts.constructionFunctionCallsSpelledAsWritten += 1
		}
		countPublicBuiltPlace(publicRecord)
		return .built(publicRecord)
	}

	private mutating func countPublicBuiltPlace(_ record: BuiltPlaceRecord) {
		publicRecordCounts.builtPlaces += 1
		if !record.property.propertyType.isConstant {
			publicRecordCounts.builtPlacesInWrappers += 1
		}
	}

	/// Records the site of a hole in a public mock's tree, written as `text`, as production records a seam's site
	/// (`ScopeGenerator.holeSitePlace`): a place the type key copies as written, with what it reads and binds.
	mutating func recordPublicHoleSite(text: String, of property: Property, at site: SeamSignature.Hole, functionName: String?, readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>) {
		guard buildsPublicMock else { return }
		let place = ScopeGenerator.holeSitePlace(
			text: text,
			of: property,
			at: site,
			functionName: functionName,
			valuesBindings: [],
			readingInstancesOf: lazilyInstantiatedInstanceProperties,
			carrierUse: nil,
		)
		guard case let .place(plan) = place.node, let record = plan.record else { return }
		if case let .alias(aliasRecord) = record, aliasRecord.reads == nil {
			publicRecordCounts.holeSitesWithoutReads += 1
		}
		publicHoleSiteRecords[childIndexPath] = record
		publicRecordCounts.holeSites += 1
		if !property.propertyType.isConstant {
			publicRecordCounts.holeSitesInWrappers += 1
		}
	}
}
