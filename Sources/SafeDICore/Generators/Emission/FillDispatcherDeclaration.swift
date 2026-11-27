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

extension ScopeGenerator.FillDispatcher {
	/// The body of a fill generated in the one case of a dispatcher that calls it, in place of a function of its own
	/// (see `ScopeGenerator.inlinableFillKeys`): what the case binds, and the fill's body, indented for the case.
	struct InlinedFill {
		/// Whether the case carries a payload struct, which the fill is handed as its scope.
		let carriesPayload: Bool
		/// Whether the body reads the scope; a case that binds a value it never reads draws a warning.
		let readsScope: Bool
		/// The name the fill's function gives the value an instantiator forwards, or `nil` for a place that forwards none.
		let forwardedValueName: String?
		/// Whether the body reads the forwarded value: a fill never reads a forwarded `Void`.
		let readsForwardedValue: Bool
		let body: [String]

		init(carriesPayload: Bool, readsScope: Bool, forwardedValueName: String?, readsForwardedValue: Bool, body: [String]) {
			self.carriesPayload = carriesPayload
			self.readsScope = readsScope
			self.forwardedValueName = forwardedValueName
			self.readsForwardedValue = readsForwardedValue
			self.body = body
		}

		/// The body of the fill of `hole`, which builds `builtProperty` and whose function is `code` indented by
		/// `leadingMemberWhitespace`, as the dispatcher case that calls it holds it: the function's body under the names the
		/// case binds. `nil` for a fill whose scope parameter is named apart, because its place carries a field or its tree
		/// reads a value labeled `scope`, which the dispatcher's own parameter would hide: it keeps its function.
		/// - Parameter carrierUse: How a member of the seam's carrier takes the case's values, where it does.
		init?(hole: SeamSignature.Hole?, carrierUse: SeamCarrierValues.Use?, builtProperty: Property?, code: String, leadingMemberWhitespace: String) {
			// A fill is its function's declaration, its body, and the line closing it.
			let lines = GeneratedCodeText.lines(of: code)
			let valuesType = hole?.valuesType(qualifiedBy: nil)
			let carriesPayload = valuesType != nil
			// A seam's carrier hands the fill the payload's fields as arguments, the first named `scope_<label>`
			// (`SeamHoles.argumentName(of:inPayloadNamed:)`), where a builder struct hands it the payload named `scope`.
			let argumentFields: [SeamSignature.Hole.Field]? = if case let .nested(_, enumType, _)? = valuesType, ReservedName.seamCarrier(ofEnum: enumType) != nil {
				hole.map { $0.enumPlace?.values ?? $0.fields } ?? []
			} else {
				nil
			}
			let scopePrefix = argumentFields.map { fields in (carrierUse?.parameterNames(of: fields, inPayloadNamed: "scope") ?? fields.map { SeamHoles.argumentName(of: $0, inPayloadNamed: "scope") }).first.map { "(_ \($0): " } ?? "(" } ?? "(_ scope: "
			guard lines.count > 2,
			      !carriesPayload || lines[0].contains(scopePrefix),
			      lines[lines.count - 1] == leadingMemberWhitespace + "}"
			else { return nil }
			let body = lines[1..<(lines.count - 1)].map { ScopeGenerator.standardIndent + $0 }
			// The fill binds the fields its tree reads first, each from the scope; nothing after them reads the scope.
			// safedi-source-rule: allow stringScan — reads the first line of one inlined fill, once per fill.
			let readsScope = carriesPayload && lines[1].hasPrefix(leadingMemberWhitespace + ScopeGenerator.standardIndent + "let ") && (lines[1].contains(" = scope.") || (argumentFields != nil && lines[1].contains(" = scope_")))
			let forwardedValueName = hole?.forwardedType == nil ? nil : builtProperty.map(ScopeGenerator.forwardedValueParameterName(forBuilding:))
			let readsForwardedValue = forwardedValueName.map { name in
				body.contains { line in GeneratedCodeText.containsIdentifier(name, in: line) }
			} ?? false
			self.init(carriesPayload: carriesPayload, readsScope: readsScope, forwardedValueName: forwardedValueName, readsForwardedValue: readsForwardedValue, body: body)
		}
	}

