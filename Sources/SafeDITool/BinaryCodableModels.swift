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

// Each type writes its fields in the order its initializer takes them, and reads them back through that
// initializer, whose argument expressions Swift evaluates from left to right. A field the initializer derives
// from the others is not written. `binaryLayout` lists every stored property, derived or not, because tests
// compare it against the properties the type declares.

// MARK: - SafeDITool types

extension CachedScannedModuleInfo: BinarySchemaMember {
	static let binaryLayout = [
		"moduleInfo",
		"conditionSensitiveFileScans",
		"additionalModuleInfo",
		"additionalConditionSensitiveFileScans",
		"projectRoot",
		"scannedInputs",
		"csvInputPaths",
		"additionalInputAbsolutePaths",
		"additionalDirectories",
		"activeCompilationConditions",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			moduleInfo: reader.read(),
			conditionSensitiveFileScans: reader.read(),
			additionalModuleInfo: reader.read(),
			additionalConditionSensitiveFileScans: reader.read(),
			projectRoot: reader.read(),
			scannedInputs: reader.read(),
			csvInputPaths: reader.read(),
			additionalInputAbsolutePaths: reader.read(),
			additionalDirectories: reader.read(),
			activeCompilationConditions: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(moduleInfo)
		writer.write(conditionSensitiveFileScans)
		writer.write(additionalModuleInfo)
		writer.write(additionalConditionSensitiveFileScans)
		writer.write(projectRoot)
		writer.write(scannedInputs)
		writer.write(csvInputPaths)
		writer.write(additionalInputAbsolutePaths)
		writer.write(additionalDirectories)
		writer.write(activeCompilationConditions)
	}
}

extension ScannedInput: BinarySchemaMember {
	static let binaryLayout = [
		"path",
		"modificationStamp",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			path: reader.read(),
			modificationStamp: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(path)
		writer.write(modificationStamp)
	}
}

extension FileScan: BinarySchemaMember {
	static let binaryLayout = [
		"path",
		"imports",
		"mockImports",
		"instantiables",
		"configurations",
		"encounteredUnexpectedNodes",
		"conditionalCompilationDecisions",
		"consultedCompilationConditions",
		"importSegments",
		"importOnlyConsultedCompilationConditions",
		"outputFileDeclarations",
		"nestedTypeDeclarations",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			path: reader.read(),
			imports: reader.read(),
			mockImports: reader.read(),
			instantiables: reader.read(),
			configurations: reader.read(),
			encounteredUnexpectedNodes: reader.read(),
			conditionalCompilationDecisions: reader.read(),
			consultedCompilationConditions: reader.read(),
			importSegments: reader.read(),
			importOnlyConsultedCompilationConditions: reader.read(),
			outputFileDeclarations: reader.read(),
			nestedTypeDeclarations: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(path)
		writer.write(imports)
		writer.write(mockImports)
		writer.write(instantiables)
		writer.write(configurations)
		writer.write(encounteredUnexpectedNodes)
		writer.write(conditionalCompilationDecisions)
		writer.write(consultedCompilationConditions)
		writer.write(importSegments)
		writer.write(importOnlyConsultedCompilationConditions)
		writer.write(outputFileDeclarations)
		writer.write(nestedTypeDeclarations)
	}
}

extension OutputFileDeclarations: BinarySchemaMember {
	static let binaryLayout = [
		"declaresRoot",
		"declaresMockGeneratingType",
		"declaresConfiguration",
		"additionalMocksToGenerate",
		"additionalDirectoriesToInclude",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			declaresRoot: reader.read(),
			declaresMockGeneratingType: reader.read(),
			declaresConfiguration: reader.read(),
			additionalMocksToGenerate: reader.read(),
			additionalDirectoriesToInclude: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(declaresRoot)
		writer.write(declaresMockGeneratingType)
		writer.write(declaresConfiguration)
		writer.write(additionalMocksToGenerate)
		writer.write(additionalDirectoriesToInclude)
	}
}

