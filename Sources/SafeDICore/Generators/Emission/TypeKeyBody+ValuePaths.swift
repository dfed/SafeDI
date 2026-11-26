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

extension BuiltPlaceRecord {
	/// The reads the place's construction makes where it is built: its arguments, then the reads of each alternative's
	/// closure and of the values that must be absent, then the reads of its construction value.
	var constructionReads: [PlaceRead] {
		guard let sharingFields else { return arguments }
		var reads = [PlaceRead]()
		for (position, argument) in arguments.enumerated() {
			if let value = sharingFields.argumentValues[position] {
				reads.append(contentsOf: value.reads)
			} else {
				reads.append(argument)
			}
		}
		for alternative in alternatives {
			reads.append(contentsOf: alternative.closure.reads)
			for absent in alternative.requiresAbsent {
				reads.append(contentsOf: absent.reads)
			}
		}
		if let constructionValue {
			reads.append(contentsOf: constructionValue.value.reads)
		}
		return reads
	}

	/// The values the place's function is handed and declares for its body: what its wrapper forwards, then its passed
	/// arguments, which a read in its body resolves to as it resolves to a forwarded value.
	var parameterProperties: [Property] {
		guard let sharingFields else { return forwardedProperties }
		return forwardedProperties + sharingFields.passedArguments.map { Property(label: $0.parameterName, typeDescription: $0.type) }
	}

	/// The reads the place's call makes in its parent's body: what it passes its cycle parameters, then the reads of what
	/// it hands its passed arguments.
	var callSiteReads: [PlaceRead] {
		guard let sharingFields else { return callCycleArguments }
		return callCycleArguments + sharingFields.passedArguments.flatMap(\.value.reads)
	}

	/// The shape of what the place's construction does besides calling its target, for a structural key: never a label a
	/// read names apart from the read itself.
	var constructionShape: [String] {
		guard sharingFields != nil else { return [] }
		var shape = alternatives.map { alternative in
			"alternative|\(alternative.closure.shape)|\(alternative.bindingName ?? "")|\(alternative.requiresAbsent.map(\.shape).joined(separator: ","))|\(alternative.use)|\(alternative.resultWrapper?.asSource ?? "")"
		}
		for (position, value) in argumentValues.sorted(by: { $0.key < $1.key }) {
			shape.append("argumentValue|\(position)|\(value.shape)")
		}
		if let constructionValue {
			shape.append("value|\(constructionValue.value.shape)|\(constructionValue.resultWrapper?.asSource ?? "")")
		}
		if let functionReturnType {
			shape.append("returns|\(functionReturnType.asSource)")
		}
		return shape
	}
}

extension ClosingPlaceRecord {
	/// The reads the closing call makes: what it passes the cycle parameters, then the reads of its passed arguments.
	var callSiteReads: [PlaceRead] {
		passedArguments.isEmpty ? cycleArguments : cycleArguments + passedArguments.flatMap(\.value.reads)
	}
}

extension ValuePath {
	/// The ordinary reads the path makes, in the order it is spelled.
	var reads: [PlaceRead] {
		switch self {
		case .rootDeclaration,
		     .passedArgument,
		     .emptyInitialization:
			[]
		case let .read(read):
			[read]
		case let .memberRead(_, base),
		     let .optionalMemberRead(_, base):
			base.value.reads
		case let .call(_, value, arguments, _):
			value.reads + arguments
		case let .spliced(segments):
			segments.flatMap(\.reads)
		}
	}

	/// The functions the path names that a statement before it declares (`ValueSegment.declaredFunction`), in the order
	/// it is spelled.
	var declaredFunctionNames: [String] {
		switch self {
		case .rootDeclaration,
		     .read,
		     .passedArgument,
		     .emptyInitialization:
			[]
		case let .memberRead(_, base),
		     let .optionalMemberRead(_, base):
			base.value.declaredFunctionNames
		case let .call(_, value, _, _):
			value.declaredFunctionNames
		case let .spliced(segments):
			segments.flatMap { segment -> [String] in
				switch segment {
				case .text:
					[]
				case let .value(value):
					value.declaredFunctionNames
				case let .declaredFunction(name):
					[name]
				}
			}
		}
	}

