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

extension TypeKeyLayout {
	// MARK: Decorators and names

	mutating func computeDecoratorsAndNames() {
		let classCount = membersByClass.count
		isDecorated = membersByClass.indices.map { owner in
			owner != 0 && membersByClass[owner].contains { bodies[$0].record?.isSendable == true || bodies[$0].callingFunction?.isSendable == true }
		}
		// A function a `@Sendable` function declared beneath it calls is captured by that function, so it is `@Sendable` too.
		var changed = true
		while changed {
			changed = false
			for owner in 1..<max(classCount, 1) where !isDecorated[owner] {
				let decorated = callSitesByClass[owner].contains { site in
					var current = site.owner
					while current != 0, current != placementOwner[owner] {
						if isDecorated[current] {
							return true
						}
						current = placementOwner[current]
					}
					return false
				}
				if decorated {
					isDecorated[owner] = true
					changed = true
				}
			}
		}
		var allocator = GeneratedNameAllocator(reserving: namesInScope)
		// A function's parameters are declarations of its body, where a function or a local of a parameter's name would be
		// hidden by it, or hide it: every name the layout claims is apart from every parameter a call hands.
		for owner in membersByClass.indices {
			allocator.reserve(representative(of: owner)?.passedArguments.map(\.parameterName) ?? [])
		}
		// A function a place written as text declares keeps its name, which the text's binding hands its wrapper.
		allocator.reserve(membersByClass.indices.compactMap { callingFunction(ofClass: $0)?.name })
		functionNames = membersByClass.indices.map { owner in
			if let function = callingFunction(ofClass: owner) {
				return function.name
			}
			guard let representative = representative(of: owner) else { return "" }
			return allocator.claim(ScopeGenerator.functionName(toBuildPropertyNamed: representative.property.label))
		}
		// Each call names its locals after the function it calls and the parameter, apart from every other call's.
		for owner in membersByClass.indices {
			for (index, statement) in statements(ofClass: owner).enumerated() {
				let callee: Int
				switch statement {
				case let .built(child):
					callee = classByBody[child]
				case let .closer(_, target):
					callee = classByBody[target]
				case .inline,
				     .alias,
				     .function:
					continue
				}
				for argument in passedArguments(ofStatementAt: index, inBody: owner == 0 ? 0 : membersByClass[owner][0]) where argument.bindsBeforeCall {
					boundArgumentNames[CallSite(owner: owner, index: index), default: [:]][argument.parameterName] = allocator.claim("\(functionNames[callee])__\(argument.parameterName)".spelledAsJoinedIdentifier)
				}
			}
		}
	}

	// MARK: Spelling

	mutating func spelledRootStatements() -> [GeneratedCode]? {
		var functionCode = [GeneratedCode](repeating: .empty, count: membersByClass.count)
		let classesByDepth = membersByClass.indices.dropFirst().sorted { placementDepth[$0] > placementDepth[$1] }
		for owner in classesByDepth {
			if let function = callingFunction(ofClass: owner) {
				guard let code = spelledCallingFunction(function, ofClass: owner, functionCode: functionCode) else { return nil }
				functionCode[owner] = code
				continue
			}
			guard let representative = representative(of: owner),
			      let body = spelledStatements(ofClass: owner, indentation: ScopeGenerator.standardIndent, functionCode: functionCode),
			      let argumentValues = spelledArgumentValues(representative.arguments, replacedAt: representative.argumentValues, inClass: owner, before: statements(ofClass: owner).count, sourceAtMember: { member, position in bodies[member].record?.arguments[position].source })
			else { return nil }
			let arguments = Self.labeled(argumentValues, of: representative.arguments)
			var parameters = representative.forwardedProperties
			var typesDeclaredEscaping = representative.typesDeclaredEscaping
			for label in reads[membersByClass[owner][0]] where outcomes[owner][label] == .passed {
				guard let parameterType = parameterTypes[owner][label] else { return nil }
				parameters.append(Property(label: label, typeDescription: parameterType))
				if parameterType.isClosure {
					typesDeclaredEscaping.insert(parameterType)
				}
			}
			for argument in representative.passedArguments {
				parameters.append(Property(label: argument.parameterName, typeDescription: argument.type))
				if argument.type.isClosure {
					typesDeclaredEscaping.insert(argument.type)
				}
			}
			// A function that returns a type of its own erases an erased place's value itself, so its calls do not.
			var value = Expression.construction(representative.target, arguments: arguments)
			if let functionReturnType = representative.functionReturnType {
				value = value.erased(to: functionReturnType, where: representative.isErased)
			}
			if !representative.alternatives.isEmpty || representative.constructionValue != nil {
				guard let construction = spelledConstruction(of: representative, call: value.spelled, argumentValues: argumentValues, inClass: owner, before: statements(ofClass: owner).count) else { return nil }
				value = .spelledConstruction(construction)
			}
			functionCode[owner] = BuilderNode(
				name: functionNames[owner],
				isSendable: isDecorated[owner],
				parameters: parameters,
				typesDeclaredEscaping: typesDeclaredEscaping,
				returnType: representative.functionReturnType ?? representative.concreteType,
				body: BuilderBody(statements: body),
				value: value,
				lineEnd: representative.lineEnd,
			).spelled()
		}
		return spelledStatements(ofClass: 0, indentation: TypeKeyBody.rootStatementIndentation, functionCode: functionCode)
	}

