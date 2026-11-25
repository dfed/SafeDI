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

import SafeDICore

// How a module info file holds the places of its module's seams (`ModuleSeamSignatures`). A seam that calls another
// seam passes that seam's unfilled places up, and its signature holds a copy of each, so a place was written again in
// the file of every module above the one that declares it, and a file grew with everything beneath its module. A
// passed-up place is instead written as the record of the seam it was passed up from and what the call adds, and read
// back from that record (`PlaceResolver`), so a file holds what its own module adds.

/// A seam whose records a module's passed-up places are read from: a seam the module's own seams call.
struct StoredLowerSeam: Codable, Sendable {
	/// The module that declares the seam, or the empty string for the module the places are of.
	let moduleName: String
	let seamType: TypeDescription
	/// The checksum of the places that module's file holds (`ModuleSeamSignatures.placesChecksum`), or zero for the module
	/// the places are of. A read whose file of that module holds other places reads none of them.
	let checksum: UInt64
}

/// A record of a seam a module's seams call: the place at `record` among the places of the seam at `lowerSeam` among
/// the module's `StoredModulePlaces.lowerSeams`.
struct StoredRecordReference: Codable, Sendable {
	let lowerSeam: Int
	let record: Int
}

/// How the seam that passes a place up names and admits its builder, where that differs from the record's.
struct StoredPlacePresentation: Codable, Sendable {
	init(_ hole: SeamSignature.Hole) {
		declaringModuleNames = hole.declaringModuleNames
		builderLabel = hole.builderLabel
		narrowerTierBuilderLabels = hole.narrowerTierBuilderLabels
		internalName = hole.internalName
		tierAccess = hole.tierAccess
		accessCause = hole.accessCause
		wrapperFunctionName = hole.wrapperFunctionName
	}

	init(declaringModuleNames: [String], builderLabel: String, narrowerTierBuilderLabels: [AccessLevel: String], internalName: String, tierAccess: AccessLevel, accessCause: TypeAccessProof.Cause?, wrapperFunctionName: String?) {
		self.declaringModuleNames = declaringModuleNames
		self.builderLabel = builderLabel
		self.narrowerTierBuilderLabels = narrowerTierBuilderLabels
		self.internalName = internalName
		self.tierAccess = tierAccess
		self.accessCause = accessCause
		self.wrapperFunctionName = wrapperFunctionName
	}

	let declaringModuleNames: [String]
	let builderLabel: String
	let narrowerTierBuilderLabels: [AccessLevel: String]
	let internalName: String
	let tierAccess: AccessLevel
	let accessCause: TypeAccessProof.Cause?
	let wrapperFunctionName: String?
}

extension StoredPlacePresentation {
	/// Whether this is how `record` names and admits its builder, as far as that is seen without writing both: a
	/// presentation that differs only where this does not look is written, which costs its bytes.
	func isPlainlyThat(of record: SeamSignature.Hole) -> Bool {
		accessCause == nil && record.accessCause == nil
			&& builderLabel == record.builderLabel && internalName == record.internalName
			&& declaringModuleNames == record.declaringModuleNames && narrowerTierBuilderLabels == record.narrowerTierBuilderLabels
			&& tierAccess == record.tierAccess && wrapperFunctionName == record.wrapperFunctionName
	}
}

/// One run of the declarations a passed-up place cannot read (`SeamSignature.Hole.uncarriedDeclarations`).
enum StoredPlaceDeclaration: Codable, Sendable {
	/// Every declaration of the record, in order. Places with records of different lengths then write the same addition.
	case record
	/// `count` declarations of the record, from the one at `first`.
	case kept(first: Int, count: Int)
	/// The declaration at `declaration` of the record at `other` among the place's other records
	/// (`StoredPassedUpPlace.others`): a call of another seam presents the same site, and the place keeps the
	/// declarations of every call.
	case taken(other: Int, declaration: Int)
	/// A declaration bound on the path to a call, whose reason names the place the call presents
	/// (`SeamSignature.Hole.UncarriedDeclaration.Reason.boundByPassingUpSeam`): the record's where `placeOf` is zero,
	/// and otherwise the record's at `placeOf - 1` among the place's other records. `declaration` holds a stand-in for
	/// that place, so every place one call presents writes the same declarations, once.
	case boundOnPath(declaration: SeamSignature.Hole.UncarriedDeclaration, placeOf: Int)
	/// A declaration no record holds.
	case written(SeamSignature.Hole.UncarriedDeclaration)
}

