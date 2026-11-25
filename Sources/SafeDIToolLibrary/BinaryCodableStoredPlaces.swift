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

// The places a module info file holds of its module's seams (`StoredModulePlaces`), each type written as
// `BinaryCodableModels.swift` writes the declarations: every field it stores, in the order its initializer takes them.

extension StoredModulePlaces: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("lowerSeams", \.lowerSeams),
				BinaryLayoutField("placesBySeam", \.placesBySeam),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(lowerSeams: reader.read(), placesBySeam: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(lowerSeams)
		writer.write(placesBySeam)
	}
}

extension StoredLowerSeam: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("seamType", \.seamType),
				BinaryLayoutField("checksum", \.checksum),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(moduleName: reader.read(), seamType: reader.read(), checksum: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(moduleName)
		writer.write(seamType)
		writer.write(checksum)
	}
}

extension StoredRecordReference: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("lowerSeam", \.lowerSeam),
				BinaryLayoutField("record", \.record),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(lowerSeam: reader.read(), record: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(lowerSeam)
		writer.write(record)
	}
}

extension StoredPlacePresentation: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("declaringModuleNames", \.declaringModuleNames),
				BinaryLayoutField("builderLabel", \.builderLabel),
				BinaryLayoutField("narrowerTierBuilderLabels", \.narrowerTierBuilderLabels),
				BinaryLayoutField("internalName", \.internalName),
				BinaryLayoutField("tierAccess", \.tierAccess),
				BinaryLayoutField("accessCause", \.accessCause),
				BinaryLayoutField("wrapperFunctionName", \.wrapperFunctionName),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			declaringModuleNames: reader.read(),
			builderLabel: reader.read(),
			narrowerTierBuilderLabels: reader.read(),
			internalName: reader.read(),
			tierAccess: reader.read(),
			accessCause: reader.read() as TypeAccessProof.Cause?,
			wrapperFunctionName: reader.read() as String?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(declaringModuleNames)
		writer.write(builderLabel)
		writer.write(narrowerTierBuilderLabels)
		writer.write(internalName)
		writer.write(tierAccess)
		writer.write(accessCause)
		writer.write(wrapperFunctionName)
	}
}

extension StoredPlaceAddition: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("typesToCall", \.typesToCall),
				BinaryLayoutField("route", \.route),
				BinaryLayoutField("isSendable", \.isSendable),
				BinaryLayoutField("declarations", \.declarations),
			],
			unwrittenProperties: [],
		)
	}

	/// Among a module's places an addition is read once, however many places a call presents alike.
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
		try self.init(typesToCall: reader.read(), route: reader.read(), isSendable: reader.read(), declarations: reader.read())
	}

	private func writeUnshared(to writer: inout BinaryWriter) {
		writer.write(typesToCall)
		writer.write(route)
		writer.write(isSendable)
		writer.write(declarations)
	}
}

extension StoredPassedUpPlace: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("record", \.record),
				BinaryLayoutField("others", \.others),
				BinaryLayoutField("presentation", \.presentation),
				BinaryLayoutField("addition", \.addition),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(record: reader.read(), others: reader.read(), presentation: reader.read() as StoredPlacePresentation?, addition: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(record)
		writer.write(others)
		writer.write(presentation)
		writer.write(addition)
	}
}

extension StoredPlaceDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .record: []
			case .kept: [.init("first", Int.self), .init("count", Int.self)]
			case .taken: [.init("other", Int.self), .init("declaration", Int.self)]
			case .boundOnPath: [.init("declaration", SeamSignature.Hole.UncarriedDeclaration.self), .init("placeOf", Int.self)]
			case .written: [.init(nil, SeamSignature.Hole.UncarriedDeclaration.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .record:
			.record
		case .kept:
			try .kept(first: reader.read(), count: reader.read())
		case .taken:
			try .taken(other: reader.read(), declaration: reader.read())
		case .boundOnPath:
			try .boundOnPath(declaration: reader.read(), placeOf: reader.read())
		case .written:
			try .written(reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .record:
			writer.writeTag(Tag.record)
		case let .kept(first, count):
			writer.writeTag(Tag.kept)
			writer.write(first)
			writer.write(count)
		case let .taken(other, declaration):
			writer.writeTag(Tag.taken)
			writer.write(other)
			writer.write(declaration)
		case let .boundOnPath(declaration, placeOf):
			writer.writeTag(Tag.boundOnPath)
			writer.write(declaration)
			writer.write(placeOf)
		case let .written(declaration):
			writer.writeTag(Tag.written)
			writer.write(declaration)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case record
		case kept
		case taken
		case boundOnPath
		case written
	}
}

extension StoredPlace: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .written: [.init(nil, SeamSignature.Hole.self)]
			case .passedUp: [.init(nil, StoredPassedUpPlace.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .written:
			try .written(reader.read())
		case .passedUp:
			try .passedUp(reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .written(place):
			writer.writeTag(Tag.written)
			writer.write(place)
		case let .passedUp(place):
			writer.writeTag(Tag.passedUp)
			writer.write(place)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case written
		case passedUp
	}
}
