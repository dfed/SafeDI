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
// from the others is not written. `binaryLayout` lists each field in the order it is written, with the value it
// writes, and names every stored property that is not itself a field, because tests compare it against the
// properties the type declares and the bytes it writes. An enum writes each case's payload in declaration order.

// MARK: - SafeDITool types

extension CachedScannedModuleInfo: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleInfo", \.moduleInfo),
				BinaryLayoutField("conditionSensitiveFileScans", \.conditionSensitiveFileScans),
				BinaryLayoutField("additionalModuleInfo", \.additionalModuleInfo),
				BinaryLayoutField("additionalConditionSensitiveFileScans", \.additionalConditionSensitiveFileScans),
				BinaryLayoutField("projectRoot", \.projectRoot),
				BinaryLayoutField("scannedInputs", \.scannedInputs),
				BinaryLayoutField("csvInputPaths", \.csvInputPaths),
				BinaryLayoutField("additionalInputAbsolutePaths", \.additionalInputAbsolutePaths),
				BinaryLayoutField("additionalDirectories", \.additionalDirectories),
				BinaryLayoutField("activeCompilationConditions", \.activeCompilationConditions),
			],
			unwrittenProperties: [],
		)
	}

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

extension AdditionalDirectory: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("entry", \.entry),
				BinaryLayoutField("path", \.path),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			entry: reader.read(),
			path: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(entry)
		writer.write(path)
	}
}

extension ScannedInput: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("path", \.path),
				BinaryLayoutField("modificationStamp", \.modificationStamp),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("path", \.path),
				BinaryLayoutField("imports", \.imports),
				BinaryLayoutField("mockImports", \.mockImports),
				BinaryLayoutField("instantiables", \.instantiables),
				BinaryLayoutField("configurations", \.configurations),
				BinaryLayoutField("encounteredUnexpectedNodes", \.encounteredUnexpectedNodes),
				BinaryLayoutField("conditionalCompilationDecisions", \.conditionalCompilationDecisions),
				BinaryLayoutField("consultedCompilationConditions", \.consultedCompilationConditions),
				BinaryLayoutField("importSegments", \.importSegments),
				BinaryLayoutField("importOnlyConsultedCompilationConditions", \.importOnlyConsultedCompilationConditions),
				BinaryLayoutField("outputFileDeclarations", \.outputFileDeclarations),
			],
			unwrittenProperties: [],
		)
	}

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
	}
}

extension OutputFileDeclarations: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("declaresRoot", \.declaresRoot),
				BinaryLayoutField("declaresMockGeneratingType", \.declaresMockGeneratingType),
				BinaryLayoutField("declaresConfiguration", \.declaresConfiguration),
				BinaryLayoutField("instantiableTypeNames", \.instantiableTypeNames),
				BinaryLayoutField("additionalMocksToGenerate", \.additionalMocksToGenerate),
				BinaryLayoutField("additionalDirectoriesToInclude", \.additionalDirectoriesToInclude),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			declaresRoot: reader.read(),
			declaresMockGeneratingType: reader.read(),
			declaresConfiguration: reader.read(),
			instantiableTypeNames: reader.read(),
			additionalMocksToGenerate: reader.read(),
			additionalDirectoriesToInclude: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(declaresRoot)
		writer.write(declaresMockGeneratingType)
		writer.write(declaresConfiguration)
		writer.write(instantiableTypeNames)
		writer.write(additionalMocksToGenerate)
		writer.write(additionalDirectoriesToInclude)
	}
}

extension ModuleInfo: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("imports", \.imports),
				BinaryLayoutField("mockImports", \.mockImports),
				BinaryLayoutField("instantiables", \.instantiables),
				BinaryLayoutField("configurations", \.configurations),
				BinaryLayoutField("filesWithUnexpectedNodes", \.filesWithUnexpectedNodes),
				BinaryLayoutField("conditionalCompilationDecisions", \.conditionalCompilationDecisions),
				BinaryLayoutField("instantiableTypeNamesInAnyClause", \.instantiableTypeNamesInAnyClause),
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("packageName", \.packageName),
				BinaryLayoutField("dependencyModuleNames", \.dependencyModuleNames),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			imports: reader.read(),
			mockImports: reader.read(),
			instantiables: reader.read(),
			configurations: reader.read(),
			filesWithUnexpectedNodes: reader.read() as [String]?,
			conditionalCompilationDecisions: reader.read(),
			instantiableTypeNamesInAnyClause: reader.read(),
			moduleName: reader.read() as String?,
			packageName: reader.read() as String?,
			dependencyModuleNames: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(imports)
		writer.write(mockImports)
		writer.write(instantiables)
		writer.write(configurations)
		writer.write(filesWithUnexpectedNodes)
		writer.write(conditionalCompilationDecisions)
		writer.write(instantiableTypeNamesInAnyClause)
		writer.write(moduleName)
		writer.write(packageName)
		writer.write(dependencyModuleNames)
	}
}

// MARK: - SafeDICore types