	/// The names of the passed arguments the path reads.
	var passedArgumentNames: [String] {
		switch self {
		case .rootDeclaration,
		     .read,
		     .emptyInitialization:
			[]
		case let .passedArgument(name):
			[name]
		case let .memberRead(_, base),
		     let .optionalMemberRead(_, base):
			base.value.passedArgumentNames
		case let .call(_, value, _, _):
			value.passedArgumentNames
		case let .spliced(segments):
			segments.flatMap { segment -> [String] in
				guard case let .value(value) = segment else { return [] }
				return value.passedArgumentNames
			}
		}
	}

	/// The path with each read reduced to its argument label, label, property and whether it reads `nil`.
	var shape: String {
		switch self {
		case let .rootDeclaration(name):
			"root:\(name)"
		case let .read(read):
			"read:\(read.shape)"
		case let .passedArgument(name):
			"passed:\(name)"
		case let .memberRead(name, base):
			"\(base.value.shape).\(name)"
		case let .optionalMemberRead(name, base):
			"\(base.value.shape)?.\(name)"
		case let .call(name, value, arguments, argumentsWrapper):
			"\(value.shape).\(name)(\(argumentsWrapper?.asSource ?? "")|\(arguments.map(\.shape).joined(separator: ",")))"
		case let .emptyInitialization(type):
			"new:\(type.asSource)"
		case let .spliced(segments):
			"spliced[\(segments.map(\.shape).joined(separator: ","))]"
		}
	}
}

extension ValueSegment {
	/// The reads the segment makes, in the order it is spelled.
	var reads: [PlaceRead] {
		switch self {
		case .text,
		     .declaredFunction:
			[]
		case let .value(value):
			value.reads
		}
	}

	/// The segment for a structural key: its text, its value's shape, or the function's name, each marked apart so no
	/// two kinds of segment share a key.
	var shape: String {
		switch self {
		case let .text(text):
			"text:\(text.count):\(text)"
		case let .value(value):
			"value:\(value.shape)"
		case let .declaredFunction(name):
			"function:\(name)"
		}
	}
}

extension PlaceRead {
	/// The read for a structural key: its argument label, label, property, and whether it reads `nil`.
	var shape: String {
		"\(argumentLabel):\(label):\(property.asSource):\(source == .nil)"
	}
}

extension PassedArgument {
	/// The argument for a caller's structural key: its parameter, its type and the shape of its value.
	var shape: String {
		"passed|\(parameterName)|\(type.asSource)|\(value.shape)|\(staysOutsideSendableFunctions)|\(bindsBeforeCall)"
	}
}

extension PassedArgument {
	/// The argument for a closer's structural key: a read as its parameter, its type and the label it reads, never the
	/// declaration that resolves to, which `checkEveryRead` proves alike at every member; any other value as a built
	/// place's call keys it (`shape`), so a closing call and a built call of one function that hand alike values share a
	/// key. Each value is checked as a built call's is (`checkValuePaths`, `checkSendableMarks`).
	var closerShape: String {
		switch value {
		case let .read(read):
			"passed|\(parameterName)|\(type.asSource)|read:\(read.label)|\(bindsBeforeCall)"
		case .rootDeclaration,
		     .passedArgument,
		     .memberRead,
		     .optionalMemberRead,
		     .call,
		     .emptyInitialization,
		     .spliced:
			shape
		}
	}
}

extension TypeKeyLayout {
	// MARK: Passed arguments and value paths

	/// The passed arguments the statement at `index` of `body` hands the function it calls, as its own place records them.
	func passedArguments(ofStatementAt index: Int, inBody body: Int) -> [PassedArgument] {
		switch bodies[body].statements[index] {
		case .built:
			passedArgumentsByCall[[body, index]] ?? []
		case let .closer(record, _):
			record.passedArguments
		case .inline,
		     .alias:
			[]
		}
	}