/// What a call adds to a record it passes up, which is the same for every place the call presents alike, so a file
/// writes each once (`BinaryWriter.writeSharedByBytes(_:)`).
struct StoredPlaceAddition: Codable, Sendable {
	/// The types from the passing seam to the call, which precede the record's `typesToOwner`.
	let typesToCall: [SeamSignature.Hole.PathType]
	/// The properties from the passing seam's root to the call, which precede the record's `passedUpRoute`.
	let route: [SeamSignature.Hole.DeclaredProperty]
	let isSendable: Bool
	let declarations: [StoredPlaceDeclaration]
	/// The place's `reenteringCallDeclarations` where they are not the record's: a seam that calls the record's seam
	/// inside a fill built again gives the place its own.
	let reenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration]?
	/// The place's `reenteringPlaceFields` where they are not the record's.
	let reenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField]?
}

/// A place a seam passes up, as the record it copies and what the seam adds.
struct StoredPassedUpPlace: Codable, Sendable {
	/// The record the place copies: the place of the seam the call builds, whose type is the place's `innerSeamType`.
	let record: StoredRecordReference
	/// The records of the same site that other seams the passing seam calls hold, which `addition` reads.
	let others: [StoredRecordReference]
	/// `nil` where the passing seam names and admits the builder as the record does.
	let presentation: StoredPlacePresentation?
	let addition: StoredPlaceAddition
}

/// A place of a seam, as a module info file holds it.
enum StoredPlace: Codable, Sendable {
	/// A place in the seam's own tree, or a passed-up place that does not read back from its record.
	case written(SeamSignature.Hole)
	case passedUp(StoredPassedUpPlace)
}

/// The places of a module's seams, which a module info file holds apart from the rest of their signatures, so that a
/// read of a place passed up through the module reads no enum, builder or route of it.
struct StoredModulePlaces: Codable, Sendable {
	let lowerSeams: [StoredLowerSeam]
	/// The places of each of the module's seams, in the order of `ModuleSeamSignatures.seamTypes`: none for a seam
	/// without a signature.
	let placesBySeam: [[StoredPlace]]
}

/// The check a run makes of each passed-up place it writes as a record (`ModulePlacesEncoder`).
enum StoredPlaceWriteCheck {
	/// Returns the place the check compares in place of `readBack`, what the record written reads back as, given the
	/// `record` it copies: set by a test that makes the check fail, never by the tool.
	@TaskLocal static var alteringPlaceReadBack: (@Sendable (_ readBack: SeamSignature.Hole, _ record: SeamSignature.Hole) -> SeamSignature.Hole)?
}

/// A module info file's places cannot be read: the caller computes every signature instead
/// (`Generate.generate(buildLog:)`).
enum StoredPlaceError: Error, CustomStringConvertible {
	/// The files hold no places of `seam` in the module named `moduleName`, or other places than the ones a passed-up
	/// place was written against.
	case lowerPlacesUnavailable(moduleName: String, seam: TypeDescription)
	/// A place of the module named `moduleName` names a record or a declaration its files do not hold, or records that
	/// name one another.
	case malformedPlace(moduleName: String)

	var description: String {
		switch self {
		case let .lowerPlacesUnavailable(moduleName, seam):
			"The module info given holds no places of `\(seam.asSource)` in module `\(moduleName)` that match the ones a place passed up from it was written against."
		case let .malformedPlace(moduleName):
			"The module info of module `\(moduleName)` holds a place that names a record it does not hold."
		}
	}
}

/// A place as it is read from a module info file: the place written whole at the end of the records it was passed up
/// through, and what each seam on the way added. A place passed up through a chain of seams is read from each record
/// in turn, and only the places a run asks for are made whole (`place`), so reading a record costs what its seam adds,
/// never what the seams beneath it added.
struct ReadPlace {
	init(_ written: SeamSignature.Hole) {
		self.written = written
		presentation = StoredPlacePresentation(written)
		typesToOwner = .elements(written.typesToOwner)
		passedUpRoute = .elements(written.passedUpRoute)
		innerSeamType = written.innerSeamType
		isSendable = written.isSendable
		declarations = .run(written.uncarriedDeclarations[...])
		reenteringCallDeclarations = written.reenteringCallDeclarations
		reenteringPlaceFields = written.reenteringPlaceFields
	}

	/// The place as a signature holds it.
	var place: SeamSignature.Hole {
		place(sitePath: written.sitePath)
	}

	/// The place's site.
	var site: SeamSignature.Hole.Site {
		written.site
	}

