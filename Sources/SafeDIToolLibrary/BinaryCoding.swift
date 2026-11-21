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

/// A value that SafeDITool writes in its compact binary format and reads back.
///
/// The format is written and read by hand rather than through `Codable`: most of the time `Codable` takes to
/// read and write scan's cache and `.safedi` files goes to its generic machinery rather than to the text it
/// produces, so no format underneath `Codable` can remove it.
///
/// Values are written depth first, each field in turn, with no names or delimiters. Unsigned integers are
/// LEB128 variable-length integers; signed integers are zigzag-encoded first. A `Bool`, an `Optional`'s presence,
/// and an enum's case are each one tag byte. An `Array`'s length precedes its elements, and a `Set` is written
/// as its elements sorted, so a value always encodes to the same bytes. A `String` is an index into a table of
/// the distinct strings written, which ``BinaryWriter/encoded`` places before the values. Strings are distinct
/// when their UTF-8 bytes differ, so canonically equivalent spellings that `String`'s `==` calls equal each
/// read back as written.
///
/// Readers infer what to read from the type each field has, so changing a field's type changes how it is read
/// and written alike, and a field whose type cannot be written fails to compile.
protocol BinaryCodable {
	/// Reads a value that ``write(to:)`` wrote.
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError)

	/// Appends this value to `writer`.
	func write(to writer: inout BinaryWriter)
}

/// A struct or enum whose layout is part of the schema of the files in ``BinaryFile``.
///
/// Every such file's header carries a fingerprint of every member's ``binaryLayout``: the name and type of
/// each field a struct writes, and the name and payload types of each case an enum writes, in the order they
/// are written. A file written by a SafeDITool whose stored types write other fields, fields of other types, or
/// the same fields in another order is therefore never read. Tests compare each layout against the stored
/// properties the type has and against the bytes ``BinaryCodable/write(to:)`` produces, so a stored property
/// added to a stored type fails the tests until it is written, read, and listed here.
protocol BinarySchemaMember: BinaryCodable {
	static var binaryLayout: BinaryLayout<Self> { get }
}

extension BinarySchemaMember {
	/// The member's layout in a line of ``BinaryFile/schemaDescription``.
	static var binaryLayoutDescription: String {
		binaryLayout.description
	}
}

/// The tag a case of a cached enum is written as. Its cases are the enum's cases in the schema.
/// A line and column in a source file, which a module info file writes as absent where a declaration another module
/// records is read without positions (``BinaryWriter/writingPositionsAsAbsent(_:)``).
protocol BinaryPosition: BinaryCodable {}

protocol BinaryTag: RawRepresentable, CaseIterable where RawValue == UInt8 {}

/// How a ``BinarySchemaMember`` is written.
enum BinaryLayout<Member>: CustomStringConvertible {
	/// A struct, written as each of `fields` in turn. `unwrittenProperties` names each stored property that is
	/// not written as a field of its own name, because the initializer derives it from the fields or because
	/// fields of other names write it.
	case structure(fields: [BinaryLayoutField<Member>], unwrittenProperties: [String])
	/// An enum, written as the tag of its case, then that case's payload. The cases are in tag order.
	case enumeration(cases: [BinaryLayoutCase])

	/// An enum whose cases are written as `Tag`, each followed by the payload `payload` returns for it.
	static func enumeration<Tag: BinaryTag>(writtenAs _: Tag.Type, payload: (Tag) -> [BinaryLayoutPayloadElement]) -> Self {
		.enumeration(cases: Tag.allCases.map { tag in
			BinaryLayoutCase(name: "\(tag)", payload: payload(tag))
		})
	}

	/// Every field or case in the order it is written, with the type of each value written.
	var description: String {
		switch self {
		case let .structure(fields, _):
			fields.map { "\($0.name): \(String(reflecting: $0.type))" }.joined(separator: ", ")
		case let .enumeration(cases):
			cases.map(\.description).joined(separator: ", ")
		}
	}
}

/// A field a struct writes.
struct BinaryLayoutField<Member> {
	/// - Parameters:
	///   - name: The stored property the field writes, or, for a field the initializer splits into or
	///     combines from stored properties, the value it writes.
	///   - keyPath: The value the field writes. Its type is the type the field is written and read as.
	init<Value: BinaryCodable>(_ name: String, _ keyPath: KeyPath<Member, Value>) {
		self.name = name
		self.keyPath = keyPath
		type = Value.self
	}