	/// The read that binds the place of the statement at `index` of `body` to `nil`, where its place records one
	/// (`BuiltPlaceRecord.nilAlternative`). Unlike what a call hands, it is the same at every place of one plan node,
	/// whose record holds it: the mock's walk makes places that read different ones different nodes
	/// (`MockLowering.SharedRecordKey`), and production's records hold none.
	func nilAlternative(ofStatementAt index: Int, inBody body: Int) -> ValuePath? {
		switch bodies[body].statements[index] {
		case let .built(child):
			bodies[child].record?.nilAlternative
		case let .inline(record):
			record.nilAlternative
		case .closer,
		     .alias:
			nil
		}
	}

	/// Whether every value path of every place names only passed arguments its function takes, the root's names none, and
	/// each ordinary read in a path reads in the type key's code what it reads in the path key's.
	func checkValuePaths() -> Bool {
		for body in bodies.indices {
			let owner = classByBody[body]
			let takenNames = Set(representative(of: owner)?.passedArguments.map(\.parameterName) ?? [])
			let statements = bodies[body].statements
			func check(_ path: ValuePath, before index: Int) -> Bool {
				guard path.passedArgumentNames.allSatisfy(takenNames.contains),
				      // A function is in scope only where a statement before the value's in its own body declares it.
				      path.declaredFunctionNames.allSatisfy({ bodies[body].positionsByDeclaredFunction[$0]?.contains(where: { $0 < index }) == true })
				else { return false }
				return path.reads.allSatisfy { read in
					checkRead(read, inBody: body, before: index, owner: owner, isNilAtEveryMember: read.source == .nil)
				}
			}
			if let record = bodies[body].record {
				guard record.argumentValues.keys.allSatisfy({ $0 < record.arguments.count }) else { return false }
				for path in record.argumentValues.values {
					guard check(path, before: statements.count) else { return false }
				}
				for path in record.alternatives.flatMap({ [$0.closure] + $0.requiresAbsent }) + (record.constructionValue.map { [$0.value] } ?? []) {
					guard check(path, before: statements.count) else { return false }
				}
			}
			for index in statements.indices {
				if case let .inline(record) = statements[index] {
					guard record.argumentValues.keys.allSatisfy({ $0 < record.arguments.count }) else { return false }
					for path in record.argumentValues.values {
						guard check(path, before: index) else { return false }
					}
					for path in record.alternatives.flatMap({ [$0.closure] + $0.requiresAbsent }) + (record.constructionValue.map { [$0.value] } ?? []) {
						guard check(path, before: index) else { return false }
					}
				}
				for argument in passedArguments(ofStatementAt: index, inBody: body) {
					guard check(argument.value, before: index) else { return false }
				}
				if let nilAlternative = nilAlternative(ofStatementAt: index, inBody: body) {
					guard check(nilAlternative, before: index) else { return false }
				}
			}
		}
		return true
	}

	/// Whether no value that stays outside `@Sendable` functions is read, or handed on, by a class whose function is
	/// `@Sendable`.
	func checkSendableMarks() -> Bool {
		for owner in membersByClass.indices.dropFirst() where isDecorated[owner] {
			for member in membersByClass[owner] {
				guard let record = bodies[member].record,
				      !record.constructionReads.contains(where: \.staysOutsideSendableFunctions),
				      // A value bound before the call is read where the call is made, outside this function.
				      !record.passedArguments.contains(where: { $0.staysOutsideSendableFunctions && !$0.bindsBeforeCall })
				else { return false }
				for (index, statement) in bodies[member].statements.enumerated() {
					let reads: [PlaceRead] = switch statement {
					case let .built(child):
						bodies[child].record?.callCycleArguments ?? []
					case let .inline(record):
						record.constructionReads
					case let .closer(record, _):
						record.callSiteReads
					case .alias:
						// A place written as text reads what the layout's text reads list (another lane's).
						[]
					}
					let passed = passedArguments(ofStatementAt: index, inBody: member)
					guard !reads.contains(where: \.staysOutsideSendableFunctions),
					      !passed.contains(where: { $0.staysOutsideSendableFunctions || $0.value.reads.contains(where: \.staysOutsideSendableFunctions) })
					else { return false }
				}
			}
		}
		return true
	}

