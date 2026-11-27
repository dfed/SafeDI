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
				BinaryLayoutField("keptPlainTypeNames", \.keptPlainTypeNames),
				BinaryLayoutField("additionalKeptPlainTypeNames", \.additionalKeptPlainTypeNames),
				BinaryLayoutField("activeCompilationConditions", \.activeCompilationConditions),
				BinaryLayoutField("reservedTypeNameDeclarations", \.reservedTypeNameDeclarations),
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
			keptPlainTypeNames: reader.read(),
			additionalKeptPlainTypeNames: reader.read(),
			activeCompilationConditions: reader.read(),
			reservedTypeNameDeclarations: reader.read(),
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
		writer.write(keptPlainTypeNames)
		writer.write(additionalKeptPlainTypeNames)
		writer.write(activeCompilationConditions)
		writer.write(reservedTypeNameDeclarations)
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
				BinaryLayoutField("plainTypeDeclarations", \.plainTypeDeclarations),
				BinaryLayoutField("keptGuardedPlainTypeNames", \.keptGuardedPlainTypeNames),
				BinaryLayoutField("reservedTypeNameDeclarations", \.reservedTypeNameDeclarations),
			],
			// A cached scan is one whose module kept its plain type declarations
			// (`FileScan.keepingPlainTypeDeclarations(ofTypesWithin:keepingThoseOtherModulesPackageCanName:isInReadingModule:)`),
			// which leaves no block undecided.
			unwrittenProperties: ["plainTypeDeclarationDecisions"],
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
			plainTypeDeclarations: reader.read(),
			plainTypeDeclarationDecisions: [],
			keptGuardedPlainTypeNames: reader.read(),
			reservedTypeNameDeclarations: reader.read(),
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
		writer.write(plainTypeDeclarations)
		writer.write(keptGuardedPlainTypeNames)
		writer.write(reservedTypeNameDeclarations)
	}
}

extension OutputFileDeclarations: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("declaresRoot", \.declaresRoot),
				BinaryLayoutField("declaresDependencyTreeType", \.declaresDependencyTreeType),
				BinaryLayoutField("declaresMockGeneratingType", \.declaresMockGeneratingType),
				BinaryLayoutField("declaresConfiguration", \.declaresConfiguration),
				BinaryLayoutField("instantiableTypeNames", \.instantiableTypeNames),
				BinaryLayoutField("extendedTypeNames", \.extendedTypeNames),
				BinaryLayoutField("additionalMocksToGenerate", \.additionalMocksToGenerate),
				BinaryLayoutField("additionalDirectoriesToInclude", \.additionalDirectoriesToInclude),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			declaresRoot: reader.read(),
			declaresDependencyTreeType: reader.read(),
			declaresMockGeneratingType: reader.read(),
			declaresConfiguration: reader.read(),
			instantiableTypeNames: reader.read(),
			extendedTypeNames: reader.read(),
			additionalMocksToGenerate: reader.read(),
			additionalDirectoriesToInclude: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(declaresRoot)
		writer.write(declaresDependencyTreeType)
		writer.write(declaresMockGeneratingType)
		writer.write(declaresConfiguration)
		writer.write(instantiableTypeNames)
		writer.write(extendedTypeNames)
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
				BinaryLayoutField("plainTypeDeclarations", \.plainTypeDeclarations),
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
			plainTypeDeclarations: reader.read(),
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
		writer.write(plainTypeDeclarations)
	}
}

// MARK: - SafeDICore types

