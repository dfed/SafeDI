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

extension NodeRecords {
	/// `inlineSeam` where `declaration` is a seam of another module built inline (`ConstructionScope.builtInlineSeamComment`)
	/// and is otherwise a node `builtByInitializer` makes, `nil` for any other node.
	/// - Throws: The refusal `checkBuiltByInitializer(_:in:admittingInlineSeam:)` finds for a seam built inline that is no
	///   such node.
	static func inlineSeamKind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind? {
		guard world.scope(of: declaration).builtInlineSeamComment != nil else { return nil }
		try checkBuiltByInitializer(declaration, in: world, admittingInlineSeam: true)
		return .inlineSeam
	}

	/// The record of `declaration`'s place, a node of kind `inlineSeam`: `builtByInitializerRecord`'s, with the comment that
	/// ends the line constructing the type, as the tree writes a seam built inline.
	static func inlineSeamRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		// Never `nil`: the node is of kind `inlineSeam` (`inlineSeamKind(of:in:)`).
		let comment = world.scope(of: declaration).builtInlineSeamComment.map { " \($0)" } ?? ""
		return try builtByInitializerRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: typesDeclaredEscaping, children: children, lineEnd: comment)
	}
}
