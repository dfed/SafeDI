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

// The signatures a module info file carries of the seams its module declares (`StoredSeamSignature`), each type
// written as `BinaryCodableModels.swift` writes the declarations: every field it stores, in the order its initializer
// takes them.

extension StoredSeamSignature: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("signature", \.signature),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			signature: reader.read() as SeamSignature?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(signature)
	}
}

extension SeamSignature: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("parameters", \.parameters),
				BinaryLayoutField("tiers", \.tiers),
				BinaryLayoutField("noTierParameters", \.noTierParameters),
				BinaryLayoutField("holes", \.holes),
				BinaryLayoutField("builders", \.builders),
				BinaryLayoutField("scopeEnums", \.scopeEnums),
				BinaryLayoutField("typesDeclaredEscaping", \.typesDeclaredEscaping),
			],
			unwrittenProperties: ["callShape", "guardTypeName"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			parameters: reader.read(),
			tiers: reader.read(),
			noTierParameters: reader.read(),
			holes: reader.read(),
			builders: reader.read(),
			scopeEnums: reader.read(),
			typesDeclaredEscaping: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(parameters)
		writer.write(tiers)
		writer.write(noTierParameters)
		writer.write(holes)
		writer.write(builders)
		writer.write(scopeEnums)
		writer.write(typesDeclaredEscaping)
	}
}

extension SeamSignature.Receiver: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("aliasProperty", \.aliasProperty),
				BinaryLayoutField("isInstantiateMethodParameter", \.isInstantiateMethodParameter),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			declaringType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			access: reader.read(),
			aliasProperty: reader.read() as Property?,
			isInstantiateMethodParameter: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(access)
		writer.write(aliasProperty)
		writer.write(isInstantiateMethodParameter)
	}
}

extension SeamSignature.NestedSeamCall: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("seamModuleName", \.seamModuleName),
				BinaryLayoutField("tier", \.tier),
				BinaryLayoutField("requirement", \.requirement),
				BinaryLayoutField("callerModuleName", \.callerModuleName),
				BinaryLayoutField("parameterTierAccess", \.parameterTierAccess),
				BinaryLayoutField("receivingTypes", \.receivingTypes),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			seamModuleName: reader.read() as String?,
			tier: reader.read(),
			requirement: reader.read(),
			callerModuleName: reader.read() as String?,
			parameterTierAccess: reader.read() as AccessLevel?,
			receivingTypes: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(seamModuleName)
		writer.write(tier)
		writer.write(requirement)
		writer.write(callerModuleName)
		writer.write(parameterTierAccess)
		writer.write(receivingTypes)
	}
}

extension SeamSignature.Parameter: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("isPassThrough", \.isPassThrough),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("accessCause", \.accessCause),
				BinaryLayoutField("tierAccess", \.tierAccess),
				BinaryLayoutField("isOnlyIfAvailable", \.isOnlyIfAvailable),
				BinaryLayoutField("requiredThroughAlias", \.requiredThroughAlias),
				BinaryLayoutField("receivers", \.receivers),
				BinaryLayoutField("nestedSeamCall", \.nestedSeamCall),
				BinaryLayoutField("deferral", \.deferral),
				BinaryLayoutField("internalName", \.internalName),
				BinaryLayoutField("otherInitializerArgumentsAccess", \.otherInitializerArgumentsAccess),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			storing: reader.read(),
			isPassThrough: reader.read(),
			access: reader.read(),
			accessCause: reader.read() as TypeAccessProof.Cause?,
			tierAccess: reader.read(),
			isOnlyIfAvailable: reader.read(),
			requiredThroughAlias: reader.read(),
			receivers: reader.read(),
			nestedSeamCall: reader.read() as SeamSignature.NestedSeamCall?,
			deferral: reader.read(),
			internalName: reader.read(),
			otherInitializerArgumentsAccess: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(isPassThrough)
		writer.write(access)
		writer.write(accessCause)
		writer.write(tierAccess)
		writer.write(isOnlyIfAvailable)
		writer.write(requiredThroughAlias)
		writer.write(receivers)
		writer.write(nestedSeamCall)
		writer.write(deferral)
		writer.write(internalName)
		writer.write(otherInitializerArgumentsAccess)
	}
}

extension SeamSignature.Hole.Field: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("accessCause", \.accessCause),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("isReceivedOnlyIfAvailable", \.isReceivedOnlyIfAvailable),
				BinaryLayoutField("parameterTakingType", \.parameterTakingType),
				BinaryLayoutField("deferral", \.deferral),
				BinaryLayoutField("bindsMemo", \.bindsMemo),
				BinaryLayoutField("isSeamParameter", \.isSeamParameter),
				BinaryLayoutField("isBoundByPublicMockRoot", \.isBoundByPublicMockRoot),
				BinaryLayoutField("seamParameterOrigin", \.seamParameterOrigin),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		if reader.sharesSignatureValues {
			self = try reader.readSharedByBytes { reader throws(BinaryDecodingError) in try Self(readingUnsharedFrom: &reader) }
		} else {
			try self.init(readingUnsharedFrom: &reader)
		}
	}

	func write(to writer: inout BinaryWriter) {
		if writer.sharesSignatureValues {
			writer.writeSharedByBytes { writeUnshared(to: &$0) }
		} else {
			writeUnshared(to: &writer)
		}
	}

	private init(readingUnsharedFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			property: reader.read(),
			access: reader.read(),
			accessCause: reader.readOptional(flaggedIn: &fieldFlags) as TypeAccessProof.Cause?,
			declaringType: reader.read(),
			declarationLocation: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.DeclarationLocation?,
			isReceivedOnlyIfAvailable: fieldFlags.next(),
			parameterTakingType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			deferral: reader.read(),
			bindsMemo: fieldFlags.next(),
			isSeamParameter: fieldFlags.next(),
			isBoundByPublicMockRoot: fieldFlags.next(),
			seamParameterOrigin: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Hole.Field.SeamParameterOrigin?,
		)
		try fieldFlags.finish()
	}

	private func writeUnshared(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(property)
		writer.write(access)
		writer.writeOptional(accessCause, flaggedIn: &fieldFlags)
		writer.write(declaringType)
		writer.writeOptional(declarationLocation, flaggedIn: &fieldFlags)
		fieldFlags.append(isReceivedOnlyIfAvailable)
		writer.writeOptional(parameterTakingType, flaggedIn: &fieldFlags)
		writer.write(deferral)
		fieldFlags.append(bindsMemo)
		fieldFlags.append(isSeamParameter)
		fieldFlags.append(isBoundByPublicMockRoot)
		writer.writeOptional(seamParameterOrigin, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Hole.Field.SeamParameterOrigin: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("seamDeclarationLocation", \.seamDeclarationLocation),
				BinaryLayoutField("isPassThrough", \.isPassThrough),
				BinaryLayoutField("receivers", \.receivers),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			seamDeclarationLocation: reader.read() as Dependency.DeclarationLocation?,
			isPassThrough: reader.read(),
			receivers: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(seamDeclarationLocation)
		writer.write(isPassThrough)
		writer.write(receivers)
	}
}

