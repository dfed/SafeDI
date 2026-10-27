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
/// the distinct strings written, which ``BinaryWriter/encoded`` places before the values.
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
/// Every such file's header carries a fingerprint of every member's ``binaryLayout``, so a file written
/// by a SafeDITool whose types were laid out differently is never read. Tests compare each struct's
/// ``binaryLayout`` against the stored properties the type actually has, so a stored property added to a
/// stored type fails the tests until it is written, read, and listed here.
protocol BinarySchemaMember: BinaryCodable {
	/// For a struct, the names of its stored properties, in declaration order. For an enum, the names
	/// of the tags its cases are written as.
	static var binaryLayout: [String] { get }
}

/// The tag a case of a cached enum is written as. Its cases are the enum's layout in the schema.
protocol BinaryTag: RawRepresentable, CaseIterable where RawValue == UInt8 {}

extension BinarySchemaMember {
	/// The layout of an enum whose cases are written as `Tag`.
	static func tagNames<Tag: BinaryTag>(_: Tag.Type) -> [String] {
		Tag.allCases.map { "\($0)" }
	}
}

/// Accumulates values in SafeDITool's binary format.
struct BinaryWriter {
	// MARK: Initialization

	init() {}

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
		if let index = stringIndices[string] {
			writeUnsigned(index)
		} else {
			let index = UInt64(strings.count)
			stringIndices[string] = index
			strings.append(string)
			writeUnsigned(index)
		}
	}

	/// Every value written, without the string table.
	private(set) var bytes = [UInt8]()

	// MARK: Private

	private var strings = [String]()
	private var stringIndices = [String: UInt64]()
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

	/// Reads a value that may contain itself, such as a type description, throwing rather than recursing
	/// without bound when the bytes nest more deeply than any value SafeDITool writes.
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
	private var nestingDepth = 0

	/// Far deeper than any type written in practice. A cache holding a type nested more deeply than this
	/// is not read, which costs a fresh parse, while reading such bytes without a limit could exhaust the stack.
	private static let maximumNestingDepth = 128

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
		if let self {
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

extension Set: BinaryCodable where Element: BinaryCodable & Comparable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init([Element](readingFrom: &reader))
	}

	/// Writes the elements sorted, because a set's iteration order differs between processes.
	func write(to writer: inout BinaryWriter) {
		writer.write(sorted())
	}
}