	/// The place as a signature holds it, with `sitePath`, which equals its own, as its site's path: the generator
	/// looks sites up in sets of the sites a signature's enums hold, and two paths that share storage compare at once.
	func place(sitePath: [Property]) -> SeamSignature.Hole {
		SeamSignature.Hole(
			storing: written.ownerType,
			declaringModuleNames: presentation.declaringModuleNames,
			property: written.property,
			instantiatedType: written.instantiatedType,
			declarationLocation: written.declarationLocation,
			erasedToConcreteExistential: written.erasedToConcreteExistential,
			sitePath: sitePath,
			declaredSitePath: written.declaredSitePath,
			fillPropertyStack: written.fillPropertyStack,
			fillConcreteTypeStack: written.fillConcreteTypeStack,
			builderLabel: presentation.builderLabel,
			narrowerTierBuilderLabels: presentation.narrowerTierBuilderLabels,
			internalName: presentation.internalName,
			scopeSeamType: written.scopeSeamType,
			scopeSeamModule: written.scopeSeamModule,
			typesToOwner: typesToOwner.elements,
			scopeTypeName: written.scopeTypeName,
			enumPlace: written.enumPlace,
			wrapperFunctionName: presentation.wrapperFunctionName,
			fields: written.fields,
			tierAccess: presentation.tierAccess,
			accessCause: presentation.accessCause,
			uncarriedDeclarations: declarations.elements,
			cycleReentryDeclarations: written.cycleReentryDeclarations,
			reenteringCallDeclarations: reenteringCallDeclarations,
			reenteringPlaceFields: reenteringPlaceFields,
			declarationsHiddenByFields: written.declarationsHiddenByFields,
			innerSeamType: innerSeamType,
			passedUpRoute: passedUpRoute.elements,
			isSendable: isSendable,
		)
	}

	// MARK: Fileprivate

	/// The place written whole, whose own fields every copy passed up keeps.
	fileprivate let written: SeamSignature.Hole
	fileprivate var presentation: StoredPlacePresentation
	fileprivate var typesToOwner: Prefixed<SeamSignature.Hole.PathType>
	fileprivate var passedUpRoute: Prefixed<SeamSignature.Hole.DeclaredProperty>
	fileprivate var innerSeamType: TypeDescription?
	fileprivate var isSendable: Bool
	fileprivate var declarations: Runs
	fileprivate var reenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration]
	fileprivate var reenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField]

	/// The place as its seam presents it to a call (`SeamSignature.Hole.UncarriedDeclaration.PresentedPlace.init(_:)`).
	fileprivate var presentedPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace {
		.init(storing: written.scopeSeamType, ownerType: written.ownerType, property: written.property, instantiatedType: written.instantiatedType, builderLabel: presentation.builderLabel, caseName: written.enumPlace?.caseName, isBuiltBySendableBuilder: written.enumPlace?.isBuiltBySendableBuilder ?? false)
	}

	/// The elements of a record with what each seam above put before them, each seam's kept as it added them: a copy
	/// passed up shares its record's, so a chain of copies holds each element once.
	indirect fileprivate enum Prefixed<Element> {
		case elements([Element])
		case prefixed([Element], Prefixed<Element>)

		var elements: [Element] {
			var elements = [Element]()
			var rest = self
			while case let .prefixed(prefix, following) = rest {
				elements += prefix
				rest = following
			}
			if case let .elements(last) = rest {
				elements += last
			}
			return elements
		}
	}

	/// The declarations a place cannot read, as the runs each record on the way added, in order: a copy passed up shares
	/// its record's runs.
	indirect fileprivate enum Runs {
		case run(ArraySlice<SeamSignature.Hole.UncarriedDeclaration>)
		case joined([Runs], count: Int)

		var count: Int {
			switch self {
			case let .run(run):
				run.count
			case let .joined(_, count):
				count
			}
		}

		var elements: [SeamSignature.Hole.UncarriedDeclaration] {
			var elements = [SeamSignature.Hole.UncarriedDeclaration]()
			elements.reserveCapacity(count)
			// The runs still to add, the next one last: runs joined as deep as the records are followed without a function
			// that calls itself.
			var runsToAdd = [self]
			while let next = runsToAdd.popLast() {
				switch next {
				case let .run(run):
					elements += run
				case let .joined(runs, _):
					runsToAdd += runs.reversed()
				}
			}
			return elements
		}

		/// `count` of the declarations from the one at `first`, or `nil` when there are fewer.
		func declarations(first: Int, count: Int) -> Runs? {
			guard first >= 0, count >= 0, first <= self.count - count else { return nil }
			return first == 0 && count == self.count ? self : .run(elements[first..<first + count])
		}
	}
}