extension SeamSignature.Hole.UncarriedDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("parameterTakingType", \.parameterTakingType),
				BinaryLayoutField("builtAfter", \.builtAfter),
				BinaryLayoutField("reason", \.reason),
				BinaryLayoutField("isBoundFromCallersArgument", \.isBoundFromCallersArgument),
				BinaryLayoutField("isBuildableAboveSeam", \.isBuildableAboveSeam),
				BinaryLayoutField("labelsHeldAboveSeam", \.labelsHeldAboveSeam),
				// Every declaration beside one tree lists the same places, as many as the tree's paths.
				BinaryLayoutField("placesInTree", \.sharedPlacesInTree),
				BinaryLayoutField("holdsPlaceFilledElsewhere", \.holdsPlaceFilledElsewhere),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(readingFrom: &reader, readsBuiltAfter: true)
	}

	/// Reads a declaration, which holds no `builtAfter` unless `readsBuiltAfter`: a list written as a difference holds
	/// each declaration without it (``listReadAsDifference(from:)``).
	fileprivate init(readingFrom reader: inout BinaryReader, readsBuiltAfter: Bool) throws(BinaryDecodingError) {
		try self.init(
			storing: reader.read(),
			declaringType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			parameterTakingType: reader.read() as TypeDescription?,
			builtAfter: readsBuiltAfter ? reader.read() as Property? : nil,
			reason: reader.read(),
			isBoundFromCallersArgument: reader.read(),
			isBuildableAboveSeam: reader.read(),
			labelsHeldAboveSeam: reader.read(),
			placesInTree: (reader.read() as BinaryShared<[SeamSignature.Hole.Site]>).value,
			holdsPlaceFilledElsewhere: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		write(to: &writer, writesBuiltAfter: true)
	}

	/// Writes the declaration, without `builtAfter` unless `writesBuiltAfter`.
	fileprivate func write(to writer: inout BinaryWriter, writesBuiltAfter: Bool) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(parameterTakingType)
		if writesBuiltAfter {
			writer.write(builtAfter)
		}
		writer.write(reason)
		writer.write(isBoundFromCallersArgument)
		writer.write(isBuildableAboveSeam)
		writer.write(labelsHeldAboveSeam)
		writer.write(sharedPlacesInTree)
		writer.write(holdsPlaceFilledElsewhere)
	}

	private var sharedPlacesInTree: BinaryShared<[SeamSignature.Hole.Site]> {
		BinaryShared(placesInTree)
	}
}

// A place's list of the declarations bound after it is a sibling place's list less the declarations between the two,
// but for `builtAfter`, which names the place itself: so the declarations are written without it, as a difference from
// another place's (`BinaryWriter.writeDifference(of:in:)`), and `builtAfter` after them as runs of equal values: none
// for the place itself, and the place for every declaration after it.
extension SeamSignature.Hole.UncarriedDeclaration {
	/// The declaration built after `builtAfter`.
	private func with(builtAfter: Property?) -> Self {
		Self(
			storing: property,
			declaringType: declaringType,
			declarationLocation: declarationLocation,
			parameterTakingType: parameterTakingType,
			builtAfter: builtAfter,
			reason: reason,
			isBoundFromCallersArgument: isBoundFromCallersArgument,
			isBuildableAboveSeam: isBuildableAboveSeam,
			labelsHeldAboveSeam: labelsHeldAboveSeam,
			placesInTree: placesInTree,
			holdsPlaceFilledElsewhere: holdsPlaceFilledElsewhere,
		)
	}

	/// Writes `declarations` as ``listReadAsDifference(from:)`` reads them.
	static func writeAsDifference(_ declarations: [Self], to writer: inout BinaryWriter) {
		guard writer.sharesSignatureValues else {
			writer.write(declarations)
			return
		}
		writer.writeDifference(of: declarations, in: .uncarriedDeclarations) { declaration, writer in
			declaration.write(to: &writer, writesBuiltAfter: false)
		}
		// Two values are the same when they are written as the same bytes: a property's `==` ignores `any`.
		var runs = [(length: UInt64, encoding: [UInt8], builtAfter: Property?)]()
		for declaration in declarations {
			var valueWriter = BinaryWriter.writingStringsInline()
			valueWriter.write(declaration.builtAfter)
			if let last = runs.last, last.encoding == valueWriter.bytes {
				runs[runs.count - 1].length += 1
			} else {
				runs.append((1, valueWriter.bytes, declaration.builtAfter))
			}
		}
		// The declarations after the last run written hold none, as every declaration of a seam with one place.
		if let last = runs.last, last.builtAfter == nil {
			runs.removeLast()
		}
		writer.writeUnsigned(UInt64(runs.count))
		for run in runs {
			writer.writeUnsigned(run.length)
			writer.write(run.builtAfter)
		}
	}