extension ImportStatement: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("attribute", \.attribute),
				BinaryLayoutField("kind", \.kind),
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("type", \.type),
				BinaryLayoutField("accessLevel", \.accessLevel),
				BinaryLayoutField("sourceFilePath", \.sourceFilePath),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			attribute: reader.read(),
			kind: reader.read(),
			moduleName: reader.read(),
			type: reader.read(),
			accessLevel: reader.readOptional(flaggedIn: &fieldFlags),
			sourceFilePath: reader.readOptional(flaggedIn: &fieldFlags),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(attribute)
		writer.write(kind)
		writer.write(moduleName)
		writer.write(type)
		writer.writeOptional(accessLevel, flaggedIn: &fieldFlags)
		writer.writeOptional(sourceFilePath, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
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

extension KeptPlainTypeNames: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("outermostTypeNames", \.outermostTypeNames),
				BinaryLayoutField("mentionedTypeNames", \.mentionedTypeNames),
				BinaryLayoutField("extendedTypeNames", \.extendedTypeNames),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			outermostTypeNames: reader.read(),
			mentionedTypeNames: reader.read(),
			extendedTypeNames: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(outermostTypeNames)
		writer.write(mentionedTypeNames)
		writer.write(extendedTypeNames)
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
				BinaryLayoutField("generatePlainDependencyTreeInitializers", \.generatePlainDependencyTreeInitializers),
				BinaryLayoutField("defaultIsolation", \.defaultIsolation),
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
			generatePlainDependencyTreeInitializers: reader.read(),
			defaultIsolation: reader.read() as SafeDIConfiguration.DefaultIsolation?,
			declarationLocation: reader.read() as Dependency.DeclarationLocation?,
		)
		sourceFilePath = try reader.read() as String?
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(additionalImportedModules)
		writer.write(additionalDirectoriesToInclude)
		writer.write(additionalMocksToGenerate)
		writer.write(mockConditionalCompilation)
		writer.write(generatePlainDependencyTreeInitializers)
		writer.write(defaultIsolation)
		writer.write(declarationLocation)
		writer.write(sourceFilePath)
	}
}

extension SafeDIConfiguration.DefaultIsolation: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { _ in [] }
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .mainActor: .mainActor
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .mainActor: writer.writeTag(Tag.mainActor)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case mainActor
	}
}

