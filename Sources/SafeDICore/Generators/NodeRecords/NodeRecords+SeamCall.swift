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
	/// The claim of `declaration` as `seamCall` where it calls another module's seam (`TypeFactsConstruction.seamCall`), which
	/// discharges stage 1's refusal of a construction other than an initializer; `nil` for any other node, and for every
	/// node of a mock root's world, which builds every seam inline. Every other check of stage 1 still runs on it, so a call
	/// that passes builders (`ConstructionScope.holeArguments`) is still refused as `fill`. A call that forwards values binds
	/// them inside its text, which no record lists yet: refused as `construction`.
	static func seamCallClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard !world.isMockWorld, world.construction(of: declaration) == .seamCall else { return nil }
		let forwardsValues = world.scope(of: declaration).instantiable.dependencies.contains { $0.source == .forwarded }
		return NodeRecordClaim(kind: .seamCall, discharges: [.construction], refusals: forwardsValues ? [.construction] : [])
	}

	/// The record of `declaration`'s place, a node of kind `seamCall`: `builtByInitializerRecord`'s, with the seam's tier's
	/// initializer as its target (the scope's instantiable is the seam's leaf), a builder function always declared, and the
	/// guard line that function begins with (`CallFields.leadingStatement`). A call that passes no builder hands no closure.
	static func seamCallRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let scope = world.scope(of: declaration)
		var record = try builtByInitializerRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: typesDeclaredEscaping, children: children, declaresFunction: true)
		// Never `nil`: the node is of kind `seamCall` (`seamCallClaim(of:in:)`), whose construction is a call of the seam.
		record.callFields = scope.seamCall.map { seamCall in
			CallFields(leadingStatement: seamCall.callGuard(for: scope.instantiable.concreteInstantiable), closureArguments: [])
		}
		return record
	}
}