	/// The function of the dispatcher's level, indented by `indent`, `@Sendable` as `isSendable` says, which returns the
	/// level's builder struct (`structDeclaration`). A case whose fill is in `inlinedFills`, by key, holds the fill's body.
	/// - Parameter parametersByKey: What each dispatcher of the call takes beside its enum
	///   (`dispatcherParameters(of:fillReads:)`), and each fill nested by type beside its case's payload, by key.
	func declaration(
		isSendable: Bool,
		indent: String,
		inlinedFills: [String: InlinedFill],
		parametersByKey: [String: [SeamSignature.Hole.Field]] = [:],
		callerArgumentByParameter: [Property: String] = [:],
		callerMemoArgumentByMemo: [Property: String] = [:],
		typesDeclaredEscaping: Set<TypeDescription> = [],
		fillsTakingPayloadFields: Set<String> = [],
		labelsHiddenByReenteringCalls: Set<String> = [],
	) -> String {
		let parameters = parametersByKey[key] ?? []
		let parameterNames = Self.parameterNames(of: parameters)
		// What this function hands on of a value no case carries to a target that takes it as `parameter`: its own parameter
		// of that form (`parameter(handing:among:)`), or, for the root dispatcher, which takes none, the caller's declaration
		// in the form that target takes (`ScopeGenerator.FillCallerReads`), whatever form another target of the call takes it
		// in.
		func ownValue(for parameter: SeamSignature.Hole.Field) -> String {
			takesValuesOfOuterTypes ? parameterNames[parameter.property] ?? parameter.property.label : callerArgumentByParameter[parameter.property] ?? parameter.property.label
		}
		// The names this function binds, apart from the names of what it takes and passes on.
		let labels = Set(parameterNames.values).union(cases.flatMap { dispatcherCase in
			dispatcherCase.target.map { Self.parameterNames(of: parametersByKey[$0.key] ?? []).values.map(\.self) } ?? []
		})
		func name(_ base: String) -> String {
			var name = base
			while labels.contains(name) {
				name += "_"
			}
			return name
		}
		return structDeclaration(
			isSendable: isSendable,
			indent: indent,
			inlinedFills: inlinedFills,
			fillsTakingPayloadFields: fillsTakingPayloadFields,
			parameters: parameters,
			parametersByKey: parametersByKey,
			ownValue: ownValue(for:),
			callerMemoArgument: { callerMemoArgumentByMemo[$0.memoProperty] },
			valuesName: name("values"),
			scopeName: name("scope"),
			typesDeclaredEscaping: typesDeclaredEscaping,
			labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
		)
	}

