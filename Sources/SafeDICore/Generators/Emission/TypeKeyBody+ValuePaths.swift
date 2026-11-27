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
	func constructionShape(shapes: inout StructuralKeyParts) -> [String] {
		guard sharingFields != nil else { return [] }
		var shape = [String]()
		for alternative in alternatives {
			var requiresAbsent = [String]()
			for value in alternative.requiresAbsent {
				requiresAbsent.append(shapes.shape(of: value))
			}
			shape.append("alternative|\(shapes.shape(of: alternative.closure))|\(alternative.bindingName ?? "")|\(requiresAbsent.joined(separator: ","))|\(alternative.use)|\(alternative.resultWrapper?.asSource ?? "")")
		}
		for (position, value) in argumentValues.sorted(by: { $0.key < $1.key }) {
			shape.append("argumentValue|\(position)|\(shapes.shape(of: value))")
		}
		if let constructionValue {
			shape.append("value|\(shapes.shape(of: constructionValue.value))|\(constructionValue.resultWrapper?.asSource ?? "")")
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
}

extension PlaceRead {
	/// The read for a structural key: its argument label, label, property, and whether it reads `nil`.
	var shape: String {
		"\(argumentLabel):\(label):\(property.asSource):\(source == .nil)"
	}
}

extension PassedArgument {
	/// The argument for a caller's structural key: its parameter, its type and the shape of its value.
	func part(parts: inout StructuralKeyParts) -> StructuralKeyParts.Part {
		.passed(
			parameterName: parameterName,
			type: type.asSource,
			value: parts.id(of: value),
			staysOutsideSendableFunctions: staysOutsideSendableFunctions,
			bindsBeforeCall: bindsBeforeCall,
		)
	}

	/// The argument for a closer's structural key: a read as its parameter, its type and the label it reads, never the
	/// declaration that resolves to, which `checkEveryRead` proves alike at every member; any other value as a built
	/// place's call keys it (`part(parts:)`), so a closing call and a built call of one function that hand alike values
	/// share a key. Each value is checked as a built call's is (`checkValuePaths`, `checkSendableMarks`).
	func closerPart(parts: inout StructuralKeyParts) -> StructuralKeyParts.Part {
		switch value {
		case let .read(read):
			.passedRead(parameterName: parameterName, type: type.asSource, label: read.label, bindsBeforeCall: bindsBeforeCall)
		case .rootDeclaration,
		     .passedArgument,
		     .memberRead,
		     .optionalMemberRead,
		     .call,
		     .emptyInitialization,
		     .spliced:
			part(parts: &parts)
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

/// The parts of the structural keys of one partition of places into classes (`computeClasses`), each an id. A key was a
/// list of strings, each a part spelled out: a passed argument's type, value and flags spelled into one string, and a
/// value path spelled out again at each of its member reads. Two parts take one id exactly when they are alike in what
/// their strings spelled, so two keys are equal exactly when their strings were, and no class moves; a part's value path
/// is an id too, made of its base's id. Ids are handed out in the order parts are first met and are read only for
/// equality, never for order. It holds one entry per distinct part and path met, and dies with `computeClasses`.
struct StructuralKeyParts {
	/// A part of a structural key. Each case is a kind of string the key held, so no two kinds of part are alike.
	enum Part: Hashable {
		/// What the place builds and how, as `structuralKey(of:isInSendableFamily:parts:)` lists it.
		case header(
			concreteType: String,
			callee: String,
			isExtension: Bool,
			lineEnd: String,
			isInSendableFamily: Bool,
			forwardedProperties: [String],
			reads: [String],
		)
		case argument(argumentLabel: String, label: String, property: String)
		/// A part spelled as text: what a construction does besides calling its target, or an inline or alias statement.
		case text(String)
		case parameter(name: String, type: String)
		/// A parameter a variant of the per-type plan takes for a label its body's answers declare.
		case variantParameter(String)
		/// A call of a built place's function or a closer's.
		case call(property: String, isErased: Bool, isExtension: Bool)
		case passedArgumentCount(Int)
		case passed(parameterName: String, type: String, value: Int, staysOutsideSendableFunctions: Bool, bindsBeforeCall: Bool)
		case passedRead(parameterName: String, type: String, label: String, bindsBeforeCall: Bool)
	}

	/// The id of `part`.
	mutating func id(of part: Part) -> Int {
		guard let id = idsByPart[part] else {
			let id = idsByPart.count
			idsByPart[part] = id
			return id
		}
		return id
	}

	/// The id of `value`'s shape, spelled for a part spelled as text.
	mutating func shape(of value: ValuePath) -> String {
		"v\(id(of: value))"
	}

	// MARK: Private

	private enum Node: Hashable {
		case rootDeclaration(String)
		case read(String)
		case passedArgument(String)
		case member(name: String, base: Int, throughOptional: Bool)
		case call(name: String, value: Int, arguments: [String], argumentsWrapper: String?)
		case emptyInitialization(String)
		case spliced([Segment])
	}

	/// A segment of a spliced path: its text, its value's id, or the function's name, each a case of its own so no two
	/// kinds of segment are alike.
	private enum Segment: Hashable {
		case text(String)
		case value(Int)
		case declaredFunction(String)
	}

	private var idsByPart = [Part: Int]()
	private var idsByNode = [Node: Int]()

	/// The id of `value`, reached through its member reads without recursing, since a chain of them can be as deep as the
	/// configurations it reads through.
	mutating func id(of value: ValuePath) -> Int {
		var members = [(name: String, throughOptional: Bool)]()
		var current = value
		var node: Node
		reading: while true {
			switch current {
			case let .memberRead(name, base):
				members.append((name, false))
				current = base.value
			case let .optionalMemberRead(name, base):
				members.append((name, true))
				current = base.value
			case let .rootDeclaration(name):
				node = .rootDeclaration(name)
				break reading
			case let .read(read):
				node = .read(read.shape)
				break reading
			case let .passedArgument(name):
				node = .passedArgument(name)
				break reading
			case let .call(name, value, arguments, argumentsWrapper):
				node = Node.call(
					name: name,
					value: id(of: value),
					arguments: arguments.map(\.shape),
					argumentsWrapper: argumentsWrapper?.asSource,
				)
				break reading
			case let .emptyInitialization(type):
				node = .emptyInitialization(type.asSource)
				break reading
			case let .spliced(segments):
				var spliced = [Segment]()
				for segment in segments {
					switch segment {
					case let .text(text):
						spliced.append(.text(text))
					case let .value(value):
						spliced.append(.value(id(of: value)))
					case let .declaredFunction(name):
						spliced.append(.declaredFunction(name))
					}
				}
				node = .spliced(spliced)
				break reading
			}
		}
		return id(of: node, beneath: members)
	}

	/// The id of `node` read through `members`, the read nearest the node last.
	private mutating func id(of node: Node, beneath members: [(name: String, throughOptional: Bool)]) -> Int {
		var id = id(of: node)
		for member in members.reversed() {
			id = self.id(of: .member(name: member.name, base: id, throughOptional: member.throughOptional))
		}
		return id
	}

	private mutating func id(of node: Node) -> Int {
		guard let id = idsByNode[node] else {
			let id = idsByNode.count
			idsByNode[node] = id
			return id
		}
		return id
	}
}
