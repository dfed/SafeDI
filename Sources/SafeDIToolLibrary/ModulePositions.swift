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

/// The positions of a module's own declarations, collected to rank them (`BinaryWriter.collectingPositions(_:)`).
struct CollectedPositions {
	/// Every location the module's own declarations record.
	var locations = Set<Dependency.DeclarationLocation>()
	/// The locations at which aliased dependencies are declared.
	var aliasDeclarationLocations = Set<Dependency.DeclarationLocation>()
}

/// How a module info file whose positions are stored in a positions file of their own (`--module-info-positions-in-own-file`)
/// writes them: each location ranked among the locations of its file, its line and column in `stream`, and each range in
/// `stream` alone. A dependent then reads the file without the positions file, and a line moved in the module that keeps
/// every rank changes only the positions file.
struct PositionsStoredElsewhere {
	/// Ranks `positions` by file, line and column, from 1.
	init(ranking positions: CollectedPositions) {
		var orderByLocation = [Dependency.DeclarationLocation: Int]()
		for (_, locations) in Dictionary(grouping: positions.locations, by: \.filePath) {
			for (index, location) in locations.sorted().enumerated() {
				orderByLocation[location] = index + 1
			}
		}
		self.orderByLocation = orderByLocation
		aliasDeclarationLocations = positions.aliasDeclarationLocations
	}

	/// The lines and columns written so far, in the order the file writes the locations and ranges they belong to, each
	/// a point (`PositionCoding`): a location's from the line of the location or range before it, a range's start from
	/// the same, and its end from its start, so a point on the line it is measured from takes one value.
	private(set) var stream = [UInt64]()

	/// Appends a location's line and column.
	mutating func append(line: Int, column: Int) {
		PositionCoding.append(line: line, column: column, from: previousLine, to: &stream)
		previousLine = line
	}

	/// Appends a range's start and end.
	mutating func append(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
		PositionCoding.append(line: startLine, column: startColumn, from: previousLine, to: &stream)
		PositionCoding.append(line: endLine, column: endColumn, from: startLine, to: &stream)
		previousLine = startLine
	}

	private var previousLine = 0

	/// `location` ranked, with its line and column where it is an aliased dependency's declaration, or `nil` where
	/// it was not collected.
	func ranked(_ location: Dependency.DeclarationLocation) -> Dependency.DeclarationLocation? {
		orderByLocation[location].map { order in
			Dependency.DeclarationLocation(
				filePath: location.filePath,
				order: order,
				placement: aliasDeclarationLocations.contains(location) ? location.placement : .storedElsewhere,
			)
		}
	}

	private let orderByLocation: [Dependency.DeclarationLocation: Int]
	private let aliasDeclarationLocations: Set<Dependency.DeclarationLocation>
}

/// The lines and columns of a positions file, read in order as a module info file reads what it stores elsewhere.
struct ReattachedPositions {
	init(_ values: [UInt64]) {
		self.values = values
	}

	/// Whether the positions file holds no value.
	var isEmpty: Bool {
		values.isEmpty
	}

	/// Whether every value was read.
	var isExhausted: Bool {
		index == values.count
	}

	/// Whether a location or range was asked for after the values ended, which a positions file that holds fewer lines
	/// and columns than its module info file stores elsewhere leads to.
	private(set) var endedEarly = false

	/// The line and column of the next location, or a placeholder once the values have ended (``endedEarly``).
	mutating func nextLocation() -> Dependency.DeclarationLocation.Placement {
		let (line, column) = nextPoint(from: previousLine)
		previousLine = line
		return .here(line: line, column: column)
	}

	/// The next range, or a placeholder once the values have ended (``endedEarly``).
	mutating func nextRange() -> Dependency.SourceRange {
		let (startLine, startColumn) = nextPoint(from: previousLine)
		let (endLine, endColumn) = nextPoint(from: startLine)
		previousLine = startLine
		return Dependency.SourceRange(placement: .here(startLine: startLine, startColumn: startColumn, endLine: endLine, endColumn: endColumn))
	}