extension Instantiable: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("concreteInstantiable", \.concreteInstantiable),
				BinaryLayoutField("isRoot", \.isRoot),
				BinaryLayoutField("generatesDependencyTree", \.generatesDependencyTree),
				BinaryLayoutField("initializer", \.initializer),
				BinaryLayoutField("otherInitializers", \.otherInitializers),
				BinaryLayoutField("additionalInstantiables", \.additionalInstantiables),
				BinaryLayoutField("dependencies", \.dependencies),
				BinaryLayoutField("declarationType", \.declarationType),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("enclosingTypeAccess", \.enclosingTypeAccess),
				BinaryLayoutField("enclosingExtensionAccess", \.enclosingExtensionAccess),
				BinaryLayoutField("generatedInitializerAttributes", \.generatedInitializerAttributes),
				BinaryLayoutField("mockAttributes", \.mockAttributes),
				BinaryLayoutField("generateMock", \.generateMock),
				BinaryLayoutField("mockGenerationArgumentRange", \.mockGenerationArgumentRange),
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
				BinaryLayoutField("usesModuleDefaultIsolation", \.usesModuleDefaultIsolation),
				BinaryLayoutField("initializerUsesModuleDefaultIsolation", \.initializerUsesModuleDefaultIsolation),
				BinaryLayoutField("sourceFilePath", \.sourceFilePath),
				BinaryLayoutField("isInsideCompilerDecidedBlock", \.isInsideCompilerDecidedBlock),
				BinaryLayoutField("conformanceListNamesSendable", \.conformanceListNamesSendable),
				BinaryLayoutField("conformanceListNamesOtherTypes", \.conformanceListNamesOtherTypes),
				BinaryLayoutField("unstatedGlobalActorIsolation", \.unstatedGlobalActorIsolation),
				BinaryLayoutField("dependencyLabelsInUnselectedClauses", \.dependencyLabelsInUnselectedClauses),
				BinaryLayoutField("dependencyLabelsInsideConditionalBlocks", \.dependencyLabelsInsideConditionalBlocks),
			],
			// `rarelySetFields` holds fields written under their own names above, and `declaredName`, what one run makes
			// of the declaration, which no file records.
			unwrittenProperties: ["instantiableTypes", "rarelySetFields"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		// `instantiableTypes` is written as its first element and then the rest, so it is never empty.
		try self.init(
			instantiableType: reader.read(),
			isRoot: fieldFlags.next(),
			generatesDependencyTree: fieldFlags.next(),
			initializer: reader.readOptional(flaggedIn: &fieldFlags) as Initializer?,
			otherInitializers: reader.read(),
			additionalInstantiables: reader.read() as [TypeDescription],
			dependencies: reader.read(),
			declarationType: reader.read(),
			access: reader.read(),
			enclosingTypeAccess: reader.read(),
			enclosingExtensionAccess: reader.readOptional(flaggedIn: &fieldFlags) as AccessDeclaration?,
			generatedInitializerAttributes: reader.read(),
			mockAttributes: reader.read(),
			generateMock: reader.read(),
			mockGenerationArgumentRange: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.SourceRange?,
			mockOnly: fieldFlags.next(),
			mockInitializer: reader.readOptional(flaggedIn: &fieldFlags) as Initializer?,
			mockReturnType: reader.readOptional(flaggedIn: &fieldFlags) as TypeDescription?,
			customMockName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			mockDeclarationLocation: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.DeclarationLocation?,
			mockDeclarationAccess: reader.readOptional(flaggedIn: &fieldFlags) as AccessDeclaration?,
			mockDeclarationModuleName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			mockDeclarationPackageName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			declarationLocation: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.DeclarationLocation?,
			moduleName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			packageName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			usesModuleDefaultIsolation: fieldFlags.next(),
			initializerUsesModuleDefaultIsolation: fieldFlags.next(),
		)
		sourceFilePath = try reader.readOptional(flaggedIn: &fieldFlags) as String?
		isInsideCompilerDecidedBlock = fieldFlags.next()
		conformanceListNamesSendable = fieldFlags.next()
		conformanceListNamesOtherTypes = fieldFlags.next()
		unstatedGlobalActorIsolation = try reader.readOptional(flaggedIn: &fieldFlags) as UnstatedGlobalActorIsolation?
		dependencyLabelsInUnselectedClauses = try reader.read()
		dependencyLabelsInsideConditionalBlocks = try reader.read()
		try fieldFlags.finish()
	}

	/// Every type description a file holds is part of an instantiable, which names the one that nests too deeply.
	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.writeDescribed(as: concreteInstantiable.asSource) { writer in
			writer.write(concreteInstantiable)
			fieldFlags.append(isRoot)
			fieldFlags.append(generatesDependencyTree)
			writer.writeOptional(initializer, flaggedIn: &fieldFlags)
			writer.write(otherInitializers)
			writer.write(additionalInstantiables)
			writer.write(dependencies)
			writer.write(declarationType)
			writer.write(access)
			writer.write(enclosingTypeAccess)
			writer.writeOptional(enclosingExtensionAccess, flaggedIn: &fieldFlags)
			writer.write(generatedInitializerAttributes)
			writer.write(mockAttributes)
			writer.write(generateMock)
			writer.writeOptional(mockGenerationArgumentRange, flaggedIn: &fieldFlags)
			fieldFlags.append(mockOnly)
			writer.writeOptional(mockInitializer, flaggedIn: &fieldFlags)
			writer.writeOptional(mockReturnType, flaggedIn: &fieldFlags)
			writer.writeOptional(customMockName, flaggedIn: &fieldFlags)
			writer.writeOptional(mockDeclarationLocation, flaggedIn: &fieldFlags)
			writer.writeOptional(mockDeclarationAccess, flaggedIn: &fieldFlags)
			writer.writeOptional(mockDeclarationModuleName, flaggedIn: &fieldFlags)
			writer.writeOptional(mockDeclarationPackageName, flaggedIn: &fieldFlags)
			writer.writeOptional(declarationLocation, flaggedIn: &fieldFlags)
			writer.writeOptional(moduleName, flaggedIn: &fieldFlags)
			writer.writeOptional(packageName, flaggedIn: &fieldFlags)
			fieldFlags.append(usesModuleDefaultIsolation)
			fieldFlags.append(initializerUsesModuleDefaultIsolation)
			writer.writeOptional(sourceFilePath, flaggedIn: &fieldFlags)
			fieldFlags.append(isInsideCompilerDecidedBlock)
			fieldFlags.append(conformanceListNamesSendable)
			fieldFlags.append(conformanceListNamesOtherTypes)
			writer.writeOptional(unstatedGlobalActorIsolation, flaggedIn: &fieldFlags)
			writer.write(dependencyLabelsInUnselectedClauses)
			writer.write(dependencyLabelsInsideConditionalBlocks)
		}
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
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

