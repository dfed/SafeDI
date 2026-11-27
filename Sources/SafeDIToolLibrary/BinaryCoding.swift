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
	/// Whether the struct writes its optional and Boolean fields as one integer of flags before its fields
	/// (``BinaryFieldFlags``): whether each optional field holds a value, and each Boolean field's value. Every struct
	/// with two or more such fields that a file holds many of does.
	static var writesFieldFlags: Bool { get }
}

extension BinarySchemaMember {
	static var writesFieldFlags: Bool {
		false
	}

	/// The member's layout in a line of ``BinaryFile/schemaDescription``.
	static var binaryLayoutDescription: String {
		if writesFieldFlags {
			"field flags, " + binaryLayout.description
		} else {
			binaryLayout.description
		}
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
			fields.map { "\($0.name): \(String(reflecting: $0.type))\($0.isAbsentWhenEmpty ? " absent when empty" : "")" }.joined(separator: ", ")
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
		isAbsentWhenEmpty = false
	}

	/// A list a struct that writes field flags writes as a flag alone when it is empty
	/// (``BinaryWriter/writeAbsentWhenEmpty(_:flaggedIn:)``).
	/// - Parameters:
	///   - name: The stored property the field writes.
	///   - keyPath: The list the field writes.
	init<Element: BinaryCodable>(_ name: String, absentWhenEmpty keyPath: KeyPath<Member, [Element]>) {
		self.name = name
		self.keyPath = keyPath
		type = [Element].self
		isAbsentWhenEmpty = true
	}

	let name: String
	/// The value the field writes, through which tests confirm that the field reads back into it.
	let keyPath: PartialKeyPath<Member>
	/// The type the field is written and read as.
	let type: any BinaryCodable.Type
	/// Whether the field is a list written as a flag alone when it is empty, which the schema states: a file that
	/// writes the list with its count is another layout.
	let isAbsentWhenEmpty: Bool
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

	/// Writes what another writer encoded (``encoded``), its length first, so that a reader can keep the bytes without
	/// reading what they hold (``BinaryReader/readEncoding()``) and decode them later with a reader of their own.
	mutating func writeEncoding(_ encoding: [UInt8]) {
		writeUnsigned(UInt64(encoding.count))
		bytes.append(contentsOf: encoding)
	}

	/// Whether every optional ``BinaryPosition`` is written as absent, as inside ``writingPositionsAsAbsent(_:)``.
	private(set) var writesPositionsAsAbsent = false

	/// Runs `write` with every optional ``BinaryPosition`` it writes written as absent. Every position a value holds is
	/// optional, so `write` writes what it would write of a copy of the values with every position `nil`, without making
	/// that copy.
	mutating func writingPositionsAsAbsent(_ write: (inout BinaryWriter) -> Void) {
		let wasWritingPositionsAsAbsent = writesPositionsAsAbsent
		writesPositionsAsAbsent = true
		write(&self)
		writesPositionsAsAbsent = wasWritingPositionsAsAbsent
	}

	/// The positions of the module's own declarations, collected inside ``collectingPositions(_:)`` to rank them before
	/// they are written to a file that stores them elsewhere.
	private(set) var collectedPositions: CollectedPositions?

	/// Where ``positionsStoredElsewhere`` is set, how positions are written: each location with its file and its rank,
	/// and its line and column in the stream of the positions file, but an aliased dependency's location with its line
	/// and column too, since the code generated above reads it; each range in that stream alone.
	var positionsStoredElsewhere: PositionsStoredElsewhere?

	/// Runs `write`, which writes nothing anyone reads, and returns the positions it wrote.
	static func collectingPositions(_ write: (inout BinaryWriter) -> Void) -> CollectedPositions {
		var writer = BinaryWriter()
		writer.collectedPositions = CollectedPositions()
		write(&writer)
		return writer.collectedPositions ?? CollectedPositions()
	}

	/// Notes that `location` is where an aliased dependency is declared, which a file that stores positions elsewhere
	/// keeps with its line and column, since the code generated above reads its line.
	mutating func noteAliasDeclaration(at location: Dependency.DeclarationLocation?) {
		guard let location, collectedPositions != nil else { return }
		collectedPositions?.aliasDeclarationLocations.insert(location)
	}

	/// Writes `location` as it is, or, where positions are stored elsewhere, ranked.
	mutating func writeLocation(_ location: Dependency.DeclarationLocation) {
		collectedPositions?.locations.insert(location)
		guard let ranked = positionsStoredElsewhere?.ranked(location) else {
			return writeLocationFields(of: location)
		}
		if ranked.placement == .storedElsewhere, case let .here(line, column) = location.placement {
			positionsStoredElsewhere?.append(line: line, column: column)
		}
		writeLocationFields(of: ranked)
	}

	/// Writes `range` as it is, or, where positions are stored elsewhere, as stored there.
	mutating func writeRange(_ range: Dependency.SourceRange) {
		guard positionsStoredElsewhere != nil, case let .here(startLine, startColumn, endLine, endColumn) = range.placement else {
			return writeRangeFields(of: range)
		}
		positionsStoredElsewhere?.append(startLine: startLine, startColumn: startColumn, endLine: endLine, endColumn: endColumn)
		writeRangeFields(of: Dependency.SourceRange(placement: .storedElsewhere))
	}

	/// The file, then the line or the order (`Dependency.DeclarationLocation.binaryLineOrOrder`), then, where the location
	/// holds them, the column, after the line where the location is ranked: so a location that is not ranked is written
	/// as its file, line and column, as it was before locations were ranked.
	private mutating func writeLocationFields(of location: Dependency.DeclarationLocation) {
		write(location.filePath)
		write(location.binaryLineOrOrder)
		guard case let .here(line, column) = location.placement else { return }
		if location.order != 0 {
			write(line)
		}
		write(column)
	}

	/// The start line, or `-1` where the range is stored elsewhere, and then the start column, end line and end column.
	private mutating func writeRangeFields(of range: Dependency.SourceRange) {
		write(range.binaryStartLine)
		guard case .here = range.placement else { return }
		write(range.binaryStartColumn)
		write(range.binaryEndLine)
		write(range.binaryEndColumn)
	}

	mutating func writeTag(_ tag: some BinaryTag) {
		bytes.append(tag.rawValue)
	}

	/// Where a struct's fields begin: a struct that writes its optional and Boolean fields as flags
	/// (``BinaryFieldFlags``) writes its fields after this and then ``finishFields(_:startingAt:)``, which writes the
	/// flags before them. One byte is held for the flags, which is all that most structs' flags take.
	mutating func startFields() -> Int {
		let start = bytes.count
		bytes.append(0)
		return start
	}