extension StoredPassedUpPlace {
	/// The place read from `record`, the place its `record` names, of the seam `innerSeamType`, and `others`, the places
	/// its `others` name, or `nil` when it names a declaration they do not hold.
	func place(record: ReadPlace, innerSeamType: TypeDescription, others: [ReadPlace]) -> ReadPlace? {
		var runs = [ReadPlace.Runs]()
		var count = 0
		for stored in addition.declarations {
			switch stored {
			case .record:
				runs.append(record.declarations)
				count += record.declarations.count
			case let .kept(first, keptCount):
				guard let kept = record.declarations.declarations(first: first, count: keptCount) else { return nil }
				runs.append(kept)
				count += keptCount
			case let .taken(other, declaration):
				guard others.indices.contains(other), let taken = others[other].declarations.declarations(first: declaration, count: 1) else { return nil }
				runs.append(taken)
				count += 1
			case let .boundOnPath(declaration, placeOf):
				guard case let .boundByPassingUpSeam(seam, module, _) = declaration.reason, placeOf >= 0, placeOf <= others.count else { return nil }
				let presented = placeOf == 0 ? record : others[placeOf - 1]
				runs.append(.run([declaration.withReason(.boundByPassingUpSeam(seam: seam, module: module, place: presented.presentedPlace))]))
				count += 1
			case let .written(declaration):
				runs.append(.run([declaration]))
				count += 1
			}
		}
		var place = record
		if let presentation {
			place.presentation = presentation
		}
		place.typesToOwner = .prefixed(addition.typesToCall, record.typesToOwner)
		place.passedUpRoute = .prefixed(addition.route, record.passedUpRoute)
		place.innerSeamType = innerSeamType
		place.isSendable = addition.isSendable
		place.declarations = .joined(runs, count: count)
		if let reenteringCallDeclarations = addition.reenteringCallDeclarations {
			place.reenteringCallDeclarations = reenteringCallDeclarations
		}
		if let reenteringPlaceFields = addition.reenteringPlaceFields {
			place.reenteringPlaceFields = reenteringPlaceFields
		}
		return place
	}
}

extension SeamSignature.Hole.UncarriedDeclaration {
	/// The declaration with `reason` in place of its own.
	fileprivate func withReason(_ reason: Reason) -> Self {
		Self(storing: property, declaringType: declaringType, declarationLocation: declarationLocation, parameterTakingType: parameterTakingType, builtAfter: builtAfter, reason: reason, isBoundFromCallersArgument: isBoundFromCallersArgument, isBuildableAboveSeam: isBuildableAboveSeam, labelsHeldAboveSeam: labelsHeldAboveSeam, placesInTree: placesInTree, holdsPlaceFilledElsewhere: holdsPlaceFilledElsewhere)
	}
}

/// Reads the places of seams from the module info files a run was given, each record once, and a module's places only
/// when a place read came through that module.
///
/// A place passed up through a chain of seams names the record of the seam beneath, which names the next. The chain is
/// followed with a list of the records still to read, never by a function that calls itself, so a chain as deep as the
/// module graph reads in constant stack. A resolver is a value one read owns: nothing is shared between tasks.
struct PlaceResolver {
	/// - Parameters:
	///   - signaturesByModuleName: What the files hold of each module's seams, by module name.
	///   - openedModules: The places of the modules already read, by module name.
	init(signaturesByModuleName: [String: ModuleSeamSignatures], openedModules: [String: OpenedModule] = [:]) {
		self.signaturesByModuleName = signaturesByModuleName
		for moduleName in openedModules.keys.sorted() {
			if let opened = openedModules[moduleName] {
				moduleIndices[moduleName] = modules.count
				modules.append(Module(opened))
			}
		}
	}

	/// The places a file holds of one module's seams, read.
	struct OpenedModule: Sendable {
		/// Reads the places `signatures` holds of the module named `moduleName`.
		init(reading signatures: ModuleSeamSignatures, ofModuleNamed moduleName: String) throws {
			places = try signatures.storedPlaces
			guard places.placesBySeam.count == signatures.seamTypes.count else {
				throw StoredPlaceError.malformedPlace(moduleName: moduleName)
			}
			GenerationWork.recordStoredPlaces(1, by: .openingStoredPlaces)
			// Of two signatures of one seam, the first is kept, as a run that reads them keeps it.
			seamIndices = Dictionary(zip(signatures.seamTypes, signatures.seamTypes.indices), uniquingKeysWith: { first, _ in first })
			checksum = signatures.placesChecksum
		}

		fileprivate let places: StoredModulePlaces
		fileprivate let seamIndices: [TypeDescription: Int]
		fileprivate let checksum: UInt64
	}

