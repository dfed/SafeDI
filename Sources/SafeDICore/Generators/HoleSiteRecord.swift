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

extension ScopeGenerator {
	/// The place of a hole's site in a seam's tree, written as `text`, the payloads bound at its path (`valuesBindings`)
	/// followed by `buildSiteCode`'s code, recorded as a place the type key copies as written (`AliasPlaceRecord`): it binds
	/// the hole's property, and each payload and wrapper function it declares besides, and reads the builder struct or
	/// level it calls a member of and each value it hands that member, as the path key resolves them. Where a read is of a
	/// value no binding of the seam's tree types – the struct a fill is handed, or a level bound by a call's route from
	/// another builder – it records no reads, which keeps the place and the bodies enclosing it one per path.
	// Kept out of `generatePropertyCode`'s async frame, as the functions that write a property's scope are.
	@inline(never)
	static func holeSitePlace(
		text: String,
		of property: Property,
		at site: SeamSignature.Hole,
		functionName: String?,
		valuesBindings: [SeamHoles.ValuesBinding],
		readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>,
		carrierUse: SeamCarrierValues.Use?,
	) -> GeneratedCode {
		var recorder = HoleSiteReads(site: site, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties, carrierUse: carrierUse)
		for binding in valuesBindings {
			recorder.record(binding)
		}
		let wrapperFunction = recorder.recordSite(of: property, functionName: functionName)
		let record = AliasPlaceRecord(
			property: property,
			fulfillingProperty: nil,
			text: text,
			reads: recorder.reads,
			otherBindings: recorder.otherBindings + (wrapperFunction.map { [$0] } ?? []),
			calledFunctionNames: [],
		)
		if let observer = HoleSiteRecordObservation.observer {
			observer(HoleSiteRecordObservation(text: text, readNames: record.reads?.map(\.label), boundNames: [record.property.label] + record.otherBindings.map(\.label)))
		}
		return .place(PlacePlan(code: .text(text), record: .alias(record)))
	}
}

/// The reads a hole's site makes, as `holeSitePlace` records them, in the order its text makes them, each name once: a name
/// the site's own text binds before reading it is no read.
private struct HoleSiteReads {
	init(site: SeamSignature.Hole, lazilyInstantiatedInstanceProperties: Set<Property>, carrierUse: SeamCarrierValues.Use?) {
		self.site = site
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		self.carrierUse = carrierUse
		// The type of each struct a member call is made on by name: the root builder's, and each level its route binds. A
		// level's type is spelled over the type the builder builds, which is the root's too.
		guard let enumPlace = site.enumPlace else { return }
		let members = enumPlace.route.compactMap(\.member)
		let builtType = members.lazy.compactMap { Self.builtType(ofLevel: $0.levelType) }.first ?? site.builtType
		let rootEnumType = TypeDescription.simple(name: enumPlace.rootEnumTypeName ?? enumPlace.enumTypeName, generics: [])
		levelTypesByName[site.internalName] = ReservedName.levelType(ofEnum: rootEnumType, built: builtType)
		for member in members {
			levelTypesByName[member.bindingName] = member.levelType
		}
		structStaysOutsideSendableFunctions = !enumPlace.isBuiltBySendableBuilder
	}

	/// What the site reads, or `nil` once a read is of a value no binding of the seam's tree types.
	private(set) var reads: [PlaceRead]? = []
	/// The payloads the site binds besides its property.
	private(set) var otherBindings = [Property]()

	/// Records `binding`, bound before the site's own code.
	mutating func record(_ binding: SeamHoles.ValuesBinding) {
		if binding.formsRunAfter != nil {
			// A run's struct reads the run before it, bound at this path or at another of the body that binds the level.
			if let previousName = binding.formsRunAfter ?? nil {
				readStruct(named: previousName, ofType: previousRunType(of: binding))
			}
			readFields(binding.fields)
		} else if case let .nested(_, enumType, _) = binding.type, ReservedName.seamCarrier(ofEnum: enumType) != nil {
			readStruct(named: binding.memberCall.parentName, ofType: levelTypesByName[binding.memberCall.parentName])
			if !binding.isLetChild {
				readCarrierArguments(of: binding.fields, use: binding.carrierUse)
			}
		} else {
			readStruct(named: binding.memberCall.parentName, ofType: levelTypesByName[binding.memberCall.parentName])
			readFields(binding.fields)
		}
		bind(Property(label: binding.bindingName, typeDescription: binding.boundType))
	}