extension ImportStatement: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("attribute", \.attribute),
				BinaryLayoutField("kind", \.kind),
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("type", \.type),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .imports: [.init(nil, [ImportStatement].self)]
			case .conditionalImports: [.init("source", String.self)]
			}
		}
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("condition", \.condition),
				BinaryLayoutField("isActive", \.isActive),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("additionalImportedModules", \.additionalImportedModules),
				BinaryLayoutField("additionalDirectoriesToInclude", \.additionalDirectoriesToInclude),
				BinaryLayoutField("additionalMocksToGenerate", \.additionalMocksToGenerate),
				BinaryLayoutField("mockConditionalCompilation", \.mockConditionalCompilation),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("sourceFilePath", \.sourceFilePath),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("concreteInstantiable", \.concreteInstantiable),
				BinaryLayoutField("isRoot", \.isRoot),
				BinaryLayoutField("initializer", \.initializer),
				BinaryLayoutField("additionalInstantiables", \.additionalInstantiables),
				BinaryLayoutField("dependencies", \.dependencies),
				BinaryLayoutField("declarationType", \.declarationType),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("enclosingTypeAccess", \.enclosingTypeAccess),
				BinaryLayoutField("enclosingExtensionAccess", \.enclosingExtensionAccess),
				BinaryLayoutField("mockAttributes", \.mockAttributes),
				BinaryLayoutField("generateMock", \.generateMock),
				BinaryLayoutField("mockOnly", \.mockOnly),
				BinaryLayoutField("mockInitializer", \.mockInitializer),
				BinaryLayoutField("mockReturnType", \.mockReturnType),
				BinaryLayoutField("customMockName", \.customMockName),
				BinaryLayoutField("mockDeclarationLocation", \.mockDeclarationLocation),
				BinaryLayoutField("mockDeclarationAccess", \.mockDeclarationAccess),
				BinaryLayoutField("mockDeclarationModuleName", \.mockDeclarationModuleName),
				BinaryLayoutField("mockDeclarationPackageName", \.mockDeclarationPackageName),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("packageName", \.packageName),
				BinaryLayoutField("sourceFilePath", \.sourceFilePath),
			],
			unwrittenProperties: ["instantiableTypes"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		// `instantiableTypes` is written as its first element and then the rest, so it is never empty.
		try self.init(
			instantiableType: reader.read(),
			isRoot: reader.read(),
			initializer: reader.read() as Initializer?,
			additionalInstantiables: reader.read() as [TypeDescription],
			dependencies: reader.read(),
			declarationType: reader.read(),
			access: reader.read(),
			enclosingTypeAccess: reader.read(),
			enclosingExtensionAccess: reader.read() as AccessDeclaration?,
			mockAttributes: reader.read(),
			generateMock: reader.read(),
			mockOnly: reader.read(),
			mockInitializer: reader.read() as Initializer?,
			mockReturnType: reader.read() as TypeDescription?,
			customMockName: reader.read() as String?,
			mockDeclarationLocation: reader.read() as Dependency.DeclarationLocation?,
			mockDeclarationAccess: reader.read() as AccessDeclaration?,
			mockDeclarationModuleName: reader.read() as String?,
			mockDeclarationPackageName: reader.read() as String?,
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
			moduleName: reader.read() as String?,
			packageName: reader.read() as String?,
		)
		sourceFilePath = try reader.read() as String?
	}

	/// Every type description a file holds is part of an instantiable, which names the one that nests too deeply.
	func write(to writer: inout BinaryWriter) {
		writer.writeDescribed(as: concreteInstantiable.asSource) { writer in
			writer.write(concreteInstantiable)
			writer.write(isRoot)
			writer.write(initializer)
			writer.write(additionalInstantiables)
			writer.write(dependencies)
			writer.write(declarationType)
			writer.write(access)
			writer.write(enclosingTypeAccess)
			writer.write(enclosingExtensionAccess)
			writer.write(mockAttributes)
			writer.write(generateMock)
			writer.write(mockOnly)
			writer.write(mockInitializer)
			writer.write(mockReturnType)
			writer.write(customMockName)
			writer.write(mockDeclarationLocation)
			writer.write(mockDeclarationAccess)
			writer.write(mockDeclarationModuleName)
			writer.write(mockDeclarationPackageName)
			writer.write(declarationLocation)
			writer.write(moduleName)
			writer.write(packageName)
			writer.write(sourceFilePath)
		}
	}

	/// Every type the instantiable fulfills but its concrete type.
	fileprivate var additionalInstantiables: [TypeDescription] {
		Array(instantiableTypes.dropFirst())
	}
}

extension Instantiable.DeclarationType: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { _ in [] }
	}

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

extension AccessDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("level", \.level),
				BinaryLayoutField("modifierRange", \.modifierRange),
				BinaryLayoutField("declarationStartLocation", \.declarationStartLocation),
				BinaryLayoutField("isExtension", \.isExtension),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			level: reader.read(),
			modifierRange: reader.read() as Dependency.SourceRange?,
			declarationStartLocation: reader.read() as Dependency.DeclarationLocation?,
			isExtension: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(level)
		writer.write(modifierRange)
		writer.write(declarationStartLocation)
		writer.write(isExtension)
	}
}

