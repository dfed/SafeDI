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

// A seam's places as a module info file carries them (`SeamSignature.Places`): the levels, the cases and the levels'
// lists of declarations, each type written as `BinaryCodableSeamSignatures.swift` writes the rest of a signature, every
// field it stores in the order its initializer takes them. A level, a declaration, what a declaration holds as a child
// of its scope and a level's key write their optional and Boolean fields as flags: most of what a declaration can hold
// is absent. A file holds each list of declarations once, whichever of a type's properties its levels lead on through,
// so a type with many places is written with one declaration per property, not one per pair of them.

extension SeamSignature.Places: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("levels", \.levels),
				BinaryLayoutField("cases", \.cases),
				BinaryLayoutField("declarationLists", \.declarationLists),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			levels: reader.read(),
			cases: reader.read(),
			declarationLists: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(levels)
		writer.write(cases)
		writer.write(declarationLists)
	}
}

extension SeamSignature.Places.LevelKey: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("builtType", \.builtType),
				BinaryLayoutField("nextProperty", \.nextProperty),
				BinaryLayoutField("isSeamRoot", \.isSeamRoot),
				BinaryLayoutField("isInFill", \.isInFill),
				BinaryLayoutField("filledType", \.filledType),
				BinaryLayoutField("filledCase", \.filledCase),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			builtType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			nextProperty: reader.readOptional(flaggedIn: &fieldFlags) as Property?,
			isSeamRoot: fieldFlags.next(),
			isInFill: fieldFlags.next(),
			filledType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			filledCase: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.CalledCase?,
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.writeOptional(builtType, flaggedIn: &fieldFlags)
		writer.writeOptional(nextProperty, flaggedIn: &fieldFlags)
		fieldFlags.append(isSeamRoot)
		fieldFlags.append(isInFill)
		writer.writeOptional(filledType, flaggedIn: &fieldFlags)
		writer.writeOptional(filledCase, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Places.StackEntry: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("concreteType", \.concreteType),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			concreteType: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(concreteType)
	}
}

extension SeamSignature.Places.SendableFunctionOpened: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("function", \.function),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			property: reader.read(),
			function: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(function)
	}
}

extension SeamSignature.Places.FillFieldHiding: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("calledSeam", \.calledSeam),
				BinaryLayoutField("receivingSeam", \.receivingSeam),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			calledSeam: reader.read(),
			receivingSeam: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(calledSeam)
		writer.write(receivingSeam)
	}
}

extension SeamSignature.Places.Buildability: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("labelsHeldAboveSeam", \.labelsHeldAboveSeam),
				BinaryLayoutField("placesInTree", \.placesInTree),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			labelsHeldAboveSeam: reader.read(),
			placesInTree: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(labelsHeldAboveSeam)
		writer.write(placesInTree)
	}
}