	/// The statements of `owner`'s body, each with the functions declared before it, each indented by `indentation`.
	func spelledStatements(ofClass owner: Int, upTo end: Int? = nil, indentation: String, functionCode: [GeneratedCode]) -> [GeneratedCode]? {
		var code = [GeneratedCode]()
		for (index, statement) in statements(ofClass: owner).prefix(end ?? .max).enumerated() where owner != 0 || index >= outerDeclarationCount {
			let site = CallSite(owner: owner, index: index)
			for function in hoistedFunctions[site] ?? [] {
				code.append(.indented(functionCode[function], by: indentation))
			}
			if let function = attachedFunction[site] {
				code.append(.indented(functionCode[function], by: indentation))
			}
			if case let .function(_, function) = statement {
				// The function is spelled at each statement that declares it, before the text's binding of its wrapper.
				code.append(.indented(functionCode[classByBody[function]], by: indentation))
			}
			guard let text = spelledStatement(statement, inClass: owner, at: index) else { return nil }
			// A place that declares only its function writes no line of its own.
			if case let .built(child) = statement, bodies[child].record?.bindsProperty == false {
				continue
			}
			code.append(.indented(.text(text), by: indentation))
		}
		return code
	}

	func spelledStatement(_ statement: Statement, inClass owner: Int, at index: Int) -> String? {
		switch statement {
		case let .inline(record):
			guard let argumentValues = spelledArgumentValues(record.arguments, replacedAt: record.argumentValues, inClass: owner, before: index, sourceAtMember: { member, position in
				guard case let .inline(memberRecord) = bodies[member].statements[index] else { return nil }
				return memberRecord.arguments[position].source
			}) else { return nil }
			let arguments = Self.labeled(argumentValues, of: record.arguments)
			let declaration = BindingDeclaration(
				property: record.property,
				rule: .constant(
					isErased: record.isErased,
					constructedTypeIsPropertyType: record.concreteType.asSource == record.property.typeDescription.asSource,
					hasBuilderFunction: false,
					isExtension: record.isExtension,
				),
			)
			let call = Expression.construction(record.target, arguments: arguments).erased(to: record.property.typeDescription.unwrapped, where: record.isErased).spelled
			guard let value = spelledConstruction(of: record, call: call, argumentValues: argumentValues, inClass: owner, before: index) else { return nil }
			return "\(declaration.spelled) = \(value)\(record.lineEnd)"
		case let .built(child):
			guard let record = bodies[child].record else { return nil }
			// A place that declares only its function binds nothing: a later statement hands its wrapper the function.
			guard record.bindsProperty else { return "" }
			return spelledCall(of: classByBody[child], binding: record.property, isErased: record.isErased, isExtension: record.isExtension, inClass: owner, at: index)
		case let .closer(record, target):
			return spelledCall(of: classByBody[target], binding: record.property, isErased: record.isErased, isExtension: record.isExtension, inClass: owner, at: index)
		case let .alias(record):
			guard let call = record.call else { return record.text }
			return spelledInPlace(call, inClass: owner, at: index)
		case let .function(record, _):
			// The text holds the binding alone (`AliasPlaceRecord.function`); `spelledStatements` writes the function before it.
			return record.text
		}
	}

