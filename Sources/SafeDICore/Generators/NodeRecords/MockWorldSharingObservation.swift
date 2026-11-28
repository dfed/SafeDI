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

/// What a test observes of sharing between a module's mock worlds, where it sets `observer`. The declarations several
/// mock roots reach live in one module-wide shared graph; the record of each of its variants a world reaches (a row) is
/// made once, and every world that reaches the row takes that one record, building only its own top graph's records.
/// A world that cannot take rows is built whole, as it is with no sharing.
///
/// The mock worlds' pre-pass fills the report, once per module's mock generation, after every world is built: where
/// `observer` is set it also builds each world whole, without rows, and compares that world's records with the records
/// it holds with sharing (`MockWorldSharingReport.differences`). Only a test sets it.
public enum MockWorldSharingObservation {
	/// Handed the sharing report of each module's mock generation, where set. Only a test sets it.
	@TaskLocal public static var observer: (@Sendable (MockWorldSharingReport) -> Void)?
}

/// The rows a module's mock worlds share, what each world built and took, and every way sharing changed a world's records
/// (`MockWorldSharingObservation`). Made only by the mock worlds' pre-pass.
public struct MockWorldSharingReport: Equatable, Sendable {
	/// One shared record: a variant of the shared graph, with the answers its record read of the names a mock root
	/// decides (`MockRootNames`). Two worlds whose roots answer those questions alike take one row; a root that answers
	/// one of them otherwise makes a row of its own of the same variant.
	public struct Row: Equatable, Sendable {
		/// The row's declaration: its position among the shared graph's declarations, numbered from 0 in the order the
		/// worlds first meet them (worlds in the order of `worlds`, each walked from its root, parent before child, children
		/// in declaration order). Two rows of one declaration share the number.
		public let declaration: Int
		/// The label of the row's property.
		public let label: String
		/// The type of the row's property, as the declaration spells it.
		public let type: String
		/// Whether every parent of the row's declaration, in every world that takes the row, is that world's root.
		public let isEveryParentTheRoot: Bool
		/// Each question the row's record asked of a mock root's names (`MockRootNames`) with the answer it read, in the
		/// order it asked them, each spelled `question: answer`: empty where the record read none.
		public let namesRead: [String]
	}

	/// Why a world takes no row and is built whole, as it is with no sharing.
	public enum BuiltWholeReason: String, Equatable, Sendable {
		/// Node records refuse the world (`NodeRecordRefusal`), so it holds no records to share.
		case recordsRefused
		/// The world's root is on a cycle, which is the world's own.
		case rootOnCycle
		/// The root of a public mock or of a seam reaches a hole, a place its builder fills.
		case rootReachesHole
		/// The world reaches a variant of the shared graph that is no row.
		case reachesSharedVariantThatIsNoRow
		/// The world reaches two variants of one shared declaration that differ only in the class a read is offered (a
		/// root statement, a parameter, or nothing): built whole, the world joins their calls into one variant, whose
		/// outcome neither shared variant has.
		case callsSharedDeclarationInOtherClasses
	}

	/// One mock root's world.
	public struct World: Equatable, Sendable {
		/// The mocked type.
		public let mockedType: String
		/// Why the world was built whole, or `nil` where it is clean: it built its top graph and took rows.
		public let builtWholeReason: BuiltWholeReason?
		/// How many records the world made itself: one per variant of its top graph but its root's and the rows', or, for
		/// a world built whole, `recordCountBuiltWhole`.
		public let ownRecordCount: Int
		/// How many rows' records the world took: those at the top of each shared subtree it reaches, since a row's record
		/// holds the records beneath it. Zero for a world built whole.
		public let sharedRecordCount: Int
		/// How many records the same world makes when it is built whole: one per variant of its whole graph but its root's.
		public let recordCountBuiltWhole: Int
	}

	/// Each row, in the order the worlds first meet it (as `Row.declaration` orders declarations).
	public let rows: [Row]
	/// Each world, in the order the module lowers its mock roots.
	public let worlds: [World]
	/// Each way a world's records with sharing differ from the records of the same world built whole, record content
	/// compared field by field as `NodeRecordsObservation` compares records, each line starting with the mocked type:
	/// empty where sharing changed nothing. A test fails on any.
	public let differences: [String]
}