	/// Reads a place's declarations: the declarations without `builtAfter`, as a difference from another place's
	/// (``BinaryWriter/writeDifference(of:in:)``), and then `builtAfter` as runs, each a count of declarations and the
	/// value they hold, the declarations after the last run holding none. Outside a signature's shared values, the
	/// declarations as any list.
	static func listReadAsDifference(from reader: inout BinaryReader) throws(BinaryDecodingError) -> [Self] {
		guard reader.sharesSignatureValues else {
			return try reader.read()
		}
		return try reader.readDifference(in: .uncarriedDeclarations) { reader throws(BinaryDecodingError) in
			try Self(readingFrom: &reader, readsBuiltAfter: false)
		} readingSuffix: { reader, count throws(BinaryDecodingError) in
			var runs = [(length: Int, builtAfter: Property?)]()
			var declarationsInRuns = 0
			for _ in try 0..<reader.readCount() {
				let lengthOffset = reader.offset
				let length = try reader.readUnsigned()
				let builtAfter = try reader.read() as Property?
				guard length <= UInt64(count - declarationsInRuns) else {
					throw .countExceedsRemainingBytes(count: length, offset: lengthOffset)
				}
				runs.append((Int(length), builtAfter))
				declarationsInRuns += Int(length)
			}
			return runs
		} applying: { runs, declarations in
			// Every declaration is set, since each came from another place's list, but one that holds none and is to
			// hold none: a list none of whose declarations is built after a place stays the storage it was read as.
			var index = 0
			for run in runs {
				for _ in 0..<run.length {
					declarations[index] = declarations[index].with(builtAfter: run.builtAfter)
					index += 1
				}
			}
			for laterIndex in index..<declarations.count where declarations[laterIndex].builtAfter != nil {
				declarations[laterIndex] = declarations[laterIndex].with(builtAfter: nil)
			}
		}
	}
}

extension SeamSignature.Hole.UncarriedDeclaration.AliasOrigin: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("fulfillingProperty", \.fulfillingProperty),
				BinaryLayoutField("isSeams", \.isSeams),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			fulfillingProperty: reader.read(),
			isSeams: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(fulfillingProperty)
		writer.write(isSeams)
	}
}

extension SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("takingType", \.takingType),
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("isForwarded", \.isForwarded),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			takingType: reader.read(),
			property: reader.read(),
			declaringType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			isForwarded: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(takingType)
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(isForwarded)
	}
}

extension SeamSignature.Hole.UncarriedDeclaration.PresentedPlace: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("ownerType", \.ownerType),
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("instantiatedType", \.instantiatedType),
				BinaryLayoutField("builderLabel", \.builderLabel),
				BinaryLayoutField("caseName", \.caseName),
				BinaryLayoutField("isBuiltBySendableBuilder", \.isBuiltBySendableBuilder),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			storing: reader.read(),
			ownerType: reader.read(),
			property: reader.read(),
			instantiatedType: reader.read(),
			builderLabel: reader.read(),
			caseName: reader.read() as String?,
			isBuiltBySendableBuilder: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(ownerType)
		writer.write(property)
		writer.write(instantiatedType)
		writer.write(builderLabel)
		writer.write(caseName)
		writer.write(isBuiltBySendableBuilder)
	}
}

extension SeamSignature.Hole.CycleReentryDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("parameterTakingType", \.parameterTakingType),
				BinaryLayoutField("closedOnProperty", \.closedOnProperty),
				BinaryLayoutField("closedOnBuiltType", \.closedOnBuiltType),
				BinaryLayoutField("closedOnDeclaringType", \.closedOnDeclaringType),
				BinaryLayoutField("reenteringType", \.reenteringType),
				BinaryLayoutField("calledSeamType", \.calledSeamType),
				BinaryLayoutField("placeIsInFurtherSendableFunction", \.placeIsInFurtherSendableFunction),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			declaringType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			parameterTakingType: reader.read() as TypeDescription?,
			closedOnProperty: reader.read(),
			closedOnBuiltType: reader.read(),
			closedOnDeclaringType: reader.read(),
			reenteringType: reader.read(),
			calledSeamType: reader.read() as TypeDescription?,
			placeIsInFurtherSendableFunction: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(parameterTakingType)
		writer.write(closedOnProperty)
		writer.write(closedOnBuiltType)
		writer.write(closedOnDeclaringType)
		writer.write(reenteringType)
		writer.write(calledSeamType)
		writer.write(placeIsInFurtherSendableFunction)
	}
}

extension SeamSignature.Hole.ReenteringCallDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("pathPlace", \.pathPlace),
				BinaryLayoutField("callingType", \.callingType),
				BinaryLayoutField("callProperty", \.callProperty),
				BinaryLayoutField("calledSeam", \.calledSeam),
				BinaryLayoutField("reenteredPlace", \.reenteredPlace),
				BinaryLayoutField("reenteredSeamModule", \.reenteredSeamModule),
				BinaryLayoutField("fillingModule", \.fillingModule),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			declaringType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			pathPlace: reader.read(),
			callingType: reader.read(),
			callProperty: reader.read(),
			calledSeam: reader.read(),
			reenteredPlace: reader.read(),
			reenteredSeamModule: reader.read(),
			fillingModule: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(pathPlace)
		writer.write(callingType)
		writer.write(callProperty)
		writer.write(calledSeam)
		writer.write(reenteredPlace)
		writer.write(reenteredSeamModule)
		writer.write(fillingModule)
	}
}

