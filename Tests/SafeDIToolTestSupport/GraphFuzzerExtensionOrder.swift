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

import SwiftParser
import SwiftSyntax

/// What a renamed graph's generated file may reorder: its extensions, read from the file's syntax so that text that only
/// looks like an extension or a conditional block – in a string, in a comment, or spelled unusually – is what it is.
enum GraphFuzzerExtensionOrder {
	/// The UTF-8 of `code` with the movable declarations of each run sorted among the places those declarations hold, and
	/// every other byte where it was, which says whether two files differ only in the order they declare their
	/// extensions. A file that does not parse is returned as it is.
	///
	/// A movable declaration is one of:
	/// - A top-level extension, with the forwarders of its defaults (`@usableFromInline` functions) on the lines right
	///   after it.
	/// - A public mock's module-level configuration: its struct, documented `/// Configuration for how …`, with the
	///   extension right after it and that extension's forwarders, as one unit, which may take the place of an extension.
	/// - Such a struct with no extension after it, as decomposing a module's combined output leaves it, which may take
	///   the place only of another such struct.
	///
	/// Only whitespace may separate the declarations of a run, and any other declaration or comment ends it, except that a
	/// run goes on from a top-level `#if` block with no other clause into the first clause of the next block, when only
	/// whitespace separates them and the two blocks' `#if` conditions are spelled identically: whichever of those places
	/// holds an extension, the same builds compile it. A generated file's mock code and configurations hold one condition,
	/// the module's mock condition, and a module's combined output holds a block of it for each mock root's own
	/// configuration. The places stay where they are, so how many extensions each block holds is still compared.
	static func sortingExtensionsWithinTheirPlaces(in code: String) -> [UInt8] {
		let source = Array(code.utf8)
		let file = Parser.parse(source: code)
		guard !file.hasError else { return source }
		var collector = RunCollector(source: source)
		collector.visit(file.statements, isTopLevel: true)
		collector.endRun()
		return collector.sourceWithRunsSorted
	}

	/// Finds the runs of movable declarations of one file, in the order of the file.
	private struct RunCollector {
		init(source: [UInt8]) {
			self.source = source
		}

		mutating func visit(_ statements: CodeBlockItemListSyntax, isTopLevel: Bool) {
			for statement in statements {
				if let block = IfConfigDeclSyntax(statement.item) {
					visit(block, isTopLevel: isTopLevel)
				} else if ExtensionDeclSyntax(statement.item) != nil {
					addExtension(statement)
				} else if let configuration = StructDeclSyntax(statement.item), let documentationStart = configurationDocumentationStart(of: configuration) {
					addConfigurationStruct(statement, startingAt: documentationStart)
				} else if isForwarder(statement), canExtendLastDeclaration(with: statement) {
					run[run.count - 1].range = run[run.count - 1].range.lowerBound..<end(of: statement)
					position = end(of: statement)
				} else {
					endRun()
					closedBlockCondition = nil
					position = end(of: statement)
				}
			}
		}

		/// Ends the current run and records how its declarations are sorted among their places.
		mutating func endRun() {
			for kind in Declaration.Kind.allCases {
				let places = run.filter { $0.kind == kind }.map(\.range)
				let contents = places.sorted { source[$0].lexicographicallyPrecedes(source[$1]) }
				replacements += zip(places, contents).map { (place: $0, content: $1) }
			}
			run = []
		}

		/// The source with each place's bytes replaced by the bytes of the declaration sorted into it.
		var sourceWithRunsSorted: [UInt8] {
			var result = [UInt8]()
			var copiedUpTo = 0
			for replacement in replacements.sorted(by: { $0.place.lowerBound < $1.place.lowerBound }) {
				result += source[copiedUpTo..<replacement.place.lowerBound]
				result += source[replacement.content]
				copiedUpTo = replacement.place.upperBound
			}
			return result + source[copiedUpTo...]
		}

		private struct Declaration {
			/// Only declarations of one kind take each other's places.
			enum Kind: CaseIterable {
				/// An extension, or a public configuration's struct with its extension.
				case extensionOrConfiguration
				/// A public configuration's struct with no extension after it.
				case configurationStruct
			}

			var kind: Kind
			var range: Range<Int>
		}

		private let source: [UInt8]
		private var run = [Declaration]()
		private var replacements = [(place: Range<Int>, content: Range<Int>)]()
		/// The offset just past the last element visited.
		private var position = 0
		/// The `#if` line of the block that closed before `position` with only whitespace since, when a run can go on from
		/// that block.
		private var closedBlockCondition: [UInt8]?

