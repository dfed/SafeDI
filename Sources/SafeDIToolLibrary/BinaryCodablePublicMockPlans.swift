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

// The plans a module info file carries of the public mocks its module declares (`StoredPublicMockPlan`), each type
// written as `BinaryCodableModels.swift` writes the declarations: every field it stores, in the order its initializer
// takes them.

extension ModulePublicMockPlans: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("mockedTypes", \.mockedTypes),
				BinaryLayoutField("compilesGeneratedMocks", \.compilesGeneratedMocks),
				BinaryLayoutField("encoding", \.encodingWithPositions),
			],
			// Written as `encoding`.
			unwrittenProperties: ["storage"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(mockedTypes: reader.read(), compilesGeneratedMocks: reader.read(), encoding: (reader.read() as BinaryEncoding).bytes)
	}

	/// Writes the mocked types, then the encoding of their plans (``encoding(writingPositionsAsAbsent:)``), which shares
	/// the values a plan repeats among the module's plans alone: a run that reads one module's decodes no other's.
	func write(to writer: inout BinaryWriter) {
		writer.write(mockedTypes)
		writer.write(compilesGeneratedMocks)
		writer.write(BinaryEncoding(bytes: encoding(writingPositionsAsAbsent: writer.writesPositionsAsAbsent)))
	}

	/// The encoding as a writer that writes positions writes it.
	private var encodingWithPositions: BinaryEncoding {
		BinaryEncoding(bytes: encoding(writingPositionsAsAbsent: false))
	}
}

extension StoredPublicMockPlan: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("mockedType", \.mockedType),
				BinaryLayoutField("parameters", \.parameters),
				BinaryLayoutField("noTierParameters", \.noTierParameters),
				BinaryLayoutField("tiers", \.tiers),
				BinaryLayoutField("guardTypeName", \.guardTypeName),
				BinaryLayoutField("holes", \.holes),
				BinaryLayoutField("builders", \.builders),
				BinaryLayoutField("scopeEnums", \.scopeEnums),
				BinaryLayoutField("receivers", \.receivers),
				BinaryLayoutField("typesDeclaredEscaping", \.typesDeclaredEscaping),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			mockedType: reader.read(),
			parameters: reader.read(),
			noTierParameters: reader.read(),
			tiers: reader.read(),
			guardTypeName: reader.read(),
			holes: reader.read(),
			builders: reader.read(),
			scopeEnums: reader.read(),
			receivers: reader.read(),
			typesDeclaredEscaping: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(mockedType)
		writer.write(parameters)
		writer.write(noTierParameters)
		writer.write(tiers)
		writer.write(guardTypeName)
		writer.write(holes)
		writer.write(builders)
		writer.write(scopeEnums)
		writer.write(receivers)
		writer.write(typesDeclaredEscaping)
	}
}

extension StoredPublicMockPlan.Parameter: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("name", \.name),
				BinaryLayoutField("narrowerTierNames", \.narrowerTierNames),
				BinaryLayoutField("type", \.type),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("accessCause", \.accessCause),
				BinaryLayoutField("nestedOmission", \.nestedOmission),
				BinaryLayoutField("role", \.role),
				BinaryLayoutField("isBuiltWhenNil", \.isBuiltWhenNil),
				BinaryLayoutField("builtWrapper", \.builtWrapper),
				BinaryLayoutField("builder", \.builder),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			name: reader.read(),
			narrowerTierNames: reader.read(),
			type: reader.read(),
			access: reader.read(),
			accessCause: reader.read() as TypeAccessProof.Cause?,
			nestedOmission: reader.read() as StoredPublicMockPlan.NestedOmission?,
			role: reader.read(),
			isBuiltWhenNil: reader.read(),
			builtWrapper: reader.read() as Property?,
			builder: reader.read() as SeamSignature.Builder?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(name)
		writer.write(narrowerTierNames)
		writer.write(type)
		writer.write(access)
		writer.write(accessCause)
		writer.write(nestedOmission)
		writer.write(role)
		writer.write(isBuiltWhenNil)
		writer.write(builtWrapper)
		writer.write(builder)
	}
}

extension StoredPublicMockPlan.Role: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .forwarded: [.init(nil, Property.self)]
			case .constructionDefault: []
			case .received: [.init(nil, Property.self), .init("isRequired", Bool.self)]
			case .overrides: []
			case .optionalBuilder: [.init("joinedBuilder", SeamSignature.ScopeEnum.Key?.self)]
			}
		}
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .forwarded:
			try .forwarded(reader.read())
		case .constructionDefault:
			.constructionDefault
		case .received:
			try .received(reader.read(), isRequired: reader.read())
		case .overrides:
			.overrides
		case .optionalBuilder:
			try .optionalBuilder(joinedBuilder: reader.read() as SeamSignature.ScopeEnum.Key?)
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .forwarded(property):
			writer.writeTag(Tag.forwarded)
			writer.write(property)
		case .constructionDefault:
			writer.writeTag(Tag.constructionDefault)
		case let .received(property, isRequired):
			writer.writeTag(Tag.received)
			writer.write(property)
			writer.write(isRequired)
		case .overrides:
			writer.writeTag(Tag.overrides)
		case let .optionalBuilder(joinedBuilder):
			writer.writeTag(Tag.optionalBuilder)
			writer.write(joinedBuilder)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case forwarded
		case constructionDefault
		case received
		case overrides
		case optionalBuilder
	}
}

extension StoredPublicMockPlan.NestedOmission: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("type", \.type),
				BinaryLayoutField("tier", \.tier),
				BinaryLayoutField("parameterAccess", \.parameterAccess),
				BinaryLayoutField("declaringModule", \.declaringModule),
				BinaryLayoutField("callerModule", \.callerModule),
				BinaryLayoutField("requirement", \.requirement),
				BinaryLayoutField("receivers", \.receivers),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			type: reader.read(),
			tier: reader.read(),
			parameterAccess: reader.read(),
			declaringModule: reader.read(),
			callerModule: reader.read(),
			requirement: reader.read(),
			receivers: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(type)
		writer.write(tier)
		writer.write(parameterAccess)
		writer.write(declaringModule)
		writer.write(callerModule)
		writer.write(requirement)
		writer.write(receivers)
	}
}

extension StoredPublicMockPlan.Receiver: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("declaringType", \.declaringType),
				BinaryLayoutField("dependency", \.dependency),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(declaringType: reader.read(), dependency: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(declaringType)
		writer.write(dependency)
	}
}
