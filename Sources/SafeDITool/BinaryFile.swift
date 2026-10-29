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

/// A file SafeDITool writes in its binary format: the cache `scan` writes for `generate`, or the `.safedi`
/// module info file `generate --module-info-output` writes for the modules that depend on this one.
///
/// The file is a fixed-size header followed by a body in SafeDITool's binary format (see ``BinaryCodable``).
/// All of the header's integers are little-endian:
///
/// | Offset | Size | Field |
/// | ------ | ---- | ----- |
/// | 0 | 4 | The kind's ``Kind/magic``: `SDSC` for a scan cache, `SDMI` for module info |
/// | 4 | 2 | ``formatVersion`` |
/// | 6 | 8 | ``schemaFingerprint`` |
/// | 14 | 8 | The body's length in bytes |
/// | 22 | 8 | The body's ``checksum(of:)`` |
/// | 30 | | The body: a string table, then one ``CachedScannedModuleInfo`` or ``ModuleInfo`` |
///
/// A file that fails any check is not read. A scan cache that cannot be read makes `generate` parse the
/// module afresh, so a cache written by a SafeDITool whose stored types write other fields, fields of other
/// types, or fields in another order (see ``BinarySchemaMember``), cut short by an interrupted write, or
/// corrupted on disk costs a parse, never a wrong result. Module info that cannot be read fails the build
/// with the reason, because nothing else describes the module that wrote it. A value that nests more deeply
/// than a ``BinaryReader`` reads is never written, so every file SafeDITool writes, it can read.
enum BinaryFile {
	/// What a file holds.
	enum Kind: Equatable {
		/// The cache `scan` writes for `generate`, which holds a ``CachedScannedModuleInfo``.
		case scanCache
		/// The `.safedi` file `generate` writes for dependent modules, which holds a ``ModuleInfo``.
		case moduleInfo

		/// The bytes that begin every file of this kind.
		var magic: [UInt8] {
			switch self {
			case .scanCache:
				Array("SDSC".utf8)
			case .moduleInfo:
				Array("SDMI".utf8)
			}
		}

		/// The kind's name in a sentence.
		var name: String {
			switch self {
			case .scanCache:
				"scan cache"
			case .moduleInfo:
				"module info file"
			}
		}

		/// The kind's ``magic`` in a sentence.
		var magicDescription: String {
			"`\(String(decoding: magic, as: UTF8.self))`"
		}
	}

	/// Why SafeDITool most likely cannot read a file meant to be one it writes, and how to fix that. It
	/// follows the reason the file could not be read.
	static let unreadableFileExplanation = "A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it."

	/// The version of the layout of the header and of the primitives in ``BinaryCodable``. Changes to how a
	/// stored type is laid out change ``schemaFingerprint`` instead.
	static let formatVersion: UInt16 = 1

	/// Every struct and enum a file holds.
	static var schemaMembers: [any BinarySchemaMember.Type] {
		[
			CachedScannedModuleInfo.self,
			AdditionalDirectory.self,
			ScannedInput.self,
			FileModificationStamp.self,
			CachedFileScan.self,
			FileScan.self,
			OutputFileDeclarations.self,
			ModuleInfo.self,
			ImportStatement.self,
			FileVisitor.ImportSegment.self,
			ConditionalCompilationDecision.self,
			SafeDIConfiguration.self,
			Instantiable.self,
			Instantiable.DeclarationType.self,
			Initializer.self,
			Initializer.Argument.self,
			Dependency.self,
			Dependency.Source.self,
			Dependency.SourceRange.self,
			Dependency.DeclarationLocation.self,
			Property.self,
			TypeDescription.self,
			TypeDescription.VoidSpelling.self,
			TypeDescription.TupleElement.self,
			UnorderedEquatingCollection<TypeDescription>.self,
		]
	}

	/// A fingerprint of the layout of every type in ``schemaMembers``, so that a file written by a SafeDITool
	/// whose stored types are written differently is never read, even when both report the same version.
	static let schemaFingerprint = Array(schemaDescription.utf8).withUnsafeBytes(checksum(of:))

	/// The format version and every schema member's layout, one member per line: the name and type of each
	/// field a struct writes, and the name and payload types of each case an enum writes, in the order written.
	static var schemaDescription: String {
		(["\(formatVersion)"] + schemaMembers.map { member in
			"\(String(reflecting: member)): \(member.binaryLayoutDescription)"
		}).joined(separator: "\n")
	}