		private mutating func visit(_ block: IfConfigDeclSyntax, isTopLevel: Bool) {
			var firstCondition: [UInt8]?
			for (index, clause) in block.clauses.enumerated() {
				let clauseStart = clause.poundKeyword.positionAfterSkippingLeadingTrivia.utf8Offset
				crossGap(to: clauseStart)
				let headerEnd = (clause.condition?.endPositionBeforeTrailingTrivia ?? clause.poundKeyword.endPositionBeforeTrailingTrivia).utf8Offset
				if index == 0 {
					let condition = Array(source[clauseStart..<headerEnd])
					firstCondition = condition
					if condition != closedBlockCondition {
						endRun()
					}
					closedBlockCondition = nil
				} else {
					endRun()
				}
				position = headerEnd
				if case let .statements(statements) = clause.elements {
					visit(statements, isTopLevel: false)
				}
			}
			crossGap(to: block.poundEndif.positionAfterSkippingLeadingTrivia.utf8Offset)
			position = block.poundEndif.endPositionBeforeTrailingTrivia.utf8Offset
			if isTopLevel, block.clauses.count == 1 {
				closedBlockCondition = firstCondition
			} else {
				endRun()
				closedBlockCondition = nil
			}
		}

		private mutating func addExtension(_ statement: CodeBlockItemSyntax) {
			let adjoinsLastDeclaration = run.last?.range.upperBound == position
			crossGap(to: start(of: statement))
			// An extension right after a block is outside it, so it takes the place of none inside the block.
			if closedBlockCondition != nil {
				endRun()
				closedBlockCondition = nil
			}
			if adjoinsLastDeclaration, let last = run.last, last.kind == .configurationStruct {
				run[run.count - 1] = Declaration(kind: .extensionOrConfiguration, range: last.range.lowerBound..<end(of: statement))
			} else {
				run.append(Declaration(kind: .extensionOrConfiguration, range: start(of: statement)..<end(of: statement)))
			}
			position = end(of: statement)
		}

		private mutating func addConfigurationStruct(_ statement: CodeBlockItemSyntax, startingAt documentationStart: Int) {
			crossGap(to: documentationStart)
			if closedBlockCondition != nil {
				endRun()
				closedBlockCondition = nil
			}
			run.append(Declaration(kind: .configurationStruct, range: documentationStart..<end(of: statement)))
			position = end(of: statement)
		}

		/// Ends the run unless only whitespace lies between `position` and `offset`.
		private mutating func crossGap(to offset: Int) {
			if !source[position..<offset].allSatisfy(Self.isWhitespace) {
				endRun()
				closedBlockCondition = nil
			}
			position = offset
		}

		/// Whether `statement` is on the line right after the extension or configuration that ends at `position`.
		private func canExtendLastDeclaration(with statement: CodeBlockItemSyntax) -> Bool {
			run.last?.kind == .extensionOrConfiguration
				&& run.last?.range.upperBound == position
				&& source[position..<start(of: statement)].elementsEqual([Self.newline])
		}

		private func isForwarder(_ statement: CodeBlockItemSyntax) -> Bool {
			FunctionDeclSyntax(statement.item)?.attributes.contains { attribute in
				attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "usableFromInline"
			} == true
		}

		/// The offset of the `/// Configuration for how` documentation directly above `declaration`, or `nil` when it has none.
		private func configurationDocumentationStart(of declaration: StructDeclSyntax) -> Int? {
			var offset = declaration.position.utf8Offset
			var documentationStart: Int?
			for piece in declaration.leadingTrivia {
				if case let .docLineComment(text) = piece {
					documentationStart = text.hasPrefix("/// Configuration for how ") ? offset : nil
				} else if !piece.isWhitespace {
					documentationStart = nil
				}
				offset += piece.sourceLength.utf8Length
			}
			return documentationStart
		}

		private func start(of statement: CodeBlockItemSyntax) -> Int {
			statement.positionAfterSkippingLeadingTrivia.utf8Offset
		}

		private func end(of statement: CodeBlockItemSyntax) -> Int {
			statement.endPositionBeforeTrailingTrivia.utf8Offset
		}

		private static func isWhitespace(_ byte: UInt8) -> Bool {
			byte == newline || byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r")
		}

		private static let newline = UInt8(ascii: "\n")
	}
}