	/// The function of `owner`'s class if it is the class of a function a place written as text declares.
	func callingFunction(ofClass owner: Int) -> CallingFunction? {
		owner == 0 ? nil : bodies[membersByClass[owner][0]].callingFunction
	}

	/// The function a place written as text declares, spelled from its class: its statements, then the call its last
	/// statement makes of another function, which the function returns.
	func spelledCallingFunction(_ function: CallingFunction, ofClass owner: Int, functionCode: [GeneratedCode]) -> GeneratedCode? {
		let statements = statements(ofClass: owner)
		guard case let .closer(returnedCall, target) = statements.last,
		      var body = spelledStatements(ofClass: owner, upTo: statements.count - 1, indentation: ScopeGenerator.standardIndent, functionCode: functionCode),
		      let call = spelledArguments(toCallOf: classByBody[target], inClass: owner, at: statements.count - 1)
		else { return nil }
		if !call.bindings.isEmpty {
			body.append(.indented(.text(String(call.bindings.dropLast())), by: ScopeGenerator.standardIndent))
		}
		let forwardedArguments = returnedCall.forwardedProperties.map { CallArgument(label: $0.label, source: .binding(label: $0.label)).spelled }
		return BuilderNode(
			name: function.name,
			isSendable: isDecorated[owner],
			parameters: function.parameters,
			typesDeclaredEscaping: function.typesDeclaredEscaping,
			returnType: function.returnType,
			body: BuilderBody(statements: body),
			value: .call(function: functionNames[classByBody[target]], arguments: (forwardedArguments + call.arguments).joined(separator: ", ")),
			lineEnd: "",
		).spelled()
	}

	/// The text of a call written where its place is, at `index` of `owner`'s body: its builder function, then the binding
	/// of its result. Each argument is read as the declaration visible there, which the function captures.
	func spelledInPlace(_ call: InPlaceCall, inClass owner: Int, at index: Int) -> String? {
		let record = call.record
		guard let argumentValues = spelledArgumentValues(record.arguments, replacedAt: record.argumentValues, inClass: owner, before: index, sourceAtMember: { member, position in
			guard case let .alias(memberRecord) = bodies[member].statements[index], let memberCall = memberRecord.call else { return nil }
			return memberCall.record.arguments[position].source
		}) else { return nil }
		var statements = call.statementsBeforeLeadingStatement
		if let leadingStatement = record.leadingStatement {
			statements.append(.text("\(ScopeGenerator.standardIndent)\(leadingStatement.spelled)"))
		}
		statements += call.statementsAfterLeadingStatement
		let function = SafeDICore.Statement.function(BuilderNode(
			name: record.functionName,
			isSendable: record.isSendable,
			parameters: [],
			typesDeclaredEscaping: record.typesDeclaredEscaping,
			returnType: record.concreteType,
			body: BuilderBody(statements: statements),
			value: .construction(record.target, arguments: Self.labeled(argumentValues, of: record.arguments)),
			lineEnd: record.lineEnd,
		)).spelled
		let declaration = BindingDeclaration(
			property: record.property,
			rule: .constant(
				isErased: record.isErased,
				constructedTypeIsPropertyType: record.concreteType.asSource == record.property.typeDescription.asSource,
				hasBuilderFunction: true,
				isExtension: record.isExtension,
			),
		)
		let binding = SafeDICore.Statement.binding(
			declaration,
			Expression.call(function: record.functionName, arguments: "").erased(to: record.property.typeDescription.unwrapped, where: record.isErased),
			lineEnd: "",
		)
		return GeneratedCode.sequence([function, binding.spelled, .text("\n")]).spelled()
	}