extension ModuleInfo: BinarySchemaMember {
	static let binaryLayout = [
		"imports",
		"mockImports",
		"instantiables",
		"configurations",
		"filesWithUnexpectedNodes",
		"conditionalCompilationDecisions",
		"nestedTypeDeclarations",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			imports: reader.read(),
			mockImports: reader.read(),
			instantiables: reader.read(),
			configurations: reader.read(),
			filesWithUnexpectedNodes: reader.read() as [String]?,
			conditionalCompilationDecisions: reader.read(),
			nestedTypeDeclarations: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(imports)
		writer.write(mockImports)
		writer.write(instantiables)
		writer.write(configurations)
		writer.write(filesWithUnexpectedNodes)
		writer.write(conditionalCompilationDecisions)
		writer.write(nestedTypeDeclarations)
	}
}

extension NestedTypeDeclarations: BinarySchemaMember {
	static let binaryLayout = [
		"declarations",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(reader.read() as [NestedTypeDeclaration])
	}

	/// Writes the declarations sorted, because a set's iteration order differs between processes.
	func write(to writer: inout BinaryWriter) {
		writer.write(sortedDeclarations)
	}
}

extension NestedTypeDeclaration: BinarySchemaMember {
	static let binaryLayout = [
		"path",
		"kind",
		"access",
		"superclassCandidate",
		"scopePath",
		"isCompilerDetermined",
		"isAbsent",
		"consultedCompilationConditions",
		"conditionalCompilationDecisions",
		"filePath",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			path: reader.read(),
			kind: reader.read(),
			access: reader.read(),
			superclassCandidate: reader.read() as String?,
			scopePath: reader.read() as String?,
			isCompilerDetermined: reader.read(),
			isAbsent: reader.read(),
			consultedCompilationConditions: reader.read(),
			conditionalCompilationDecisions: reader.read(),
			filePath: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(path)
		writer.write(kind)
		writer.write(access)
		writer.write(superclassCandidate)
		writer.write(scopePath)
		writer.write(isCompilerDetermined)
		writer.write(isAbsent)
		writer.write(consultedCompilationConditions)
		writer.write(conditionalCompilationDecisions)
		writer.write(filePath)
	}
}

extension NestedTypeDeclaration.Kind: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .classType: .classType
		case .protocolType: .protocolType
		case .otherType: .otherType
		case .genericParameter: .genericParameter
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .classType: writer.writeTag(Tag.classType)
		case .protocolType: writer.writeTag(Tag.protocolType)
		case .otherType: writer.writeTag(Tag.otherType)
		case .genericParameter: writer.writeTag(Tag.genericParameter)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case classType
		case protocolType
		case otherType
		case genericParameter
	}
}

extension NestedTypeDeclaration.Access: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .file: .file
		case .module: .module
		case .package: .package
		case .exported: .exported
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .file: writer.writeTag(Tag.file)
		case .module: writer.writeTag(Tag.module)
		case .package: writer.writeTag(Tag.package)
		case .exported: writer.writeTag(Tag.exported)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case file
		case module
		case package
		case exported
	}
}

// MARK: - SafeDICore types

extension ImportStatement: BinarySchemaMember {
	static let binaryLayout = [
		"attribute",
		"kind",
		"moduleName",
		"type",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			attribute: reader.read(),
			kind: reader.read(),
			moduleName: reader.read(),
			type: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(attribute)
		writer.write(kind)
		writer.write(moduleName)
		writer.write(type)
	}
}

extension FileVisitor.ImportSegment: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .imports:
			try .imports(reader.read())
		case .conditionalImports:
			try .conditionalImports(source: reader.read())
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .imports(importStatements):
			writer.writeTag(Tag.imports)
			writer.write(importStatements)
		case let .conditionalImports(source):
			writer.writeTag(Tag.conditionalImports)
			writer.write(source)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case imports
		case conditionalImports
	}
}

