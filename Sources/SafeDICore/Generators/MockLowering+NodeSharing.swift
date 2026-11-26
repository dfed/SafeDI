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
	/// What tells a built place's record apart from an alike one's within one mock root (`BuiltRecordShape`). Places whose
	/// records have one such key are one node of the plan, as the places of one generator's cached code are in production:
	/// a mock's walk writes every place afresh, so without it each place was a node of its own, and the type key read a
	/// body per place. Each place keeps its own passed arguments, which each call hands its own (`TypeKeyBody`'s
	/// `passedArgumentsByCall`).
	///
	/// A child that declares a function is read by its node and what the call hands it; any other child by its keyed
	/// fields. A record with a child that is no recorded place has no key, so its place keeps a node of its own.
	/// `SafeDIToolMockNodeSharingTests` fails when a record type gains a field this key neither reads nor leaves out with
	/// a reason.
	struct SharedRecordKey: Hashable {
		let record: BuiltRecordShape

		init?(_ record: BuiltPlaceRecord) {
			guard let shape = BuiltRecordShape(record) else { return nil }
			self.record = shape
		}
	}

	/// The fields of a built place's record that tell alike places apart. The record's other fields follow from these
	/// within one mock root, or are ones the type key derives again for each call and class (`notKeyedFields` in
	/// `SafeDIToolMockNodeSharingTests` gives the reason for each).
	struct BuiltRecordShape: Hashable {
		let property: Property
		let concreteType: TypeDescription
		let target: ConstructionTarget
		/// Where each argument of the construction is read from: an argument handed `nil` inside one build and a binding
		/// inside another needs a function of its own for each.
		let arguments: [PlaceRead]
		let children: [ChildShape]
		/// The override closures, which name the configuration of the place's parent.
		let alternatives: [AlternativeShape]

		init?(_ record: BuiltPlaceRecord) {
			var children = [ChildShape]()
			for child in record.children {
				guard let shape = ChildShape(child) else { return nil }
				children.append(shape)
			}
			self.init(record, children: children)
		}

		/// The shape of `record` with its children's shapes given.
		init(_ record: BuiltPlaceRecord, children: [ChildShape]) {
			property = record.property
			concreteType = record.concreteType
			target = record.target
			arguments = record.arguments
			self.children = children
			alternatives = record.alternatives.map(AlternativeShape.init)
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
		let targetVariant: Int?

		init(_ record: ClosingPlaceRecord) {
			property = record.property
			isErased = record.isErased
			isExtension = record.isExtension
			closedOnFunctionName = record.closedOnFunctionName
			forwardedProperties = record.forwardedProperties
			cycleArguments = record.cycleArguments
			passedArguments = record.passedArguments
			targetVariant = record.targetVariant
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
		let readsOnlyIfAvailable: Bool

		init(_ record: AliasPlaceRecord) {
			property = record.property
			fulfillingProperty = record.fulfillingProperty
			text = record.text
			reads = record.reads
			otherBindings = record.otherBindings
			calledFunctionNames = record.calledFunctionNames
			declaredFunctionNames = record.declaredFunctionNames
			calledRootFunctionNames = record.calledRootFunctionNames
			readsOnlyIfAvailable = record.readsOnlyIfAvailable
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
					self = .inline(BuiltRecordShape(built, children: []))
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