	/// `path` as a statement before `index` of `owner`'s body spells it, or `nil` where a read cannot be spelled.
	func spelledValuePath(_ path: ValuePath, inClass owner: Int, before index: Int) -> String? {
		switch path {
		case let .rootDeclaration(name),
		     let .passedArgument(name):
			return name
		case let .read(read):
			return spelledValue(of: read, inClass: owner, before: index)
		case let .emptyInitialization(type):
			return "\(type.asSource)()"
		case let .memberRead(name, base):
			return spelledValuePath(base.value, inClass: owner, before: index).map { "\($0).\(name)" }
		case let .optionalMemberRead(name, base):
			return spelledValuePath(base.value, inClass: owner, before: index).map { "\($0)?.\(name)" }
		case let .call(name, value, arguments, argumentsWrapper):
			guard let receiver = spelledValuePath(value, inClass: owner, before: index) else { return nil }
			var spelledArguments = [String]()
			for argument in arguments {
				guard let value = spelledValue(of: argument, inClass: owner, before: index) else { return nil }
				spelledArguments.append("\(argument.argumentLabel.spelledAsArgumentLabel): \(value)")
			}
			let joined = spelledArguments.joined(separator: ", ")
			if let argumentsWrapper {
				return "\(receiver).\(name)(\(argumentsWrapper.asSource)(\(joined)))"
			} else {
				return "\(receiver).\(name)(\(joined))"
			}
		case let .spliced(segments):
			var spelled = ""
			for segment in segments {
				switch segment {
				case let .text(text):
					spelled += text
				case let .value(value):
					guard let value = spelledValuePath(value, inClass: owner, before: index) else { return nil }
					spelled += value
				case let .declaredFunction(name):
					spelled += name
				}
			}
			return spelled
		}
	}

	/// The value `read` passes where a statement before `index` of `owner`'s body makes it.
	func spelledValue(of read: PlaceRead, inClass owner: Int, before index: Int) -> String? {
		guard read.source != .nil, let declaredType = type(of: typeLookUp(read.label, inClass: owner, before: index), label: read.label) else { return "nil" }
		return Self.spelledRead(read, declaredAs: declaredType)
	}

	/// The construction of `record`, made before `index` of `owner`'s body: its construction value or its call, `call`,
	/// after each alternative in order.
	func spelledConstruction(of record: BuiltPlaceRecord, call: String, argumentValues: [String], inClass owner: Int, before index: Int) -> String? {
		var construction = call
		if let constructionValue = record.constructionValue {
			guard let value = spelledValuePath(constructionValue.value, inClass: owner, before: index) else { return nil }
			construction = constructionValue.resultWrapper.map { "\($0.asSource)(\(value))" } ?? value
		}
		for alternative in record.alternatives.reversed() {
			guard let closure = spelledValuePath(alternative.closure, inClass: owner, before: index) else { return nil }
			var conditions = [String]()
			if let bindingName = alternative.bindingName {
				conditions.append(bindingName == closure ? "let \(bindingName)" : "let \(bindingName) = \(closure)")
			}
			for absent in alternative.requiresAbsent {
				guard let value = spelledValuePath(absent, inClass: owner, before: index) else { return nil }
				conditions.append("\(value) == nil")
			}
			let callee = alternative.bindingName ?? closure
			let result = switch alternative.use {
			case .calledWithConstructionArguments:
				"\(callee)(\(argumentValues.joined(separator: ", ")))"
			case .calledWithNoArguments:
				"\(callee)()"
			case let .wrapped(wrapperType):
				"\(wrapperType.spelledForConstruction)(\(callee))"
			}
			let value = alternative.resultWrapper.map { "\($0.asSource)(\(result))" } ?? result
			if conditions.isEmpty {
				construction = value
			} else {
				let otherwise = construction.hasPrefix("if ") ? construction : "{ \(construction) }"
				construction = "if \(conditions.joined(separator: ", ")) { \(value) } else \(otherwise)"
			}
		}
		return construction
	}
}
