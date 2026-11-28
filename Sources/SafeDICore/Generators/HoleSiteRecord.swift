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

/// The code of a hole's place: what a seam's tree writes where it builds a hole, made from the site and what the tree
/// binds at its path alone, so that a seam's tree and node records (`NodeRecords`) write it with one function.
enum HoleSitePlaces {
	/// The place of a hole `property` in a tree: where the tree holds no site (a tree built only to compute a seam's
	/// signature, or a root's, in which only a property instantiated only if available is a hole), `nil` for an optional
	/// property and nothing otherwise; else the payloads bound at its path, each a place of its own unless a loop's box holds
	/// them (`loopBindsPayloads`), then the site's own place.
	/// - Parameters:
	///   - routeMembers: The member call each step of the site's route makes (`SeamHoles.routeMembers(at:)`).
	///   - valuesBindings: The payloads the tree binds just before the site (`SeamHoles.CarrierSite.formations`).
	///   - functionName: The name of the function the site builds a wrapper around, where it is renamed.
	///   - lazilyInstantiatedInstanceProperties: The by-value properties whose labels the site's owner holds only as a
	///     `LazilyInstantiated` property.
	static func place(
		of property: Property,
		at site: SeamSignature.Hole?,
		routeMembers: [SeamSignature.Hole.RouteStep.Member?],
		functionName: String?,
		valuesBindings: [SeamHoles.ValuesBinding],
		carrierUse: SeamCarrierValues.Use?,
		readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>,
		loopBindsPayloads: Bool,
	) -> GeneratedCode {
		// A tree built only to compute the seam's signature has no site, and generates nothing. Nor has a root's tree,
		// where only a property instantiated only if available is a hole, since validation reports any other: no builder
		// reaches a root, so the property is `nil` there, as in a module that generates no seam.
		guard let site else {
			guard property.typeDescription.isOptional else { return .empty }
			return .place(PlacePlan(code: .text("let \(property.asSource) = nil"), record: .alias(recordOfPropertyBoundToNil(property))))
		}
		// The payloads bound at the site's path are places of their own, as a scope's are (`valuesBindingPlaces`), so the
		// site's place binds only its property and the function it declares; where a loop's box holds them, the site's
		// text holds them too.
		let bindingPlaces = loopBindsPayloads ? nil : valuesBindingPlaces(of: valuesBindings, readingInstancesOf: lazilyInstantiatedInstanceProperties)
		let bindingLines = bindingPlaces == nil ? valuesBindings.map { "\($0.line(readingInstancesOf: lazilyInstantiatedInstanceProperties))\n" }.joined() : ""
		let sitePlace = holeSitePlace(
			text: bindingLines + buildSiteCode(of: property, at: site, routeMembers: routeMembers, functionName: functionName, readingInstancesOf: lazilyInstantiatedInstanceProperties, carrierUse: carrierUse),
			of: property,
			at: site,
			routeMembers: routeMembers,
			functionName: functionName,
			valuesBindings: valuesBindings,
			readingInstancesOf: lazilyInstantiatedInstanceProperties,
			carrierUse: carrierUse,
		)
		guard let bindingPlaces else { return sitePlace }
		return .sequence(bindingPlaces + [sitePlace])
	}

	/// The payloads `valuesBindings` binds, each a place of its own written as its text, which lists what its line reads, so
	/// the type key lays them out as statements; `nil` where there are none.
	static func valuesBindingPlaces(of valuesBindings: [SeamHoles.ValuesBinding], readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>) -> [GeneratedCode]? {
		guard !valuesBindings.isEmpty else { return nil }
		return valuesBindings.map { binding in
			let line = binding.line(readingInstancesOf: lazilyInstantiatedInstanceProperties)
			let record = AliasPlaceRecord(
				property: Property(label: binding.bindingName, typeDescription: binding.boundType),
				fulfillingProperty: nil,
				text: line,
				reads: binding.reads(readingInstancesOf: lazilyInstantiatedInstanceProperties),
			)
			return .place(PlacePlan(code: .text("\(line)\n"), record: .alias(record)))
		}
	}