	/// The places of the seam at `seam` among the seams of the module named `moduleName`, each with the path its site has
	/// in an enum of `signature`, the seam's signature, which shares its storage (`ReadPlace.place(sitePath:)`).
	mutating func places(ofSeamAt seam: Int, inModuleNamed moduleName: String, sharingSitePathsOf signature: SeamSignature?) throws -> [SeamSignature.Hole] {
		guard let signatures = signaturesByModuleName[moduleName], signatures.seamTypes.indices.contains(seam) else {
			throw StoredPlaceError.malformedPlace(moduleName: moduleName)
		}
		let module = try moduleIndex(named: moduleName, for: signatures.seamTypes[seam])
		for record in modules[module].places[seam].indices {
			try read(Record(module: module, seam: seam, record: record), ofModuleNamed: moduleName)
		}
		// Of two enums' paths of one site, the first is kept.
		var sitePaths = [SeamSignature.Hole.Site: [Property]]()
		for scopeEnum in signature?.scopeEnums ?? [] {
			for enumCase in scopeEnum.cases {
				if case let .place(sites) = enumCase.kind {
					for site in sites where sitePaths[site] == nil {
						sitePaths[site] = site.path
					}
				}
			}
		}
		return modules[module].places[seam].compactMap { place in
			place.map { $0.place(sitePath: sitePaths[$0.site] ?? $0.site.path) }
		}
	}

	// MARK: Private

	/// A place among those read: of the seam at `seam` among the seams of the module at `module` among `modules`.
	private struct Record: Hashable {
		let module: Int
		let seam: Int
		let record: Int
	}

	/// A seam a module's places name, found among the modules read.
	private struct LowerSeam {
		let module: Int
		let seam: Int
		let seamType: TypeDescription
	}

	private struct Module {
		init(_ opened: OpenedModule) {
			self.opened = opened
			lowerSeams = Array(repeating: nil, count: opened.places.lowerSeams.count)
			places = opened.places.placesBySeam.map { Array(repeating: nil, count: $0.count) }
		}

		let opened: OpenedModule
		/// Each of the module's lower seams, once a place that names it is read.
		var lowerSeams: [LowerSeam?]
		/// Each place read, where the file holds it.
		var places: [[ReadPlace?]]
	}

	private let signaturesByModuleName: [String: ModuleSeamSignatures]
	private var moduleIndices = [String: Int]()
	private var modules = [Module]()

	/// Where the module named `moduleName`, which holds `seamType`, is among `modules`, its places read when they were not.
	private mutating func moduleIndex(named moduleName: String, for seamType: TypeDescription) throws -> Int {
		if let index = moduleIndices[moduleName] {
			return index
		} else {
			guard let signatures = signaturesByModuleName[moduleName] else {
				throw StoredPlaceError.lowerPlacesUnavailable(moduleName: moduleName, seam: seamType)
			}
			try modules.append(Module(OpenedModule(reading: signatures, ofModuleNamed: moduleName)))
			moduleIndices[moduleName] = modules.count - 1
			return modules.count - 1
		}
	}

	/// The record `reference` names among the lower seams of the module at `module`, named `moduleName`.
	private mutating func record(_ reference: StoredRecordReference, ofModuleAt module: Int, named moduleName: String) throws -> (record: Record, seamType: TypeDescription) {
		guard modules[module].lowerSeams.indices.contains(reference.lowerSeam) else {
			throw StoredPlaceError.malformedPlace(moduleName: moduleName)
		}
		let lowerSeam: LowerSeam
		if let found = modules[module].lowerSeams[reference.lowerSeam] {
			lowerSeam = found
		} else {
			let stored = modules[module].opened.places.lowerSeams[reference.lowerSeam]
			let lowerModule = try stored.moduleName.isEmpty ? module : moduleIndex(named: stored.moduleName, for: stored.seamType)
			guard stored.moduleName.isEmpty || modules[lowerModule].opened.checksum == stored.checksum, let seam = modules[lowerModule].opened.seamIndices[stored.seamType] else {
				throw StoredPlaceError.lowerPlacesUnavailable(moduleName: stored.moduleName.isEmpty ? moduleName : stored.moduleName, seam: stored.seamType)
			}
			lowerSeam = LowerSeam(module: lowerModule, seam: seam, seamType: stored.seamType)
			modules[module].lowerSeams[reference.lowerSeam] = lowerSeam
		}
		guard modules[lowerSeam.module].places[lowerSeam.seam].indices.contains(reference.record) else {
			throw StoredPlaceError.malformedPlace(moduleName: moduleName)
		}
		return (Record(module: lowerSeam.module, seam: lowerSeam.seam, record: reference.record), lowerSeam.seamType)
	}

	private func placeRead(_ record: Record) -> ReadPlace? {
		modules[record.module].places[record.seam][record.record]
	}