extension SeamSignature.Hole.FieldOfReenteringPlace: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("field", \.field),
				BinaryLayoutField("reenteringPlace", \.reenteringPlace),
				BinaryLayoutField("callProperty", \.callProperty),
				BinaryLayoutField("calledSeam", \.calledSeam),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			field: reader.read(),
			reenteringPlace: reader.read(),
			callProperty: reader.read(),
			calledSeam: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(field)
		writer.write(reenteringPlace)
		writer.write(callProperty)
		writer.write(calledSeam)
	}
}

extension SeamSignature.Hole.ReenteringPlaceField: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("carried", \.carried),
				BinaryLayoutField("reenteredPlace", \.reenteredPlace),
				BinaryLayoutField("reenteredSeamModule", \.reenteredSeamModule),
				BinaryLayoutField("fillingModule", \.fillingModule),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			carried: reader.read(),
			reenteredPlace: reader.read(),
			reenteredSeamModule: reader.read(),
			fillingModule: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(carried)
		writer.write(reenteredPlace)
		writer.write(reenteredSeamModule)
		writer.write(fillingModule)
	}
}

extension SeamSignature.Hole.DeclarationHiddenByField: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("calledSeam", \.calledSeam),
				BinaryLayoutField("receivingSeam", \.receivingSeam),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			declaringType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			calledSeam: reader.read(),
			receivingSeam: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(calledSeam)
		writer.write(receivingSeam)
	}
}

extension SeamSignature.Hole.PathType: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("type", \.type),
				BinaryLayoutField("moduleName", \.moduleName),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			type: reader.read(),
			moduleName: reader.read() as String?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(type)
		writer.write(moduleName)
	}
}

extension SeamSignature.Hole: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("ownerType", \.ownerType),
				BinaryLayoutField("declaringModuleNames", \.declaringModuleNames),
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("instantiatedType", \.instantiatedType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("erasedToConcreteExistential", \.erasedToConcreteExistential),
				BinaryLayoutField("sitePath", \.sitePath),
				BinaryLayoutField("declaredSitePath", \.declaredSitePath),
				BinaryLayoutField("fillPropertyStack", \.fillPropertyStack),
				BinaryLayoutField("fillConcreteTypeStack", \.fillConcreteTypeStack),
				BinaryLayoutField("builderLabel", \.builderLabel),
				BinaryLayoutField("narrowerTierBuilderLabels", \.narrowerTierBuilderLabels),
				BinaryLayoutField("internalName", \.internalName),
				BinaryLayoutField("scopeSeamType", \.scopeSeamType),
				BinaryLayoutField("scopeSeamModule", \.scopeSeamModule),
				BinaryLayoutField("typesToOwner", \.typesToOwner),
				BinaryLayoutField("scopeTypeName", \.scopeTypeName),
				BinaryLayoutField("enumPlace", \.enumPlace),
				BinaryLayoutField("wrapperFunctionName", \.wrapperFunctionName),
				BinaryLayoutField("fields", \.fields),
				BinaryLayoutField("tierAccess", \.tierAccess),
				BinaryLayoutField("accessCause", \.accessCause),
				BinaryLayoutField("uncarriedDeclarations", \.uncarriedDeclarations),
				BinaryLayoutField("cycleReentryDeclarations", \.cycleReentryDeclarations),
				BinaryLayoutField("reenteringCallDeclarations", \.reenteringCallDeclarations),
				BinaryLayoutField("reenteringPlaceFields", \.reenteringPlaceFields),
				BinaryLayoutField("declarationsHiddenByFields", \.declarationsHiddenByFields),
				BinaryLayoutField("innerSeamType", \.innerSeamType),
				BinaryLayoutField("passedUpRoute", \.passedUpRoute),
				BinaryLayoutField("isSendable", \.isSendable),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			storing: reader.read(),
			declaringModuleNames: reader.read(),
			property: reader.read(),
			instantiatedType: reader.read(),
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			erasedToConcreteExistential: reader.read(),
			sitePath: reader.read(),
			declaredSitePath: reader.read(),
			fillPropertyStack: reader.read(),
			fillConcreteTypeStack: reader.read(),
			builderLabel: reader.read(),
			narrowerTierBuilderLabels: reader.read(),
			internalName: reader.read(),
			scopeSeamType: reader.read(),
			scopeSeamModule: reader.read(),
			typesToOwner: reader.read(),
			scopeTypeName: reader.read(),
			enumPlace: reader.read() as SeamSignature.Hole.EnumPlace?,
			wrapperFunctionName: reader.read() as String?,
			fields: reader.readDifference(in: .fields),
			tierAccess: reader.read(),
			accessCause: reader.read() as TypeAccessProof.Cause?,
			uncarriedDeclarations: SeamSignature.Hole.UncarriedDeclaration.listReadAsDifference(from: &reader),
			cycleReentryDeclarations: reader.read(),
			reenteringCallDeclarations: reader.read(),
			reenteringPlaceFields: reader.read(),
			declarationsHiddenByFields: reader.read(),
			innerSeamType: reader.read() as TypeDescription?,
			passedUpRoute: reader.read(),
			isSendable: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(ownerType)
		writer.write(declaringModuleNames)
		writer.write(property)
		writer.write(instantiatedType)
		writer.write(declarationLocation)
		writer.write(erasedToConcreteExistential)
		writer.write(sitePath)
		writer.write(declaredSitePath)
		writer.write(fillPropertyStack)
		writer.write(fillConcreteTypeStack)
		writer.write(builderLabel)
		writer.write(narrowerTierBuilderLabels)
		writer.write(internalName)
		writer.write(scopeSeamType)
		writer.write(scopeSeamModule)
		writer.write(typesToOwner)
		writer.write(scopeTypeName)
		writer.write(enumPlace)
		writer.write(wrapperFunctionName)
		writer.writeDifference(of: fields, in: .fields)
		writer.write(tierAccess)
		writer.write(accessCause)
		SeamSignature.Hole.UncarriedDeclaration.writeAsDifference(uncarriedDeclarations, to: &writer)
		writer.write(cycleReentryDeclarations)
		writer.write(reenteringCallDeclarations)
		writer.write(reenteringPlaceFields)
		writer.write(declarationsHiddenByFields)
		writer.write(innerSeamType)
		writer.write(passedUpRoute)
		writer.write(isSendable)
	}
}