	/// The record of `property` bound to `nil`, which reads nothing.
	static func recordOfPropertyBoundToNil(_ property: Property) -> AliasPlaceRecord {
		AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "let \(property.asSource) = nil", reads: [])
	}

	/// The code a seam's tree generates at a site of `property`, a hole: the member of its case called on the builder struct
	/// in scope there, handed the values in scope there. A constant is bound with its declared type, as inline binds an
	/// existential. An instantiator is built around what its member returns, the builder the wrapper keeps, with no function
	/// of the seam's own. Any other wrapper is built around a function that makes the call, as inline builds a wrapper around
	/// its builder function, which is `@Sendable` for a `Sendable` wrapper.
	/// - Parameters:
	///   - routeMembers: The member call each step of the site's route makes (`SeamHoles.routeMembers(at:)`).
	///   - functionName: The name of that function where it differs from `functionName(toBuild:)`.
	///   - lazilyInstantiatedInstanceProperties: The by-value properties whose labels the site's owner holds only as a
	///     `LazilyInstantiated` property, whose instance the payload reads, as the owner's receivers do
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:)`).
	///   - lazilyInstantiatedBindingNames: In a public mock, the names the wrappers it binds apart from their instances' labels
	///     have where the site is built, which the payload reads a field of such a wrapper by
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:bindingNamesPassedByName:lazilyInstantiatedBindingNames:)`).
	// Kept out of `generatePropertyCode`'s async frame, as the functions that write a property's scope are.
	@inline(never)
	static func buildSiteCode(of property: Property, at site: SeamSignature.Hole, routeMembers: [SeamSignature.Hole.RouteStep.Member?], functionName: String?, readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property> = [], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:], carrierUse: SeamCarrierValues.Use? = nil) -> String {
		// A place nested by type is handed what its owner binds before it; the cases that lead to it carry what each type on
		// the way binds, which the tree bound before building the next. A place in a `@Sendable` enum held in a `Sendable`
		// wrapper carries nothing.
		let fields = site.enumPlace?.values ?? site.fields
		let arguments = SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)
		// The expression that builds the value: the place's member, called on the struct the last case on its route returned,
		// or on the builder itself. An instantiator's member returns the builder its wrapper keeps. Every place of a seam's or
		// a public mock's tree has its enum's case, whose member takes a struct (`SeamBuilderFamilies`). The `""` is never
		// returned: a hole is built before its place's case is known, so `enumPlace` is optional, and it is assigned to every
		// place before any code is generated; no type holds that order. 2.3.1's emitter rewrite replaces this code and drops
		// the fallback.
		guard let enumPlace = site.enumPlace, let memberValuesTypeName = enumPlace.memberValuesTypeName else { return "" }
		let valuesType = TypeDescription.nested(name: memberValuesTypeName, parentType: enumPlace.enumType(qualifiedBy: nil), generics: [])
		// Inside a fill whose call's case leads on, the fill is handed the struct of its own level.
		let lastStep = enumPlace.route.last
		let lastMember = routeMembers.last ?? nil
		let parentName = (lastMember == nil ? nil : lastStep?.innerScope?.name) ?? lastMember?.bindingName ?? site.internalName
		let buildExpression = if ReservedName.seamCarrier(ofEnum: enumPlace.enumType(qualifiedBy: nil)) != nil {
			// A seam's carrier takes the place's values as its member's arguments.
			"\(parentName).\(enumPlace.caseName)(\(SeamHoles.carrierArguments(of: fields, use: carrierUse, readingInstancesOf: lazilyInstantiatedInstanceProperties, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)))"
		} else {
			"\(parentName).\(enumPlace.caseName)(\(valuesType.asSource)(\(arguments)))"
		}
		let propertyType = property.propertyType
		guard !propertyType.isConstant else {
			return "let \(property.asSource) = \(buildExpression)"
		}
		let unwrappedType = property.typeDescription.unwrapped
		// A type constructed by annotation spells its generic arguments only in the declaration's annotation.
		let declaration = property.typeDescription.asSource == unwrappedType.spelledForConstruction ? "let \(property.label)" : "let \(property.asSource)"
		guard !propertyType.isAnyInstantiator else {
			// An instantiator's member returns the builder the wrapper keeps, which takes the forwarded value itself.
			return "\(declaration) = \(unwrappedType.spelledForConstruction)(\(buildExpression))"
		}
		let functionName = functionName ?? site.wrapperFunctionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
		return """
		\(ScopeGenerator.localFunctionPrefix(isSendable: propertyType.isSendable))func \(functionName)() -> \(site.builtType.asSource) {
		\(ScopeGenerator.standardIndent)\(buildExpression)
		}
		\(declaration) = \(unwrappedType.spelledForConstruction)(\(functionName))
		"""
	}

	/// The place of a hole's site in a seam's tree, written as `text`: `buildSiteCode`'s code. The payloads bound at its path
	/// (`valuesBindings`) are places of their own, before it, which type the names it reads; where a loop's box holds them
	/// instead, the text binds them too, and the record lists none of them, since a body a loop's levels are bound in is
	/// one the type key does not plan (`isPlannedByTypeKey`), so it is written per path whatever the site records. It is
	/// recorded as a place the type key copies as written (`AliasPlaceRecord`): it binds the hole's property, declares the
	/// function it builds a wrapper around, and reads the builder struct or level it calls a member of and each value it
	/// hands that member, as the path key resolves them.
	/// Where a read is of a value no binding of the seam's tree types – the struct a fill is handed, or a level bound by a
	/// call's route from another builder – it records no reads, which keeps the place and the bodies enclosing it one per
	/// path.
	// Kept out of `generatePropertyCode`'s async frame, as the functions that write a property's scope are.
	@inline(never)
	private static func holeSitePlace(
		text: String,
		of property: Property,
		at site: SeamSignature.Hole,
		routeMembers: [SeamSignature.Hole.RouteStep.Member?],
		functionName: String?,
		valuesBindings: [SeamHoles.ValuesBinding],
		readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>,
		carrierUse: SeamCarrierValues.Use?,
	) -> GeneratedCode {
		var recorder = HoleSiteReads(site: site, routeMembers: routeMembers, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties, carrierUse: carrierUse)
		for binding in valuesBindings {
			recorder.type(binding)
		}
		let wrapperFunction = recorder.recordSite(of: property, functionName: functionName)
		let record = AliasPlaceRecord(
			property: property,
			fulfillingProperty: nil,
			text: text,
			reads: recorder.reads,
			calledFunctionNames: [],
			declaredFunctionNames: wrapperFunction.map { [$0] } ?? [],
		)
		if let observer = HoleSiteRecordObservation.observer {
			observer(HoleSiteRecordObservation(text: text, readNames: record.reads?.map(\.label), boundNames: [record.property.label] + record.otherBindings.map(\.label) + record.declaredFunctionNames))
		}
		return .place(PlacePlan(code: .text(text), record: .alias(record)))
	}
}