	/// The next point, as `PositionCoding.append(line:column:from:to:)` writes it.
	private mutating func nextPoint(from previousLine: Int) -> (line: Int, column: Int) {
		let columnAndMove = next()
		let column = Int(truncatingIfNeeded: columnAndMove >> 1)
		guard columnAndMove & 1 == 1 else {
			return (previousLine, column)
		}
		let move = next()
		let difference = Int(truncatingIfNeeded: move >> 1) ^ -Int(truncatingIfNeeded: move & 1)
		return (previousLine &+ difference, column)
	}

	/// The next value, or 0 once the values have ended, which marks the read ``endedEarly``.
	private mutating func next() -> UInt64 {
		endedEarly = endedEarly || index == values.count
		index = min(index + 1, values.count)
		return endedEarly ? 0 : values[index - 1]
	}

	private let values: [UInt64]
	private var index = 0
	private var previousLine = 0
}

/// How a positions file writes a point, a line and a column, measured from a line before it: the column shifted left
/// once, its low bit set when the line differs, and then, only where it does, the difference, zigzag encoded. Every
/// value is unsigned, so a column below 64 and a line beside the one before it take a byte each.
enum PositionCoding {
	static func append(line: Int, column: Int, from previousLine: Int, to stream: inout [UInt64]) {
		let move = line &- previousLine
		let columnBits = UInt64(truncatingIfNeeded: column) &<< 1
		guard move != 0 else {
			stream.append(columnBits)
			return
		}
		stream.append(columnBits | 1)
		stream.append(UInt64(truncatingIfNeeded: (move &<< 1) ^ (move >> (Int.bitWidth - 1))))
	}
}

/// The lines and columns a module info file stores elsewhere (`--module-info-positions-in-own-file`), with the checksum of
/// the module info file they belong to, which that file's header carries: its magic, then that checksum, then the count
/// of values and each value, as a ``BinaryWriter`` writes them.
struct ModulePositionsFile: Equatable {
	init(moduleInfoChecksum: UInt64, values: [UInt64]) {
		self.moduleInfoChecksum = moduleInfoChecksum
		self.values = values
	}

	/// Reads the positions file `data` holds.
	/// - Throws: When `data` is not a positions file.
	init(data: Data) throws(BinaryFileReadError) {
		let headerLength = Self.magic.count + 8
		guard data.count >= headerLength, data.prefix(Self.magic.count).elementsEqual(Self.magic) else {
			throw BinaryFileReadError(kind: .modulePositions, reason: .wrongKind)
		}
		moduleInfoChecksum = data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: Self.magic.count, as: UInt64.self)) }
		let result = data.dropFirst(headerLength).withUnsafeBytes { bytes in
			Result { () throws(BinaryDecodingError) -> [UInt64] in
				var reader = try BinaryReader(bytes: bytes)
				let values: [UInt64] = try reader.read()
				try reader.finish()
				return values
			}
		}
		do throws(BinaryDecodingError) {
			values = try result.get()
		} catch {
			throw BinaryFileReadError(kind: .modulePositions, reason: .malformedBody(error))
		}
	}

	/// The checksum the header of the module info file the positions belong to carries.
	let moduleInfoChecksum: UInt64
	/// Each point, as `PositionCoding` writes it, in the order the module info file stores them elsewhere.
	let values: [UInt64]

	var data: Data {
		var writer = BinaryWriter()
		writer.write(values)
		var data = Data(Self.magic)
		withUnsafeBytes(of: moduleInfoChecksum.littleEndian) { data.append(contentsOf: $0) }
		data.append(contentsOf: writer.encoded)
		return data
	}

	private static let magic = BinaryFile.Kind.modulePositions.magic
}

extension ModuleInfoFile {
	/// The path of the positions file beside the module info file at `moduleInfoPath`.
	static func positionsFilePath(ofModuleInfoAt moduleInfoPath: String) -> String {
		moduleInfoPath + "positions"
	}