extension SeamSignature.Hole.EnumPlace: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("enumTypeName", \.enumTypeName),
				BinaryLayoutField("rootEnumTypeName", \.rootEnumTypeName),
				BinaryLayoutField("caseName", \.caseName),
				BinaryLayoutField("valuesTypeName", \.valuesTypeName),
				BinaryLayoutField("memberValuesTypeName", \.memberValuesTypeName),
				BinaryLayoutField("isBuiltBySendableBuilder", \.isBuiltBySendableBuilder),
				BinaryLayoutField("route", \.route),
				BinaryLayoutField("values", \.values),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			nestedByTypeIn: reader.read(),
			rootEnumTypeName: reader.read() as String?,
			caseName: reader.read(),
			valuesTypeName: reader.read() as String?,
			memberValuesTypeName: reader.read() as String?,
			isBuiltBySendableBuilder: reader.read(),
			route: reader.read(),
			values: reader.readDifference(in: .fields),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(enumTypeName)
		writer.write(rootEnumTypeName)
		writer.write(caseName)
		writer.write(valuesTypeName)
		writer.write(memberValuesTypeName)
		writer.write(isBuiltBySendableBuilder)
		writer.write(route)
		writer.writeDifference(of: values, in: .fields)
	}
}

extension SeamSignature.Hole.RouteStep: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("caseName", \.caseName),
				BinaryLayoutField("values", \.values),
				BinaryLayoutField("innerScope", \.innerScope),
				BinaryLayoutField("leadsIntoFill", \.leadsIntoFill),
				BinaryLayoutField("member", \.member),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			caseName: reader.read(),
			values: reader.read() as SeamSignature.Hole.RouteStep.Values?,
			innerScope: reader.read() as SeamSignature.Hole.RouteStep.InnerScope?,
			leadsIntoFill: reader.read(),
			member: reader.read() as SeamSignature.Hole.RouteStep.Member?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(caseName)
		writer.write(values)
		writer.write(innerScope)
		writer.write(leadsIntoFill)
		writer.write(member)
	}
}

extension SeamSignature.Hole.RouteStep.Member: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("bindingName", \.bindingName),
				BinaryLayoutField("valuesType", \.valuesType),
				BinaryLayoutField("fields", \.fields),
				BinaryLayoutField("levelType", \.levelType),
				BinaryLayoutField("bindingPathLength", \.bindingPathLength),
				BinaryLayoutField("isCalledInsideFunction", \.isCalledInsideFunction),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			bindingName: reader.read(),
			valuesType: reader.read(),
			fields: reader.read(),
			levelType: reader.read(),
			bindingPathLength: reader.read(),
			isCalledInsideFunction: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(bindingName)
		writer.write(valuesType)
		writer.write(fields)
		writer.write(levelType)
		writer.write(bindingPathLength)
		writer.write(isCalledInsideFunction)
	}
}

extension SeamSignature.Hole.RouteStep.Values: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("bindingName", \.bindingName),
				BinaryLayoutField("type", \.type),
				BinaryLayoutField("fields", \.fields),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			bindingName: reader.read(),
			type: reader.read(),
			fields: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(bindingName)
		writer.write(type)
		writer.write(fields)
	}
}

extension SeamSignature.Hole.RouteStep.InnerScope: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("callPathLength", \.callPathLength),
				BinaryLayoutField("innerKey", \.innerKey),
				BinaryLayoutField("enumType", \.enumType),
				BinaryLayoutField("builderLabel", \.builderLabel),
				BinaryLayoutField("name", \.name),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			callPathLength: reader.read(),
			innerKey: reader.read(),
			enumType: reader.read(),
			builderLabel: reader.read(),
			name: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(callPathLength)
		writer.write(innerKey)
		writer.write(enumType)
		writer.write(builderLabel)
		writer.write(name)
	}
}

extension SeamSignature.Hole.DeclaredProperty: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			declaringType: reader.read() as TypeDescription?,
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
	}
}

extension SeamSignature.Hole.Site: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("path", \.path),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			path: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(path)
	}
}

extension SeamSignature.HoleType: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("instantiatedType", \.instantiatedType),
				BinaryLayoutField("builtType", \.builtType),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			instantiatedType: reader.read(),
			builtType: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(instantiatedType)
		writer.write(builtType)
	}
}

extension SeamSignature.ScopeEnum: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("key", \.key),
				BinaryLayoutField("typeName", \.typeName),
				BinaryLayoutField("rootTypeName", \.rootTypeName),
				BinaryLayoutField("builderLabel", \.builderLabel),
				BinaryLayoutField("cases", \.cases),
				BinaryLayoutField("takesValuesPositionally", \.takesValuesPositionally),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			key: reader.read(),
			typeName: reader.read(),
			rootTypeName: reader.read() as String?,
			builderLabel: reader.read(),
			cases: reader.read(),
			takesValuesPositionally: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(key)
		writer.write(typeName)
		writer.write(rootTypeName)
		writer.write(builderLabel)
		writer.write(cases)
		writer.write(takesValuesPositionally)
	}
}