extension AccessLevel: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { _ in [] }
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .open: .open
		case .public: .public
		case .package: .package
		case .internal: .internal
		case .fileprivate: .fileprivate
		case .private: .private
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .open: writer.writeTag(Tag.open)
		case .public: writer.writeTag(Tag.public)
		case .package: writer.writeTag(Tag.package)
		case .internal: writer.writeTag(Tag.internal)
		case .fileprivate: writer.writeTag(Tag.fileprivate)
		case .private: writer.writeTag(Tag.private)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case open
		case `public`
		case package
		case `internal`
		case `fileprivate`
		case `private`
	}
}

extension Initializer: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("isOptional", \.isOptional),
				BinaryLayoutField("isAsync", \.isAsync),
				BinaryLayoutField("doesThrow", \.doesThrow),
				BinaryLayoutField("hasGenericParameter", \.hasGenericParameter),
				BinaryLayoutField("hasGenericWhereClause", \.hasGenericWhereClause),
				BinaryLayoutField("arguments", \.arguments),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			access: reader.read(),
			isOptional: reader.read(),
			isAsync: reader.read(),
			doesThrow: reader.read(),
			hasGenericParameter: reader.read(),
			hasGenericWhereClause: reader.read(),
			arguments: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(access)
		writer.write(isOptional)
		writer.write(isAsync)
		writer.write(doesThrow)
		writer.write(hasGenericParameter)
		writer.write(hasGenericWhereClause)
		writer.write(arguments)
	}
}

extension Initializer.Argument: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("outerLabel", \.outerLabel),
				BinaryLayoutField("innerLabel", \.innerLabel),
				BinaryLayoutField("typeDescription", \.typeDescription),
				BinaryLayoutField("defaultValueExpression", \.defaultValueExpression),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("property", \.property),
				BinaryLayoutField("source", \.source),
				BinaryLayoutField("declarationLocation", \.declarationLocation),
				BinaryLayoutField("identifierRange", \.identifierRange),
				BinaryLayoutField("typeAnnotationRange", \.typeAnnotationRange),
				BinaryLayoutField("bareAttributeRange", \.bareAttributeRange),
			],
			unwrittenProperties: ["asInstantiatedType"],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .instantiated: [.init("fulfillingTypeDescription", TypeDescription?.self), .init("erasedToConcreteExistential", Bool.self)]
			case .received: [.init("onlyIfAvailable", Bool.self)]
			case .aliased: [.init("fulfillingProperty", Property.self), .init("erasedToConcreteExistential", Bool.self), .init("onlyIfAvailable", Bool.self)]
			case .forwarded: []
			}
		}
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("startLine", \.startLine),
				BinaryLayoutField("startColumn", \.startColumn),
				BinaryLayoutField("endLine", \.endLine),
				BinaryLayoutField("endColumn", \.endColumn),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("filePath", \.filePath),
				BinaryLayoutField("line", \.line),
				BinaryLayoutField("column", \.column),
			],
			unwrittenProperties: [],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("label", \.label),
				BinaryLayoutField("typeDescription", \.typeDescription),
			],
			unwrittenProperties: ["hashOfLabelAndTypeDescription"],
		)
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { tag in
			switch tag {
			case .void: [.init(nil, VoidSpelling.self)]
			case .simple: [.init("name", String.self), .init("generics", [TypeDescription].self)]
			case .nested: [.init("name", String.self), .init("parentType", TypeDescription.self), .init("generics", [TypeDescription].self)]
			case .composition: [.init(nil, UnorderedEquatingCollection<TypeDescription>.self)]
			case .optional: [.init(nil, TypeDescription.self)]
			case .implicitlyUnwrappedOptional: [.init(nil, TypeDescription.self)]
			case .some: [.init(nil, TypeDescription.self)]
			case .any: [.init(nil, TypeDescription.self)]
			case .metatype: [.init(nil, TypeDescription.self), .init("isType", Bool.self)]
			case .attributed: [.init(nil, TypeDescription.self), .init("specifiers", [String].self), .init("attributes", [String].self)]
			case .array: [.init("element", TypeDescription.self)]
			case .dictionary: [.init("key", TypeDescription.self), .init("value", TypeDescription.self)]
			case .tuple: [.init(nil, [TupleElement].self)]
			case .closure: [.init("arguments", [TypeDescription].self), .init("isAsync", Bool.self), .init("doesThrow", Bool.self), .init("returnType", TypeDescription.self)]
			case .unknown: [.init("text", String.self)]
			}
		}
	}

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
		writer.writeNested { writer in
			writeCase(to: &writer)
		}
	}

	private func writeCase(to writer: inout BinaryWriter) {
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
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { _ in [] }
	}

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
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("label", \.label),
				BinaryLayoutField("typeDescription", \.typeDescription),
			],
			unwrittenProperties: [],
		)
	}

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
	/// `array` is written as `elements`, and `set` is derived from it.
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("array", \.elements),
			],
			unwrittenProperties: ["set"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init([Element](readingFrom: &reader))
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(elements)
	}

	/// The elements in the order the collection holds them.
	fileprivate var elements: [Element] {
		Array(self)
	}
}