extension SeamSignature.Places.Declaration: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("field", \.field),
				BinaryLayoutField("isBoundBeforeNextProperty", \.isBoundBeforeNextProperty),
				BinaryLayoutField("builtAfter", \.builtAfter),
				BinaryLayoutField("reason", \.reason),
				BinaryLayoutField("isForwarded", \.isForwarded),
				BinaryLayoutField("cycleParameterOrigin", \.cycleParameterOrigin),
				BinaryLayoutField("alias", \.alias),
				BinaryLayoutField("isBoundFromCallersArgument", \.isBoundFromCallersArgument),
				BinaryLayoutField("isCycleParameter", \.isCycleParameter),
				BinaryLayoutField("isReboundByBuilderFunction", \.isReboundByBuilderFunction),
				BinaryLayoutField("isFieldOfSeamParameter", \.isFieldOfSeamParameter),
				BinaryLayoutField("fillFieldHiding", \.fillFieldHiding),
				BinaryLayoutField("buildability", \.buildability),
				BinaryLayoutField("child", \.child),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		let declaration = try Self(
			field: reader.read(),
			isBoundBeforeNextProperty: fieldFlags.next(),
			builtAfter: reader.readOptional(flaggedIn: &fieldFlags) as Property?,
			reason: reader.read(),
			isForwarded: fieldFlags.next(),
			cycleParameterOrigin: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin?,
			alias: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Hole.UncarriedDeclaration.AliasOrigin?,
			isBoundFromCallersArgument: fieldFlags.next(),
			isCycleParameter: fieldFlags.next(),
			isReboundByBuilderFunction: fieldFlags.next(),
			isFieldOfSeamParameter: fieldFlags.next(),
			fillFieldHiding: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.FillFieldHiding?,
			buildability: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.Buildability?,
		)
		// What it holds as a child of its scope is no argument of its initializer.
		let child = try reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.ChildFacts?
		try fieldFlags.finish()
		self = child.map(declaration.asChild) ?? declaration
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(field)
		fieldFlags.append(isBoundBeforeNextProperty)
		writer.writeOptional(builtAfter, flaggedIn: &fieldFlags)
		writer.write(reason)
		fieldFlags.append(isForwarded)
		writer.writeOptional(cycleParameterOrigin, flaggedIn: &fieldFlags)
		writer.writeOptional(alias, flaggedIn: &fieldFlags)
		fieldFlags.append(isBoundFromCallersArgument)
		fieldFlags.append(isCycleParameter)
		fieldFlags.append(isReboundByBuilderFunction)
		fieldFlags.append(isFieldOfSeamParameter)
		writer.writeOptional(fillFieldHiding, flaggedIn: &fieldFlags)
		writer.writeOptional(buildability, flaggedIn: &fieldFlags)
		writer.writeOptional(child, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Places.ChildFacts: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("position", \.position),
				BinaryLayoutField("isBuilder", \.isBuilder),
				BinaryLayoutField("loop", \.loop),
				BinaryLayoutField("builtType", \.builtType),
				BinaryLayoutField("isPlace", \.isPlace),
				BinaryLayoutField("receivesOnlyIfAvailable", absentWhenEmpty: \.receivesOnlyIfAvailable),
				BinaryLayoutField("carriers", absentWhenEmpty: \.carriers),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			position: reader.read(),
			isBuilder: fieldFlags.next(),
			loop: reader.readOptional(flaggedIn: &fieldFlags) as Int?,
			builtType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			isPlace: fieldFlags.next(),
			receivesOnlyIfAvailable: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			carriers: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(position)
		fieldFlags.append(isBuilder)
		writer.writeOptional(loop, flaggedIn: &fieldFlags)
		writer.writeOptional(builtType, flaggedIn: &fieldFlags)
		fieldFlags.append(isPlace)
		writer.writeAbsentWhenEmpty(receivesOnlyIfAvailable, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(carriers, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Places.CycleReentry: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("parameterTakingType", \.parameterTakingType),
				BinaryLayoutField("closedOnProperty", \.closedOnProperty),
				BinaryLayoutField("closedOnBuiltType", \.closedOnBuiltType),
				BinaryLayoutField("reenteringType", \.reenteringType),
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
			reenteringType: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(declaringType)
		writer.write(declarationLocation)
		writer.write(parameterTakingType)
		writer.write(closedOnProperty)
		writer.write(closedOnBuiltType)
		writer.write(reenteringType)
	}
}

extension SeamSignature.Places.Level: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("key", \.key),
				BinaryLayoutField("declarationList", \.declarationList),
				BinaryLayoutField("nextPosition", \.nextPosition),
				BinaryLayoutField("nextLoop", \.nextLoop),
				BinaryLayoutField("opensSendableFunction", \.opensSendableFunction),
				BinaryLayoutField("cycleReentries", absentWhenEmpty: \.cycleReentries),
				BinaryLayoutField("fillBaseStack", absentWhenEmpty: \.fillBaseStack),
				BinaryLayoutField("fillOwnerType", \.fillOwnerType),
				BinaryLayoutField("pathSegment", absentWhenEmpty: \.pathSegment),
				BinaryLayoutField("pathTypes", absentWhenEmpty: \.pathTypes),
				BinaryLayoutField("parents", absentWhenEmpty: \.parents),
				BinaryLayoutField("declaredSegmentByParent", absentWhenEmpty: \.declaredSegmentByParent),
				BinaryLayoutField("closesOn", \.closesOn),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			key: reader.read(),
			declarationList: reader.read(),
			nextPosition: reader.readOptional(flaggedIn: &fieldFlags) as Int?,
			nextLoop: reader.readOptional(flaggedIn: &fieldFlags) as Int?,
			opensSendableFunction: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.SendableFunctionOpened?,
			cycleReentries: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			fillBaseStack: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			fillOwnerType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			pathSegment: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			pathTypes: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			parents: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			declaredSegmentByParent: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			closesOn: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.StackEntry?,
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(key)
		writer.write(declarationList)
		writer.writeOptional(nextPosition, flaggedIn: &fieldFlags)
		writer.writeOptional(nextLoop, flaggedIn: &fieldFlags)
		writer.writeOptional(opensSendableFunction, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(cycleReentries, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(fillBaseStack, flaggedIn: &fieldFlags)
		writer.writeOptional(fillOwnerType, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(pathSegment, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(pathTypes, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(parents, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(declaredSegmentByParent, flaggedIn: &fieldFlags)
		writer.writeOptional(closesOn, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Places.CalledCase: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("isPublicMock", \.isPublicMock),
				BinaryLayoutField("caseIndex", \.caseIndex),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			seamType: reader.read(),
			isPublicMock: reader.read(),
			caseIndex: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(seamType)
		writer.write(isPublicMock)
		writer.write(caseIndex)
	}
}

extension SeamSignature.Places.Case: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("ownerLevel", \.ownerLevel),
				BinaryLayoutField("isBuiltInSendableFunction", \.isBuiltInSendableFunction),
				BinaryLayoutField("siteOpensSendableFunction", \.siteOpensSendableFunction),
				BinaryLayoutField("passedUp", \.passedUp),
				BinaryLayoutField("firstCasePresentingSamePlaces", \.firstCasePresentingSamePlaces),
				BinaryLayoutField("isPassedOnSendable", \.isPassedOnSendable),
				BinaryLayoutField("calledCopyDeclarations", absentWhenEmpty: \.calledCopyDeclarations),
				BinaryLayoutField("uncarriedReplacedOnPathsToCalls", absentWhenEmpty: \.uncarriedReplacedOnPathsToCalls),
				BinaryLayoutField("reenteringCallDeclarations", absentWhenEmpty: \.reenteringCallDeclarations),
				BinaryLayoutField("reenteringPlaceFields", absentWhenEmpty: \.reenteringPlaceFields),
				BinaryLayoutField("namingRoute", \.namingRoute),
				BinaryLayoutField("narrowestAccess", \.narrowestAccess),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			ownerLevel: reader.read(),
			isBuiltInSendableFunction: fieldFlags.next(),
			siteOpensSendableFunction: fieldFlags.next(),
			passedUp: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.CalledCase?,
			firstCasePresentingSamePlaces: reader.readOptional(flaggedIn: &fieldFlags) as Int?,
			isPassedOnSendable: fieldFlags.next(),
			calledCopyDeclarations: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			uncarriedReplacedOnPathsToCalls: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			reenteringCallDeclarations: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			reenteringPlaceFields: reader.readAbsentWhenEmpty(flaggedIn: &fieldFlags),
			namingRoute: reader.read(),
			narrowestAccess: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.Case.Access?,
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(ownerLevel)
		fieldFlags.append(isBuiltInSendableFunction)
		fieldFlags.append(siteOpensSendableFunction)
		writer.writeOptional(passedUp, flaggedIn: &fieldFlags)
		writer.writeOptional(firstCasePresentingSamePlaces, flaggedIn: &fieldFlags)
		fieldFlags.append(isPassedOnSendable)
		writer.writeAbsentWhenEmpty(calledCopyDeclarations, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(uncarriedReplacedOnPathsToCalls, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(reenteringCallDeclarations, flaggedIn: &fieldFlags)
		writer.writeAbsentWhenEmpty(reenteringPlaceFields, flaggedIn: &fieldFlags)
		writer.write(namingRoute)
		writer.writeOptional(narrowestAccess, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Places.Case.Access: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("level", \.level),
				BinaryLayoutField("cause", \.cause),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			level: reader.read(),
			cause: reader.read() as TypeAccessProof.Cause?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(level)
		writer.write(cause)
	}
}
