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

/// The run's IDs of what an entry of the mock worlds' table (`MockWorldsTable`) names across worlds. A value's ID is its
/// position in the list of values in the order the table's one walk first met them, over the mock roots' worlds in the
/// order the module lowers its mock roots: never hash order, and never an order of identities. A declaration's key holds
/// its record's identity, which finds the declaration's ID and orders nothing.
///
/// It stands in for the run-wide IDs (steps 3 and 4 of the run IDs plan), and is the one file replaced when they land:
/// nothing outside the table reads it. It interns declarations alone, the only values the table names so far; labels,
/// properties, types and answer text join it when the table's entries name them.
///
/// It holds each declaration it is handed, and so the declaration's record, which keeps any other record from taking the
/// address a key holds, for as long as the table that owns it lives: one `generate` run's mock generation.
struct RunFactsInterning: Sendable {
	/// Gives each declaration, in order, the next ID; a declaration equal to one met before keeps that one's.
	init(declarationsInFirstReachOrder declarations: some Sequence<TypeFactsDeclaration>) {
		for declaration in declarations {
			_ = declarationIDs.id(of: declaration)
		}
	}

	/// How many distinct declarations, by key, the walk met.
	var declarationCount: Int {
		declarationIDs.values.count
	}

	/// The ID of the declaration whose key equals `declaration`'s, or `nil` where the walk never met one.
	func declarationID(of declaration: TypeFactsDeclaration) -> Int32? {
		declarationIDs.existingID(of: declaration)
	}

	/// The declaration whose ID is `id`, one this interning gave.
	func declaration(ofID id: Int32) -> TypeFactsDeclaration {
		declarationIDs.values[Int(id)]
	}

	private var declarationIDs = TypeFactsInterner<TypeFactsDeclaration>()
}