	let name: String
	/// The value the field writes, through which tests confirm that the field reads back into it.
	let keyPath: PartialKeyPath<Member>
	/// The type the field is written and read as.
	let type: any BinaryCodable.Type
}

/// A case an enum writes.
struct BinaryLayoutCase: CustomStringConvertible {
	let name: String
	/// The case's associated values, in the order they are declared, written, and read.
	let payload: [BinaryLayoutPayloadElement]

	var description: String {
		if payload.isEmpty {
			name
		} else {
			"\(name)(\(payload.map(\.description).joined(separator: ", ")))"
		}
	}
}

/// An associated value of an enum case.
struct BinaryLayoutPayloadElement: CustomStringConvertible {
	/// - Parameters:
	///   - label: The associated value's label, or `nil` when it has none.
	///   - type: The type the associated value is written and read as.
	init(_ label: String?, _ type: (some BinaryCodable).Type) {
		self.label = label
		self.type = type
	}

	let label: String?
	let type: any BinaryCodable.Type

	var description: String {
		if let label {
			"\(label): \(String(reflecting: type))"
		} else {
			String(reflecting: type)
		}
	}
}

/// Accumulates values in SafeDITool's binary format.
struct BinaryWriter {
	// MARK: Initialization

	init() {
		self.init(writesStringsInline: false)
	}

	private init(writesStringsInline: Bool) {
		self.writesStringsInline = writesStringsInline
	}

	/// A writer that writes each string where it is written, its length then its UTF-8 bytes, rather than its index in
	/// a table. Two values it writes as the same bytes are written as the same bytes by a writer that keeps a table, and
	/// the other way around, since each spelling follows from the other; it skips looking each string up, so it compares
	/// two values faster. What it writes is never read.
	static func writingStringsInline() -> BinaryWriter {
		BinaryWriter(writesStringsInline: true)
	}

	// MARK: Internal

	/// The string table followed by every value written.
	var encoded: [UInt8] {
		var stringTable = BinaryWriter()
		stringTable.writeUnsigned(UInt64(strings.count))
		for string in strings {
			let utf8 = string.utf8
			stringTable.writeUnsigned(UInt64(utf8.count))
			stringTable.bytes.append(contentsOf: utf8)
		}
		return stringTable.bytes + bytes
	}

	mutating func write(_ value: some BinaryCodable) {
		value.write(to: &self)
	}

	/// Whether every optional ``BinaryPosition`` is written as absent, as inside ``writingPositionsAsAbsent(_:)``.
	private(set) var writesPositionsAsAbsent = false

	/// Runs `write` with every optional ``BinaryPosition`` it writes written as absent. Every position a value holds is
	/// optional, and its `withoutPositions()` makes each one absent, so `write` writes what it would write of the values'
	/// `withoutPositions()`, without making that copy.
	mutating func writingPositionsAsAbsent(_ write: (inout BinaryWriter) -> Void) {
		let wasWritingPositionsAsAbsent = writesPositionsAsAbsent
		writesPositionsAsAbsent = true
		write(&self)
		writesPositionsAsAbsent = wasWritingPositionsAsAbsent
	}

	mutating func writeTag(_ tag: some BinaryTag) {
		bytes.append(tag.rawValue)
	}

	mutating func writeUnsigned(_ value: UInt64) {
		var remaining = value
		while remaining >= 0x80 {
			bytes.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
			remaining >>= 7
		}
		bytes.append(UInt8(remaining))
	}

	mutating func writeString(_ string: String) {
		if writesStringsInline {
			let utf8 = string.utf8
			writeUnsigned(UInt64(utf8.count))
			bytes.append(contentsOf: utf8)
		} else {
			let key = StringTableKey(string: string)
			if let index = stringIndices[key] {
				writeUnsigned(index)
			} else {
				let index = UInt64(strings.count)
				stringIndices[key] = index
				strings.append(string)
				writeUnsigned(index)
			}
		}
	}