	/// The binding of `property` to a call of `callee`'s function, made before the statement at `index` of `owner`'s body.
	func spelledCall(of callee: Int, binding property: Property, isErased placeIsErased: Bool, isExtension: Bool, inClass owner: Int, at index: Int) -> String? {
		guard let representative = representative(of: classBuilt(by: callee)),
		      let call = spelledArguments(toCallOf: callee, inClass: owner, at: index)
		else { return nil }
		// A function that returns a type of its own erased the value already (`spelledRootStatements`).
		let isErased = placeIsErased && representative.functionReturnType == nil
		let forwardedProperties = callingFunction(ofClass: callee)?.parameters ?? representative.forwardedProperties
		return call.bindings + spelledCall(of: callee, binding: property, isErased: isErased, isExtension: isExtension, handing: call.arguments, forwarding: forwardedProperties)
	}

	/// The class whose place `callee`'s function builds: the class of the call it returns where `callee` is the class of a
	/// function a place written as text declares, and `callee` otherwise.
	func classBuilt(by callee: Int) -> Int {
		guard callingFunction(ofClass: callee) != nil, case let .closer(_, target) = statements(ofClass: callee).last else { return callee }
		return classByBody[target]
	}

	/// The arguments a call of `callee`'s function made at `index` of `owner`'s body hands it, after what it passes for
	/// each read the function takes as a parameter, with the bindings of the values it binds before the call.
	func spelledArguments(toCallOf callee: Int, inClass owner: Int, at index: Int) -> (bindings: String, arguments: [String])? {
		var arguments = [String]()
		for label in reads[membersByClass[callee][0]] where outcomes[callee][label] == .passed {
			guard let parameterType = parameterTypes[callee][label],
			      let value = spelledArgument(label, passing: passedDeclaration(label, toParameterOf: callee, inClass: owner, before: index), to: parameterType)
			else { return nil }
			arguments.append("\(label.spelledAsArgumentLabel): \(value)")
		}
		// The members of `owner` hand their calls passed arguments of one shape (`structuralKey`), so its first member's
		// spell every member's.
		var bindings = ""
		for argument in passedArguments(ofStatementAt: index, inBody: owner == 0 ? 0 : membersByClass[owner][0]) {
			guard let value = spelledValuePath(argument.value, inClass: owner, before: index) else { return nil }
			if let local = boundArgumentNames[CallSite(owner: owner, index: index)]?[argument.parameterName] {
				bindings += "let \(local): \(argument.type.asSource) = \(value)\n"
				arguments.append("\(argument.parameterName.spelledAsArgumentLabel): \(local)")
			} else {
				arguments.append("\(argument.parameterName.spelledAsArgumentLabel): \(value)")
			}
		}
		return (bindings, arguments)
	}

	/// The binding of `property` to a call of `callee`'s function that hands it `arguments`.
	private func spelledCall(of callee: Int, binding property: Property, isErased: Bool, isExtension: Bool, handing arguments: [String], forwarding forwardedProperties: [Property]) -> String {
		let functionName = functionNames[callee]
		switch property.propertyType {
		case .instantiator,
		     .erasedInstantiator,
		     .sendableInstantiator,
		     .sendableErasedInstantiator:
			let isOnly = forwardedProperties.count == 1
			let forwardedArguments = forwardedProperties.map {
				CallArgument(label: $0.label, source: .forwardedSpread(label: $0.label, isOnly: isOnly, spreadName: "$0")).spelled
			}
			return ScopeGenerator.instantiatorDeclaration(
				of: property,
				isExtension: isExtension,
				isErased: isErased,
				handing: functionName,
				forwardedArguments: (forwardedArguments + arguments).joined(separator: ", "),
			)
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			return "\(BindingDeclaration(property: property, rule: .lazilyInstantiated).spelled) = \(ScopeGenerator.lazilyInstantiatedInstantiation(of: property, callingFunctionNamed: functionName, cycleArguments: arguments.joined(separator: ", "), erasedToConcreteExistential: isErased))"
		case .constant:
			// A binding to a builder function's call is annotated unless its value is erased, whatever type the function
			// returns (`BindingDeclaration.AnnotationRule.constant`), so no type is compared here.
			let declaration = BindingDeclaration(
				property: property,
				rule: .constant(
					isErased: isErased,
					constructedTypeIsPropertyType: false,
					hasBuilderFunction: true,
					isExtension: isExtension,
				),
			)
			return "\(declaration.spelled) = \(Expression.call(function: functionName, arguments: arguments.joined(separator: ", ")).erased(to: property.typeDescription.unwrapped, where: isErased).spelled)"
		}
	}