extension ConditionalCompilationDecision: BinarySchemaMember {
	static let binaryLayout = [
		"condition",
		"isActive",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			condition: reader.read(),
			isActive: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(condition)
		writer.write(isActive)
	}
}

extension SafeDIConfiguration: BinarySchemaMember {
	static let binaryLayout = [
		"additionalImportedModules",
		"additionalDirectoriesToInclude",
		"additionalMocksToGenerate",
		"mockConditionalCompilation",
		"sourceFilePath",
		"declarationLocation",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			additionalImportedModules: reader.read(),
			additionalDirectoriesToInclude: reader.read(),
			additionalMocksToGenerate: reader.read(),
			mockConditionalCompilation: reader.read() as String?,
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
		)
		sourceFilePath = try reader.read() as String?
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(additionalImportedModules)
		writer.write(additionalDirectoriesToInclude)
		writer.write(additionalMocksToGenerate)
		writer.write(mockConditionalCompilation)
		writer.write(declarationLocation)
		writer.write(sourceFilePath)
	}
}

extension Instantiable: BinarySchemaMember {
	static let binaryLayout = [
		"instantiableTypes",
		"isRoot",
		"initializer",
		"dependencies",
		"declarationType",
		"mockAttributes",
		"generateMock",
		"mockOnly",
		"mockInitializer",
		"mockReturnType",
		"customMockName",
		"mockDeclarationLocation",
		"sourceFilePath",
		"declarationLocation",
		"unsearchedEnclosingTypeCount",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		// `instantiableTypes` is written as its first element and then the rest, so it is never empty.
		try self.init(
			instantiableType: reader.read(),
			isRoot: reader.read(),
			initializer: reader.read() as Initializer?,
			additionalInstantiables: reader.read() as [TypeDescription],
			dependencies: reader.read(),
			declarationType: reader.read(),
			mockAttributes: reader.read(),
			generateMock: reader.read(),
			mockOnly: reader.read(),
			mockInitializer: reader.read() as Initializer?,
			mockReturnType: reader.read() as TypeDescription?,
			customMockName: reader.read() as String?,
			mockDeclarationLocation: reader.read() as Dependency.DeclarationLocation?,
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			unsearchedEnclosingTypeCount: reader.read(),
		)
		sourceFilePath = try reader.read() as String?
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(concreteInstantiable)
		writer.write(isRoot)
		writer.write(initializer)
		writer.write(Array(instantiableTypes.dropFirst()))
		writer.write(dependencies)
		writer.write(declarationType)
		writer.write(mockAttributes)
		writer.write(generateMock)
		writer.write(mockOnly)
		writer.write(mockInitializer)
		writer.write(mockReturnType)
		writer.write(customMockName)
		writer.write(mockDeclarationLocation)
		writer.write(declarationLocation)
		writer.write(unsearchedEnclosingTypeCount)
		writer.write(sourceFilePath)
	}
}

extension Instantiable.DeclarationType: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .classType: .classType
		case .actorType: .actorType
		case .structType: .structType
		case .extensionType: .extensionType
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .classType: writer.writeTag(Tag.classType)
		case .actorType: writer.writeTag(Tag.actorType)
		case .structType: writer.writeTag(Tag.structType)
		case .extensionType: writer.writeTag(Tag.extensionType)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case classType
		case actorType
		case structType
		case extensionType
	}
}

extension Initializer: BinarySchemaMember {
	static let binaryLayout = [
		"isPublicOrOpen",
		"isOptional",
		"isAsync",
		"doesThrow",
		"hasGenericParameter",
		"hasGenericWhereClause",
		"arguments",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			isPublicOrOpen: reader.read(),
			isOptional: reader.read(),
			isAsync: reader.read(),
			doesThrow: reader.read(),
			hasGenericParameter: reader.read(),
			hasGenericWhereClause: reader.read(),
			arguments: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(isPublicOrOpen)
		writer.write(isOptional)
		writer.write(isAsync)
		writer.write(doesThrow)
		writer.write(hasGenericParameter)
		writer.write(hasGenericWhereClause)
		writer.write(arguments)
	}
}