	/// Writes `value` once per writer: its first write writes 0 and then the value, and each later write of an equal
	/// value writes only one more than the order in which the value was first written among shared values. A value a
	/// signature repeats at many places, such as the places of a tree that every declaration beside the tree lists,
	/// is then written, and read back, once.
	mutating func writeShared<Value: BinaryCodable & BidirectionalCollection & Equatable>(_ value: Value) where Value.Element: Hashable {
		let key = AnyHashable(SharedValueKey(value: value))
		if let index = sharedValueIndices[key] {
			writeUnsigned(index + 1)
		} else {
			writeUnsigned(0)
			write(value)
			// After the value, as the reader appends it after reading it: a shared value the value holds takes its index first.
			sharedValueIndices[key] = sharedValueCount
			sharedValueCount += 1
		}
	}

	/// Whether a value a seam signature repeats is written through ``writeSharedByBytes(_:)``, as it is inside
	/// ``writeSharingSignatureValues(_:)``.
	private(set) var sharesSignatureValues = false

	/// Runs `write` with every value a seam signature repeats, at the outermost level of each, written once
	/// (``writeSharedByBytes(_:)``): a type description, a hole's field, and the reason a declaration is not carried
	/// to a hole's place. A seam signature names the same few types at many places, and repeats each field of a scope at
	/// every hole and route step that binds it: E24-fill's `Feature` wrote 4 MB of fields, 2 KB of them distinct.
	mutating func writeSharingSignatureValues(_ write: (inout BinaryWriter) -> Void) {
		let wasSharing = sharesSignatureValues
		sharesSignatureValues = true
		write(&self)
		sharesSignatureValues = wasSharing
	}

	/// Writes the value `write` writes as ``writeShared(_:)`` does, but keyed by the bytes it writes, which are equal
	/// exactly when two values read back equal in every respect, even where their type's `==` ignores a difference, as
	/// a type description's does for `any`. A value written again wrote no string the table lacked, since every string it
	/// names was written with the value it repeats, so removing its bytes leaves the table as it was.
	mutating func writeSharedByBytes(_ write: (inout BinaryWriter) -> Void) {
		let referenceStart = bytes.count
		writeUnsigned(0)
		let valueStart = bytes.count
		let wasSharing = sharesSignatureValues
		sharesSignatureValues = false
		write(&self)
		sharesSignatureValues = wasSharing
		// Copied: a slice would keep the writer's buffer shared, so that every later append copied the whole buffer.
		let key = Array(bytes[valueStart...])
		if let index = sharedValueIndicesByBytes[key] {
			bytes.removeSubrange(referenceStart...)
			writeUnsigned(index + 1)
		} else {
			sharedValueIndicesByBytes[key] = sharedValueCount
			sharedValueCount += 1
		}
	}

	/// Writes a value that may contain itself, such as a type description. A ``BinaryReader`` does not read a
	/// value nested more deeply than ``BinaryReader/maximumNestingDepth``, so the writer notes one that is, and
	/// the value around it written through ``writeDescribed(as:_:)`` names it in ``valueNestedTooDeeply``.
	mutating func writeNested(_ write: (inout BinaryWriter) -> Void) {
		nestingDepth += 1
		isNestedTooDeeply = isNestedTooDeeply || nestingDepth > BinaryReader.maximumNestingDepth
		write(&self)
		nestingDepth -= 1
	}

	/// Writes a value that holds values written through ``writeNested(_:)``. When the first of them that nests
	/// too deeply is within this value, and within no value inside it written this way, `description` is
	/// recorded as ``valueNestedTooDeeply``. It is evaluated only then: describing the nested value itself
	/// could recurse as deeply as it nests.
	/// - Parameters:
	///   - description: The value as its source spells it, for the error that names it.
	///   - write: Writes the value.
	mutating func writeDescribed(as description: @autoclosure () -> String, _ write: (inout BinaryWriter) -> Void) {
		write(&self)
		if valueNestedTooDeeply == nil, isNestedTooDeeply {
			valueNestedTooDeeply = description()
		}
	}

	/// Every value written, without the string table.
	private(set) var bytes = [UInt8]()

	/// The value written through ``writeDescribed(as:_:)`` that holds the first value written through
	/// ``writeNested(_:)`` that nests more deeply than a ``BinaryReader`` reads, as its source spells it.
	private(set) var valueNestedTooDeeply: String?

	// MARK: Private

	/// A string in the string table, compared and hashed by its UTF-8 bytes. `String`'s `==` and hashing
	/// treat canonically equivalent spellings, such as a precomposed `é` and `e` followed by a combining
	/// accent, as one string, but Swift compares identifiers byte for byte, so the table keeps each spelling.
	private struct StringTableKey: Hashable {
		let string: String