	/// What a call passes a parameter `label` of type `parameterType` where it passes `declaration`
	/// (`passedDeclaration(_:toParameterOf:inClass:before:)`): the declaration, `nil`, or a wrapper made of a value where
	/// the parameter takes a wrapper.
	func spelledArgument(_ label: String, passing declaration: TypeDeclaration, to parameterType: TypeDescription) -> String? {
		guard let declaredType = type(of: declaration, label: label) else {
			return parameterType.isOptional ? "nil" : nil
		}
		if declaredType == parameterType || (parameterType.isOptional && parameterType.unwrapped == declaredType) {
			return label
		} else {
			// The call is one of the function's call sites, whose declarations' types `computeParameterTypes` combined into
			// `parameterType` (`parameterType(combining:)`), so a declaration that is not the parameter's type, or its
			// unwrapped type, is the instance of the lazy wrapper the parameter takes.
			guard parameterType.unwrapped.lazilyInstantiatedInstanceType == declaredType, !declaredType.isOptional else { return nil }
			return "\(parameterType.unwrapped.asSource) { \(label) }"
		}
	}

	/// The arguments of a construction made before the statement at `index` of `owner`'s body, each read as the receiver
	/// declares it.
	func spelledArgumentValues(_ reads: [PlaceRead], replacedAt replacements: [Int: ValuePath], inClass owner: Int, before index: Int, sourceAtMember: (Int, Int) -> ArgumentSource?) -> [String]? {
		var values = [String]()
		let members = owner == 0 ? [0] : membersByClass[owner]
		for (position, read) in reads.enumerated() {
			let value: String
			if let path = replacements[position] {
				guard let spelled = spelledValuePath(path, inClass: owner, before: index) else { return nil }
				value = spelled
			} else if members.allSatisfy({ sourceAtMember($0, position) == .nil }) {
				value = "nil"
			} else {
				let declaration = typeLookUp(read.label, inClass: owner, before: index)
				if let declaredType = type(of: declaration, label: read.label) {
					guard let spelled = Self.spelledRead(read, declaredAs: declaredType) else { return nil }
					value = spelled
				} else {
					value = "nil"
				}
			}
			values.append(value)
		}
		return values
	}

	/// `values`, each after the argument label of its read, as a call's argument list.
	static func labeled(_ values: [String], of reads: [PlaceRead]) -> String {
		zip(reads, values).map { "\($0.argumentLabel.spelledAsArgumentLabel): \($1)" }.joined(separator: ", ")
	}

	/// How `read` reads a declaration of its label typed `declaredType`: the declaration itself, or its lazy wrapper's
	/// instance; `nil` where it reads it in neither way.
	static func spelledRead(_ read: PlaceRead, declaredAs declaredType: TypeDescription) -> String? {
		let receivedType = read.property.typeDescription
		if receivedType == declaredType || (receivedType.isOptional && receivedType.unwrapped == declaredType) {
			return read.label
		} else if let instanceType = declaredType.lazilyInstantiatedInstanceType, !declaredType.isOptional, receivedType.unwrapped == instanceType || receivedType == instanceType {
			return "\(read.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
		} else {
			guard let instanceType = declaredType.lazilyInstantiatedInstanceType, declaredType.isOptional, receivedType.isOptional, receivedType == instanceType else { return nil }
			return "\(read.label)?.\(Dependency.lazilyInstantiatedInstancePropertyName)"
		}
	}
}
