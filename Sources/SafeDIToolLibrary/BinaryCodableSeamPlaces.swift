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

// A seam's places as a module info file carries them (`SeamSignature.Places`): the levels and the cases, each type
// written as `BinaryCodableSeamSignatures.swift` writes the rest of a signature, every field it stores in the order its
// initializer takes them. A level, a declaration and a level's key write their optional and Boolean fields as flags: a
// file holds one declaration per level that binds it, and most of what a declaration can hold is absent.

extension SeamSignature.Places: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("levels", \.levels),
				BinaryLayoutField("cases", \.cases),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			levels: reader.read(),
			cases: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(levels)
		writer.write(cases)
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
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
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
		try fieldFlags.finish()
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
				BinaryLayoutField("declarations", \.declarations),
				BinaryLayoutField("opensSendableFunction", \.opensSendableFunction),
				BinaryLayoutField("cycleReentries", \.cycleReentries),
				BinaryLayoutField("fillBaseStack", \.fillBaseStack),
				BinaryLayoutField("fillOwnerType", \.fillOwnerType),
				BinaryLayoutField("pathSegment", \.pathSegment),
				BinaryLayoutField("pathTypes", \.pathTypes),
				BinaryLayoutField("parents", \.parents),
				BinaryLayoutField("declaredSegmentByParent", \.declaredSegmentByParent),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			key: reader.read(),
			declarations: reader.read(),
			opensSendableFunction: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.SendableFunctionOpened?,
			cycleReentries: reader.read(),
			fillBaseStack: reader.read(),
			fillOwnerType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			pathSegment: reader.read(),
			pathTypes: reader.read(),
			parents: reader.read(),
			declaredSegmentByParent: reader.read(),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(key)
		writer.write(declarations)
		writer.writeOptional(opensSendableFunction, flaggedIn: &fieldFlags)
		writer.write(cycleReentries)
		writer.write(fillBaseStack)
		writer.writeOptional(fillOwnerType, flaggedIn: &fieldFlags)
		writer.write(pathSegment)
		writer.write(pathTypes)
		writer.write(parents)
		writer.write(declaredSegmentByParent)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension SeamSignature.Places.PassedUpReference: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("innerSeamType", \.innerSeamType),
				BinaryLayoutField("innerIsPublicMock", \.innerIsPublicMock),
				BinaryLayoutField("innerCaseIndex", \.innerCaseIndex),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			innerSeamType: reader.read(),
			innerIsPublicMock: reader.read(),
			innerCaseIndex: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(innerSeamType)
		writer.write(innerIsPublicMock)
		writer.write(innerCaseIndex)
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
				BinaryLayoutField("isPassedOnSendable", \.isPassedOnSendable),
				BinaryLayoutField("calledCopyDeclarations", \.calledCopyDeclarations),
				BinaryLayoutField("uncarriedReplacedOnPathsToCalls", \.uncarriedReplacedOnPathsToCalls),
				BinaryLayoutField("reenteringCallDeclarations", \.reenteringCallDeclarations),
				BinaryLayoutField("reenteringPlaceFields", \.reenteringPlaceFields),
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
			passedUp: reader.readOptional(flaggedIn: &fieldFlags) as SeamSignature.Places.PassedUpReference?,
			isPassedOnSendable: fieldFlags.next(),
			calledCopyDeclarations: reader.read(),
			uncarriedReplacedOnPathsToCalls: reader.read(),
			reenteringCallDeclarations: reader.read(),
			reenteringPlaceFields: reader.read(),
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
		fieldFlags.append(isPassedOnSendable)
		writer.write(calledCopyDeclarations)
		writer.write(uncarriedReplacedOnPathsToCalls)
		writer.write(reenteringCallDeclarations)
		writer.write(reenteringPlaceFields)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}