		static func == (lhs: Self, rhs: Self) -> Bool {
			// A lookup compares the key with every key its probe meets, most of another length, so the lengths are
			// compared first, and the bytes in place rather than through the string's UTF-8 view.
			var lhsString = lhs.string
			var rhsString = rhs.string
			return lhsString.utf8.count == rhsString.utf8.count
				&& lhsString.withUTF8 { lhsBytes in
					rhsString.withUTF8 { rhsBytes in
						lhsBytes.elementsEqual(rhsBytes)
					}
				}
		}

		func hash(into hasher: inout Hasher) {
			var string = string
			string.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
		}
	}

	private let writesStringsInline: Bool

	/// A value written through ``writeShared(_:)``, hashed by its count and its first and last elements alone: hashing
	/// every element of each of many long arrays costs what writing them did, while an array equal to one already
	/// written shares its storage, which `==` compares first.
	private struct SharedValueKey<Value: BinaryCodable & BidirectionalCollection & Equatable>: Hashable where Value.Element: Hashable {
		let value: Value

		/// Whether the two values read back the same. A value's `==` can ignore what its bytes keep, as a type description's
		/// does for `any`, so two values that `==` calls equal are compared by their bytes unless they share their storage.
		static func == (lhs: Self, rhs: Self) -> Bool {
			guard lhs.value == rhs.value else { return false }
			let sharesStorage = lhs.value.withContiguousStorageIfAvailable { lhsElements in
				rhs.value.withContiguousStorageIfAvailable { lhsElements.baseAddress == $0.baseAddress }
			}
			return sharesStorage == true || bytes(of: lhs.value) == bytes(of: rhs.value)
		}

		func hash(into hasher: inout Hasher) {
			hasher.combine(value.count)
			hasher.combine(value.first)
			hasher.combine(value.last)
		}

		private static func bytes(of value: Value) -> [UInt8] {
			var writer = BinaryWriter()
			writer.write(value)
			return writer.encoded
		}
	}

	private var strings = [String]()
	private var stringIndices = [StringTableKey: UInt64]()
	private var sharedValueIndices = [AnyHashable: UInt64]()
	private var sharedValueIndicesByBytes = [[UInt8]: UInt64]()
	private var sharedValueCount: UInt64 = 0
	private var nestingDepth = 0
	private var isNestedTooDeeply = false
}

/// Reads values in SafeDITool's binary format from bytes that ``BinaryWriter/encoded`` produced.
///
/// Every read is checked against the bytes that remain, so bytes that were not written by the same layout
/// throw ``BinaryDecodingError`` rather than trap or read out of bounds.
struct BinaryReader {
	// MARK: Initialization