	/// Records the site's own code, as `ScopeGenerator.buildSiteCode` writes it, and returns the function it declares to
	/// build the wrapper the property is held in, where it declares one.
	mutating func recordSite(of property: Property, functionName: String?) -> Property? {
		guard let enumPlace = site.enumPlace, enumPlace.memberValuesTypeName != nil else {
			// The site writes nothing (`buildSiteCode`), so it reads nothing.
			reads = []
			return nil
		}
		let fields = enumPlace.values
		let lastStep = enumPlace.route.last
		if lastStep?.member != nil, lastStep?.innerScope != nil {
			// The struct of a fill's own level, which the fill is handed.
			reads = nil
		} else {
			let parentName = lastStep?.member?.bindingName ?? site.internalName
			readStruct(named: parentName, ofType: levelTypesByName[parentName])
		}
		if ReservedName.seamCarrier(ofEnum: enumPlace.enumType(qualifiedBy: nil)) != nil {
			readCarrierArguments(of: fields, use: carrierUse)
		} else {
			readFields(fields)
		}
		let propertyType = property.propertyType
		guard !propertyType.isConstant, !propertyType.isAnyInstantiator else { return nil }
		let functionType = TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: site.builtType)
		return Property(
			label: functionName ?? site.wrapperFunctionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			typeDescription: propertyType.isSendable ? .attributed(functionType, specifiers: [], attributes: ["Sendable"]) : functionType,
		)
	}

	// MARK: Private

	private let site: SeamSignature.Hole
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	private let carrierUse: SeamCarrierValues.Use?
	private var levelTypesByName = [String: TypeDescription]()
	private var structStaysOutsideSendableFunctions = true
	private var boundNames = Set<String>()
	private var readNames = Set<String>()

	private mutating func bind(_ property: Property) {
		boundNames.insert(property.label)
		otherBindings.append(property)
		levelTypesByName[property.label] = property.typeDescription
	}

	private mutating func read(_ read: PlaceRead) {
		guard !boundNames.contains(read.label), readNames.insert(read.label).inserted else { return }
		reads?.append(read)
	}

	/// A read of the struct bound as `name`, a builder, a level or a run, of `type`; `nil` where no binding types it.
	private mutating func readStruct(named name: String, ofType type: TypeDescription?) {
		guard !boundNames.contains(name) else { return }
		guard let type else {
			reads = nil
			return
		}
		read(PlaceRead(
			argumentLabel: name,
			label: name,
			property: Property(label: name, typeDescription: type),
			source: .binding(label: name),
			staysOutsideSendableFunctions: structStaysOutsideSendableFunctions,
		))
	}

	/// The reads `SeamHoles.valuesArguments(of:readingInstancesOf:)` makes of `fields`: each by its label, the instance of a
	/// `LazilyInstantiated` the label names where the site's owner holds the value only as one, and a deferred parameter's
	/// memo as itself. SafeDI cannot tell a value's type is `Sendable`, so none crosses into a `@Sendable` function.
	private mutating func readFields(_ fields: some Sequence<SeamSignature.Hole.Field>) {
		for field in fields {
			let label = field.property.label
			let readsInstance = !field.isDeferredParameter && lazilyInstantiatedInstanceProperties.contains(field.property.asUnwrappedProperty)
			read(PlaceRead(
				argumentLabel: label,
				label: label,
				property: field.isDeferredParameter ? Property(label: label, typeDescription: field.memoType ?? field.property.typeDescription) : field.property,
				source: readsInstance ? .lazyInstance(label: label, throughOptional: false) : .binding(label: label),
				staysOutsideSendableFunctions: true,
			))
		}
	}

	/// The reads `SeamHoles.carrierArguments(of:use:readingInstancesOf:)` makes: the struct of the run the values end, then
	/// each value after it.
	private mutating func readCarrierArguments(of fields: [SeamSignature.Hole.Field], use: SeamCarrierValues.Use?) {
		if let use, let name = use.structBindingName {
			readStruct(named: name, ofType: use.structType(qualifiedBy: nil))
		}
		readFields(fields[(use?.extras ?? 0..<fields.count).clamped(to: 0..<fields.count)])
	}

	/// The type of the run before the one `binding` forms, of the level the site's carrier takes its values from.
	private func previousRunType(of binding: SeamHoles.ValuesBinding) -> TypeDescription? {
		guard let carrierUse,
		      let end = carrierUse.ends.first(where: { SeamCarrierValues.structType(ofLevel: carrierUse.level, end: $0, qualifiedBy: nil) == binding.type }),
		      let previousEnd = carrierUse.ends.last(where: { $0 < end })
		else { return nil }
		return SeamCarrierValues.structType(ofLevel: carrierUse.level, end: previousEnd, qualifiedBy: nil)
	}

	/// The type a level's struct or carrier is spelled over (`ReservedName.levelType(ofEnum:built:)`).
	private static func builtType(ofLevel levelType: TypeDescription) -> TypeDescription? {
		switch levelType {
		case let .nested(_, _, generics),
		     let .simple(_, generics):
			generics.first
		case .void, .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .variadic, .unknown:
			nil
		}
	}
}

/// A hole's site as `ScopeGenerator.holeSitePlace` records it: its text, the names its record says it reads, and the
/// names it binds. Handed to `observer`, which the tests set to check that the record lists every value the text reads
/// and binds, and nothing else, where the site's code is generated in a task that inherits it.
public struct HoleSiteRecordObservation: Sendable {
	/// The site's code.
	public let text: String
	/// The names the record says the text reads, or `nil` where it records none.
	public let readNames: [String]?
	/// The names the record says the text binds.
	public let boundNames: [String]

	/// Called with each hole's site as it is recorded, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (HoleSiteRecordObservation) -> Void)?
}