	/// A file of `kind` that holds `value`.
	/// - Throws: When `value` holds an instantiable whose declaration names a type that nests more deeply than a
	///   ``BinaryReader`` reads.
	static func data(_ kind: Kind, holding value: some BinaryCodable) throws(BinaryFileWriteError) -> Data {
		var writer = BinaryWriter()
		writer.write(value)
		if let valueNestedTooDeeply = writer.valueNestedTooDeeply {
			throw BinaryFileWriteError(kind: kind, instantiableNestedTooDeeply: valueNestedTooDeeply)
		} else {
			return data(kind, body: writer.encoded)
		}
	}

	/// A file of `kind` that holds `body`, a value ``BinaryWriter/encoded`` produced.
	static func data(_ kind: Kind, body: [UInt8]) -> Data {
		var data = Data(capacity: headerLength + body.count)
		data.append(contentsOf: kind.magic)
		append(formatVersion, to: &data)
		append(schemaFingerprint, to: &data)
		append(UInt64(body.count), to: &data)
		append(body.withUnsafeBytes(checksum(of:)), to: &data)
		data.append(contentsOf: body)
		return data
	}

	/// The value a file of `kind` holds.
	static func value<Value: BinaryCodable>(_ kind: Kind, from data: Data) throws(BinaryFileReadError) -> Value {
		let result = data.withUnsafeBytes { bytes in
			Result { () throws(BinaryFileReadError.Reason) in
				try value(from: bytes, magic: kind.magic) as Value
			}
		}
		do throws(BinaryFileReadError.Reason) {
			return try result.get()
		} catch {
			throw BinaryFileReadError(kind: kind, reason: error)
		}
	}

	/// Whether `data` begins as a file of `kind` does.
	static func data(_ data: Data, beginsAs kind: Kind) -> Bool {
		data.prefix(kind.magic.count).elementsEqual(kind.magic)
	}

	/// A checksum of `bytes`: a single lane of xxHash64's rounds, which consumes eight bytes at a time.
	/// Each round is a bijection of the running value, so a change confined to any one eight-byte word
	/// always changes the checksum.
	static func checksum(of bytes: UnsafeRawBufferPointer) -> UInt64 {
		let prime1: UInt64 = 0x9E3779B185EBCA87
		let prime2: UInt64 = 0xC2B2AE3D27D4EB4F
		func round(_ checksum: UInt64, _ word: UInt64) -> UInt64 {
			let accumulated = checksum &+ word &* prime2
			return ((accumulated << 31) | (accumulated >> 33)) &* prime1
		}
		var checksum: UInt64 = 0x27D4EB2F165667C5
		var offset = 0
		while offset + 8 <= bytes.count {
			checksum = round(checksum, UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
			offset += 8
		}
		var lastWord: UInt64 = 0
		for (index, byte) in bytes[offset...].enumerated() {
			lastWord |= UInt64(byte) << (8 * UInt64(index))
		}
		return round(checksum, lastWord)
	}

	// MARK: Private

	private static let headerLength = 30

	private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
		withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
	}

	private static func value<Value: BinaryCodable>(from bytes: UnsafeRawBufferPointer, magic: [UInt8]) throws(BinaryFileReadError.Reason) -> Value {
		func integer<Integer: FixedWidthInteger>(at offset: Int) -> Integer {
			Integer(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Integer.self))
		}
		guard bytes.count >= headerLength else {
			throw .shorterThanHeader(byteCount: bytes.count)
		}
		guard bytes.prefix(magic.count).elementsEqual(magic) else {
			throw .wrongKind
		}
		let formatVersion: UInt16 = integer(at: 4)
		guard formatVersion == Self.formatVersion else {
			throw .formatVersionMismatch(found: formatVersion, expected: Self.formatVersion)
		}
		let schemaFingerprint: UInt64 = integer(at: 6)
		guard schemaFingerprint == Self.schemaFingerprint else {
			throw .schemaFingerprintMismatch(found: schemaFingerprint, expected: Self.schemaFingerprint)
		}
		let body = UnsafeRawBufferPointer(rebasing: bytes[headerLength...])
		let bodyLength: UInt64 = integer(at: 14)
		guard bodyLength == UInt64(body.count) else {
			throw .bodyLengthMismatch(recorded: bodyLength, actual: body.count)
		}
		guard integer(at: 22) == checksum(of: body) else {
			throw .checksumMismatch
		}
		do throws(BinaryDecodingError) {
			var reader = try BinaryReader(bytes: body)
			let value: Value = try reader.read()
			try reader.finish()
			return value
		} catch {
			throw .malformedBody(error)
		}
	}
}