extension SeamSignature.ScopeEnum.Key: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("holeType", \.holeType),
				BinaryLayoutField("isSendable", \.isSendable),
				BinaryLayoutField("describedType", \.describedType),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			holeType: reader.read(),
			isSendable: reader.read(),
			describedType: reader.read() as TypeDescription?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(holeType)
		writer.write(isSendable)
		writer.write(describedType)
	}
}

extension SeamSignature.ScopeEnum.Values: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("typeName", \.typeName),
				BinaryLayoutField("fields", \.fields),
				BinaryLayoutField("labelsBoundLater", \.labelsBoundLater),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			typeName: reader.read(),
			fields: reader.readDifference(in: .fields),
			labelsBoundLater: Set(reader.readDifference(in: .labelsBoundLater) as [String]),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(typeName)
		writer.writeDifference(of: fields, in: .fields)
		writer.writeDifference(of: labelsBoundLater.sorted(), in: .labelsBoundLater)
	}
}

extension SeamSignature.ScopeEnum.Case: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("name", \.name),
				BinaryLayoutField("kind", \.kind),
				BinaryLayoutField("values", \.values),
				BinaryLayoutField("memberValuesTypeName", \.memberValuesTypeName),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			storing: reader.read(),
			kind: reader.read(),
			values: reader.read() as SeamSignature.ScopeEnum.Values?,
			memberValuesTypeName: reader.read() as String?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(name)
		writer.write(kind)
		writer.write(values)
		writer.write(memberValuesTypeName)
	}
}

extension SeamSignature.Builder: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("enumKey", \.enumKey),
				BinaryLayoutField("label", \.label),
				BinaryLayoutField("internalName", \.internalName),
				BinaryLayoutField("parameterType", \.parameterType),
				BinaryLayoutField("readableParameterType", \.readableParameterType),
				BinaryLayoutField("takesBuilderStruct", \.takesBuilderStruct),
				BinaryLayoutField("tierAccess", \.tierAccess),
				BinaryLayoutField("accessCause", \.accessCause),
				BinaryLayoutField("narrowingInnerSeam", \.narrowingInnerSeam),
				BinaryLayoutField("narrowerTierLabels", \.narrowerTierLabels),
			],
			// The initializer derives it from `parameterType`.
			unwrittenProperties: ["parameterTypeWithoutAny"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			enumKey: reader.read(),
			label: reader.read(),
			internalName: reader.read(),
			parameterType: reader.read(),
			readableParameterType: reader.read(),
			takesBuilderStruct: reader.read(),
			tierAccess: reader.read(),
			accessCause: reader.read() as TypeAccessProof.Cause?,
			narrowingInnerSeam: reader.read() as TypeDescription?,
			narrowerTierLabels: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(enumKey)
		writer.write(label)
		writer.write(internalName)
		writer.write(parameterType)
		writer.write(readableParameterType)
		writer.write(takesBuilderStruct)
		writer.write(tierAccess)
		writer.write(accessCause)
		writer.write(narrowingInnerSeam)
		writer.write(narrowerTierLabels)
	}
}

extension TypeAccessProof.Prover: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("carrier", \.carrier),
				BinaryLayoutField("member", \.member),
				BinaryLayoutField("argumentLabels", \.argumentLabels),
				BinaryLayoutField("level", \.level),
				BinaryLayoutField("location", \.location),
				BinaryLayoutField("cap", \.cap),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			carrier: reader.read(),
			member: reader.read(),
			argumentLabels: reader.read(),
			level: reader.read(),
			location: reader.read() as Dependency.DeclarationLocation?,
			cap: reader.read() as TypeAccessProof.Cause?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(carrier)
		writer.write(member)
		writer.write(argumentLabels)
		writer.write(level)
		writer.write(location)
		writer.write(cap)
	}
}

extension ModuleIdentity: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("packageName", \.packageName),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			moduleName: reader.read() as String?,
			packageName: reader.read() as String?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(moduleName)
		writer.write(packageName)
	}
}