	/// This module as a module info file, as `moduleInfoDataWritingSeamSignaturesWithoutPositions` writes it, but with the
	/// line and column of every position but an aliased dependency's in a positions file of its own: a line moved in the
	/// module then changes only the positions file, which a dependent opens only to report a diagnostic.
	var moduleInfoDataStoringPositionsElsewhere: (moduleInfo: Data, positions: Data) {
		get throws(BinaryFileWriteError) {
			let collected = BinaryWriter.collectingPositions { writer in
				writeFieldsBeforeSeamSignatures(to: &writer)
			}
			var positions = PositionsStoredElsewhere(ranking: collected)
			let moduleInfo = try BinaryFile.data(.moduleInfo) { writer in
				writer.positionsStoredElsewhere = positions
				write(to: &writer) { writer in
					writer.writingPositionsAsAbsent { writer in
						writer.write(seamSignatures)
						writer.write(publicMockPlans)
					}
				}
				positions = writer.positionsStoredElsewhere ?? positions
			}
			let positionsFile = ModulePositionsFile(
				moduleInfoChecksum: BinaryFile.recordedBodyChecksum(of: moduleInfo) ?? 0,
				values: positions.stream,
			)
			return (moduleInfo, positionsFile.data)
		}
	}

	/// The module info file `data` holds, with the positions it stores elsewhere read from `positionsData`, the positions
	/// file beside it, where `reattachesPositions`.
	/// - Parameter readingView: Whether to read the file's view, which `false` leaves empty.
	/// - Returns: The file, and how its positions were read.
	/// - Throws: When `data` is not a module info file. A positions file that does not pair with it is no error here:
	///   the file is read with those positions stored elsewhere, and the read says why.
	static func reading(
		moduleInfoData data: Data,
		readingView: Bool,
		positionsData: Data?,
		reattachesPositions: Bool,
	) throws(BinaryFileReadError) -> (file: ModuleInfoFile, positions: PositionsRead) {
		var unpairedReason: PositionsRead.UnpairedReason?
		var reattached: ReattachedPositions?
		if reattachesPositions {
			if let positionsData {
				do {
					let positions = try ModulePositionsFile(data: positionsData)
					if positions.moduleInfoChecksum == BinaryFile.recordedBodyChecksum(of: data) {
						reattached = ReattachedPositions(positions.values)
					} else {
						unpairedReason = .belongsToAnotherModuleInfoFile
					}
				} catch {
					unpairedReason = .unreadable("\(error)")
				}
			} else {
				unpairedReason = .missing
			}
		}
		var read = try reading(moduleInfoData: data, readingView: readingView, reattaching: reattached, collectsStoredElsewhereFilePaths: reattachesPositions)
		// Positions that end early fill the locations after them with placeholders, and positions left over say the
		// file does not pair with this one either: read the file again without them.
		if let reattached = read.reattached, reattached.endedEarly || !reattached.isExhausted {
			unpairedReason = reattached.endedEarly ? .holdsTooFewPositions : .holdsTooManyPositions
			read = try reading(moduleInfoData: data, readingView: readingView, reattaching: nil, collectsStoredElsewhereFilePaths: true)
		}
		let positions: PositionsRead = if !read.readsPositionStoredElsewhere, reattached?.isEmpty != false {
			.notStoredElsewhere
		} else if !reattachesPositions {
			.storedElsewhere
		} else if let unpairedReason {
			.unpaired(unpairedReason, storedElsewhereFilePaths: read.storedElsewhereFilePaths ?? [])
		} else {
			.reattached
		}
		return (read.file, positions)
	}

	private static func reading(
		moduleInfoData data: Data,
		readingView: Bool,
		reattaching reattached: ReattachedPositions?,
		collectsStoredElsewhereFilePaths: Bool,
	) throws(BinaryFileReadError) -> (file: ModuleInfoFile, readsPositionStoredElsewhere: Bool, reattached: ReattachedPositions?, storedElsewhereFilePaths: Set<String>?) {
		try BinaryFile.value(.moduleInfo, from: data) { (reader: inout BinaryReader) throws(BinaryDecodingError) in
			reader.reattachedPositions = reattached
			reader.storedElsewhereFilePaths = collectsStoredElsewhereFilePaths && reattached == nil ? [] : nil
			let file = try readingView ? ModuleInfoFile(readingFrom: &reader) : ModuleInfoFile(readingAllButViewFrom: &reader)
			if readingView {
				try reader.finish()
			}
			return (file, reader.readsPositionStoredElsewhere, reader.reattachedPositions, reader.storedElsewhereFilePaths)
		}
	}
}