extension Instantiable.DependencyLabelInUnselectedClause: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("label", \.label),
				BinaryLayoutField("clause", \.clause),
				BinaryLayoutField("clauseLocation", \.clauseLocation),
				BinaryLayoutField("isDeclaredDirectlyInClause", \.isDeclaredDirectlyInClause),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			label: reader.read(),
			clause: reader.read(),
			clauseLocation: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.DeclarationLocation?,
			isDeclaredDirectlyInClause: fieldFlags.next(),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(label)
		writer.write(clause)
		writer.writeOptional(clauseLocation, flaggedIn: &fieldFlags)
		fieldFlags.append(isDeclaredDirectlyInClause)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension Instantiable.UnstatedGlobalActorIsolation: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("typeName", \.typeName),
				BinaryLayoutField("attributeRange", \.attributeRange),
				BinaryLayoutField("findings", \.findings),
				BinaryLayoutField("attributeFixingEveryFinding", \.attributeFixingEveryFinding),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			typeName: reader.read(),
			attributeRange: reader.read(),
			findings: reader.read(),
			attributeFixingEveryFinding: reader.read(),
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(typeName)
		writer.write(attributeRange)
		writer.write(findings)
		writer.write(attributeFixingEveryFinding)
	}
}

extension Instantiable.UnstatedGlobalActorIsolation.Finding: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("generatedDeclaration", \.generatedDeclaration),
				BinaryLayoutField("handWrittenMockName", \.handWrittenMockName),
				BinaryLayoutField("argumentLabel", \.argumentLabel),
				BinaryLayoutField("attributeFixingFinding", \.attributeFixingFinding),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			generatedDeclaration: reader.read(),
			handWrittenMockName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			argumentLabel: reader.read(),
			attributeFixingFinding: reader.read(),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(generatedDeclaration)
		writer.writeOptional(handWrittenMockName, flaggedIn: &fieldFlags)
		writer.write(argumentLabel)
		writer.write(attributeFixingFinding)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension Instantiable.UnstatedGlobalActorIsolation.GeneratedDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { _ in [] }
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .rootInitializer: .rootInitializer
		case .seamInitializers: .seamInitializers
		case .mock: .mock
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .rootInitializer: writer.writeTag(Tag.rootInitializer)
		case .seamInitializers: writer.writeTag(Tag.seamInitializers)
		case .mock: writer.writeTag(Tag.mock)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case rootInitializer
		case seamInitializers
		case mock
	}
}

extension ReservedTypeNameDeclaration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("typeName", \.typeName),
				BinaryLayoutField("prefix", \.prefix),
				BinaryLayoutField("location", \.location),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			typeName: reader.read(),
			prefix: reader.read(),
			location: reader.read() as Dependency.DeclarationLocation?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(typeName)
		writer.write(prefix)
		writer.write(location)
	}
}

extension PlainTypeDeclaration: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("typeDescription", \.typeDescription),
				BinaryLayoutField("access", \.access),
				BinaryLayoutField("enclosingTypeAccess", \.enclosingTypeAccess),
				BinaryLayoutField("enclosingExtensionAccess", \.enclosingExtensionAccess),
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("packageName", \.packageName),
				BinaryLayoutField("sourceFilePath", \.sourceFilePath),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			typeDescription: reader.read(),
			access: reader.read(),
			enclosingTypeAccess: reader.read(),
			enclosingExtensionAccess: reader.readOptional(flaggedIn: &fieldFlags) as AccessDeclaration?,
			moduleName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			packageName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			sourceFilePath: reader.readOptional(flaggedIn: &fieldFlags) as String?,
		)
		try fieldFlags.finish()
	}

	/// A declaration's type nests one level for each type that encloses it. When that is too deep, the outermost type
	/// enclosing it names it: spelling the declared type recurses as deeply as it nests.
	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		var outermostType = typeDescription
		while let enclosingType = outermostType.popNested {
			outermostType = enclosingType
		}
		writer.writeDescribed(as: outermostType.asSource) { writer in
			writer.write(typeDescription)
			writer.write(access)
			writer.write(enclosingTypeAccess)
			writer.writeOptional(enclosingExtensionAccess, flaggedIn: &fieldFlags)
			writer.writeOptional(moduleName, flaggedIn: &fieldFlags)
			writer.writeOptional(packageName, flaggedIn: &fieldFlags)
			writer.writeOptional(sourceFilePath, flaggedIn: &fieldFlags)
		}
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension MockGeneration: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.enumeration(writtenAs: Tag.self) { _ in [] }
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = switch try reader.readTag() as Tag {
		case .none: .none
		case .internal: .internal
		case .public: .public
		}
	}

	func write(to writer: inout BinaryWriter) {
		switch self {
		case .none: writer.writeTag(Tag.none)
		case .internal: writer.writeTag(Tag.internal)
		case .public: writer.writeTag(Tag.public)
		}
	}

	enum Tag: UInt8, BinaryTag {
		case none
		case `internal`
		case `public`
	}
}