	/// Reads the place of `wanted`, a record of the module named `moduleName`, and of every record it is read from.
	private mutating func read(_ wanted: Record, ofModuleNamed moduleName: String) throws {
		var recordsToRead = [wanted]
		var recordsWaiting = Set<Record>()
		while let next = recordsToRead.last {
			guard placeRead(next) == nil else {
				recordsToRead.removeLast()
				continue
			}
			switch modules[next.module].opened.places.placesBySeam[next.seam][next.record] {
			case let .written(place):
				modules[next.module].places[next.seam][next.record] = ReadPlace(place)
				recordsToRead.removeLast()
			case let .passedUp(stored):
				let copied = try record(stored.record, ofModuleAt: next.module, named: moduleName)
				var others = [Record]()
				for other in stored.others {
					try others.append(record(other, ofModuleAt: next.module, named: moduleName).record)
				}
				let unread = ([copied.record] + others).filter { placeRead($0) == nil }
				if unread.isEmpty {
					let placesRead = ([copied.record] + others).compactMap(placeRead)
					guard let copiedPlace = placesRead.first,
					      let place = stored.place(record: copiedPlace, innerSeamType: copied.seamType, others: Array(placesRead.dropFirst()))
					else {
						throw StoredPlaceError.malformedPlace(moduleName: moduleName)
					}
					GenerationWork.recordStoredPlaces(1, by: .resolvingStoredPlaces)
					modules[next.module].places[next.seam][next.record] = place
					recordsToRead.removeLast()
				} else {
					// A record that waits a second time waits for one that waits for it.
					guard recordsWaiting.insert(next).inserted else {
						throw StoredPlaceError.malformedPlace(moduleName: moduleName)
					}
					recordsToRead += unread
				}
			}
		}
	}
}

/// Writes the places of a module's seams as a module info file holds them.
enum ModulePlacesEncoder {
	/// The places of `signatures`, the signatures of a module's seams, each passed-up place as the record it copies,
	/// wherever that reads back as the place itself: a record of the module's own seams, or of `signaturesRead`, the
	/// signatures the run read of the seams the module calls, whose modules' files hold `lower`.
	static func places(of signatures: [StoredSeamSignature], signaturesRead: [TypeDescription: DependencyTreeGenerator.SeamSignatureRead], lower: [String: ModuleSeamSignatures]) -> StoredModulePlaces {
		var encoder = Encoder(signatures: signatures, signaturesRead: signaturesRead, lower: lower)
		let placesBySeam = signatures.map { stored in
			encoder.places(of: stored.signature?.holes ?? [])
		}
		return StoredModulePlaces(lowerSeams: encoder.lowerSeams, placesBySeam: placesBySeam)
	}

	// MARK: Private

	/// The places of one seam the module's seams call, and where each site's is.
	private struct Records {
		init(_ places: [SeamSignature.Hole]) {
			self.places = places
			// Of two places of one site, the first is kept.
			indicesBySite = Dictionary(zip(places.map(\.site), places.indices), uniquingKeysWith: { first, _ in first })
		}

		let places: [SeamSignature.Hole]
		let indicesBySite: [SeamSignature.Hole.Site: Int]
	}

	private struct Encoder {
		init(signatures: [StoredSeamSignature], signaturesRead: [TypeDescription: DependencyTreeGenerator.SeamSignatureRead], lower: [String: ModuleSeamSignatures]) {
			self.signaturesRead = signaturesRead
			self.lower = lower
			// Of two signatures of one seam, the first is kept.
			for stored in signatures where ownRecordsBySeam[stored.seamType] == nil {
				ownRecordsBySeam[stored.seamType] = Records(stored.signature?.holes ?? [])
			}
		}

		private(set) var lowerSeams = [StoredLowerSeam]()

		mutating func places(of places: [SeamSignature.Hole]) -> [StoredPlace] {
			// The seams the places were passed up from, in the order of the places.
			var innerSeamTypes = [TypeDescription]()
			for place in places {
				if let innerSeamType = place.innerSeamType, !innerSeamTypes.contains(innerSeamType) {
					innerSeamTypes.append(innerSeamType)
				}
			}
			return places.map { place in
				guard let innerSeamType = place.innerSeamType else {
					return .written(place)
				}
				guard let stored = storedPlace(place, passedUpFrom: innerSeamType, amongPlacesOf: innerSeamTypes) else {
					GenerationWork.recordStoredPlaces(1, by: .writingPassedUpPlaceInFull)
					return .written(place)
				}
				return stored
			}
		}

		// MARK: Private

		private let signaturesRead: [TypeDescription: DependencyTreeGenerator.SeamSignatureRead]
		private let lower: [String: ModuleSeamSignatures]
		private var ownRecordsBySeam = [TypeDescription: Records]()
		private var lowerRecordsBySeam = [TypeDescription: Records?]()
		private var lowerSeamIndices = [TypeDescription: Int]()
		private var checksumsByModuleName = [String: UInt64]()