extension Initializer.Argument: BinarySchemaMember {
	static let binaryLayout = [
		"outerLabel",
		"innerLabel",
		"typeDescription",
		"defaultValueExpression",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			outerLabel: reader.read() as String?,
			innerLabel: reader.read(),
			typeDescription: reader.read(),
			defaultValueExpression: reader.read() as String?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(outerLabel)
		writer.write(innerLabel)
		writer.write(typeDescription)
		writer.write(defaultValueExpression)
	}
}

extension Dependency: BinarySchemaMember {
	static let binaryLayout = [
		"property",
		"source",
		"asInstantiatedType",
		"declarationLocation",
		"identifierRange",
		"typeAnnotationRange",
		"bareAttributeRange",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		// `asInstantiatedType` is derived from `property` and `source`.
		try self.init(
			property: reader.read(),
			source: reader.read(),
			declarationLocation: reader.read() as DeclarationLocation?,
			identifierRange: reader.read() as SourceRange?,
			typeAnnotationRange: reader.read() as SourceRange?,
			bareAttributeRange: reader.read() as SourceRange?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(property)
		writer.write(source)
		writer.write(declarationLocation)
		writer.write(identifierRange)
		writer.write(typeAnnotationRange)
		writer.write(bareAttributeRange)
	}
}

extension Dependency.Source: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .instantiated:
			try .instantiated(
				fulfillingTypeDescription: reader.read() as TypeDescription?,
				erasedToConcreteExistential: reader.read(),
			)
		case .received:
			try .received(onlyIfAvailable: reader.read())
		case .aliased:
			try .aliased(
				fulfillingProperty: reader.read(),
				erasedToConcreteExistential: reader.read(),
				onlyIfAvailable: reader.read(),
			)
		case .forwarded:
			.forwarded
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
			writer.writeTag(Tag.instantiated)
			writer.write(fulfillingTypeDescription)
			writer.write(erasedToConcreteExistential)
		case let .received(onlyIfAvailable):
			writer.writeTag(Tag.received)
			writer.write(onlyIfAvailable)
		case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
			writer.writeTag(Tag.aliased)
			writer.write(fulfillingProperty)
			writer.write(erasedToConcreteExistential)
			writer.write(onlyIfAvailable)
		case .forwarded:
			writer.writeTag(Tag.forwarded)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case instantiated
		case received
		case aliased
		case forwarded
	}
}

extension Dependency.SourceRange: BinarySchemaMember {
	static let binaryLayout = [
		"startLine",
		"startColumn",
		"endLine",
		"endColumn",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			startLine: reader.read(),
			startColumn: reader.read(),
			endLine: reader.read(),
			endColumn: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(startLine)
		writer.write(startColumn)
		writer.write(endLine)
		writer.write(endColumn)
	}
}

extension Dependency.DeclarationLocation: BinarySchemaMember {
	static let binaryLayout = [
		"filePath",
		"line",
		"column",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			filePath: reader.read(),
			line: reader.read(),
			column: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(filePath)
		writer.write(line)
		writer.write(column)
	}
}

