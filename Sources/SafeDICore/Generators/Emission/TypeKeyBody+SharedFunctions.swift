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

extension TypeKeyBody {
	/// The static function that builds `record`'s place on its own, laid out as a root's body whose one statement is the
	/// place, `parameters` declared around it: the function of the place's class, which the function takes the
	/// parameters of besides its own, its body holding the functions the root would declare before the place. Its
	/// declaration is spelled after `attributes` and `static`, indented as a member of an extension, with no line ending
	/// it, and named `ReservedName.sharedBuilderFunctionName`. `nil` where the place's class is not the root's alone: a
	/// function a second place shares, that the root hands a value, or that is `@Sendable`; or where the root would
	/// declare a function of its own (`RootFunctionHoisting`), or the type key cannot lay the body out.
	static func staticFunction(building record: BuiltPlaceRecord, parameters: [Property], attributes: String) -> String? {
		let rootBody = [GeneratedCode.place(PlacePlan(code: .empty, record: .built(record)))]
		guard record.hasFunction, RootFunctionHoisting.records(in: rootBody).isEmpty else { return nil }
		var layout = TypeKeyLayout()
		layout.declareOuter(parameters)
		layout.namesInScope = Set(parameters.map(\.label)).union(record.parameterProperties.map(\.label))
		let position = layout.outerDeclarationCount
		guard plans(rootBody, in: &layout),
		      position < layout.bodies[0].statements.count,
		      case let .built(body) = layout.bodies[0].statements[position]
		else { return nil }
		let owner = layout.classByBody[body]
		guard layout.membersByClass[owner].count == 1,
		      layout.callSitesByClass[owner] == [CallSite(owner: 0, index: position)],
		      !layout.isDecorated[owner],
		      !layout.outcomes[owner].values.contains(.passed),
		      let functionCode = layout.spelledFunctionCode(),
		      let node = layout.builderNode(ofClass: owner, functionCode: functionCode)
		else { return nil }
		// The functions the root would declare before the place, then the place's own body.
		var statements = [GeneratedCode]()
		for index in layout.bodies[0].statements.indices {
			let site = CallSite(owner: 0, index: index)
			for function in (layout.hoistedFunctions[site] ?? []) + [layout.attachedFunction[site]].compactMap(\.self) where function != owner {
				statements.append(.indented(functionCode[function], by: ScopeGenerator.standardIndent))
			}
		}
		statements.append(contentsOf: node.body.statements)
		var typesDeclaredEscaping = node.typesDeclaredEscaping
		for parameter in parameters where parameter.typeDescription.isClosure {
			typesDeclaredEscaping.insert(parameter.typeDescription)
		}
		// The forwarded values first, as the place's function takes them, then the parameters, then what it is handed.
		let forwardedCount = record.forwardedProperties.count
		var functionParameters = Array(node.parameters.prefix(forwardedCount))
		functionParameters.append(contentsOf: parameters)
		functionParameters.append(contentsOf: node.parameters.dropFirst(forwardedCount))
		let function = BuilderNode(
			name: ReservedName.sharedBuilderFunctionName,
			isSendable: false,
			parameters: functionParameters,
			typesDeclaredEscaping: typesDeclaredEscaping,
			returnType: node.returnType,
			body: BuilderBody(statements: statements),
			value: node.value,
			lineEnd: node.lineEnd,
		)
		var declaration = GeneratedCode.indented(function.spelled(after: attributes.isEmpty ? "static " : "\(attributes) static "), by: ScopeGenerator.standardIndent).spelled()
		while declaration.hasSuffix("\n") {
			declaration.removeLast()
		}
		return declaration
	}
}