		/// The places of `seamType`, or `nil` for a seam whose places the run read from no file.
		private mutating func records(of seamType: TypeDescription) -> Records? {
			if let own = ownRecordsBySeam[seamType] {
				return own
			} else if let read = lowerRecordsBySeam[seamType] {
				return read
			} else {
				let read = signaturesRead[seamType].flatMap { lower[$0.moduleName] == nil ? nil : Records($0.signature.holes) }
				lowerRecordsBySeam[seamType] = .some(read)
				return read
			}
		}

		/// Where `seamType`, whose places `records(of:)` returned, is among `lowerSeams`, added when it is not there yet.
		private mutating func lowerSeamIndex(of seamType: TypeDescription) -> Int {
			if let index = lowerSeamIndices[seamType] {
				return index
			} else {
				let lowerSeam: StoredLowerSeam
				if ownRecordsBySeam[seamType] == nil, let lowerModuleName = signaturesRead[seamType]?.moduleName, let signatures = lower[lowerModuleName] {
					let checksum: UInt64
					if let known = checksumsByModuleName[lowerModuleName] {
						checksum = known
					} else {
						checksum = signatures.placesChecksum
						checksumsByModuleName[lowerModuleName] = checksum
					}
					lowerSeam = StoredLowerSeam(moduleName: lowerModuleName, seamType: seamType, checksum: checksum)
				} else {
					lowerSeam = StoredLowerSeam(moduleName: "", seamType: seamType, checksum: 0)
				}
				lowerSeamIndices[seamType] = lowerSeams.count
				lowerSeams.append(lowerSeam)
				return lowerSeams.count - 1
			}
		}

		/// `place`, passed up from `innerSeamType`, as the record it copies and what its seam adds; whole where its route
		/// does not extend its record's; or `nil` where the record and the addition do not read back as `place`.
		private mutating func storedPlace(_ place: SeamSignature.Hole, passedUpFrom innerSeamType: TypeDescription, amongPlacesOf innerSeamTypes: [TypeDescription]) -> StoredPlace? {
			guard let records = records(of: innerSeamType), let recordIndex = records.indicesBySite[place.site] else {
				return nil
			}
			let record = records.places[recordIndex]
			// A record is a place whose route the place's extends. Seams of one module that call one another in a cycle
			// settle on places that pass one another up, where neither route extends the other's: those are written
			// whole, as a place in a seam's own tree is, so that a read never follows records in a circle. A module's
			// seams are in no cycle with another module's, so such a place is written whole once, in its module's file.
			guard place.typesToOwner.count > record.typesToOwner.count, place.passedUpRoute.count > record.passedUpRoute.count else {
				return .written(place)
			}
			// The same site as the other seams the place's seam calls hold it.
			var candidates = [(seamType: TypeDescription, index: Int, place: SeamSignature.Hole)]()
			for otherSeamType in innerSeamTypes where otherSeamType != innerSeamType {
				if let otherRecords = self.records(of: otherSeamType), let index = otherRecords.indicesBySite[place.site] {
					candidates.append((otherSeamType, index, otherRecords.places[index]))
				}
			}
			// A declaration is found among a record's by its label, which a place holds once, its declaring type and its kind
			// of reason; that the place then reads back as written is checked below.
			let recordDeclarations = Self.declarationIndices(of: record)
			let candidateDeclarations = candidates.map { Self.declarationIndices(of: $0.place) }
			let presentedPlaces = ([record] + candidates.map(\.place)).map(SeamSignature.Hole.UncarriedDeclaration.PresentedPlace.init)
			// The candidates the place reads, in the order it first reads each.
			var othersRead = [Int]()
			func other(_ candidate: Int) -> Int {
				if let other = othersRead.firstIndex(of: candidate) {
					return other
				} else {
					othersRead.append(candidate)
					return othersRead.count - 1
				}
			}
			var declarations = [StoredPlaceDeclaration]()
			for declaration in place.uncarriedDeclarations {
				let key = DeclarationKey(declaration)
				if let kept = recordDeclarations[key] {
					if case let .kept(first, count) = declarations.last, first + count == kept {
						declarations[declarations.count - 1] = .kept(first: first, count: count + 1)
					} else {
						declarations.append(.kept(first: kept, count: 1))
					}
				} else if let candidate = candidateDeclarations.firstIndex(where: { $0[key] != nil }), let taken = candidateDeclarations[candidate][key] {
					declarations.append(.taken(other: other(candidate), declaration: taken))
				} else if case let .boundByPassingUpSeam(seam, module, presentedPlace) = declaration.reason,
				          let presenting = presentedPlaces.firstIndex(where: { $0.seamType == presentedPlace.seamType && $0.builderLabel == presentedPlace.builderLabel })
				{
					// A stand-in for the place, which the read puts back.
					let standIn = SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(storing: seam, ownerType: seam, property: declaration.property, instantiatedType: seam, builderLabel: "", caseName: nil, isBuiltBySendableBuilder: false)
					declarations.append(.boundOnPath(
						declaration: declaration.withReason(.boundByPassingUpSeam(seam: seam, module: module, place: standIn)),
						placeOf: presenting == 0 ? 0 : other(presenting - 1) + 1,
					))
				} else {
					declarations.append(.written(declaration))
				}
			}
			if let whole = declarations.firstIndex(where: {
				if case .kept(first: 0, count: record.uncarriedDeclarations.count) = $0 {
					true
				} else {
					false
				}
			}) {
				declarations[whole] = .record
			}
			let presentation = StoredPlacePresentation(place)
			let passedUp = StoredPassedUpPlace(
				record: StoredRecordReference(lowerSeam: lowerSeamIndex(of: innerSeamType), record: recordIndex),
				others: othersRead.map { StoredRecordReference(lowerSeam: lowerSeamIndex(of: candidates[$0].seamType), record: candidates[$0].index) },
				presentation: presentation.isPlainlyThat(of: record) ? nil : presentation,
				addition: StoredPlaceAddition(
					typesToCall: Array(place.typesToOwner.dropLast(record.typesToOwner.count)),
					route: Array(place.passedUpRoute.dropLast(record.passedUpRoute.count)),
					isSendable: place.isSendable,
					declarations: declarations,
					reenteringCallDeclarations: areWritten(place.reenteringCallDeclarations, as: record.reenteringCallDeclarations) ? nil : place.reenteringCallDeclarations,
					reenteringPlaceFields: areWritten(place.reenteringPlaceFields, as: record.reenteringPlaceFields) ? nil : place.reenteringPlaceFields,
				),
			)
			// What a read will make of it, compared as the bytes a file holds, which differ wherever two places do.
			guard let readBack = passedUp.place(record: ReadPlace(record), innerSeamType: innerSeamType, others: othersRead.map { ReadPlace(candidates[$0].place) })?.place,
			      isWritten(StoredPlaceWriteCheck.alteringPlaceReadBack?(readBack, record) ?? readBack, as: place)
			else {
				return nil
			}
			return .passedUp(passedUp)
		}