/// How a run read the positions a module info file stores elsewhere.
enum PositionsRead: Equatable, Sendable {
	/// The file stores no position elsewhere.
	case notStoredElsewhere
	/// The run did not read the file's positions file, so its positions are stored elsewhere.
	case storedElsewhere
	/// The run read every position from the file's positions file.
	case reattached
	/// The run could not read the file's positions from its positions file, for the reason given, so the locations it
	/// read in the files at `storedElsewhereFilePaths` have no line and column.
	case unpaired(UnpairedReason, storedElsewhereFilePaths: Set<String>)

	enum UnpairedReason: Equatable, Sendable {
		case missing
		case unreadable(String)
		case belongsToAnotherModuleInfoFile
		case holdsTooFewPositions
		case holdsTooManyPositions

		var sentence: String {
			switch self {
			case .missing:
				"no positions file exists at that path."
			case let .unreadable(reason):
				"the positions file cannot be read. \(reason)"
			case .belongsToAnotherModuleInfoFile:
				"the positions file was written beside another version of the module info file."
			case .holdsTooFewPositions:
				"the positions file holds fewer lines and columns than the module info file stores in it."
			case .holdsTooManyPositions:
				"the positions file holds more lines and columns than the module info file stores in it."
			}
		}
	}
}

/// What one run of `generate` read of the positions files beside the module info files it read: whether it reattached
/// them, which it opened, and which did not pair with their module info file.
actor ModulePositionsReading {
	init(reattachesPositions: Bool) {
		self.reattachesPositions = reattachesPositions
	}

	/// Whether the run reads each module info file's positions file.
	nonisolated let reattachesPositions: Bool

	/// The run's reading, which a module info file's read records itself in.
	@TaskLocal static var current: ModulePositionsReading?

	/// Whether some module info file the run read stores positions elsewhere.
	private(set) var readsPositionStoredElsewhere = false
	/// The paths of the positions files the run opened.
	private(set) var openedPositionsFilePaths = Set<String>()

	/// Records the read of the module info file at `moduleInfoPath`.
	func record(_ read: PositionsRead, ofModuleInfoAt moduleInfoPath: String, openedPositionsFile: Bool) {
		if openedPositionsFile {
			openedPositionsFilePaths.insert(ModuleInfoFile.positionsFilePath(ofModuleInfoAt: moduleInfoPath))
		}
		switch read {
		case .notStoredElsewhere:
			break
		case .storedElsewhere, .reattached:
			readsPositionStoredElsewhere = true
		case let .unpaired(reason, storedElsewhereFilePaths):
			readsPositionStoredElsewhere = true
			unpairedByModuleInfoPath[moduleInfoPath] = (reason, storedElsewhereFilePaths)
		}
	}

	/// `diagnostics` followed by an error for each module info file whose positions file does not pair with it and that
	/// left out a position one of them prints, or `nil` when none did: a module whose positions did not pair, but whose
	/// files no diagnostic is located in, changes nothing the run reports.
	func pairingError(after diagnostics: [SourceDiagnostic]) -> ModulePositionsPairingError? {
		let filePathsLackingPositions = Set(diagnostics.lazy.filter(\.printsPositionStoredElsewhere).compactMap(\.location?.filePath))
		let unpairedModuleInfoPaths = unpairedByModuleInfoPath.keys.sorted().filter { moduleInfoPath in
			unpairedByModuleInfoPath[moduleInfoPath].map { !$0.storedElsewhereFilePaths.isDisjoint(with: filePathsLackingPositions) } ?? false
		}
		guard !unpairedModuleInfoPaths.isEmpty else { return nil }
		return ModulePositionsPairingError(sourceDiagnostics: diagnostics + unpairedModuleInfoPaths.compactMap { moduleInfoPath in
			unpairedByModuleInfoPath[moduleInfoPath].map { reason, _ in
				SourceDiagnostic(
					severity: .error,
					location: nil,
					message: "SafeDI could not read the positions of the module info file at \(moduleInfoPath) from \(ModuleInfoFile.positionsFilePath(ofModuleInfoAt: moduleInfoPath)): \(reason.sentence) The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.",
				)
			}
		})
	}

	private var unpairedByModuleInfoPath = [String: (reason: PositionsRead.UnpairedReason, storedElsewhereFilePaths: Set<String>)]()
}

/// A run's diagnostics, followed by an error for each module info file whose positions file does not pair with it.
struct ModulePositionsPairingError: SourceLocatedError {
	let sourceDiagnostics: [SourceDiagnostic]
}