	/// The function of one level of a seam's tree that returns its enum's builder struct (`returnsBuilderStruct`): it takes
	/// the values the members' targets read that the cases do not carry, as the enum's dispatcher takes them, and returns a
	/// struct whose member for each case calls the function of the next level, handing it what it reads of the values the
	/// member is handed, or holds the fill of the case's place, which reads them. No member's closure captures the values
	/// it is handed: it reads what it needs out of them. A seam's caller fills every place of an enum, so every case has a
	/// target, and no place forwards a value.
	private func structDeclaration(
		isSendable: Bool,
		indent: String,
		inlinedFills: [String: InlinedFill],
		fillsTakingPayloadFields: Set<String>,
		parameters: [SeamSignature.Hole.Field],
		parametersByKey: [String: [SeamSignature.Hole.Field]],
		ownValue: (SeamSignature.Hole.Field) -> String,
		callerMemoArgument: (SeamSignature.Hole.Field) -> String?,
		valuesName: String,
		scopeName: String,
		typesDeclaredEscaping: Set<TypeDescription>,
		labelsHiddenByReenteringCalls: Set<String>,
	) -> String {
		let memberIndent = indent + ScopeGenerator.standardIndent
		/// The names a carrier's member takes `dispatcherCase`'s values under, given the payload's name: the struct of the run
		/// they end, then each value after it (`SeamCarrierValues.Use`), or every value, each under the payload's name joined
		/// with its label.
		func carrierParameterNames(of dispatcherCase: Case, payloadName: String) -> [String] {
			let values = dispatcherCase.values ?? []
			return dispatcherCase.carrierUse?.parameterNames(of: values, inPayloadNamed: payloadName) ?? values.map { SeamHoles.argumentName(of: $0, inPayloadNamed: payloadName) }
		}
		/// What reads `field` of `dispatcherCase`'s values from the names `carrierParameterNames` gives them.
		func carrierRead(of field: SeamSignature.Hole.Field, in dispatcherCase: Case, payloadName: String, bindingMemo: Bool) -> String {
			let values = dispatcherCase.values ?? []
			guard let use = dispatcherCase.carrierUse, let index = values.firstIndex(where: { $0.property == field.property }) else { return SeamHoles.argumentRead(of: field, inPayloadNamed: payloadName, bindingMemo: bindingMemo) }
			return use.read(ofFieldAt: index, of: values, inPayloadNamed: payloadName, bindingMemo: bindingMemo)
		}
		/// The argument `target`, the target of `dispatcherCase`, takes for `parameter`, reading the case's payload bound as
		/// `payloadName`, and whether it reads the payload: the struct the caller's member of this level returns for the case,
		/// for the struct of a level on a carried route; else the case's payload's field, or this function's own value.
		func argument(_ parameter: SeamSignature.Hole.Field, named argumentLabel: String, of target: Case.Target, for dispatcherCase: Case, payloadName: String, readsOwnPayload: Bool) -> (text: String, readsPayload: Bool) {
			let label = parameter.property.label
			if let carriedInnerScope = carriedInnerScopes.first(where: { $0.name == label }) {
				// A level function an enclosing call declares takes the struct under its own name for it.
				let argumentLabel = Self.isFill(target) ? label : target.reusedCarriedInnerScopes.first { $0.type == carriedInnerScope.type }?.upName ?? carriedInnerScope.upName
				// A carrier's member takes the case's values as arguments, which the closure binds under the payload's name.
				let memberArguments = takesValuesAsArguments ? carrierParameterNames(of: dispatcherCase, payloadName: payloadName).joined(separator: ", ") : payloadName
				let member = "\(carriedInnerScope.upName).\(dispatcherCase.name.spelledAsMemberReference)"
				return ("\(argumentLabel.spelledAsArgumentLabel): \(dispatcherCase.isLetChild ? member : "\(member)(\(memberArguments))")", true)
			} else if readsOwnPayload, (dispatcherCase.carriedLabels.contains(label) && dispatcherCase.handsOn(parameter)) || (parameter.bindsMemo && labelsHiddenByReenteringCalls.contains(label) && dispatcherCase.values?.contains { $0.property.label == label } == true), let field = dispatcherCase.values?.first(where: { $0.property.label == label }) {
				// A target that binds a deferred parameter's memo is handed the memo, whose instance it reads where it reads the
				// value: also a deferred field `carriedLabels` leaves out where a call inside a fill passes a fill of this call on
				// beneath another declaration of the label (`fillDeferredLabelsHiddenByReenteringCalls`), which builds the seam
				// again (`Scope.fillUnderConstruction`): the target binds the memo of the seam whose struct it is handed, where the
				// enclosing value is another declaration's. Elsewhere the caller's declaration is the one inline reads, which the
				// branches below hand. The payload is read before the member returns, so no memo made of it captures the payload.
				let source = HandedSource(field, readsMemo: parameter.bindsMemo, expression: takesValuesAsArguments ? carrierRead(of: field, in: dispatcherCase, payloadName: payloadName, bindingMemo: parameter.bindsMemo) : "\(payloadName).\(field.memberName(bindingMemo: parameter.bindsMemo))")
				return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: true))", true)
			} else if let ownParameter = Self.parameter(handing: parameter, among: parameters) {
				// This function's own parameter of the target's form: a target of another form is handed its own.
				let source = HandedSource(ownParameter, readsMemo: ownParameter.bindsMemo, expression: ownValue(ownParameter))
				return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: false))", false)
			} else if parameter.bindsMemo, parameter.deferral == .deferred(isSendable: true), let memoArgument = callerMemoArgument(parameter) {
				// The root dispatcher hands a target that takes a `SendableLazilyInstantiated` the caller's declaration of it, or
				// one made of the caller's value (`ScopeGenerator.FillCallerReads.memoArgumentByMemo`).
				return ("\(argumentLabel.spelledAsArgumentLabel): \(memoArgument)", false)
			} else {
				// The root dispatcher hands the caller's declaration, in the form a target that takes the value takes it
				// (`ScopeGenerator.FillCallerReads`).
				let source = HandedSource(expression: ownValue(parameter), type: parameter.property.typeDescription, isMemo: false)
				return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: false))", false)
			}
		}
		/// The parameters of `target`, in the order it declares them: a fill's in their own order; a level function's with
		/// the structs of carried levels first, in the order this function takes them, and the rest in their order; a level
		/// function an enclosing call declares takes only structs, in its own order.
		func orderedCarriedFirst(_ parameters: [SeamSignature.Hole.Field], of target: Case.Target) -> [SeamSignature.Hole.Field] {
			guard !Self.isFill(target), target.reusedCarriedInnerScopes.isEmpty else { return parameters }
			let carriedNames = carriedInnerScopes.map(\.name)
			let carried = carriedNames.compactMap { name in parameters.first { $0.property.label == name } }
			return carried + parameters.filter { !carriedNames.contains($0.property.label) }
		}
		// A seam's carrier hands each member the case's values as arguments, not as a payload struct; the member's closure
		// takes each under the payload's name joined with its label.
		let takesValuesAsArguments = ReservedName.seamCarrier(ofEnum: enumType) != nil
		func closureHead(of dispatcherCase: Case, payloadName: String, readsPayload: Bool) -> String {
			guard takesValuesAsArguments else { return "{ \(readsPayload ? payloadName : "_") in" }
			let names = carrierParameterNames(of: dispatcherCase, payloadName: payloadName)
			return names.isEmpty ? "{" : "{ \(names.joined(separator: ", ")) in"
		}
		var members = [(name: String, lines: [String])]()
		for (dispatcherCase, target) in cases.compactMap({ dispatcherCase in dispatcherCase.target.map { (dispatcherCase, $0) } }) {
			let targetParameters = parametersByKey[target.key] ?? []
			let targetParameterNames = Self.parameterNames(of: targetParameters)
			if let inlinedFill = inlinedFills[target.key] {
				// The fill's body, which declares no function: a fill that does is called by name, so no function is declared
				// inside the closure the struct stores (`ScopeGenerator.declaresFunction(inFillBody:)`).
				let head = closureHead(of: dispatcherCase, payloadName: "scope", readsPayload: inlinedFill.carriesPayload && inlinedFill.readsScope)
				members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(head)"] + inlinedFill.body.map { String($0.dropFirst(memberIndent.count)) } + ["}"]))
			} else if fillsTakingPayloadFields.contains(target.key) || !Self.isFill(target) {
				// A fill that returns a wrapper's builder takes each field of the payload it reads, from the payload, and each
				// value it reads that the payload does not carry, under its label: the builder it returns captures no payload.
				// The next level's function likewise takes what it reads from this case's payload where it carries one.
				let arguments = orderedCarriedFirst(targetParameters, of: target).map { argument($0, named: targetParameterNames[$0.property] ?? $0.property.label, of: target, for: dispatcherCase, payloadName: valuesName, readsOwnPayload: true) }
				let readsValues = arguments.contains(where: \.readsPayload)
				var call = "\(target.name)(\(arguments.map(\.text).joined(separator: ", ")))"
				if dispatcherCase.returnsWrapperBuilder, !Self.isFill(target) {
					// The member of an instantiator's place on a carried route returns the builder the wrapper keeps, which ignores the
					// forwarded value: the fill's level reads it from its own payload. A level that reads the payload is called before
					// the builder is returned, so the builder captures the level's struct, never the payload.
					call = readsValues ? "{ [level = \(call)] _ in level }" : "{ _ in \(call) }"
				}
				if dispatcherCase.isLetChild, !Self.isFill(target) {
					// A carrier's `let` child is formed with its parent, by the next level's function.
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(call)"]))
				} else {
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(closureHead(of: dispatcherCase, payloadName: valuesName, readsPayload: readsValues)) \(call) }"]))
				}
			} else {
				// A fill nested by type takes the case's payload, and each value it reads that the payload does not carry, under
				// its label: this function's own, or the caller's.
				let bound = if !dispatcherCase.carriesPayload {
					[String]()
				} else if takesValuesAsArguments {
					carrierParameterNames(of: dispatcherCase, payloadName: scopeName)
				} else {
					[scopeName]
				}
				let arguments = orderedCarriedFirst(targetParameters, of: target).map { argument($0, named: targetParameterNames[$0.property] ?? $0.property.label, of: target, for: dispatcherCase, payloadName: scopeName, readsOwnPayload: false) }
				let readsPayload = !bound.isEmpty || arguments.contains(where: \.readsPayload)
				members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): \(closureHead(of: dispatcherCase, payloadName: scopeName, readsPayload: readsPayload)) \(target.name)(\((bound + arguments.map(\.text)).joined(separator: ", "))) }"]))
			}
		}
		// The struct of this level the caller's member returns, on a carried route, before the values the members' targets
		// read.
		var valueParameterList = [String]()
		for carriedInnerScope in carriedInnerScopes where parameters.contains(where: { $0.property.label == carriedInnerScope.name }) || (innerScopeName != nil && cases.contains { dispatcherCase in
			dispatcherCase.target.map { (parametersByKey[$0.key] ?? []).contains { $0.property.label == carriedInnerScope.name } } ?? false
		}) {
			valueParameterList.append("\(carriedInnerScope.upName.spelledAsArgumentLabel): \(ReservedName.levelType(ofEnum: enumType, built: Self.carried(carriedInnerScope.type, through: returnType)).asSource)")
		}
		let carriedNames = Set(carriedInnerScopes.map(\.name))
		let parameterNames = Self.parameterNames(of: parameters)
		valueParameterList += parameters.filter { !carriedNames.contains($0.property.label) }.map { "\((parameterNames[$0.property] ?? $0.property.label).spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
		let valueParameters = valueParameterList.joined(separator: ", ")
		let builderType = ReservedName.levelType(ofEnum: enumType, built: returnType)
		var lines = ["\(indent)\(ScopeGenerator.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(valueParameters)) -> \(builderType.asSource) {"]
		if members.allSatisfy({ $0.lines.count == 1 }) {
			lines.append("\(memberIndent).init(\(members.map { $0.lines[0] }.joined(separator: ", ")))")
		} else if members.count == 1 {
			// One member over several lines opens on the initializer's line and closes the call on its last.
			let memberLines = members[0].lines
			lines.append("\(memberIndent).init(\(memberLines[0])")
			lines += memberLines.dropFirst().dropLast().map { "\(memberIndent)\($0)" }
			lines.append("\(memberIndent)\(memberLines[memberLines.count - 1]))")
		} else {
			// Several members, one of them over several lines: one member per line, each indented once more.
			lines.append("\(memberIndent).init(")
			for (index, member) in members.enumerated() {
				let separator = index == members.count - 1 ? "" : ","
				let memberLines = member.lines
				lines += memberLines.dropLast().map { "\(memberIndent)\(ScopeGenerator.standardIndent)\($0)" }
				lines.append("\(memberIndent)\(ScopeGenerator.standardIndent)\(memberLines[memberLines.count - 1])\(separator)")
			}
			lines.append("\(memberIndent))")
		}
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// What a level function hands a target of one label: `expression`, of `type`, a deferred parameter's memo where
	/// `isMemo`, else the value, which can be a `LazilyInstantiated` or its `Sendable` twin a type declares.
	struct HandedSource {
		let expression: String
		let type: TypeDescription?
		let isMemo: Bool

		init(expression: String, type: TypeDescription?, isMemo: Bool) {
			self.expression = expression
			self.type = type
			self.isMemo = isMemo
		}

		/// `field` read as `expression`: its memo where `readsMemo` and it is a deferred parameter's, else its value.
		init(_ field: SeamSignature.Hole.Field, readsMemo: Bool, expression: String) {
			let isMemo = readsMemo && field.isDeferredParameter
			self.init(expression: expression, type: isMemo ? field.memoType : field.property.typeDescription, isMemo: isMemo)
		}

		/// The expression `parameter` is handed: the memo's instance where it takes the value, the memo where it takes a memo
		/// of the same type, and else a `LazilyInstantiated` of the parameter's memo type made of what is handed, which reads
		/// the instance of a memo or of a type's `LazilyInstantiated` when its own instance is read, so the value is created
		/// where the target's tree reads it. Where `capturingExpression`, the expression reads the payload, which the closure
		/// of a memo made of it reads first, so it captures no payload.
		func handed(to parameter: SeamSignature.Hole.Field, capturingExpression: Bool) -> String {
			guard parameter.bindsMemo, let memoType = parameter.memoType else {
				return isMemo ? "\(expression).\(Dependency.lazilyInstantiatedInstancePropertyName)" : expression
			}
			guard type != memoType else { return expression }
			let readsInstance = isMemo || type.map { $0.propertyType.isLazilyInstantiated && !$0.isOptional } == true
			let read = readsInstance ? ".\(Dependency.lazilyInstantiatedInstancePropertyName)" : ""
			return capturingExpression
				? "\(memoType.asSource)({ [handed = \(expression)] in handed\(read) })"
				: "\(memoType.asSource)({ \(expression)\(read) })"
		}
	}

	/// Whether `target` is a fill rather than a dispatcher.
	private static func isFill(_ target: Case.Target) -> Bool {
		!target.key.hasPrefix("dispatcher ")
	}
}