extension SeamSignature.Parameter.Deferral: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .none: []
			case .deferred: [.init("isSendable", Bool.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .none:
			.none
		case .deferred:
			try .deferred(isSendable: reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .none:
			writer.writeTag(Tag.none)
		case let .deferred(isSendable):
			writer.writeTag(Tag.deferred)
			writer.write(isSendable)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case none
		case deferred
	}
}

extension SeamSignature.Hole.UncarriedDeclaration.Reason: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .receivesPathScopeOnlyIfAvailable: [.init("type", TypeDescription.self)]
			case .requiresOtherCarrier: [.init("type", TypeDescription.self), .init("carrier", Property.self)]
			case .instantiatorBuildingSite: []
			case .other: []
			case .boundByPassingUpSeam: [.init("seam", TypeDescription.self), .init("module", ModuleIdentity.self), .init("place", SeamSignature.Hole.UncarriedDeclaration.PresentedPlace.self)]
			case .boundOutsideSendableFunction: [.init("functionProperty", Property.self), .init("function", SeamSignature.Hole.UncarriedDeclaration.SendableFunction.self), .init("isForwarded", Bool.self), .init("cycleParameter", SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin?.self), .init("alias", SeamSignature.Hole.UncarriedDeclaration.AliasOrigin?.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		if reader.sharesSignatureValues {
			self = try reader.readSharedByBytes { reader throws(BinaryDecodingError) in try Self(readingUnsharedFrom: &reader) }
		} else {
			try self.init(readingUnsharedFrom: &reader)
		}
	}

	func write(to writer: inout BinaryWriter) {
		if writer.sharesSignatureValues {
			writer.writeSharedByBytes { writeUnshared(to: &$0) }
		} else {
			writeUnshared(to: &writer)
		}
	}

	private init(readingUnsharedFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .receivesPathScopeOnlyIfAvailable:
			try .receivesPathScopeOnlyIfAvailable(type: reader.read())
		case .requiresOtherCarrier:
			try .requiresOtherCarrier(type: reader.read(), carrier: reader.read())
		case .instantiatorBuildingSite:
			.instantiatorBuildingSite
		case .other:
			.other
		case .boundByPassingUpSeam:
			try .boundByPassingUpSeam(seam: reader.read(), module: reader.read(), place: reader.read())
		case .boundOutsideSendableFunction:
			try .boundOutsideSendableFunction(functionProperty: reader.read(), function: reader.read(), isForwarded: reader.read(), cycleParameter: reader.read() as SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin?, alias: reader.read() as SeamSignature.Hole.UncarriedDeclaration.AliasOrigin?)
		}
	}

	private func writeUnshared(to writer: inout BinaryWriter) {
		switch self {
		case let .receivesPathScopeOnlyIfAvailable(type):
			writer.writeTag(Tag.receivesPathScopeOnlyIfAvailable)
			writer.write(type)
		case let .requiresOtherCarrier(type, carrier):
			writer.writeTag(Tag.requiresOtherCarrier)
			writer.write(type)
			writer.write(carrier)
		case .instantiatorBuildingSite:
			writer.writeTag(Tag.instantiatorBuildingSite)
		case .other:
			writer.writeTag(Tag.other)
		case let .boundByPassingUpSeam(seam, module, place):
			writer.writeTag(Tag.boundByPassingUpSeam)
			writer.write(seam)
			writer.write(module)
			writer.write(place)
		case let .boundOutsideSendableFunction(functionProperty, function, isForwarded, cycleParameter, alias):
			writer.writeTag(Tag.boundOutsideSendableFunction)
			writer.write(functionProperty)
			writer.write(function)
			writer.write(isForwarded)
			writer.write(cycleParameter)
			writer.write(alias)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case receivesPathScopeOnlyIfAvailable
		case requiresOtherCarrier
		case instantiatorBuildingSite
		case other
		case boundByPassingUpSeam
		case boundOutsideSendableFunction
	}
}

extension SeamSignature.Hole.UncarriedDeclaration.SendableFunction: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .instantiator: [.init("builtType", TypeDescription.self)]
			case .sendableLazyWrapper: [.init("builtType", TypeDescription.self)]
			case .other: []
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .instantiator:
			try .instantiator(builtType: reader.read())
		case .sendableLazyWrapper:
			try .sendableLazyWrapper(builtType: reader.read())
		case .other:
			.other
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .instantiator(builtType):
			writer.writeTag(Tag.instantiator)
			writer.write(builtType)
		case let .sendableLazyWrapper(builtType):
			writer.writeTag(Tag.sendableLazyWrapper)
			writer.write(builtType)
		case .other:
			writer.writeTag(Tag.other)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case instantiator
		case sendableLazyWrapper
		case other
	}
}

