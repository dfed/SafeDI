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

import Foundation
import SafeDICore

/// Gives the diagnostics a run reports about another module's declarations the lines and columns that module's `.safedi`
/// file leaves out, when it reports them: each location there is its file and its rank among the locations the module
/// recorded in that file, and each range the part of the declaration it spans (`LocationRanks`,
/// `Dependency.SourceRange.Span.unlocated(owner:part:)`). The locator reads the file again, walks it under this run's
/// conditions, collects exactly the locations a module info file ranks in it, and, where it finds as many as the `.safedi`
/// file recorded there, maps each rank to its line and column and each part to its range. Where the file cannot be read,
/// or holds another number of locations, the diagnostic keeps its file and message and prints no fix-it.
///
/// It reads each file at most once per run, and only for a diagnostic that prints a location or a fix-it the `.safedi`
/// file left without its line (`SourceDiagnostic.printsUnlocatedPosition`), so a run that reports none reads nothing more.
/// It holds what it found of each file it read until the run's diagnostics are located.
struct DiagnosticLocator {
	/// What a run read that the locator needs: the module info files whose declarations its diagnostics can name, the
	/// conditions it walks files under, and its own input files, under whose resolved root another module's file can open.
	struct Inputs: Sendable {
		let moduleInfoFiles: [ModuleInfoFile]
		let evaluator: ConditionalCompilationEvaluator
		let inputFilePaths: Set<String>
	}

	init(inputs: Inputs?) {
		self.inputs = inputs
	}

	/// `diagnostics`, each location and fix-it range read from a `.safedi` file located where its file can be read again.
	mutating func locating(_ diagnostics: [SourceDiagnostic]) -> [SourceDiagnostic] {
		diagnostics.map { locating($0) }
	}

	/// `error`, its diagnostics located as ``locating(_:)-([SourceDiagnostic])`` locates them, where it is a
	/// `SourceLocatedError` with something to locate.
	mutating func locating(_ error: any Error) -> any Error {
		guard let sourceLocatedError = error as? any SourceLocatedError,
		      sourceLocatedError.sourceDiagnostics.contains(where: \.printsUnlocatedPosition)
		else { return error }
		return LocatedDiagnosticsError(underlyingError: sourceLocatedError, sourceDiagnostics: locating(sourceLocatedError.sourceDiagnostics))
	}

	// MARK: Private

	private let inputs: Inputs?
	/// What the locator found of each file it read, by the path the `.safedi` file records: `nil` where it could not
	/// locate the file's declarations.
	private var locatedFileByRecordedPath = [String: LocatedFile?]()
	/// The directories the run's input files resolve under, once one is needed (``resolvedInputRoots()``).
	private var inputRoots: [String]?

	private mutating func locating(_ diagnostic: SourceDiagnostic) -> SourceDiagnostic {
		guard diagnostic.printsUnlocatedPosition else { return diagnostic }
		return SourceDiagnostic(
			severity: diagnostic.severity,
			location: diagnostic.location.map { locating($0) },
			message: diagnostic.message,
			fixIts: diagnostic.fixIts.map { SourceDiagnostic.FixIt(range: locating($0.range), replacement: $0.replacement) },
		)
	}

	private mutating func locating(_ location: Dependency.DeclarationLocation) -> Dependency.DeclarationLocation {
		guard location.position == nil,
		      let position = locatedFile(recordedAt: location.filePath)?.position(ofRank: location.order)
		else { return location }
		return Dependency.DeclarationLocation(filePath: location.filePath, line: position.line, column: position.column)
	}

	/// A fix-it's range of a diagnostic that `printsUnlocatedPosition` is unlocated: every fix-it takes its range from the
	/// record its diagnostic takes its location from (`PublicMockGeneration.narrowerEnclosingType`,
	/// `SeamAccessExplanation.declarationNotes`, `InaccessibleConstruction.sourceDiagnostic`,
	/// `UnfulfillableProperty.sourceDiagnostics`), a declaration read from a `.safedi` file has neither a position nor a
	/// located range, and one read from the run's own files has both. So a range that is located, or that its file no
	/// longer locates, is kept as it is.
	private mutating func locating(_ range: Dependency.SourceRange) -> Dependency.SourceRange {
		guard case let .unlocated(owner, part) = range.span,
		      let locatedRange = locatedFile(recordedAt: owner.filePath)?.range(of: part, ofDeclarationRanked: owner.order)
		else { return range }
		return locatedRange
	}