extension AccessDeclaration: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("level", \.level),
				BinaryLayoutField("spellsAccessModifier", \.spellsAccessModifier),
				BinaryLayoutField("modifierRange", \.modifierRange),
				BinaryLayoutField("declarationStartLocation", \.declarationStartLocation),
				BinaryLayoutField("isExtension", \.isExtension),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			level: reader.read(),
			spellsAccessModifier: fieldFlags.next(),
			modifierRange: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.SourceRange?,
			declarationStartLocation: reader.readOptional(flaggedIn: &fieldFlags) as Dependency.DeclarationLocation?,
			isExtension: fieldFlags.next(),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(level)
		fieldFlags.append(spellsAccessModifier)
		writer.writeOptional(modifierRange, flaggedIn: &fieldFlags)
		writer.writeOptional(declarationStartLocation, flaggedIn: &fieldFlags)
		fieldFlags.append(isExtension)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
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
	static let writesFieldFlags = true

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
				BinaryLayoutField("spelledAttributes", \.spelledAttributes),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			access: reader.read(),
			isOptional: fieldFlags.next(),
			isAsync: fieldFlags.next(),
			doesThrow: fieldFlags.next(),
			hasGenericParameter: fieldFlags.next(),
			hasGenericWhereClause: fieldFlags.next(),
			arguments: reader.read(),
			spelledAttributes: reader.readOptional(flaggedIn: &fieldFlags) as String?,
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(access)
		fieldFlags.append(isOptional)
		fieldFlags.append(isAsync)
		fieldFlags.append(doesThrow)
		fieldFlags.append(hasGenericParameter)
		fieldFlags.append(hasGenericWhereClause)
		writer.write(arguments)
		writer.writeOptional(spelledAttributes, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension Initializer.Argument: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("outerLabel", \.outerLabel),
				BinaryLayoutField("innerLabel", \.innerLabel),
				BinaryLayoutField("typeDescription", \.typeDescription),
				BinaryLayoutField("defaultValueExpression", \.defaultValueExpression),
				BinaryLayoutField("defaultValueThrows", \.defaultValueThrows),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			outerLabel: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			innerLabel: reader.read(),
			typeDescription: reader.read(),
			defaultValueExpression: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			defaultValueThrows: fieldFlags.next(),
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.writeOptional(outerLabel, flaggedIn: &fieldFlags)
		writer.write(innerLabel)
		writer.write(typeDescription)
		writer.writeOptional(defaultValueExpression, flaggedIn: &fieldFlags)
		fieldFlags.append(defaultValueThrows)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension Dependency: BinarySchemaMember {
	static let writesFieldFlags = true

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
		var fieldFlags = try reader.readFieldFlags()
		// `asInstantiatedType` is derived from `property` and `source`.
		try self.init(
			property: reader.read(),
			source: reader.read(),
			declarationLocation: reader.readOptional(flaggedIn: &fieldFlags) as DeclarationLocation?,
			identifierRange: reader.readOptional(flaggedIn: &fieldFlags) as SourceRange?,
			typeAnnotationRange: reader.readOptional(flaggedIn: &fieldFlags) as SourceRange?,
			bareAttributeRange: reader.readOptional(flaggedIn: &fieldFlags) as SourceRange?,
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(property)
		writer.write(source)
		writer.writeOptional(declarationLocation, flaggedIn: &fieldFlags)
		writer.writeOptional(identifierRange, flaggedIn: &fieldFlags)
		writer.writeOptional(typeAnnotationRange, flaggedIn: &fieldFlags)
		writer.writeOptional(bareAttributeRange, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
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

extension Dependency.SourceRange: BinaryPosition {}

extension Dependency.DeclarationLocation: BinaryPosition {}

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
		self = try reader.readSharingValuesOfOneStringAndSharedValue { reader throws(BinaryDecodingError) in
			try Self(
				label: reader.read(),
				typeDescription: reader.read(),
			)
		}
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
			case .closure: [.init("arguments", [TypeDescription].self), .init("isAsync", Bool.self), .init("doesThrow", Bool.self), .init("thrownType", TypeDescription?.self), .init("returnType", TypeDescription.self)]
			case .unknown: [.init("text", String.self)]
			case .variadic: [.init(nil, TypeDescription.self)]
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

	private init(readingUnsharedFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
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
				try .closure(arguments: reader.read(), isAsync: reader.read(), doesThrow: reader.read(), thrownType: reader.read(), returnType: reader.read())
			case .unknown:
				try .unknown(text: reader.read())
			case .variadic:
				try .variadic(reader.read())
			}
		}
	}

	func write(to writer: inout BinaryWriter) {
		if writer.sharesSignatureValues {
			writer.writeSharedByBytes(self) { writeUnshared(to: &$0) }
		} else {
			writeUnshared(to: &writer)
		}
	}

	private func writeUnshared(to writer: inout BinaryWriter) {
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
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			writer.writeTag(Tag.closure)
			writer.write(arguments)
			writer.write(isAsync)
			writer.write(doesThrow)
			writer.write(thrownType)
			writer.write(returnType)
		case let .unknown(text):
			writer.writeTag(Tag.unknown)
			writer.write(text)
		case let .variadic(type):
			writer.writeTag(Tag.variadic)
			writer.write(type)
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
		case variadic
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

// MARK: - Module info files

extension ModuleInfoFile: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("ownEntryChecksum", \.ownEntryChecksum),
				BinaryLayoutField("packageName", \.packageName),
				BinaryLayoutField("dependencyModuleNames", \.dependencyModuleNames),
				BinaryLayoutField("imports", \.imports),
				BinaryLayoutField("mockImports", \.mockImports),
				BinaryLayoutField("instantiables", \.instantiables),
				BinaryLayoutField("configurations", \.configurations),
				BinaryLayoutField("filesWithUnexpectedNodes", \.filesWithUnexpectedNodes),
				BinaryLayoutField("conditionalCompilationDecisions", \.conditionalCompilationDecisions),
				BinaryLayoutField("instantiableTypeNamesInAnyClause", \.instantiableTypeNamesInAnyClause),
				BinaryLayoutField("plainTypeDeclarations", \.plainTypeDeclarations),
				BinaryLayoutField("seamSignatures", \.seamSignatures),
				BinaryLayoutField("publicMockPlans", \.publicMockPlans),
				BinaryLayoutField("view", \.view),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		let fileWithoutView = try ModuleInfoFile(readingAllButViewFrom: &reader)
		try self.init(
			moduleName: fileWithoutView.moduleName,
			ownEntryChecksum: fileWithoutView.ownEntryChecksum,
			packageName: fileWithoutView.packageName,
			dependencyModuleNames: fileWithoutView.dependencyModuleNames,
			imports: fileWithoutView.imports,
			mockImports: fileWithoutView.mockImports,
			instantiables: fileWithoutView.instantiables,
			configurations: fileWithoutView.configurations,
			filesWithUnexpectedNodes: fileWithoutView.filesWithUnexpectedNodes,
			conditionalCompilationDecisions: fileWithoutView.conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: fileWithoutView.instantiableTypeNamesInAnyClause,
			plainTypeDeclarations: fileWithoutView.plainTypeDeclarations,
			seamSignatures: fileWithoutView.seamSignatures,
			publicMockPlans: fileWithoutView.publicMockPlans,
			view: reader.read(),
		)
	}

	/// The file as far as its view, which is written last, with an empty view: a run reads its view only of the files whose
	/// modules it reads, and a file's view grows with the modules beneath the file's module.
	init(readingAllButViewFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			moduleName: reader.read(),
			ownEntryChecksum: reader.read() as UInt64?,
			packageName: reader.read() as String?,
			dependencyModuleNames: reader.read(),
			imports: reader.read(),
			mockImports: reader.read(),
			instantiables: reader.read(),
			configurations: reader.read(),
			filesWithUnexpectedNodes: reader.read() as [String]?,
			conditionalCompilationDecisions: reader.read(),
			instantiableTypeNamesInAnyClause: reader.read(),
			plainTypeDeclarations: reader.read(),
			seamSignatures: reader.read() as ModuleSeamSignatures,
			publicMockPlans: reader.read() as ModulePublicMockPlans,
			view: .empty,
		)
	}

	func write(to writer: inout BinaryWriter) {
		write(to: &writer) { writer in
			writer.write(seamSignatures)
			writer.write(publicMockPlans)
		}
	}

	/// Writes the file with `writeSeamSignatures` in place of writing `seamSignatures` and `publicMockPlans`.
	func write(to writer: inout BinaryWriter, writingSeamSignatures writeSeamSignatures: (inout BinaryWriter) -> Void) {
		writer.write(moduleName)
		writer.write(ownEntryChecksum)
		writer.write(packageName)
		writer.write(dependencyModuleNames)
		writer.write(imports)
		writer.write(mockImports)
		writer.write(instantiables)
		writer.write(configurations)
		writer.write(filesWithUnexpectedNodes)
		writer.write(conditionalCompilationDecisions)
		writer.write(instantiableTypeNamesInAnyClause)
		writer.write(plainTypeDeclarations)
		writeSeamSignatures(&writer)
		writer.write(view)
	}
}

