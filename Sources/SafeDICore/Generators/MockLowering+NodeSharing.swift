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

extension MockLowering {
	/// Everything the type key reads of a built place's record but its node and the values its passed arguments are
	/// handed, which each call hands its own (`TypeKeyBody`'s `passedArgumentsByCall`). Places whose records have one such
	/// key are one node of the plan, as the places of one generator's cached code are in production: a mock's walk writes
	/// every place afresh, so without it each place was a node of its own, and the type key read a body per place.
	///
	/// A child that declares a function is read by its node and what the call hands it; any other child by its whole
	/// record. A record with a child that is no recorded place has no key, so its place keeps a node of its own.
	/// `SafeDIToolMockNodeSharingTests` fails when a record type gains a field this key does not read.
	struct SharedRecordKey: Hashable {
		let record: BuiltRecordShape

		init?(_ record: BuiltPlaceRecord) {
			guard let shape = BuiltRecordShape(record, passedArgumentValues: false) else { return nil }
			self.record = shape
		}
	}

	struct BuiltRecordShape: Hashable {
		let property: Property
		let isErased: Bool
		let concreteType: TypeDescription
		let isExtension: Bool
		let target: ConstructionTarget
		let arguments: [PlaceRead]
		let forwardedProperties: [Property]
		let cycleParameters: [Property]
		let callCycleArguments: [PlaceRead]
		let functionName: String
		let isSendable: Bool
		let typesDeclaredEscaping: Set<TypeDescription>
		let lineEnd: String
		let hasFunction: Bool
		let children: [ChildShape]
		/// The passed arguments in full where the place's call is in the body being keyed, else only what the function
		/// declares of them.
		let passedArguments: [PassedArgumentShape]
		let constructionValue: ConstructionValue?
		let alternatives: [AlternativeShape]
		let argumentValues: [Int: ValuePath]
		let functionReturnType: TypeDescription?
		/// The read that binds the place to `nil`, a read of its call site that no call hands the function: two places alike
		/// but for it are two nodes, so neither takes the other's, and every place of one node reads one.
		let nilAlternative: ValuePath?

		init?(_ record: BuiltPlaceRecord, passedArgumentValues: Bool) {
			var children = [ChildShape]()
			for child in record.children {
				guard let shape = ChildShape(child) else { return nil }
				children.append(shape)
			}
			self.init(record, children: children, passedArgumentValues: passedArgumentValues)
		}

		/// The shape of `record` with its children's shapes given.
		init(_ record: BuiltPlaceRecord, children: [ChildShape], passedArgumentValues: Bool) {
			property = record.property
			isErased = record.isErased
			concreteType = record.concreteType
			isExtension = record.isExtension
			target = record.target
			arguments = record.arguments
			forwardedProperties = record.forwardedProperties
			cycleParameters = record.cycleParameters
			callCycleArguments = record.callCycleArguments
			functionName = record.functionName
			isSendable = record.isSendable
			typesDeclaredEscaping = record.typesDeclaredEscaping
			lineEnd = record.lineEnd
			hasFunction = record.hasFunction
			self.children = children
			passedArguments = record.passedArguments.map { PassedArgumentShape($0, value: passedArgumentValues) }
			constructionValue = record.constructionValue
			alternatives = record.alternatives.map(AlternativeShape.init)
			argumentValues = record.argumentValues
			functionReturnType = record.functionReturnType
			nilAlternative = record.nilAlternative
		}
	}

	/// A passed argument as the function declares it, with the value its call hands it where that call is keyed.
	struct PassedArgumentShape: Hashable {
		let parameterName: String
		let type: TypeDescription
		let staysOutsideSendableFunctions: Bool
		let bindsBeforeCall: Bool
		let value: ValuePath?

		init(_ argument: PassedArgument, value: Bool) {
			parameterName = argument.parameterName
			type = argument.type
			staysOutsideSendableFunctions = argument.staysOutsideSendableFunctions
			bindsBeforeCall = argument.bindsBeforeCall
			self.value = value ? argument.value : nil
		}
	}

	struct AlternativeShape: Hashable {
		let closure: ValuePath
		let bindingName: String?
		let requiresAbsent: [ValuePath]
		let use: ConstructionAlternative.Use
		let resultWrapper: TypeDescription?

		init(_ alternative: ConstructionAlternative) {
			closure = alternative.closure
			bindingName = alternative.bindingName
			requiresAbsent = alternative.requiresAbsent
			use = alternative.use
			resultWrapper = alternative.resultWrapper
		}
	}

	struct ClosingShape: Hashable {
		let property: Property
		let isErased: Bool
		let isExtension: Bool
		let closedOnFunctionName: String
		let forwardedProperties: [Property]
		let cycleArguments: [PlaceRead]
		let passedArguments: [PassedArgument]
		let rebindsLoopMember: Bool

		init(_ record: ClosingPlaceRecord) {
			property = record.property
			isErased = record.isErased
			isExtension = record.isExtension
			closedOnFunctionName = record.closedOnFunctionName
			forwardedProperties = record.forwardedProperties
			cycleArguments = record.cycleArguments
			passedArguments = record.passedArguments
			rebindsLoopMember = record.rebindsLoopMember
		}
	}

	struct AliasShape: Hashable {
		let property: Property
		let fulfillingProperty: Property?
		let text: String
		let reads: [PlaceRead]?
		let otherBindings: [Property]
		let calledFunctionNames: [String]
		let declaredFunctionNames: [String]
		let calledRootFunctionNames: [String]

		init(_ record: AliasPlaceRecord) {
			property = record.property
			fulfillingProperty = record.fulfillingProperty
			text = record.text
			reads = record.reads
			otherBindings = record.otherBindings
			calledFunctionNames = record.calledFunctionNames
			declaredFunctionNames = record.declaredFunctionNames
			calledRootFunctionNames = record.calledRootFunctionNames
		}
	}

	/// A child of a keyed record: a place with a function by its node and what its call hands it, as the body that holds
	/// the call reads it; any other recorded place by its whole record. The type key reads a place's record, never the
	/// code its plan holds.
	indirect enum ChildShape: Hashable {
		case function(node: ObjectIdentifier, passedArguments: [PassedArgument])
		case inline(BuiltRecordShape)
		case closer(ClosingShape)
		case alias(AliasShape)

		init?(_ code: GeneratedCode) {
			guard case let .place(plan) = code.node, let record = plan.record else { return nil }
			switch record {
			case let .built(built):
				if built.hasFunction {
					self = .function(node: ObjectIdentifier(built.node), passedArguments: built.passedArguments)
				} else {
					// A place with no function holds no children: its record's are its function's body (`recordBuiltPlaces`).
					self = .inline(BuiltRecordShape(built, children: [], passedArgumentValues: true))
				}
			case let .closer(closer):
				self = .closer(ClosingShape(closer))
			case let .alias(alias):
				self = .alias(AliasShape(alias))
			}
		}
	}
}

extension MockLowering.Walk {
	/// Gives the built place recorded at `path` the node of an alike place recorded before it (`SharedRecordKey`), keeping
	/// what its own call hands its function. `nodesByKey` holds the node of each key while the records are made.
	mutating func sharingNode(ofBuiltPlaceAt path: [Int], nodesByKey: inout [MockLowering.SharedRecordKey: BuiltPlaceRecord]) {
		guard case let .built(record) = builtRecords[path], let key = MockLowering.SharedRecordKey(record) else { return }
		guard var shared = nodesByKey[key] else {
			nodesByKey[key] = record
			return
		}
		shared.passedArguments = record.passedArguments
		builtRecords[path] = .built(shared)
	}
}