/// Why a file could not be read as a ``BinaryFile`` of the kind expected.
struct BinaryFileReadError: Error, Equatable, CustomStringConvertible {
	enum Reason: Error, Equatable {
		case shorterThanHeader(byteCount: Int)
		case wrongKind
		case formatVersionMismatch(found: UInt16, expected: UInt16)
		case schemaFingerprintMismatch(found: UInt64, expected: UInt64)
		case bodyLengthMismatch(recorded: UInt64, actual: Int)
		case checksumMismatch
		case malformedBody(BinaryDecodingError)
	}

	let kind: BinaryFile.Kind
	let reason: Reason

	var description: String {
		let name = kind.name
		return switch reason {
		case let .shorterThanHeader(byteCount):
			"The file is \(byteCount) bytes long, shorter than a \(name)’s header."
		case .wrongKind:
			"The file is not a \(name): it does not begin with \(kind.magicDescription)."
		case let .formatVersionMismatch(found, expected):
			"The \(name) is in format version \(found), but this SafeDITool reads format version \(expected)."
		case let .schemaFingerprintMismatch(found, expected):
			"The \(name) was written by a SafeDITool whose types are laid out differently: its schema fingerprint is \(Self.hexadecimal(found)), but this SafeDITool’s is \(Self.hexadecimal(expected))."
		case let .bodyLengthMismatch(recorded, actual):
			"The \(name)’s header records a body of \(recorded) bytes, but \(actual) bytes follow the header."
		case .checksumMismatch:
			"The \(name)’s body does not match the checksum in its header."
		case let .malformedBody(.truncated(offset)):
			"The \(name)’s body ends unexpectedly at byte \(offset)."
		case let .malformedBody(.integerTooLong(offset)):
			"The \(name)’s body holds an integer longer than 64 bits at byte \(offset)."
		case let .malformedBody(.countExceedsRemainingBytes(count, offset)):
			"The \(name)’s body records a count of \(count) at byte \(offset), more than the bytes that remain."
		case let .malformedBody(.stringIndexOutOfRange(index, offset)):
			"The \(name)’s body refers to string \(index) at byte \(offset), which its string table does not hold."
		case let .malformedBody(.invalidTag(tag, tagType, offset)):
			"The \(name)’s body holds \(tag) at byte \(offset), which is not a tag of \(tagType)."
		case let .malformedBody(.nestedTooDeeply(offset)):
			"The \(name)’s body nests values too deeply at byte \(offset)."
		case let .malformedBody(.trailingBytes(offset)):
			"The \(name)’s body continues past its end at byte \(offset)."
		}
	}

	private static func hexadecimal(_ value: UInt64) -> String {
		"0x" + String(value, radix: 16)
	}
}

/// Why a ``BinaryFile`` could not be written.
struct BinaryFileWriteError: Error, CustomStringConvertible {
	let kind: BinaryFile.Kind
	/// The instantiable whose declaration names a type that nests more deeply than a ``BinaryReader`` reads, as
	/// its source spells it.
	let instantiableNestedTooDeeply: String

	var description: String {
		"SafeDI cannot write `\(instantiableNestedTooDeeply)` to a \(kind.name): a type its declaration names nests more than \(BinaryReader.maximumNestingDepth) types deep, which is more than SafeDI reads back. To fix this, declare a typealias for part of that type, so that no type in the declaration nests more than \(BinaryReader.maximumNestingDepth) types deep."
	}
}

extension CachedScannedModuleInfo {
	/// Reads the scan cache `data` holds.
	init(scanCacheData data: Data) throws(BinaryFileReadError) {
		self = try BinaryFile.value(.scanCache, from: data)
	}

	/// This value as a scan cache.
	var scanCacheData: Data {
		get throws(BinaryFileWriteError) {
			try BinaryFile.data(.scanCache, holding: self)
		}
	}
}

extension ModuleInfo {
	/// Reads the module info file `data` holds.
	init(moduleInfoData data: Data) throws(BinaryFileReadError) {
		self = try BinaryFile.value(.moduleInfo, from: data)
	}

	/// This module as a module info file.
	var moduleInfoData: Data {
		get throws(BinaryFileWriteError) {
			try BinaryFile.data(.moduleInfo, holding: self)
		}
	}
}