	private mutating func locatedFile(recordedAt recordedPath: String) -> LocatedFile? {
		if let locatedFile = locatedFileByRecordedPath[recordedPath] {
			return locatedFile
		} else {
			let locatedFile = locatingFile(recordedAt: recordedPath)
			locatedFileByRecordedPath[recordedPath] = .some(locatedFile)
			return locatedFile
		}
	}

	/// Reads the file at `recordedPath` again, or under the root of an input where it is relative and cannot be read
	/// there, and locates its declarations, where the first module info file that records locations there records as
	/// many as the file holds.
	private mutating func locatingFile(recordedAt recordedPath: String) -> LocatedFile? {
		guard let inputs,
		      let moduleInfoFile = inputs.moduleInfoFiles.first(where: { $0.locationCountsByFilePath[recordedPath] != nil }),
		      let locationCount = moduleInfoFile.locationCountsByFilePath[recordedPath]
		else { return nil }
		DiagnosticLocatorObservation.fileReadObserver?(recordedPath)
		guard let fileScan = scan(ofFileRecordedAt: recordedPath, inputs: inputs) else { return nil }
		// The module's run kept the plain type declarations whose outermost type has a name the whole module mentions, and,
		// where it wrote its `.safedi` without a target graph, every `package` one too
		// (`FileScan.keepingPlainTypeDeclarations`). A name it kept whole shows as a declaration recorded here that is not
		// `package`; of any other recorded name the file holds only `package` declarations, or the run kept only those.
		var recordedOutermostNames = Set<String?>()
		var outermostNamesKeptWhole = Set<String?>()
		for declaration in moduleInfoFile.plainTypeDeclarations where declaration.access.declarationStartLocation?.filePath == recordedPath {
			let outermostName = declaration.typeDescription.outermostTypeName?.spelledWithoutBackticks
			recordedOutermostNames.insert(outermostName)
			if AccessLevel.normalized(declaration.levelBeforeExtendedTypeCap) != .package {
				outermostNamesKeptWhole.insert(outermostName)
			}
		}
		let plainTypeDeclarations = fileScan.plainTypeDeclarations.filter { declaration in
			let outermostName = declaration.typeDescription.outermostTypeName?.spelledWithoutBackticks
			return outermostNamesKeptWhole.contains(outermostName)
				|| (recordedOutermostNames.contains(outermostName) && AccessLevel.normalized(declaration.levelBeforeExtendedTypeCap) == .package)
		}
		let entry = ModuleInfoFile(
			moduleName: moduleInfoFile.moduleName,
			packageName: nil,
			dependencyModuleNames: [],
			imports: [],
			mockImports: [],
			instantiables: fileScan.instantiables,
			configurations: fileScan.configurations.map(\.asHeldByModuleInfoFile),
			filesWithUnexpectedNodes: nil,
			conditionalCompilationDecisions: [],
			instantiableTypeNamesInAnyClause: [],
			plainTypeDeclarations: plainTypeDeclarations,
			seamSignatures: .empty,
			view: .empty,
		)
		// The locations a module info file ranks, as `ModuleInfoFile.moduleInfoData` collects them.
		let locations = BinaryWriter.collectingLocations { writer in
			entry.writeFieldsBeforeSeamSignatures(to: &writer)
		}
		let positions = locations.compactMap(\.position).sorted()
		guard positions.count == locationCount else { return nil }
		// Read once as a module info file writes it and once with lines and columns, the entry's ranges come in the same
		// order: each part of a ranked declaration beside its range.
		let ranks = LocationRanks(ranking: locations)
		var rangeByPart = [DeclarationPart: Dependency.SourceRange]()
		for (rankedRange, locatedRange) in zip(Self.rangesRead(of: entry, writtenWith: ranks), Self.rangesRead(of: entry, writtenWith: nil)) {
			if case let .unlocated(owner, part) = rankedRange.span {
				rangeByPart[DeclarationPart(rank: owner.order, part: part)] = locatedRange
			}
		}
		return LocatedFile(positions: positions, rangeByPart: rangeByPart)
	}

