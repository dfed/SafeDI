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
import Testing

/// The differential of shared hole subtrees, kept until review: every signature pass of every seam is computed once more
/// over a tree that shares no place holding a hole between the paths of the seam's tree
/// (`SeamSignatureObservation.comparesUnsharedTrees`), and the two must encode to the same bytes, or throw the same error.
enum UnsharedTreeChecks {
	/// An observer that records an issue for each pass whose unshared computation found another signature or another
	/// error, then hands the comparison to `enclosingObserver`.
	static func recordingDifferences(handingOn enclosingObserver: (@Sendable (UnsharedTreeComparison) -> Void)?) -> @Sendable (UnsharedTreeComparison) -> Void {
		{ comparison in
			// The two are compared as the bytes of a streamed encoding, which holds no tree of the values: a signature of a
			// seam reached along hundreds of paths spelled as JSON held gigabytes while it was encoded. Only a difference
			// is spelled as JSON.
			if bytes(of: comparison.shared) != bytes(of: comparison.unshared) {
				Issue.record(Comment(rawValue: """
				A signature pass of \(comparison.seamType.asSource) found otherwise over a tree that shares no hole subtree:
				shared:   \(spelled(comparison.shared))
				unshared: \(spelled(comparison.unshared))
				"""))
			}
			enclosingObserver?(comparison)
		}
	}

	private static func bytes(of outcome: UnsharedTreeComparison.Outcome) -> [UInt8]? {
		switch outcome {
		case let .found(signature):
			let encoder = StreamingEncoder()
			// A signature encodes whatever it holds; an encoding failure is itself a difference worth seeing.
			guard (try? signature.encode(to: encoder)) != nil else { return nil }
			return encoder.sink.bytes
		case let .threw(description):
			return Array("threw \(description)".utf8)
		}
	}

	private static func spelled(_ outcome: UnsharedTreeComparison.Outcome) -> String {
		switch outcome {
		case let .found(signature):
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			guard let data = try? encoder.encode(signature) else { return "(unencodable)" }
			return String(decoding: data, as: UTF8.self)
		case let .threw(description):
			return "threw \(description)"
		}
	}
}

/// An encoder that writes every key and value to one byte stream as it is encoded, each nested value bracketed, so two
/// values encode to the same bytes exactly when they encode alike.
private final class StreamingEncoder: Encoder {
	final class Sink {
		var bytes = [UInt8]()

		func write(tag: UInt8, _ text: String) {
			bytes.append(tag)
			let utf8 = Array(text.utf8)
			bytes.append(contentsOf: String(utf8.count).utf8)
			bytes.append(0x3A)
			bytes.append(contentsOf: utf8)
		}

		func encodeNested(_ value: some Encodable, encoder: StreamingEncoder) throws {
			bytes.append(0x28)
			try value.encode(to: encoder)
			bytes.append(0x29)
		}
	}

	init(sink: Sink = Sink()) {
		self.sink = sink
	}

	let sink: Sink
	var codingPath: [any CodingKey] { [] }
	var userInfo: [CodingUserInfoKey: Any] { [:] }

	func container<Key: CodingKey>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> {
		sink.write(tag: 0x7B, "")
		return KeyedEncodingContainer(KeyedContainer<Key>(encoder: self))
	}

	func unkeyedContainer() -> any UnkeyedEncodingContainer {
		sink.write(tag: 0x5B, "")
		return UnkeyedContainer(encoder: self)
	}

	func singleValueContainer() -> any SingleValueEncodingContainer {
		SingleValueContainer(encoder: self)
	}

	private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
		let encoder: StreamingEncoder
		var codingPath: [any CodingKey] { [] }

		mutating func encodeNil(forKey key: Key) throws {
			encoder.sink.write(tag: 0x6B, key.stringValue)
			encoder.sink.write(tag: 0x30, "")
		}

		mutating func encode(_ value: some Encodable, forKey key: Key) throws {
			encoder.sink.write(tag: 0x6B, key.stringValue)
			try encoder.sink.encodeNested(value, encoder: encoder)
		}

		mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
			encoder.sink.write(tag: 0x6B, key.stringValue)
			return encoder.container(keyedBy: keyType)
		}

		mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
			encoder.sink.write(tag: 0x6B, key.stringValue)
			return encoder.unkeyedContainer()
		}

		mutating func superEncoder() -> any Encoder {
			encoder
		}

		mutating func superEncoder(forKey key: Key) -> any Encoder {
			encoder.sink.write(tag: 0x6B, key.stringValue)
			return encoder
		}
	}

	private struct UnkeyedContainer: UnkeyedEncodingContainer {
		let encoder: StreamingEncoder
		var codingPath: [any CodingKey] { [] }
		var count = 0

		mutating func encodeNil() throws {
			count += 1
			encoder.sink.write(tag: 0x30, "")
		}

		mutating func encode(_ value: some Encodable) throws {
			count += 1
			try encoder.sink.encodeNested(value, encoder: encoder)
		}

		mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
			count += 1
			return encoder.container(keyedBy: keyType)
		}

		mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
			count += 1
			return encoder.unkeyedContainer()
		}

		mutating func superEncoder() -> any Encoder {
			count += 1
			return encoder
		}
	}

	private struct SingleValueContainer: SingleValueEncodingContainer {
		let encoder: StreamingEncoder
		var codingPath: [any CodingKey] { [] }

		mutating func encodeNil() throws {
			encoder.sink.write(tag: 0x30, "")
		}

		mutating func encode(_ value: Bool) throws {
			encoder.sink.write(tag: 0x62, value ? "1" : "0")
		}

		mutating func encode(_ value: String) throws {
			encoder.sink.write(tag: 0x73, value)
		}

		mutating func encode(_ value: Double) throws {
			encoder.sink.write(tag: 0x64, "\(value.bitPattern)")
		}

		mutating func encode(_ value: Float) throws {
			encoder.sink.write(tag: 0x66, "\(value.bitPattern)")
		}

		mutating func encode(_ value: Int) throws {
			encoder.sink.write(tag: 0x69, "\(value)")
		}

		mutating func encode(_ value: Int8) throws {
			encoder.sink.write(tag: 0x69, "\(value)")
		}

		mutating func encode(_ value: Int16) throws {
			encoder.sink.write(tag: 0x69, "\(value)")
		}

		mutating func encode(_ value: Int32) throws {
			encoder.sink.write(tag: 0x69, "\(value)")
		}

		mutating func encode(_ value: Int64) throws {
			encoder.sink.write(tag: 0x69, "\(value)")
		}

		mutating func encode(_ value: UInt) throws {
			encoder.sink.write(tag: 0x75, "\(value)")
		}

		mutating func encode(_ value: UInt8) throws {
			encoder.sink.write(tag: 0x75, "\(value)")
		}

		mutating func encode(_ value: UInt16) throws {
			encoder.sink.write(tag: 0x75, "\(value)")
		}

		mutating func encode(_ value: UInt32) throws {
			encoder.sink.write(tag: 0x75, "\(value)")
		}

		mutating func encode(_ value: UInt64) throws {
			encoder.sink.write(tag: 0x75, "\(value)")
		}

		mutating func encode(_ value: some Encodable) throws {
			try encoder.sink.encodeNested(value, encoder: encoder)
		}
	}
}