/// The reads a hole's site makes, as `holeSitePlace` records them, in the order its text makes them, each name once.
private struct HoleSiteReads {
	init(site: SeamSignature.Hole, routeMembers: [SeamSignature.Hole.RouteStep.Member?], lazilyInstantiatedInstanceProperties: Set<Property>, carrierUse: SeamCarrierValues.Use?) {
		self.site = site
		lastMember = routeMembers.last ?? nil
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		self.carrierUse = carrierUse
		// The type of each struct a member call is made on by name: the root builder's, and each level its route binds. A
		// level's type is spelled over the type the builder builds, which is the root's too.
		guard let enumPlace = site.enumPlace else { return }
		let members = routeMembers.compactMap(\.self)
		// A level is spelled over the type the builder builds, its innermost generic argument (`ReservedName.levelType(ofEnum:built:)`).
		let builtType = members.lazy.compactMap(\.levelType.genericArgumentsOfThisAndEnclosingTypes.last).first ?? site.builtType
		let rootEnumType = TypeDescription.simple(name: enumPlace.rootEnumTypeName ?? enumPlace.enumTypeName, generics: [])
		levelTypesByName[site.internalName] = ReservedName.levelType(ofEnum: rootEnumType, built: builtType)
		for member in members {
			levelTypesByName[member.bindingName] = member.levelType
		}
		structStaysOutsideSendableFunctions = !enumPlace.isBuiltBySendableBuilder
	}