extension ModuleSeamSignatures: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("seamTypes", \.seamTypes),
				BinaryLayoutField("encoding", \.encodingWithPositions),
			],
			// Written as `encoding`.
			unwrittenProperties: ["storage"],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(seamTypes: reader.read(), encoding: (reader.read() as BinaryEncoding).bytes)
	}

	/// Writes the seams, then the encoding of their signatures (``encoding(writingPositionsAsAbsent:)``), which shares the
	/// values a signature repeats among the module's signatures alone: a run that reads one module's decodes no other's.
	func write(to writer: inout BinaryWriter) {
		writer.write(seamTypes)
		writer.write(BinaryEncoding(bytes: encoding(writingPositionsAsAbsent: writer.writesPositionsAsAbsent)))
	}

	/// The encoding as a writer that writes positions writes it.
	private var encodingWithPositions: BinaryEncoding {
		BinaryEncoding(bytes: encoding(writingPositionsAsAbsent: false))
	}
}

extension ModuleInfoView: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleGraph", \.moduleGraph),
				BinaryLayoutField("declarations", \.declarations),
				BinaryLayoutField("references", \.references),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(moduleGraph: reader.read(), declarations: reader.read(), references: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(moduleGraph)
		writer.write(declarations)
		writer.write(references)
	}
}