	/// A reader positioned after the string table at the start of `bytes`.
	/// - Parameter bytes: Memory that outlives the reader.
	init(bytes: UnsafeRawBufferPointer) throws(BinaryDecodingError) {
		self.bytes = bytes
		let stringCount = try readCount()
		strings.reserveCapacity(stringCount)
		for _ in 0..<stringCount {
			let length = try readCount()
			strings.append(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + length]), as: UTF8.self))
			offset += length
		}
	}

	// MARK: Internal

	/// Far deeper than any type written in practice. Reading bytes that nest without a limit could exhaust the
	/// stack, so a ``BinaryWriter`` notes a value nested more deeply than this, and ``BinaryFile`` refuses to
	/// write a file that holds one rather than write a file no SafeDITool reads.
	static let maximumNestingDepth = 128

	/// Throws unless every byte has been read.
	func finish() throws(BinaryDecodingError) {
		guard offset == bytes.count else {
			throw .trailingBytes(offset: offset)
		}
	}

	mutating func read<Value: BinaryCodable>() throws(BinaryDecodingError) -> Value {
		try Value(readingFrom: &self)
	}

	mutating func readTag<Tag: BinaryTag>() throws(BinaryDecodingError) -> Tag {
		let tagOffset = offset
		let rawValue = try readByte()
		guard let tag = Tag(rawValue: rawValue) else {
			throw .invalidTag(rawValue, tagType: "\(Tag.self)", offset: tagOffset)
		}
		return tag
	}

	mutating func readUnsigned() throws(BinaryDecodingError) -> UInt64 {
		let valueOffset = offset
		var byte = try readByte()
		var value = UInt64(byte & 0x7F)
		var shift: UInt64 = 0
		while byte >= 0x80 {
			shift += 7
			guard shift < 64 else {
				throw .integerTooLong(offset: valueOffset)
			}
			byte = try readByte()
			value |= UInt64(byte & 0x7F) << shift
		}
		return value
	}

	/// Reads the number of elements or bytes that follow. Every element takes at least one byte, so a
	/// count larger than the bytes that remain cannot have been written, and is rejected before anything
	/// is allocated for it.
	mutating func readCount() throws(BinaryDecodingError) -> Int {
		let countOffset = offset
		let count = try readUnsigned()
		guard count <= UInt64(bytes.count - offset) else {
			throw .countExceedsRemainingBytes(count: count, offset: countOffset)
		}
		return Int(count)
	}

	mutating func readString() throws(BinaryDecodingError) -> String {
		let indexOffset = offset
		let index = try readUnsigned()
		guard index < UInt64(strings.count) else {
			throw .stringIndexOutOfRange(index: index, offset: indexOffset)
		}
		return strings[Int(index)]
	}

	/// Reads a value that ``BinaryWriter/writeShared(_:)`` wrote: the value itself where it was first written, and
	/// otherwise the value read there, whose storage every later read shares.
	mutating func readShared<Value: BinaryCodable>() throws(BinaryDecodingError) -> Value {
		let referenceOffset = offset
		let reference = try readUnsigned()
		if reference == 0 {
			let value: Value = try read()
			sharedValues.append(value)
			return value
		} else {
			guard reference <= UInt64(sharedValues.count), let value = sharedValues[Int(reference - 1)] as? Value else {
				throw .sharedValueReferenceOutOfRange(reference: reference, offset: referenceOffset)
			}
			return value
		}
	}

	/// Whether a value a seam signature repeats is read through ``readSharedByBytes(_:)``, as it is inside
	/// ``readSharingSignatureValues(_:)``.
	private(set) var sharesSignatureValues = false

	/// Reads what ``BinaryWriter/writeSharingSignatureValues(_:)`` wrote.
	mutating func readSharingSignatureValues<Value>(_ read: (inout BinaryReader) throws(BinaryDecodingError) -> Value) throws(BinaryDecodingError) -> Value {
		let wasSharing = sharesSignatureValues
		sharesSignatureValues = true
		defer { sharesSignatureValues = wasSharing }
		return try read(&self)
	}

	/// Reads a value that ``BinaryWriter/writeSharedByBytes(_:)`` wrote.
	mutating func readSharedByBytes<Value>(_ read: (inout BinaryReader) throws(BinaryDecodingError) -> Value) throws(BinaryDecodingError) -> Value {
		let referenceOffset = offset
		let reference = try readUnsigned()
		if reference == 0 {
			let wasSharing = sharesSignatureValues
			sharesSignatureValues = false
			defer { sharesSignatureValues = wasSharing }
			let value = try read(&self)
			sharedValues.append(value)
			return value
		} else {
			guard reference <= UInt64(sharedValues.count), let value = sharedValues[Int(reference - 1)] as? Value else {
				throw .sharedValueReferenceOutOfRange(reference: reference, offset: referenceOffset)
			}
			return value
		}
	}

	/// Reads a value that may contain itself, such as a type description, throwing rather than recursing
	/// without bound when the bytes nest more deeply than ``maximumNestingDepth``, which no SafeDITool writes.
	mutating func readNested<Value>(_ read: (inout BinaryReader) throws(BinaryDecodingError) -> Value) throws(BinaryDecodingError) -> Value {
		guard nestingDepth < Self.maximumNestingDepth else {
			throw .nestedTooDeeply(offset: offset)
		}
		nestingDepth += 1
		defer { nestingDepth -= 1 }
		return try read(&self)
	}

	// MARK: Private

	private let bytes: UnsafeRawBufferPointer
	private var offset = 0
	private var strings = [String]()
	private var sharedValues = [Any]()
	private var nestingDepth = 0

	private mutating func readByte() throws(BinaryDecodingError) -> UInt8 {
		guard offset < bytes.count else {
			throw .truncated(offset: offset)
		}
		let byte = bytes[offset]
		offset += 1
		return byte
	}
}