extension SeamSignature.ScopeEnum.Case.Kind: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .place: [.init("sites", [SeamSignature.Hole.Site].self)]
			case .nested: [.init("enumKey", SeamSignature.ScopeEnum.Key.self), .init("enumType", TypeDescription.self), .init("isIndirect", Bool.self)]
			case .inner: [.init("enumKey", SeamSignature.ScopeEnum.Key.self), .init("enumType", TypeDescription.self), .init("isIndirect", Bool.self)]
			case .fill: [.init("innerKey", SeamSignature.ScopeEnum.Key.self), .init("innerEnumType", TypeDescription?.self), .init("enumKey", SeamSignature.ScopeEnum.Key.self), .init("enumType", TypeDescription.self), .init("isIndirect", Bool.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .place:
			try .place(sites: reader.read())
		case .nested:
			try .nested(enumKey: reader.read(), enumType: reader.read(), isIndirect: reader.read())
		case .inner:
			try .inner(enumKey: reader.read(), enumType: reader.read(), isIndirect: reader.read())
		case .fill:
			try .fill(innerKey: reader.read(), innerEnumType: reader.read() as TypeDescription?, enumKey: reader.read(), enumType: reader.read(), isIndirect: reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .place(sites):
			writer.writeTag(Tag.place)
			writer.write(sites)
		case let .nested(enumKey, enumType, isIndirect):
			writer.writeTag(Tag.nested)
			writer.write(enumKey)
			writer.write(enumType)
			writer.write(isIndirect)
		case let .inner(enumKey, enumType, isIndirect):
			writer.writeTag(Tag.inner)
			writer.write(enumKey)
			writer.write(enumType)
			writer.write(isIndirect)
		case let .fill(innerKey, innerEnumType, enumKey, enumType, isIndirect):
			writer.writeTag(Tag.fill)
			writer.write(innerKey)
			writer.write(innerEnumType)
			writer.write(enumKey)
			writer.write(enumType)
			writer.write(isIndirect)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case place
		case nested
		case inner
		case fill
	}
}

extension TypeAccessProof.Cause: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .ownDeclaration: [.init("type", TypeDescription.self), .init("level", AccessLevel.self)]
			case .plainDeclaration: [.init("type", TypeDescription.self), .init("level", AccessLevel.self), .init("declarations", [PlainTypeDeclaration].self), .init("namesModules", Bool.self)]
			case .declarationInExtensionOfRecordedType: [.init("type", TypeDescription.self), .init("ownLevel", AccessLevel.self), .init("extendedType", TypeDescription.self), .init("extendedTypeLevel", AccessLevel.self), .init("spellsOwnLevel", Bool.self), .init("extendedTypeIsPlain", Bool.self), .init("extendedTypeDeclarations", [PlainTypeDeclaration].self), .init("extendedTypeEnclosingType", TypeDescription?.self)]
			case .declarationInExtension: [.init("type", TypeDescription.self), .init("level", AccessLevel.self), .init("extendedType", TypeDescription?.self), .init("extensionLevel", AccessLevel?.self), .init("isExtensionBased", Bool.self), .init("enclosingTypeLevel", AccessLevel?.self), .init("raisingProvers", [TypeAccessProof.Prover].self), .init("isMockOnly", Bool.self)]
			case .signatures: [.init("type", TypeDescription.self), .init("level", AccessLevel.self), .init("provers", [TypeAccessProof.Prover].self), .init("mentioningModuleName", String?.self)]
			case .unproven: [.init("type", TypeDescription.self)]
			case .enclosedBy: [.init("type", TypeDescription.self), .init("enclosingType", TypeDescription.self), .init("cause", TypeAccessProof.Cause.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .ownDeclaration:
			try .ownDeclaration(type: reader.read(), level: reader.read())
		case .plainDeclaration:
			try .plainDeclaration(type: reader.read(), level: reader.read(), declarations: reader.read(), namesModules: reader.read())
		case .declarationInExtensionOfRecordedType:
			try .declarationInExtensionOfRecordedType(type: reader.read(), ownLevel: reader.read(), extendedType: reader.read(), extendedTypeLevel: reader.read(), spellsOwnLevel: reader.read(), extendedTypeIsPlain: reader.read(), extendedTypeDeclarations: reader.read(), extendedTypeEnclosingType: reader.read() as TypeDescription?)
		case .declarationInExtension:
			try .declarationInExtension(type: reader.read(), level: reader.read(), extendedType: reader.read() as TypeDescription?, extensionLevel: reader.read() as AccessLevel?, isExtensionBased: reader.read(), enclosingTypeLevel: reader.read() as AccessLevel?, raisingProvers: reader.read(), isMockOnly: reader.read())
		case .signatures:
			try .signatures(type: reader.read(), level: reader.read(), provers: reader.read(), mentioningModuleName: reader.read() as String?)
		case .unproven:
			try .unproven(type: reader.read())
		case .enclosedBy:
			try .enclosedBy(type: reader.read(), enclosingType: reader.read(), cause: reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .ownDeclaration(type, level):
			writer.writeTag(Tag.ownDeclaration)
			writer.write(type)
			writer.write(level)
		case let .plainDeclaration(type, level, declarations, namesModules):
			writer.writeTag(Tag.plainDeclaration)
			writer.write(type)
			writer.write(level)
			writer.write(declarations)
			writer.write(namesModules)
		case let .declarationInExtensionOfRecordedType(type, ownLevel, extendedType, extendedTypeLevel, spellsOwnLevel, extendedTypeIsPlain, extendedTypeDeclarations, extendedTypeEnclosingType):
			writer.writeTag(Tag.declarationInExtensionOfRecordedType)
			writer.write(type)
			writer.write(ownLevel)
			writer.write(extendedType)
			writer.write(extendedTypeLevel)
			writer.write(spellsOwnLevel)
			writer.write(extendedTypeIsPlain)
			writer.write(extendedTypeDeclarations)
			writer.write(extendedTypeEnclosingType)
		case let .declarationInExtension(type, level, extendedType, extensionLevel, isExtensionBased, enclosingTypeLevel, raisingProvers, isMockOnly):
			writer.writeTag(Tag.declarationInExtension)
			writer.write(type)
			writer.write(level)
			writer.write(extendedType)
			writer.write(extensionLevel)
			writer.write(isExtensionBased)
			writer.write(enclosingTypeLevel)
			writer.write(raisingProvers)
			writer.write(isMockOnly)
		case let .signatures(type, level, provers, mentioningModuleName):
			writer.writeTag(Tag.signatures)
			writer.write(type)
			writer.write(level)
			writer.write(provers)
			writer.write(mentioningModuleName)
		case let .unproven(type):
			writer.writeTag(Tag.unproven)
			writer.write(type)
		case let .enclosedBy(type, enclosingType, cause):
			writer.writeTag(Tag.enclosedBy)
			writer.write(type)
			writer.write(enclosingType)
			writer.write(cause)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case ownDeclaration
		case plainDeclaration
		case declarationInExtensionOfRecordedType
		case declarationInExtension
		case signatures
		case unproven
		case enclosedBy
	}
}

extension TypeAccessProof.MemberKind: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .initializer: []
			case .instantiateMethod: []
			case .mockMethod: [.init("name", String.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .initializer:
			.initializer
		case .instantiateMethod:
			.instantiateMethod
		case .mockMethod:
			try .mockMethod(name: reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .initializer:
			writer.writeTag(Tag.initializer)
		case .instantiateMethod:
			writer.writeTag(Tag.instantiateMethod)
		case let .mockMethod(name):
			writer.writeTag(Tag.mockMethod)
			writer.write(name)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case initializer
		case instantiateMethod
		case mockMethod
	}
}

extension AccessRequirement: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .internal: []
			case .package: []
			case .public: []
			case .packageUnverified: []
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .internal:
			.internal
		case .package:
			.package
		case .public:
			.public
		case .packageUnverified:
			.packageUnverified
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .internal:
			writer.writeTag(Tag.internal)
		case .package:
			writer.writeTag(Tag.package)
		case .public:
			writer.writeTag(Tag.public)
		case .packageUnverified:
			writer.writeTag(Tag.packageUnverified)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case `internal`
		case package
		case `public`
		case packageUnverified
	}
}