extension ViewedModuleReference: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("checksum", \.checksum),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(moduleName: reader.read(), checksum: reader.read())
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(moduleName)
		writer.write(checksum)
	}
}

extension ViewedModuleIdentity: BinarySchemaMember {
	static let writesFieldFlags = true

	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("packageName", \.packageName),
				BinaryLayoutField("dependencyModuleNames", \.dependencyModuleNames),
				BinaryLayoutField("mockConditionalCompilation", \.mockConditionalCompilation),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		var fieldFlags = try reader.readFieldFlags()
		try self.init(
			moduleName: reader.read(),
			packageName: reader.readOptional(flaggedIn: &fieldFlags) as String?,
			dependencyModuleNames: reader.read(),
			mockConditionalCompilation: reader.readOptional(flaggedIn: &fieldFlags) as String?,
		)
		try fieldFlags.finish()
	}

	func write(to writer: inout BinaryWriter) {
		var fieldFlags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		writer.write(moduleName)
		writer.writeOptional(packageName, flaggedIn: &fieldFlags)
		writer.write(dependencyModuleNames)
		writer.writeOptional(mockConditionalCompilation, flaggedIn: &fieldFlags)
		writer.finishFields(fieldFlags, startingAt: fieldsStart)
	}
}

extension ViewedModule: BinarySchemaMember {
	static var binaryLayout: BinaryLayout<Self> {
		.structure(
			fields: [
				BinaryLayoutField("moduleName", \.moduleName),
				BinaryLayoutField("imports", \.imports),
				BinaryLayoutField("mockImports", \.mockImports),
				BinaryLayoutField("instantiables", \.instantiables),
				BinaryLayoutField("plainTypeDeclarations", \.plainTypeDeclarations),
				BinaryLayoutField("seamSignatures", \.seamSignatures),
				BinaryLayoutField("publicMockPlans", \.publicMockPlans),
			],
			unwrittenProperties: [],
		)
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			moduleName: reader.read(),
			imports: reader.read(),
			mockImports: reader.read(),
			instantiables: reader.read(),
			plainTypeDeclarations: reader.read(),
			seamSignatures: reader.read() as ModuleSeamSignatures,
			publicMockPlans: reader.read() as ModulePublicMockPlans,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(moduleName)
		writer.write(imports)
		writer.write(mockImports)
		writer.write(instantiables)
		writer.write(plainTypeDeclarations)
		writer.write(seamSignatures)
		writer.write(publicMockPlans)
	}
}