/// Why bytes could not be read as the values a ``BinaryReader`` expected.
enum BinaryDecodingError: Error, Equatable {
	case truncated(offset: Int)
	case integerTooLong(offset: Int)
	case countExceedsRemainingBytes(count: UInt64, offset: Int)
	case stringIndexOutOfRange(index: UInt64, offset: Int)
	case sharedValueReferenceOutOfRange(reference: UInt64, offset: Int)
	case invalidTag(UInt8, tagType: String, offset: Int)
	case nestedTooDeeply(offset: Int)
	case trailingBytes(offset: Int)
}

// MARK: - Standard library conformances

extension String: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = try reader.readString()
	}

	func write(to writer: inout BinaryWriter) {
		writer.writeString(self)
	}
}

extension Int: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = try Int(truncatingIfNeeded: Int64(readingFrom: &reader))
	}

	func write(to writer: inout BinaryWriter) {
		Int64(self).write(to: &writer)
	}
}

extension Int64: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		let zigzag = try reader.readUnsigned()
		self = Int64(bitPattern: (zigzag >> 1) ^ (0 &- (zigzag & 1)))
	}

	func write(to writer: inout BinaryWriter) {
		writer.writeUnsigned(UInt64(bitPattern: (self << 1) ^ (self >> 63)))
	}
}

extension Bool: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = try reader.readTag() as BooleanTag == .true
	}

	func write(to writer: inout BinaryWriter) {
		writer.writeTag(self ? BooleanTag.true : .false)
	}

	enum BooleanTag: UInt8, BinaryTag {
		case `false`
		case `true`
	}
}

extension Optional: BinaryCodable where Wrapped: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = try Bool(readingFrom: &reader) ? Wrapped(readingFrom: &reader) : nil
	}

	func write(to writer: inout BinaryWriter) {
		if let self, !(writer.writesPositionsAsAbsent && Wrapped.self is any BinaryPosition.Type) {
			writer.write(true)
			writer.write(self)
		} else {
			writer.write(false)
		}
	}
}

extension Array: BinaryCodable where Element: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		let count = try reader.readCount()
		self.init()
		reserveCapacity(count)
		for _ in 0..<count {
			try append(Element(readingFrom: &reader))
		}
	}

	func write(to writer: inout BinaryWriter) {
		writer.writeUnsigned(UInt64(count))
		for element in self {
			writer.write(element)
		}
	}
}

/// A value whose repeated type descriptions, hole fields and reasons are each written once
/// (``BinaryWriter/writeSharingSignatureValues(_:)``).
struct BinarySharingSignatureValues<Value: BinaryCodable>: BinaryCodable {
	init(_ value: Value) {
		self.value = value
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		value = try reader.readSharingSignatureValues { reader throws(BinaryDecodingError) in try reader.read() }
	}

	let value: Value

	func write(to writer: inout BinaryWriter) {
		writer.writeSharingSignatureValues { $0.write(value) }
	}
}

/// A value written once however often a file holds it (``BinaryWriter/writeShared(_:)``).
struct BinaryShared<Value: BinaryCodable & BidirectionalCollection & Equatable>: BinaryCodable where Value.Element: Hashable {
	init(_ value: Value) {
		self.value = value
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		value = try reader.readShared()
	}

	let value: Value

	func write(to writer: inout BinaryWriter) {
		writer.writeShared(value)
	}
}

extension Dictionary: BinaryCodable where Key: BinaryCodable & Comparable, Value: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		let count = try reader.readCount()
		self.init(minimumCapacity: count)
		for _ in 0..<count {
			let key = try Key(readingFrom: &reader)
			self[key] = try Value(readingFrom: &reader)
		}
	}

	/// Writes the entries sorted by key, because a dictionary's iteration order differs between processes.
	func write(to writer: inout BinaryWriter) {
		writer.writeUnsigned(UInt64(count))
		for (key, value) in sorted(by: { $0.key < $1.key }) {
			writer.write(key)
			writer.write(value)
		}
	}
}

extension Set: BinaryCodable where Element: BinaryCodable & Comparable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init([Element](readingFrom: &reader))
	}

	/// Writes the elements sorted, because a set's iteration order differs between processes.
	func write(to writer: inout BinaryWriter) {
		writer.write(sorted())
	}
}