extension Property: BinarySchemaMember {
	static let binaryLayout = [
		"label",
		"typeDescription",
		"hashOfLabelAndTypeDescription",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		// The stored hash is not written: Swift seeds hashing differently in every process, so the
		// initializer computes it again from the label and type description.
		try self.init(
			label: reader.read(),
			typeDescription: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(label)
		writer.write(typeDescription)
	}
}

extension TypeDescription: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = try reader.readNested { reader throws(BinaryDecodingError) in
			switch try reader.readTag() as Tag {
			case .void:
				try .void(reader.read())
			case .simple:
				try .simple(name: reader.read(), generics: reader.read())
			case .nested:
				try .nested(name: reader.read(), parentType: reader.read(), generics: reader.read())
			case .composition:
				try .composition(reader.read())
			case .optional:
				try .optional(reader.read())
			case .implicitlyUnwrappedOptional:
				try .implicitlyUnwrappedOptional(reader.read())
			case .some:
				try .some(reader.read())
			case .any:
				try .any(reader.read())
			case .metatype:
				try .metatype(reader.read(), isType: reader.read())
			case .attributed:
				try .attributed(reader.read(), specifiers: reader.read(), attributes: reader.read())
			case .array:
				try .array(element: reader.read())
			case .dictionary:
				try .dictionary(key: reader.read(), value: reader.read())
			case .tuple:
				try .tuple(reader.read())
			case .closure:
				try .closure(arguments: reader.read(), isAsync: reader.read(), doesThrow: reader.read(), returnType: reader.read())
			case .unknown:
				try .unknown(text: reader.read())
			}
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case let .void(spelling):
			writer.writeTag(Tag.void)
			writer.write(spelling)
		case let .simple(name, generics):
			writer.writeTag(Tag.simple)
			writer.write(name)
			writer.write(generics)
		case let .nested(name, parentType, generics):
			writer.writeTag(Tag.nested)
			writer.write(name)
			writer.write(parentType)
			writer.write(generics)
		case let .composition(types):
			writer.writeTag(Tag.composition)
			writer.write(types)
		case let .optional(type):
			writer.writeTag(Tag.optional)
			writer.write(type)
		case let .implicitlyUnwrappedOptional(type):
			writer.writeTag(Tag.implicitlyUnwrappedOptional)
			writer.write(type)
		case let .some(type):
			writer.writeTag(Tag.some)
			writer.write(type)
		case let .any(type):
			writer.writeTag(Tag.any)
			writer.write(type)
		case let .metatype(type, isType):
			writer.writeTag(Tag.metatype)
			writer.write(type)
			writer.write(isType)
		case let .attributed(type, specifiers, attributes):
			writer.writeTag(Tag.attributed)
			writer.write(type)
			writer.write(specifiers)
			writer.write(attributes)
		case let .array(element):
			writer.writeTag(Tag.array)
			writer.write(element)
		case let .dictionary(key, value):
			writer.writeTag(Tag.dictionary)
			writer.write(key)
			writer.write(value)
		case let .tuple(elements):
			writer.writeTag(Tag.tuple)
			writer.write(elements)
		case let .closure(arguments, isAsync, doesThrow, returnType):
			writer.writeTag(Tag.closure)
			writer.write(arguments)
			writer.write(isAsync)
			writer.write(doesThrow)
			writer.write(returnType)
		case let .unknown(text):
			writer.writeTag(Tag.unknown)
			writer.write(text)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case void
		case simple
		case nested
		case composition
		case optional
		case implicitlyUnwrappedOptional
		case some
		case any
		case metatype
		case attributed
		case array
		case dictionary
		case tuple
		case closure
		case unknown
	}
}

extension TypeDescription.VoidSpelling: BinarySchemaMember {
	static let binaryLayout = tagNames(Tag.self)

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .tuple: .tuple
		case .identifier: .identifier
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .tuple: writer.writeTag(Tag.tuple)
		case .identifier: writer.writeTag(Tag.identifier)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case tuple
		case identifier
	}
}

extension TypeDescription.TupleElement: BinarySchemaMember {
	static let binaryLayout = [
		"label",
		"typeDescription",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			label: reader.read() as String?,
			reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(label)
		writer.write(typeDescription)
	}
}

extension UnorderedEquatingCollection: BinaryCodable, BinarySchemaMember where Element: BinaryCodable {
	/// `set` is derived from `array`.
	static var binaryLayout: [String] {
		[
			"array",
			"set",
		]
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init([Element](readingFrom: &reader))
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(Array(self))
	}
}