	private mutating func scan(ofFileRecordedAt recordedPath: String, inputs: Inputs) -> FileScan? {
		if let fileScan = scanOfFile(readFrom: recordedPath, namedAs: recordedPath, conditionalCompilation: inputs.evaluator) {
			return fileScan
		} else {
			guard !recordedPath.hasPrefix("/") else { return nil }
			return resolvedInputRoots(of: inputs).lazy
				.compactMap { root in scanOfFile(readFrom: root + "/" + recordedPath, namedAs: recordedPath, conditionalCompilation: inputs.evaluator) }
				.first
		}
	}

	/// See ``resolvedRoots(of:)``, computed once a diagnostic needs them.
	private mutating func resolvedInputRoots(of inputs: Inputs) -> [String] {
		if let inputRoots {
			return inputRoots
		} else {
			let roots = Self.resolvedRoots(of: inputs.inputFilePaths)
			inputRoots = roots
			return roots
		}
	}

	/// Whether `recordedPath`, a path a `.safedi` file records relative to the run that wrote it, can be read under one of
	/// the directories the run's input files resolve under, where the locator reads it when it cannot be read where it
	/// is: the run's access check then reports a diagnostic at the declaration it names, which the locator locates.
	static func isReadable(underResolvedRootOfAnyOf inputFilePaths: Set<String>, recordedPath: String) -> Bool {
		guard !recordedPath.hasPrefix("/") else { return false }
		return resolvedRoots(of: inputFilePaths).contains { root in FileManager.default.isReadableFile(atPath: root + "/" + recordedPath) }
	}

	/// The distinct directories the run's input files resolve under (`resolvedRoot(ofRelativePath:)`), in the order of the
	/// files' paths.
	private static func resolvedRoots(of inputFilePaths: Set<String>) -> [String] {
		var roots = [String]()
		for root in inputFilePaths.sorted().compactMap(resolvedRoot(ofRelativePath:)) where !roots.contains(root) {
			roots.append(root)
		}
		return roots
	}

	/// Every range `entry` holds, in the order a read of the bytes `ranks` writes finds them.
	private static func rangesRead(of entry: ModuleInfoFile, writtenWith ranks: LocationRanks?) -> [Dependency.SourceRange] {
		var writer = BinaryWriter()
		writer.locationRanks = ranks
		entry.write(to: &writer)
		let bytes = writer.encoded
		// The bytes were written by this entry's own coders, so they read back.
		return bytes.withUnsafeBytes { bytes in (try? rangesRead(from: bytes)) ?? [] }
	}

	private static func rangesRead(from bytes: UnsafeRawBufferPointer) throws(BinaryDecodingError) -> [Dependency.SourceRange] {
		var reader = try BinaryReader(bytes: bytes)
		reader.rangesRead = []
		_ = try ModuleInfoFile(readingFrom: &reader)
		return reader.rangesRead ?? []
	}

	/// A part of the declaration ranked `rank` in its file.
	private struct DeclarationPart: Hashable {
		let rank: Int
		let part: Dependency.SourceRange.Part
	}

	/// What the locator found of a file whose locations it could locate.
	private struct LocatedFile {
		/// The position of each location the file ranks, by rank, from 1.
		let positions: [Dependency.DeclarationLocation.Position]
		let rangeByPart: [DeclarationPart: Dependency.SourceRange]

		func position(ofRank rank: Int) -> Dependency.DeclarationLocation.Position? {
			positions.indices.contains(rank - 1) ? positions[rank - 1] : nil
		}

		func range(of part: Dependency.SourceRange.Part, ofDeclarationRanked rank: Int) -> Dependency.SourceRange? {
			switch part {
			case .insertionPoint:
				position(ofRank: rank).map { Dependency.SourceRange(startLine: $0.line, startColumn: $0.column, endLine: $0.line, endColumn: $0.column) }
			case .identifier, .typeAnnotation, .bareAttribute, .accessModifier, .mockGenerationArgument:
				rangeByPart[DeclarationPart(rank: rank, part: part)]
			}
		}
	}
}

/// An error whose diagnostics `DiagnosticLocator` located, which prints them in place of the error it wraps.
struct LocatedDiagnosticsError: SourceLocatedError {
	let underlyingError: any SourceLocatedError
	let sourceDiagnostics: [SourceDiagnostic]
}

/// What the tests observe of `DiagnosticLocator`.
public enum DiagnosticLocatorObservation {
	/// Called with the path a `.safedi` file records of each file the locator reads again, when set: by the tests, never
	/// by the tool.
	@TaskLocal public static var fileReadObserver: (@Sendable (String) -> Void)?
}
