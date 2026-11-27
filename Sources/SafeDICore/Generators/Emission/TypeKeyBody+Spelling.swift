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
			owner != 0 && membersByClass[owner].contains { bodies[$0].record?.isSendable == true }
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
		functionNames = membersByClass.indices.map { owner in
			guard let representative = representative(of: owner) else { return "" }
			return allocator.claim(ScopeGenerator.functionName(toBuildPropertyNamed: representative.property.label))
		}
	}

	// MARK: Spelling

	mutating func spelledRootStatements() -> [GeneratedCode]? {
		var functionCode = [GeneratedCode](repeating: .empty, count: membersByClass.count)
		let classesByDepth = membersByClass.indices.dropFirst().sorted { placementDepth[$0] > placementDepth[$1] }
		for owner in classesByDepth {
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
			var value = Expression.construction(representative.target, arguments: arguments)
			if !representative.alternatives.isEmpty || representative.constructionValue != nil {
				guard let construction = spelledConstruction(of: representative, call: value.spelled, argumentValues: argumentValues, inClass: owner, before: statements(ofClass: owner).count) else { return nil }
				value = .spelledConstruction(construction)
			}
			functionCode[owner] = BuilderNode(
				name: functionNames[owner],
				isSendable: isDecorated[owner],
				parameters: parameters,
				typesDeclaredEscaping: typesDeclaredEscaping,
				returnType: representative.concreteType,
				body: BuilderBody(statements: body),
				value: value,
				lineEnd: representative.lineEnd,
			).spelled()
		}
		return spelledStatements(ofClass: 0, indentation: TypeKeyBody.rootStatementIndentation, functionCode: functionCode)
	}

	/// The statements of `owner`'s body, each with the functions declared before it, each indented by `indentation`.
	func spelledStatements(ofClass owner: Int, indentation: String, functionCode: [GeneratedCode]) -> [GeneratedCode]? {
		var code = [GeneratedCode]()
		for (index, statement) in statements(ofClass: owner).enumerated() where owner != 0 || index >= outerDeclarationCount {
			let site = CallSite(owner: owner, index: index)
			for function in hoistedFunctions[site] ?? [] {
				code.append(.indented(functionCode[function], by: indentation))
			}
			if let function = attachedFunction[site] {
				code.append(.indented(functionCode[function], by: indentation))
			}
			guard let text = spelledStatement(statement, inClass: owner, at: index) else { return nil }
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
			return spelledCall(of: classByBody[child], binding: record.property, isErased: record.isErased, isExtension: record.isExtension, inClass: owner, at: index)
		case let .closer(record, target):
			return spelledCall(of: classByBody[target], binding: record.property, isErased: record.isErased, isExtension: record.isExtension, inClass: owner, at: index)
		case let .alias(record):
			guard let call = record.call else { return record.text }
			return spelledInPlace(call, inClass: owner, at: index)
		}
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
		return GeneratedCode.sequence([function, Self.bindingOfInPlaceCall(of: record), .text("\n")]).spelled()
	}

	/// The binding of `record`'s property, a call written where its place is, to its builder function's result: by the rule
	/// a built place of the property's form binds it with, a wrapper of the function where the property is one.
	private static func bindingOfInPlaceCall(of record: BuiltPlaceRecord) -> GeneratedCode {
		switch record.property.propertyType {
		case .instantiator,
		     .erasedInstantiator,
		     .sendableInstantiator,
		     .sendableErasedInstantiator:
			.text(ScopeGenerator.instantiatorDeclaration(of: record.property, isExtension: record.isExtension, isErased: record.isErased, handing: record.functionName, forwardedArguments: ""))
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			.text("\(BindingDeclaration(property: record.property, rule: .lazilyInstantiated).spelled) = \(ScopeGenerator.lazilyInstantiatedInstantiation(of: record.property, callingFunctionNamed: record.functionName, cycleArguments: "", erasedToConcreteExistential: record.isErased))")
		case .constant:
			SafeDICore.Statement.binding(
				BindingDeclaration(
					property: record.property,
					rule: .constant(
						isErased: record.isErased,
						constructedTypeIsPropertyType: record.concreteType.asSource == record.property.typeDescription.asSource,
						hasBuilderFunction: true,
						isExtension: record.isExtension,
					),
				),
				Expression.call(function: record.functionName, arguments: "").erased(to: record.property.typeDescription.unwrapped, where: record.isErased),
				lineEnd: "",
			).spelled
		}
	}

	/// The binding of `property` to a call of `callee`'s function, made before the statement at `index` of `owner`'s body.
	func spelledCall(of callee: Int, binding property: Property, isErased: Bool, isExtension: Bool, inClass owner: Int, at index: Int) -> String? {
		guard let representative = representative(of: callee) else { return nil }
		var arguments = [String]()
		for label in reads[membersByClass[callee][0]] where outcomes[callee][label] == .passed {
			guard let parameterType = parameterTypes[callee][label],
			      let value = spelledArgument(label, passedTo: parameterType, inClass: owner, before: index)
			else { return nil }
			arguments.append("\(label.spelledAsArgumentLabel): \(value)")
		}
		// The members of `owner` hand their calls passed arguments of one shape (`structuralKey`), so its first member's
		// spell every member's.
		for argument in passedArguments(ofStatementAt: index, inBody: owner == 0 ? 0 : membersByClass[owner][0]) {
			guard let value = spelledValuePath(argument.value, inClass: owner, before: index) else { return nil }
			arguments.append("\(argument.parameterName.spelledAsArgumentLabel): \(value)")
		}
		let functionName = functionNames[callee]
		switch property.propertyType {
		case .instantiator,
		     .erasedInstantiator,
		     .sendableInstantiator,
		     .sendableErasedInstantiator:
			let isOnly = representative.forwardedProperties.count == 1
			let forwardedArguments = representative.forwardedProperties.map {
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
			let declaration = BindingDeclaration(
				property: property,
				rule: .constant(
					isErased: isErased,
					constructedTypeIsPropertyType: representative.concreteType.asSource == property.typeDescription.asSource,
					hasBuilderFunction: true,
					isExtension: isExtension,
				),
			)
			return "\(declaration.spelled) = \(Expression.call(function: functionName, arguments: arguments.joined(separator: ", ")).erased(to: property.typeDescription.unwrapped, where: isErased).spelled)"
		}
	}

	/// What a call made before the statement at `index` of `owner`'s body passes a parameter `label` of type
	/// `parameterType`: its nearest declaration, `nil`, or a wrapper made of a value where the parameter takes a wrapper.
	func spelledArgument(_ label: String, passedTo parameterType: TypeDescription, inClass owner: Int, before index: Int) -> String? {
		let declaration = typeLookUp(label, inClass: owner, before: index)
		guard let declaredType = type(of: declaration) else {
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
				if let declaredType = type(of: declaration) {
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