		/// What finds a declaration among a record's.
		private struct DeclarationKey: Hashable {
			init(_ declaration: SeamSignature.Hole.UncarriedDeclaration) {
				label = declaration.property.label
				declaringType = declaration.declaringType
				switch declaration.reason {
				case .receivesPathScopeOnlyIfAvailable:
					reason = 0
					passingSeam = nil
				case .requiresOtherCarrier:
					reason = 1
					passingSeam = nil
				case .instantiatorBuildingSite:
					reason = 2
					passingSeam = nil
				case .other:
					reason = 3
					passingSeam = nil
				case let .boundByPassingUpSeam(seam, _, place):
					reason = 4
					passingSeam = seam
					presentedBuilderLabel = place.builderLabel
				case .boundOutsideSendableFunction:
					reason = 5
					passingSeam = nil
				}
			}

			let label: String
			let declaringType: TypeDescription
			let reason: Int
			let passingSeam: TypeDescription?
			/// How the seam that passes the place up names its builder, which two seams that pass one site up may not
			/// name alike.
			var presentedBuilderLabel: String?
		}

		/// Where each of `place`'s declarations is, the first of each key.
		private static func declarationIndices(of place: SeamSignature.Hole) -> [DeclarationKey: Int] {
			Dictionary(zip(place.uncarriedDeclarations.map(DeclarationKey.init), place.uncarriedDeclarations.indices), uniquingKeysWith: { first, _ in first })
		}

		/// Whether a file holds `first` and `second` as the same bytes, with no position: two places are written as the
		/// same bytes exactly when a read finds no difference between them. Each is written by a writer of its own, since
		/// a writer writes a value it wrote before as a reference to it.
		private func isWritten(_ first: SeamSignature.Hole, as second: SeamSignature.Hole) -> Bool {
			func bytes(_ place: SeamSignature.Hole) -> [UInt8] {
				var writer = BinaryWriter.writingStringsInline()
				writer.writingPositionsAsAbsent { $0.write(place) }
				return writer.bytes
			}
			return bytes(first) == bytes(second)
		}

		/// Whether a file holds `first` and `second` as the same bytes, which two empty lists are without being written.
		private func areWritten<Element: BinaryCodable>(_ first: [Element], as second: [Element]) -> Bool {
			func bytes(_ elements: [Element]) -> [UInt8] {
				var writer = BinaryWriter.writingStringsInline()
				writer.writingPositionsAsAbsent { $0.write(elements) }
				return writer.bytes
			}
			return (first.isEmpty && second.isEmpty) || bytes(first) == bytes(second)
		}
	}
}