	/// What the site reads, or `nil` once a read is of a value no binding of the seam's tree types.
	private(set) var reads: [PlaceRead]? = []
	/// Types `binding`'s name, bound by a place before the site's.
	mutating func type(_ binding: SeamHoles.ValuesBinding) {
		levelTypesByName[binding.bindingName] = binding.boundType
	}

	/// Records the site's own code, as `HoleSitePlaces.buildSiteCode` writes it, and returns the name of the function it
	/// declares to build the wrapper the property is held in, where it declares one.
	mutating func recordSite(of property: Property, functionName: String?) -> String? {
		// Every site has its place's case before code is generated, so `buildSiteCode` writes the member call this records;
		// where it has none, the site writes nothing and reads nothing, as `reads` starts.
		guard let enumPlace = site.enumPlace, enumPlace.memberValuesTypeName != nil else { return nil }
		let fields = enumPlace.values
		let lastStep = enumPlace.route.last
		if lastMember != nil, lastStep?.innerScope != nil {
			// The struct of a fill's own level, which the fill is handed.
			reads = nil
		} else {
			let parentName = lastMember?.bindingName ?? site.internalName
			readStruct(named: parentName, ofType: levelTypesByName[parentName])
		}
		if ReservedName.seamCarrier(ofEnum: enumPlace.enumType(qualifiedBy: nil)) != nil {
			readCarrierArguments(of: fields, use: carrierUse)
		} else {
			readFields(fields)
		}
		let propertyType = property.propertyType
		guard !propertyType.isConstant, !propertyType.isAnyInstantiator else { return nil }
		return functionName ?? site.wrapperFunctionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label)
	}

	// MARK: Private

	private let site: SeamSignature.Hole
	/// The member call the last step of the site's route makes, whose result the site's own member is called on.
	private let lastMember: SeamSignature.Hole.RouteStep.Member?
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	private let carrierUse: SeamCarrierValues.Use?
	private var levelTypesByName = [String: TypeDescription]()
	private var structStaysOutsideSendableFunctions = true
	private var readNames = Set<String>()

	private mutating func read(_ read: PlaceRead) {
		guard readNames.insert(read.label).inserted else { return }
		reads?.append(read)
	}

	/// A read of the struct bound as `name`, a builder, a level or a run, of `type`; `nil` where no binding types it.
	private mutating func readStruct(named name: String, ofType type: TypeDescription?) {
		// Every struct a site calls a member of is typed: the builder and each level of its route in `init`, a run by its use.
		guard let type else { return reads = nil }
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
}

/// A hole's site as `HoleSitePlaces.holeSitePlace` records it: its text, the names its record says it reads, and the
/// names it binds or declares. Handed to `observer`, which the tests set to check that the record lists every value the
/// text reads, binds and declares, and nothing else, where the site's code is generated in a task that inherits it.
public struct HoleSiteRecordObservation: Sendable {
	/// The site's code.
	public let text: String
	/// The names the record says the text reads, or `nil` where it records none.
	public let readNames: [String]?
	/// The names the record says the text binds, and the functions it declares.
	public let boundNames: [String]

	/// Called with each hole's site as it is recorded, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (HoleSiteRecordObservation) -> Void>?
}