	/// Writes `flags` before the fields written since ``startFields()`` returned `start`.
	mutating func finishFields(_ flags: BinaryFieldFlags, startingAt start: Int) {
		if flags.bits < 0x80 {
			bytes[start] = UInt8(flags.bits)
		} else {
			var flagBytes = [UInt8]()
			var remaining = flags.bits
			while remaining >= 0x80 {
				flagBytes.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
				remaining >>= 7
			}
			flagBytes.append(UInt8(remaining))
			bytes.replaceSubrange(start..<start + 1, with: flagBytes)
		}
	}

	/// Writes an optional field of a struct that writes its fields' flags: its presence as a flag, and then its value
	/// only when it holds one. A ``BinaryPosition`` is written as absent inside ``writingPositionsAsAbsent(_:)``, as
	/// `Optional`'s own coder writes it.
	mutating func writeOptional<Value: BinaryCodable>(_ value: Value?, flaggedIn flags: inout BinaryFieldFlags) {
		if let value, !(writesPositionsAsAbsent && Value.self is any BinaryPosition.Type) {
			flags.append(true)
			write(value)
		} else {
			flags.append(false)
		}
	}

	/// Writes a list field of a struct that writes its fields' flags: whether it holds an element as a flag, and then
	/// the list only when it does. A list most records hold empty then costs a bit where its count cost a byte.
	mutating func writeAbsentWhenEmpty(_ list: [some BinaryCodable], flaggedIn flags: inout BinaryFieldFlags) {
		flags.append(!list.isEmpty)
		if !list.isEmpty {
			write(list)
		}
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
			// A string in a representation written before is the string written then, with no look at its bytes: a file
			// names a few thousand distinct strings millions of times, nearly all of them through the same few values.
			let representation = StringRepresentation(string)
			if let index = stringIndicesByRepresentation.value(for: representation) {
				writeUnsigned(index)
			} else {
				let key = StringTableKey(string: string)
				let index: UInt64
				if let writtenIndex = stringIndices[key] {
					index = writtenIndex
				} else {
					index = UInt64(strings.count)
					stringIndices[key] = index
					strings.append(string)
				}
				// The string is kept so that its storage, and so the address it is found by, is not freed and reused.
				stringIndicesByRepresentation.setValue(index, for: representation)
				valuesHeldForTheirStorage.append(string)
				writeUnsigned(index)
			}
		}
	}

	/// Writes `value` once per writer: its first write writes 0 and then the value, and each later write of an equal
	/// value writes only one more than the order in which the value was first written among shared values. A value a
	/// signature repeats at many places, such as the places of a tree that every declaration beside the tree lists,
	/// is then written, and read back, once.
	///
	/// A value whose storage was written before is written as that storage was, without comparing it again: comparing
	/// two equal values that do not share their storage writes both to bytes, and a module's view holds each value once
	/// per file it was read from, so its signatures named one value from thousands of places.
	mutating func writeShared<Value: BinaryCodable & BidirectionalCollection & Equatable>(_ value: Value) where Value.Element: Hashable {
		let storage = value.withContiguousStorageIfAvailable { elements in
			UnsafeRawPointer(elements.baseAddress).map { SharedValueStorage(valueType: ObjectIdentifier(Value.self), address: $0, count: elements.count) }
		} ?? nil
		if let storage, let written = sharedValueIndicesByStorage[storage] {
			writeUnsigned(written.index + 1)
			return
		}
		// Two values read back the same exactly when they are written as the same bytes: a value's `==` can ignore what
		// its bytes keep, as a type description's does for `any`. The value is written once by itself to be looked up, with
		// each string where it is named, and again in place only when it is new.
		var valueWriter = BinaryWriter.writingStringsInline()
		valueWriter.write(value)
		let valueType = ObjectIdentifier(Value.self)
		let index: UInt64
		if let writtenIndex = valueWriter.bytes.withUnsafeBytes({ sharedValueIndicesByOwnBytes[valueType]?.index(of: $0) }) {
			index = writtenIndex
			writeUnsigned(index + 1)
		} else {
			writeUnsigned(0)
			write(value)
			// After the value, as the reader appends it after reading it: a shared value the value holds takes its index first.
			index = sharedValueCount
			valueWriter.bytes.withUnsafeBytes { sharedValueIndicesByOwnBytes[valueType, default: SharedValueIndicesByBytes()].insert(index, for: $0) }
			sharedValueCount += 1
		}
		if let storage {
			// The value is kept so that its storage, and so the address it is found by, is not freed and reused.
			sharedValueIndicesByStorage[storage] = (index, value)
		}
	}

	/// Writes `list`, one of the lists a seam signature or a public mock plan holds for each of its places, as its
	/// difference from a list written before in the same `slot`, wherever a signature's repeated values are written once
	/// (``sharesSignatureValues``), and as any list is written elsewhere.
	///
	/// The places of one type each list the declarations bound before them and those bound after them, so N places wrote
	/// N × N entries: a plan of 80 builders was 124 KB, and one of 160, 442 KB. A place's list is another place's plus
	/// or minus a few declarations, so it is written as the list it differs from (how many lists back in the slot), how
	/// many elements it keeps from that list's start and from its end, and the elements between, in full. The list it
	/// differs from is the first list written of the same elements, where there is one, so that the reader hands that
	/// list back, storage and all; and otherwise the one that shares the most elements at its two ends among three
	/// written before: the last one, the longest that starts with this list's first element, and the longest that ends
	/// with its last. The places are written in the order of their labels, not of their declarations, so the nearest
	/// list is rarely the last one. A list that shares no element with any of the three, or that a difference would
	/// write no shorter, is written whole.
	///
	/// Two elements are the same when they are written as the same bytes here, so what is read back is what a list
	/// written whole would read back, whatever the elements are. An element is written once, where the list would have
	/// written it, and only its bytes are compared and moved: nothing is written twice to compare, since a signature's
	/// lists hold millions of elements. An empty list is never one a later list differs from.
	mutating func writeDifference(of list: [some BinaryCodable], in slot: BinaryDifferenceSlot) {
		guard sharesSignatureValues else {
			write(list)
			return
		}
		writeDifference(of: list, in: slot) { element, writer in
			writer.write(element)
		}
	}

	/// Writes `list` as ``writeDifference(of:in:)`` does, each element as `writeElement` writes it, which
	/// ``BinaryReader/readDifference(in:readingElement:)`` reads back with the function that reads what it wrote.
	///
	/// Called only where ``sharesSignatureValues`` holds.
	mutating func writeDifference<Element>(of list: [Element], in slot: BinaryDifferenceSlot, writingElement writeElement: (Element, inout BinaryWriter) -> Void) {
		guard !list.isEmpty else {
			writeUnsigned(0)
			return
		}
		var history = listHistoriesBySlot[slot] ?? ListHistory()
		// Taken out while it changes, so that it is changed in place.
		listHistoriesBySlot[slot] = nil
		let listStart = bytes.count
		var elements = [Int]()
		elements.reserveCapacity(list.count)
		var elementEnds = [Int]()
		elementEnds.reserveCapacity(list.count)
		for element in list {
			let elementStart = bytes.count
			let sharedValueCountBefore = sharedValueCount
			writeElement(element, &self)
			let elementEnd = bytes.count
			elementEnds.append(elementEnd)
			if sharedValueCount == sharedValueCountBefore {
				elements.append(bytes.withUnsafeBytes { history.identifier(ofElementWrittenAs: UnsafeRawBufferPointer(rebasing: $0[elementStart...])) })
			} else {
				// The element wrote a shared value for the first time, in full, and is written as a reference to it from
				// now on: it is the same element then, so it is known by those bytes, which writing it once more gives.
				// Every shared value it holds at its outermost level is written by now, and nothing is shared inside a
				// value written in full, so this second writing writes no value for the first time, and removing its
				// bytes leaves every table as it was. Only an element's first writing pays for it.
				writeElement(element, &self)
				elements.append(bytes.withUnsafeBytes { history.identifier(ofElementWrittenAs: UnsafeRawBufferPointer(rebasing: $0[elementEnd...])) })
				bytes.removeSubrange(elementEnd...)
			}
		}
		var wholeHeader = BinaryWriter()
		wholeHeader.writeUnsigned(UInt64(list.count) << 1)
		var isWrittenWhole = true
		if let difference = history.difference(of: elements) {
			let unsharedStart = difference.sharedAtStart == 0 ? listStart : elementEnds[difference.sharedAtStart - 1]
			let unsharedEnd = difference.sharedAtEnd == elements.count ? listStart : elementEnds[elements.count - difference.sharedAtEnd - 1]
			var header = BinaryWriter()
			header.writeUnsigned(UInt64(elements.count - difference.sharedAtStart - difference.sharedAtEnd) << 1 | 1)
			header.writeUnsigned(UInt64(history.lists.count - difference.list))
			header.writeUnsigned(UInt64(difference.sharedAtStart))
			header.writeUnsigned(UInt64(difference.sharedAtEnd))
			// Only where it is shorter: a list of one reference is no longer than the four numbers that say where it is.
			if header.bytes.count < wholeHeader.bytes.count + (unsharedStart - listStart) + (bytes.count - unsharedEnd) {
				// The elements kept from the list's two ends were each written before as the same bytes, so none of them wrote a
				// shared value or a string for the first time, and removing their bytes leaves every table as it was. The elements
				// between stay as they were written, in their order, so each shared value they wrote keeps its index.
				bytes.removeSubrange(unsharedEnd...)
				bytes.replaceSubrange(listStart..<unsharedStart, with: header.bytes)
				isWrittenWhole = false
			}
		}
		if isWrittenWhole {
			bytes.insert(contentsOf: wholeHeader.bytes, at: listStart)
		}
		history.append(elements)
		listHistoriesBySlot[slot] = history
	}

	/// The lists ``writeDifference(of:in:)`` wrote in one slot, each element as a number that two elements share exactly
	/// when they were written as the same bytes. Held until the writer is released: one number per element written, and
	/// a copy of each distinct element's bytes, where the lists themselves held a value each.
	private struct ListHistory {
		private(set) var lists = [[Int]]()

		mutating func identifier(ofElementWrittenAs bytes: UnsafeRawBufferPointer) -> Int {
			if bytes.count <= 8 {
				// Most elements are a reference of a byte or two to a value written before.
				var word: UInt64 = 0
				withUnsafeMutableBytes(of: &word) { $0.copyMemory(from: bytes) }
				let key = ShortElement(word: word, count: bytes.count)
				if let identifier = identifiersByShortBytes[key] {
					return identifier
				} else {
					let identifier = identifiersByShortBytes.count + identifiersByLongBytes.count
					identifiersByShortBytes[key] = identifier
					return identifier
				}
			} else {
				let key = [UInt8](bytes)
				if let identifier = identifiersByLongBytes[key] {
					return identifier
				} else {
					let identifier = identifiersByShortBytes.count + identifiersByLongBytes.count
					identifiersByLongBytes[key] = identifier
					return identifier
				}
			}
		}

		/// The list written before that `elements` differs least from, with how many elements the two share at their start
		/// and, after those, at their end: the first list written of the same elements, which the reader then hands back,
		/// storage and all; or else, of the last list written, the longest that starts with `elements`' first element and
		/// the longest that ends with its last, the one that shares the most, the earliest named here on a tie. `nil` when
		/// none shares an element at either end.
		func difference(of elements: [Int]) -> (list: Int, sharedAtStart: Int, sharedAtEnd: Int)? {
			if let sameList = firstListByElements[elements] {
				return (sameList, elements.count, 0)
			}
			var best: (list: Int, sharedAtStart: Int, sharedAtEnd: Int)?
			let candidates = [lists.isEmpty ? nil : lists.count - 1, elements.first.flatMap { longestListByFirstElement[$0] }, elements.last.flatMap { longestListByLastElement[$0] }]
			for case let candidate? in candidates {
				let other = lists[candidate]
				let limit = Swift.min(elements.count, other.count)
				var sharedAtStart = 0
				while sharedAtStart < limit, elements[sharedAtStart] == other[sharedAtStart] {
					sharedAtStart += 1
				}
				var sharedAtEnd = 0
				while sharedAtStart + sharedAtEnd < limit, elements[elements.count - 1 - sharedAtEnd] == other[other.count - 1 - sharedAtEnd] {
					sharedAtEnd += 1
				}
				if sharedAtStart + sharedAtEnd > (best.map { $0.sharedAtStart + $0.sharedAtEnd } ?? 0) {
					best = (candidate, sharedAtStart, sharedAtEnd)
				}
			}
			return best
		}

		mutating func append(_ elements: [Int]) {
			if let first = elements.first, longestListByFirstElement[first].map({ lists[$0].count < elements.count }) ?? true {
				longestListByFirstElement[first] = lists.count
			}
			if let last = elements.last, longestListByLastElement[last].map({ lists[$0].count < elements.count }) ?? true {
				longestListByLastElement[last] = lists.count
			}
			if firstListByElements[elements] == nil {
				firstListByElements[elements] = lists.count
			}
			lists.append(elements)
		}

		private struct ShortElement: Hashable {
			let word: UInt64
			let count: Int
		}

		private var identifiersByShortBytes = [ShortElement: Int]()
		private var identifiersByLongBytes = [[UInt8]: Int]()
		/// The first of the longest lists written that start with each element, and that end with each.
		private var longestListByFirstElement = [Int: Int]()
		private var longestListByLastElement = [Int: Int]()
		/// The first list written of each run of elements, whose storage in `lists` each key shares.
		private var firstListByElements = [[Int]: Int]()
	}

	private var listHistoriesBySlot = [BinaryDifferenceSlot: ListHistory]()

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

	/// Writes `value` as ``writeSharedByBytes(_:)`` writes what `write` writes, which must be the same bytes whatever was
	/// written before and however the writer is set. A value held as the same words as one written before, such as an
	/// indirect enum's case in the same box, is that value, so it is written as that one was without writing it out to
	/// compare: a signature names a few thousand distinct types more than a million times.
	mutating func writeSharedByBytes(_ value: some Any, _ write: (inout BinaryWriter) -> Void) {
		guard let representation = ValueRepresentation(value) else {
			writeSharedByBytes(write)
			return
		}
		if let index = sharedValueIndicesByRepresentation.value(for: representation) {
			writeUnsigned(index + 1)
		} else {
			sharedValueIndicesByRepresentation.setValue(writeSharedByBytes(write), for: representation)
			// The value is kept so that its storage, and so the address it is found by, is not freed and reused.
			valuesHeldForTheirStorage.append(value)
		}
	}

	/// Writes the value `write` writes as ``writeShared(_:)`` does, but keyed by the bytes it writes, which are equal
	/// exactly when two values read back equal in every respect, even where their type's `==` ignores a difference, as
	/// a type description's does for `any`. A value written again wrote no string the table lacked, since every string it
	/// names was written with the value it repeats, so removing its bytes leaves the table as it was.
	/// - Returns: The value's index among shared values.
	@discardableResult
	mutating func writeSharedByBytes(_ write: (inout BinaryWriter) -> Void) -> UInt64 {
		let referenceStart = bytes.count
		writeUnsigned(0)
		let valueStart = bytes.count
		let wasSharing = sharesSignatureValues
		sharesSignatureValues = false
		write(&self)
		sharesSignatureValues = wasSharing
		// Compared where they were written, against a copy kept of each value's first write: nearly every value repeats one
		// written before, so copying each to look it up allocated once per value written.
		let writtenIndex = bytes.withUnsafeBytes { bytes in
			sharedValueIndicesByBytes.index(of: UnsafeRawBufferPointer(rebasing: bytes[valueStart...]))
		}
		if let writtenIndex {
			bytes.removeSubrange(referenceStart...)
			writeUnsigned(writtenIndex + 1)
			return writtenIndex
		} else {
			let index = sharedValueCount
			bytes.withUnsafeBytes { bytes in
				sharedValueIndicesByBytes.insert(index, for: UnsafeRawBufferPointer(rebasing: bytes[valueStart...]))
			}
			sharedValueCount += 1
			return index
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

	private var strings = [String]()
	private var stringIndices = [StringTableKey: UInt64]()
	/// The index of each value written through ``writeShared(_:)``, by its type and the bytes it is written as by itself:
	/// values of two types can be written as the same bytes, as every empty collection is, and a reader hands a
	/// reference back only as the type that was read.
	private var sharedValueIndicesByOwnBytes = [ObjectIdentifier: SharedValueIndicesByBytes]()
	/// Where a value written through ``writeShared(_:)`` keeps its elements: with its type and count, since every empty
	/// collection of every type can share one address.
	private struct SharedValueStorage: Hashable {
		let valueType: ObjectIdentifier
		let address: UnsafeRawPointer
		let count: Int
	}

	/// The index of each value written through ``writeShared(_:)``, by its storage, with the value.
	private var sharedValueIndicesByStorage = [SharedValueStorage: (index: UInt64, value: Any)]()
	private var stringIndicesByRepresentation = TableByWords<StringRepresentation, UInt64>()
	private var sharedValueIndicesByBytes = SharedValueIndicesByBytes()
	private var sharedValueIndicesByRepresentation = TableByWords<ValueRepresentation, UInt64>()
	/// Each string and value whose representation one of the tables above holds: one per representation written, a few
	/// thousand in the largest files, for as long as the writer lives.
	private var valuesHeldForTheirStorage = [Any]()
	private var sharedValueCount: UInt64 = 0
	private var nestingDepth = 0
	/// Whether a value written through ``writeNested(_:)`` nests more deeply than a ``BinaryReader`` reads.
	private(set) var isNestedTooDeeply = false
}

/// A key of a ``TableByWords``: a few words compared whole, with a hash of them that costs a few multiplications.
private protocol WordsKey: Equatable {
	var hash: UInt64 { get }
}

/// A hash table from a few words to a value, probed linearly. `Dictionary` hashes each key with SipHash, which costs
/// more than everything else a writer or reader does for one of the millions of small values a file names.
private struct TableByWords<Key: WordsKey, Value> {
	func value(for key: Key) -> Value? {
		guard !slots.isEmpty else { return nil }
		return slots[slot(for: key)]?.value
	}

	/// Gives `key` the value `value`, in place of the one it has when it has one.
	mutating func setValue(_ value: Value, for key: Key) {
		if (count + 1) * 2 > slots.count {
			let filled = slots.compactMap(\.self)
			slots = [(key: Key, value: Value)?](repeating: nil, count: Swift.max(slots.count * 2, 64))
			for (key, value) in filled {
				slots[slot(for: key)] = (key, value)
			}
		}
		let slot = slot(for: key)
		if slots[slot] == nil {
			count += 1
		}
		slots[slot] = (key, value)
	}

	private var slots = [(key: Key, value: Value)?]()
	private var count = 0

	/// The slot that holds `key`, or the empty one it belongs in. The table is never full.
	private func slot(for key: Key) -> Int {
		var slot = Int(truncatingIfNeeded: key.hash >> 32) & (slots.count - 1)
		while let filled = slots[slot], filled.key != key {
			slot = (slot + 1) & (slots.count - 1)
		}
		return slot
	}
}

/// The two words a `String` is held as: a short string's bytes themselves, or else the address of its storage with its
/// length. Two strings held as the same words are the same bytes for as long as that storage lives.
private struct StringRepresentation: WordsKey {
	init(_ string: String) {
		(low, high) = unsafeBitCast(string, to: (UInt64, UInt64).self)
	}

	let low: UInt64
	let high: UInt64

	var hash: UInt64 {
		((low ^ (high >> 32)) &* 0x9E3779B185EBCA87) ^ (high &* 0xC2B2AE3D27D4EB4F)
	}
}

/// The bytes a value of at most three words is held as. Two values of one type held as the same bytes are the same
/// value for as long as the storage those bytes point to lives.
private struct ValueRepresentation: WordsKey {
	init?(_ value: some Any) {
		guard MemoryLayout.size(ofValue: value) <= 3 * MemoryLayout<UInt64>.size else { return nil }
		var words: (UInt64, UInt64, UInt64) = (0, 0, 0)
		withUnsafeBytes(of: value) { valueBytes in
			withUnsafeMutableBytes(of: &words) { $0.copyMemory(from: valueBytes) }
		}
		(first, second, third) = words
	}

	let first: UInt64
	let second: UInt64
	let third: UInt64

	var hash: UInt64 {
		((first ^ (second >> 32)) &* 0x9E3779B185EBCA87) ^ (second &* 0xC2B2AE3D27D4EB4F) ^ (third &* 0x165667B19E3779F9)
	}
}

/// Two unsigned integers a reader read one after the other.
private struct UnsignedPair: WordsKey {
	let first: UInt64
	let second: UInt64

	var hash: UInt64 {
		(first &* 0x9E3779B185EBCA87) ^ (second &* 0xC2B2AE3D27D4EB4F)
	}
}

/// What a reader finds a value it read before by: bytes of the value or their checksum, how many bytes, and the type read.
private struct RepeatableValueKey: WordsKey {
	let bytes: UInt64
	let length: UInt64
	let type: UInt64

	var hash: UInt64 {
		(bytes &* 0x9E3779B185EBCA87) ^ (length &* 0xC2B2AE3D27D4EB4F) ^ (type &* 0x165667B19E3779F9)
	}
}

/// A value a reader holds to hand out again, in a box whose type is checked by comparing one pointer, where casting a
/// value out of `Any` asks the runtime what the value conforms to.
private final class SharedValueBox<Value> {
	init(_ value: Value) {
		self.value = value
	}

	let value: Value
}

/// The index of each shared value a writer wrote, by the bytes it was written as, of which it keeps one copy per distinct
/// value for as long as the writer lives.
private struct SharedValueIndicesByBytes {
	/// The index of the value written as `valueBytes`, when one was.
	func index(of valueBytes: UnsafeRawBufferPointer) -> UInt64? {
		guard !slots.isEmpty else { return nil }
		let hash = BinaryFile.checksum(of: valueBytes)
		var slot = Int(truncatingIfNeeded: hash >> 32) & (slots.count - 1)
		while let filled = slots[slot] {
			if filled.hash == hash, filled.length == valueBytes.count,
			   keyBytes.withUnsafeBytes({ UnsafeRawBufferPointer(rebasing: $0[filled.offset..<filled.offset + filled.length]).elementsEqual(valueBytes) })
			{
				return filled.index
			}
			slot = (slot + 1) & (slots.count - 1)
		}
		return nil
	}

	/// Records that the value written as `valueBytes`, which no value was written as before, has `index`.
	mutating func insert(_ index: UInt64, for valueBytes: UnsafeRawBufferPointer) {
		if (count + 1) * 2 > slots.count {
			let filled = slots.compactMap(\.self)
			slots = [Slot?](repeating: nil, count: Swift.max(slots.count * 2, 64))
			for filledSlot in filled {
				place(filledSlot)
			}
		}
		count += 1
		place(Slot(hash: BinaryFile.checksum(of: valueBytes), offset: keyBytes.count, length: valueBytes.count, index: index))
		keyBytes.append(contentsOf: valueBytes)
	}

	private struct Slot {
		let hash: UInt64
		let offset: Int
		let length: Int
		let index: UInt64
	}

	private var slots = [Slot?]()
	private var keyBytes = [UInt8]()
	private var count = 0

	private mutating func place(_ filledSlot: Slot) {
		var slot = Int(truncatingIfNeeded: filledSlot.hash >> 32) & (slots.count - 1)
		while slots[slot] != nil {
			slot = (slot + 1) & (slots.count - 1)
		}
		slots[slot] = filledSlot
	}
}

/// Reads values in SafeDITool's binary format from bytes that ``BinaryWriter/encoded`` produced.
///
/// Every read is checked against the bytes that remain, so bytes that were not written by the same layout
/// throw ``BinaryDecodingError`` rather than trap or read out of bounds.
struct BinaryReader {
	// MARK: Initialization

	/// A reader positioned after the string table at the start of `bytes`.
	/// - Parameters:
	///   - bytes: Memory that outlives the reader.
	///   - decodesStringsUpFront: Whether to decode every string of the table now, as a reader of a whole value does, or
	///     only each string a value names when it is read, as a reader of a few fields does.
	init(bytes: UnsafeRawBufferPointer, decodesStringsUpFront: Bool = true) throws(BinaryDecodingError) {
		self.bytes = bytes
		let stringCount = try readCount()
		if decodesStringsUpFront {
			strings.reserveCapacity(stringCount)
		} else {
			stringRanges.reserveCapacity(stringCount)
		}
		for _ in 0..<stringCount {
			let length = try readCount()
			if decodesStringsUpFront {
				strings.append(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + length]), as: UTF8.self))
			} else {
				stringRanges.append(offset..<offset + length)
			}
			offset += length
		}
		self.decodesStringsUpFront = decodesStringsUpFront
	}

	// MARK: Internal

	/// Far deeper than any type written in practice. Reading bytes that nest without a limit could exhaust the
	/// stack, so a ``BinaryWriter`` notes a value nested more deeply than this, and ``BinaryFile`` refuses to
	/// write a file that holds one rather than write a file no SafeDITool reads. Reading recurses once for each
	/// level, which a debug build of Swift 6.2 or 6.4.2 compiles to about 4.4 KB of stack on Linux (0.6 KB in a
	/// release build), so 32 levels take about 140 KB: under half of the 512 KB stack of a Swift concurrency thread
	/// on Apple platforms, whereas 128 levels overflowed it.
	static let maximumNestingDepth = 32

	/// Throws unless every byte has been read.
	func finish() throws(BinaryDecodingError) {
		guard offset == bytes.count else {
			throw .trailingBytes(offset: offset)
		}
	}

	mutating func read<Value: BinaryCodable>() throws(BinaryDecodingError) -> Value {
		try Value(readingFrom: &self)
	}

	/// Reads the bytes ``BinaryWriter/writeEncoding(_:)`` wrote, without reading what they hold.
	mutating func readEncoding() throws(BinaryDecodingError) -> [UInt8] {
		let count = try readCount()
		let encoding = Array(UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + count]))
		offset += count
		return encoding
	}

	/// Reads the flags a struct writes before its fields (``BinaryWriter/finishFields(_:startingAt:)``).
	mutating func readFieldFlags() throws(BinaryDecodingError) -> BinaryFieldFlagsReader {
		let flagsOffset = offset
		return try BinaryFieldFlagsReader(remaining: readUnsigned(), offset: flagsOffset)
	}

	/// Reads an optional field that ``BinaryWriter/writeOptional(_:flaggedIn:)`` wrote.
	mutating func readOptional<Wrapped: BinaryCodable>(flaggedIn flags: inout BinaryFieldFlagsReader) throws(BinaryDecodingError) -> Wrapped? {
		if flags.next() {
			try read() as Wrapped
		} else {
			nil
		}
	}

	/// Reads a list field that ``BinaryWriter/writeAbsentWhenEmpty(_:flaggedIn:)`` wrote.
	mutating func readAbsentWhenEmpty<Element: BinaryCodable>(flaggedIn flags: inout BinaryFieldFlagsReader) throws(BinaryDecodingError) -> [Element] {
		if flags.next() {
			try read() as [Element]
		} else {
			[]
		}
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

	/// The lines and columns of the positions file of the file being read, with which a location or range the file
	/// stores elsewhere is read; `nil` reads one as stored elsewhere.
	var reattachedPositions: ReattachedPositions?
	/// Whether the reader read a location or range as stored elsewhere, which it does only without ``reattachedPositions``.
	private(set) var readsPositionStoredElsewhere = false
	/// The files of the locations the reader read as stored elsewhere, collected only where it is not `nil`.
	var storedElsewhereFilePaths: Set<String>?

	/// A location as `BinaryWriter.writeLocation(_:)` writes it.
	mutating func readLocation() throws(BinaryDecodingError) -> Dependency.DeclarationLocation {
		let filePath: String = try read()
		let lineOrOrder: Int = try read()
		guard lineOrOrder < 0 else {
			return try Dependency.DeclarationLocation(filePath: filePath, line: lineOrOrder, column: read())
		}
		// Wrapping: a crafted body may hold any value here, and an order nothing pairs with only fails to compare.
		let order = (1 &- lineOrOrder) / 2
		guard lineOrOrder % 2 != 0 else {
			return try Dependency.DeclarationLocation(filePath: filePath, order: order, placement: .here(line: read(), column: read()))
		}
		guard var positions = reattachedPositions else {
			readsPositionStoredElsewhere = true
			storedElsewhereFilePaths?.insert(filePath)
			return Dependency.DeclarationLocation(filePath: filePath, order: order, placement: .storedElsewhere)
		}
		let placement = positions.nextLocation()
		reattachedPositions = positions
		return Dependency.DeclarationLocation(filePath: filePath, order: order, placement: placement)
	}

	/// A range as `BinaryWriter.writeRange(_:)` writes it.
	mutating func readRange() throws(BinaryDecodingError) -> Dependency.SourceRange {
		let startLine: Int = try read()
		guard startLine < 0 else {
			return try Dependency.SourceRange(startLine: startLine, startColumn: read(), endLine: read(), endColumn: read())
		}
		guard var positions = reattachedPositions else {
			readsPositionStoredElsewhere = true
			return Dependency.SourceRange(placement: .storedElsewhere)
		}
		let range = positions.nextRange()
		reattachedPositions = positions
		return range
	}

	mutating func readString() throws(BinaryDecodingError) -> String {
		let indexOffset = offset
		let index = try readUnsigned()
		guard index < UInt64(decodesStringsUpFront ? strings.count : stringRanges.count) else {
			throw .stringIndexOutOfRange(index: index, offset: indexOffset)
		}
		return decodesStringsUpFront
			? strings[Int(index)]
			: String(decoding: UnsafeRawBufferPointer(rebasing: bytes[stringRanges[Int(index)]]), as: UTF8.self)
	}

	/// Reads a value that ``BinaryWriter/writeShared(_:)`` wrote: the value itself where it was first written, and
	/// otherwise the value read there, whose storage every later read shares.
	mutating func readShared<Value: BinaryCodable>() throws(BinaryDecodingError) -> Value {
		let referenceOffset = offset
		let reference = try readUnsigned()
		if reference == 0 {
			let value: Value = try read()
			sharedValues.append(SharedValueBox(value))
			return value
		} else {
			guard reference <= UInt64(sharedValues.count), let box = sharedValues[Int(reference - 1)] as? SharedValueBox<Value> else {
				throw .sharedValueReferenceOutOfRange(reference: reference, offset: referenceOffset)
			}
			return box.value
		}
	}

	/// Whether a value a seam signature repeats is read through ``readSharedByBytes(_:)``, as it is inside
	/// ``readSharingSignatureValues(_:)``.
	private(set) var sharesSignatureValues = false

	/// Reads a list ``BinaryWriter/writeDifference(of:in:)`` wrote. A list that is the whole of the one it differs from
	/// is that list, storage and all, and so is a list written whole that the same bytes wrote before, in any slot.
	mutating func readDifference<Element: BinaryCodable>(in slot: BinaryDifferenceSlot) throws(BinaryDecodingError) -> [Element] {
		guard sharesSignatureValues else {
			return try read()
		}
		return try readDifference(in: slot) { reader throws(BinaryDecodingError) in
			try Element(readingFrom: &reader)
		}
	}

	/// Reads a list ``BinaryWriter/writeDifference(of:in:writingElement:)`` wrote, each element as `readElement` reads
	/// it, which must be the one function that reads lists of `Element` written as differences.
	///
	/// Called only where ``sharesSignatureValues`` holds.
	mutating func readDifference<Element>(in slot: BinaryDifferenceSlot, readingElement readElement: (inout BinaryReader) throws(BinaryDecodingError) -> Element) throws(BinaryDecodingError) -> [Element] {
		let list = try readDifferenceNotYetKept(in: slot, sharingStorageOfRepeats: true, readingElement: readElement)
		keepDifference(list, in: slot)
		return list
	}

	/// Reads a list ``BinaryWriter/writeDifference(of:in:writingElement:)`` wrote without a part of each element, and
	/// then what `readSuffix` reads of that part, given the list's count, which `apply` sets in every element of the
	/// list: a list's elements come from the list it differs from, so each holds that list's part until then.
	///
	/// The list read is changed in place where nothing else holds it, so its elements are held once, and the list made
	/// before of the same storage and the same bytes of the part is handed back, so that lists that hold the same values
	/// are one storage. The elements of a list written in this way are longer than a difference's four numbers, so
	/// the same list is never written whole twice, and a list read whole is kept by nothing else.
	///
	/// Called only where ``sharesSignatureValues`` holds.
	mutating func readDifference<Element, Suffix>(
		in slot: BinaryDifferenceSlot,
		readingElement readElement: (inout BinaryReader) throws(BinaryDecodingError) -> Element,
		readingSuffix readSuffix: (inout BinaryReader, Int) throws(BinaryDecodingError) -> Suffix,
		applying apply: (Suffix, inout [Element]) -> Void,
	) throws(BinaryDecodingError) -> [Element] {
		var list = try readDifferenceNotYetKept(in: slot, sharingStorageOfRepeats: false, readingElement: readElement)
		let suffixOffset = offset
		let suffix = try readSuffix(&self, list.count)
		// The lists read as differences are held as long as the reader, so an address names one list.
		let suffixBytes = [UInt8](UnsafeRawBufferPointer(rebasing: bytes[suffixOffset..<offset]))
		let key = ListWithSuffixKey(storage: list.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }, suffixBytes: suffixBytes)
		if let listReadBefore = listsWithSuffix[key] as? [Element] {
			list = listReadBefore
		} else {
			apply(suffix, &list)
			listsWithSuffix[key] = list
			// Where setting the part copied the list, the copy is the list a later one is the whole of.
			listsWithSuffix[ListWithSuffixKey(storage: list.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }, suffixBytes: suffixBytes)] = list
		}
		keepDifference(list, in: slot)
		return list
	}

	private struct ListWithSuffixKey: Hashable {
		let storage: UInt
		let suffixBytes: [UInt8]
	}

	/// Each list ``readDifference(in:readingElement:readingSuffix:applying:)`` read, by the storage it was made of or is
	/// held in and the bytes of the part read after it, for as long as the reader lives: a reference and those few
	/// bytes per list.
	private var listsWithSuffix = [ListWithSuffixKey: Any]()

	/// Keeps `list` as one a later list of `slot` may differ from, as the writer keeps every list but an empty one.
	private mutating func keepDifference(_ list: [some Any], in slot: BinaryDifferenceSlot) {
		guard !list.isEmpty else {
			return
		}
		listDifferencesRead += 1
		listsReadBySlot[slot, default: []].append(list)
	}

	private mutating func readDifferenceNotYetKept<Element>(in slot: BinaryDifferenceSlot, sharingStorageOfRepeats: Bool, readingElement readElement: (inout BinaryReader) throws(BinaryDecodingError) -> Element) throws(BinaryDecodingError) -> [Element] {
		let headerOffset = offset
		let header = try readUnsigned()
		// An empty list is no list a later one differs from, so a value that holds only empty lists reads the same
		// wherever its bytes come again.
		guard header > 0 else {
			return []
		}
		if header & 1 == 0 {
			func readWhole(_ reader: inout BinaryReader) throws(BinaryDecodingError) -> ListWrittenWhole<Element> {
				let count = try reader.readUnsigned() >> 1
				guard count <= UInt64(reader.bytes.count - reader.offset) else {
					throw .countExceedsRemainingBytes(count: count, offset: headerOffset)
				}
				var elements = [Element]()
				elements.reserveCapacity(Int(count))
				for _ in 0..<count {
					try elements.append(readElement(&reader))
				}
				return ListWrittenWhole(elements: elements)
			}
			offset = headerOffset
			if sharingStorageOfRepeats {
				// Its bytes say all of it, so the same bytes are the same list, as any list a signature repeats.
				return try readSharingStorageOfRepeats(readWhole).elements
			} else {
				return try readWhole(&self).elements
			}
		} else {
			let unsharedCount = header >> 1
			let history = listsReadBySlot[slot] ?? []
			let distance = try readUnsigned()
			let sharedAtStart = try readUnsigned()
			let sharedAtEnd = try readUnsigned()
			guard distance >= 1, distance <= UInt64(history.count), let other = history[history.count - Int(distance)] as? [Element], sharedAtStart <= UInt64(other.count), sharedAtEnd <= UInt64(other.count) - sharedAtStart else {
				throw .sharedValueReferenceOutOfRange(reference: distance, offset: headerOffset)
			}
			if unsharedCount == 0, sharedAtStart + sharedAtEnd == UInt64(other.count) {
				return other
			} else {
				guard unsharedCount <= UInt64(bytes.count - offset) else {
					throw .countExceedsRemainingBytes(count: unsharedCount, offset: headerOffset)
				}
				// Exactly as long as the list: a list grown as it is read holds up to twice its elements.
				var elements = [Element]()
				elements.reserveCapacity(Int(sharedAtStart) + Int(unsharedCount) + Int(sharedAtEnd))
				elements.append(contentsOf: other[..<Int(sharedAtStart)])
				for _ in 0..<unsharedCount {
					try elements.append(readElement(&self))
				}
				elements.append(contentsOf: other[(other.count - Int(sharedAtEnd))...])
				return elements
			}
		}
	}

	/// A list ``readDifference(in:readingElement:)`` read whole, which ``readSharingStorageOfRepeats(_:)`` keeps apart
	/// from a plain list of the same elements, whose bytes say something else.
	private struct ListWrittenWhole<Element> {
		let elements: [Element]
	}

	/// Every list ``readDifference(in:)`` read that is not empty, by slot, for as long as the reader lives, which is one
	/// module's signatures or plans. The signatures read hold the same storage, so this holds one reference per list,
	/// but for the labels a case binds later, which the signature keeps as a set, and which it so holds a second copy of.
	private var listsReadBySlot = [BinaryDifferenceSlot: [Any]]()
	/// How many lists ``readDifference(in:)`` read that are not empty: a value that holds one is not one
	/// ``readSharingStorageOfRepeats(_:)`` hands back for the same bytes, since what those bytes say depends on the
	/// lists read before, and the lists read after depend on its being read.
	private var listDifferencesRead = 0

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
			sharedValues.append(SharedValueBox(value))
			return value
		} else {
			guard reference <= UInt64(sharedValues.count), let box = sharedValues[Int(reference - 1)] as? SharedValueBox<Value> else {
				throw .sharedValueReferenceOutOfRange(reference: reference, offset: referenceOffset)
			}
			return box.value
		}
	}

	/// Reads a value inside a seam signature as `read` reads it, or hands back the value read before from the same bytes
	/// elsewhere without reading it again: a signature repeats the same lists at thousands of places, and each copy of a
	/// list of hole fields is hundreds of bytes for every field.
	///
	/// Only a value whose reading added no shared value is handed back, so the same bytes read as the same value, of the
	/// same length, and reading them again would change nothing else. A value of fewer than eight bytes is found by those
	/// bytes; a longer one by its first eight, which give the lengths of the values that begin with them, and then by the
	/// checksum of that many bytes, which are compared.
	///
	/// Called only where ``sharesSignatureValues`` holds.
	mutating func readSharingStorageOfRepeats<Value>(_ read: (inout BinaryReader) throws(BinaryDecodingError) -> Value) throws(BinaryDecodingError) -> Value {
		let start = offset
		let type = UInt64(UInt(bitPattern: ObjectIdentifier(Value.self)))
		let leadingByteCount = Swift.min(bytes.count - start, 8)
		var leadingBytes: UInt64 = 0
		withUnsafeMutableBytes(of: &leadingBytes) { $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[start..<start + leadingByteCount])) }
		let leadingKey = RepeatableValueKey(bytes: leadingBytes, length: 8, type: type)
		let lengths = leadingByteCount == 8 ? lengthsOfRepeatableValuesByLeadingBytes.value(for: leadingKey) ?? [] : []
		for length in lengths where start + length <= bytes.count {
			if let value: Value = repeatableValue(readFrom: start, length: length, type: type) {
				offset = start + length
				return value
			}
		}
		var shorterLength = Swift.min(leadingByteCount, 7)
		while shorterLength >= 2 {
			if let value: Value = repeatableValue(readFrom: start, length: shorterLength, type: type) {
				offset = start + shorterLength
				return value
			}
			shorterLength -= 1
		}
		let sharedValueCount = sharedValues.count
		let listDifferencesReadBefore = listDifferencesRead
		let value = try read(&self)
		let length = offset - start
		guard sharedValues.count == sharedValueCount, listDifferencesRead == listDifferencesReadBefore, length >= 2 else {
			return value
		}
		// Found now only when too many lengths of values begin with its first bytes for it to be found before it was read.
		if let valueReadBefore: Value = repeatableValue(readFrom: start, length: length, type: type) {
			return valueReadBefore
		}
		repeatableValues.setValue((start, SharedValueBox(value)), for: repeatableValueKey(ofBytesAt: start, length: length, type: type))
		if length >= 8, lengths.count < Self.maximumLengthsOfRepeatableValuesWithSameLeadingBytes, !lengths.contains(length) {
			lengthsOfRepeatableValuesByLeadingBytes.setValue(lengths + [length], for: leadingKey)
		}
		return value
	}

	/// The value of `Value` read before from the same `length` bytes as those at `start`, when one was.
	private func repeatableValue<Value>(readFrom start: Int, length: Int, type: UInt64) -> Value? {
		guard let read = repeatableValues.value(for: repeatableValueKey(ofBytesAt: start, length: length, type: type)),
		      UnsafeRawBufferPointer(rebasing: bytes[read.start..<read.start + length]).elementsEqual(UnsafeRawBufferPointer(rebasing: bytes[start..<start + length]))
		else { return nil }
		return (read.box as? SharedValueBox<Value>)?.value
	}

	/// What a value of `length` bytes at `start` is found by: the bytes themselves when they are fewer than eight, and
	/// otherwise their checksum.
	private func repeatableValueKey(ofBytesAt start: Int, length: Int, type: UInt64) -> RepeatableValueKey {
		let valueBytes = UnsafeRawBufferPointer(rebasing: bytes[start..<start + length])
		if length < 8 {
			var shortBytes: UInt64 = 0
			withUnsafeMutableBytes(of: &shortBytes) { $0.copyMemory(from: valueBytes) }
			return RepeatableValueKey(bytes: shortBytes, length: UInt64(length), type: type)
		} else {
			return RepeatableValueKey(bytes: BinaryFile.checksum(of: valueBytes), length: UInt64(length), type: type)
		}
	}

	/// How many lengths of values that begin with the same eight bytes are tried before a value is read.
	private static var maximumLengthsOfRepeatableValuesWithSameLeadingBytes: Int {
		8
	}

	/// Reads a value written as a string and then a value shared by its bytes, as `read` reads it, and hands the same
	/// value back wherever the same string and the same shared value follow again: a signature names a few hundred
	/// distinct properties hundreds of thousands of times, and a property hashes its type when it is made.
	mutating func readSharingValuesOfOneStringAndSharedValue<Value>(_ read: (inout BinaryReader) throws(BinaryDecodingError) -> Value) throws(BinaryDecodingError) -> Value {
		let start = offset
		let stringIndex = try readUnsigned()
		let reference = try readUnsigned()
		// A reference of 0 is followed by the value itself, written there for the first time.
		guard sharesSignatureValues, reference != 0 else {
			offset = start
			return try read(&self)
		}
		let key = UnsignedPair(first: stringIndex, second: reference)
		if let box = valuesByStringAndSharedValue.value(for: key) as? SharedValueBox<Value> {
			return box.value
		} else {
			offset = start
			let value = try read(&self)
			valuesByStringAndSharedValue.setValue(SharedValueBox(value), for: key)
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
	private(set) var offset = 0
	private var strings = [String]()
	/// Where each string of the table lies, for a reader that decodes a string only when a value names it.
	private var stringRanges = [Range<Int>]()
	private var decodesStringsUpFront = true
	private var sharedValues = [AnyObject]()
	private var valuesByStringAndSharedValue = TableByWords<UnsignedPair, AnyObject>()
	/// Each value ``readSharingStorageOfRepeats(_:)`` read and can hand back, with where its bytes start: by its bytes when
	/// they are fewer than eight, and otherwise by their checksum. One box per distinct value, for as long as the reader
	/// lives.
	private var repeatableValues = TableByWords<RepeatableValueKey, (start: Int, box: AnyObject)>()
	/// The lengths of the values in `repeatableValues` of eight bytes or more, by their first eight bytes.
	private var lengthsOfRepeatableValuesByLeadingBytes = TableByWords<RepeatableValueKey, [Int]>()
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

/// The optional and Boolean fields of a struct, one bit each in the order the struct writes them: whether an optional
/// field holds a value, and a Boolean field's value. A struct writes them as one integer before its fields, in place of a
/// byte for each such field.
struct BinaryFieldFlags {
	private(set) var bits: UInt64 = 0

	mutating func append(_ flag: Bool) {
		if flag {
			bits |= 1 << count
		}
		count += 1
	}

	private var count: UInt64 = 0
}

/// The flags ``BinaryReader/readFieldFlags()`` read, taken in the order they were written.
struct BinaryFieldFlagsReader {
	fileprivate init(remaining: UInt64, offset: Int) {
		self.remaining = remaining
		self.offset = offset
	}

	mutating func next() -> Bool {
		let flag = remaining & 1 == 1
		remaining >>= 1
		return flag
	}

	/// Throws when the flags hold a flag the struct does not have.
	func finish() throws(BinaryDecodingError) {
		guard remaining == 0 else {
			throw .unreadFieldFlags(offset: offset)
		}
	}

	private var remaining: UInt64
	private let offset: Int
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
	case unreadFieldFlags(offset: Int)
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

extension UInt64: BinaryCodable {
	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		self = try reader.readUnsigned()
	}

	func write(to writer: inout BinaryWriter) {
		writer.writeUnsigned(self)
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
		// A list inside a type description, which nests, is read in this frame alone: a type's lists are never shared.
		if reader.sharesSignatureValues {
			self = try reader.readSharingStorageOfRepeats { reader throws(BinaryDecodingError) in
				try [Element](readingElementsFrom: &reader)
			}
		} else {
			let count = try reader.readCount()
			self.init()
			reserveCapacity(count)
			for _ in 0..<count {
				try append(Element(readingFrom: &reader))
			}
		}
	}

	private init(readingElementsFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
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

/// Bytes another writer encoded (``BinaryWriter/encoded``), written behind their length, so that a reader keeps them
/// without reading what they hold and decodes them later with a reader of their own.
struct BinaryEncoding: BinaryCodable {
	let bytes: [UInt8]

	init(bytes: [UInt8]) {
		self.bytes = bytes
	}

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		bytes = try reader.readEncoding()
	}

	func write(to writer: inout BinaryWriter) {
		writer.writeEncoding(bytes)
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

/// The lists a seam signature or a public mock plan writes as differences (``BinaryWriter/writeDifference(of:in:)``):
/// a list differs from one written before in its own slot.
enum BinaryDifferenceSlot: Hashable {
	/// The fields bound before a place: `SeamSignature.Hole.fields`, `SeamSignature.Hole.EnumPlace.values` and
	/// `SeamSignature.ScopeEnum.Values.fields`, which hold the same list for one place.
	case fields
	/// `SeamSignature.Hole.uncarriedDeclarations`, each without `builtAfter`.
	case uncarriedDeclarations
	/// `SeamSignature.ScopeEnum.Values.labelsBoundLater`, sorted.
	case labelsBoundLater
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
