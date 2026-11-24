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

// Shared builder functions: a mock's body declares one function per class of the builder functions
// its walk declared, at the top of the body, each taking its configuration (or its override closure) as a parameter, in
// place of one nested function per place.

extension MockLowering {
	/// A builder function the walk declared, in declaration order: what the shared layout reads of it besides its text.
	struct SharedBuilderFunction: Sendable {
		/// The function's name as the walk declared it.
		let name: String
		/// The path of the configuration (or override closure) the function reads, from the mock's overrides.
		let overridePath: String
		/// The type of what `overridePath` holds: the type's configuration, or its optional override closure.
		var overrideParameterType: String
		/// The names the function's body binds, each with its type spelled as a function parameter, which a function
		/// nested in it that reads one is passed.
		var bindings = [(name: String, typeSource: String)]()
	}

	/// What the walk records for the shared layout: each builder function it declared, or `nil` once a place it cannot
	/// share was reached, which keeps the root's body as the walk wrote it.
	struct SharedBuilders: Sendable {
		var functions: [SharedBuilderFunction]? = []
		/// The indices in `functions` of the builder functions the walk is inside, innermost last.
		var open = [Int]()

		mutating func opening(_ function: SharedBuilderFunction) {
			guard functions != nil else { return }
			functions?.append(function)
			open.append((functions?.count ?? 1) - 1)
		}

		mutating func closing(bindings: [(name: String, typeSource: String)], overrideParameterType: String) {
			guard let index = open.popLast() else { return }
			functions?[index].bindings = bindings
			functions?[index].overrideParameterType = overrideParameterType
		}

		mutating func cannotShare() {
			functions = nil
		}
	}

	/// The reserved name of a shared builder function's configuration parameter.
	static let sharedBuilderOverridesName = "__safeDI_overrides"

	/// `bodyLines`, a mock's body as the walk wrote it with its root's statements indented `bodyIndent`, laid out again
	/// with one function per class of `functions`, or `nil` where the layout cannot be proven to read what the walk's does.
	static func sharingBuilderFunctions(ofBody bodyLines: [String], bodyIndent: String, functions: [SharedBuilderFunction]) -> [String]? {
		var layout = SharedBuilderLayout(functions: functions, bodyIndent: bodyIndent)
		guard layout.read(bodyLines), layout.computeClasses() else { return nil }
		return layout.spelledBody()
	}
}

/// The shared layout of one mock body.
private struct SharedBuilderLayout {
	enum Item {
		case line(String)
		case function(Int)
	}

	struct Function {
		let record: MockLowering.SharedBuilderFunction
		let indent: Int
		let parent: Int?
		let parameters: String
		let returnType: String
		var items = [Item]()
		var children = [Int]()
		/// The names the function's own statements declare, recorded or not.
		var declaredNames = Set<String>()
		// Filled by `computeClasses()`.
		var classIndex = 0
		var passed = [(name: String, typeSource: String)]()
	}

	struct FunctionClass {
		let parameters: String
		let returnType: String
		let body: [String]
		let firstMember: Int
	}

	let records: [MockLowering.SharedBuilderFunction]
	let bodyIndent: String
	var rootItems = [Item]()
	var functions = [Function]()
	var classes = [FunctionClass]()

	init(functions records: [MockLowering.SharedBuilderFunction], bodyIndent: String) {
		self.records = records
		self.bodyIndent = bodyIndent
	}

	static let classTokenPrefix = "__safeDI_sharedClass_"

	/// Reads the body's builder functions, which must be exactly the recorded ones, in order.
	mutating func read(_ lines: [String]) -> Bool {
		var open = [Int]()
		for line in lines {
			if let index = open.last, line == String(repeating: " ", count: functions[index].indent) + "}" {
				open.removeLast()
				continue
			}
			let trimmed = line.drop { $0 == " " }
			let indent = line.count - trimmed.count
			if functions.count<records.count, trimmed.hasPrefix("func \(records[functions.count].name)("), trimmed.hasSuffix(" {"), indent>(open.last.map { functions[$0].indent } ?? bodyIndent.count - 1) {
				let header = trimmed.dropFirst("func \(records[functions.count].name)(".count).dropLast(2)
				guard let arrow = header.range(of: ") -> ", options: .backwards) else { return false }
				let function = Function(record: records[functions.count], indent: indent, parent: open.last, parameters: String(header[..<arrow.lowerBound]), returnType: String(header[arrow.upperBound...]))
				let index = functions.count
				functions.append(function)
				if let parent = open.last {
					functions[parent].items.append(.function(index))
					functions[parent].children.append(index)
				} else {
					rootItems.append(.function(index))
				}
				open.append(index)
				continue
			}
			// A function the walk did not record, such as a `@Sendable` one, is not shared.
			guard !trimmed.contains("func ") || trimmed.hasPrefix("let ") else { return false }
			if let index = open.last {
				let statement = String(line.dropFirst(functions[index].indent + 4))
				if statement.hasPrefix("let "), let name = Self.identifiers(in: String(statement.dropFirst(4))).first {
					functions[index].declaredNames.insert(name)
				}
				functions[index].items.append(.line(statement))
			} else {
				rootItems.append(.line(line))
			}
		}
		return open.isEmpty && functions.count == records.count
	}

	/// Rewrites each function's body to read its configuration from its parameter and to call its children's classes,
	/// innermost first, and classes the functions by what they would declare.
	mutating func computeClasses() -> Bool {
		let functionNames = Set(records.map(\.name))
		var classIndexByKey = [[String]: Int]()
		for index in functions.indices.reversed() {
			let function = functions[index]
			let path = function.record.overridePath
			let childNames = Set(function.children.map { functions[$0].record.name })
			var body = [String]()
			for item in function.items {
				guard case var .line(line) = item else { continue }
				// A call of a function other than its own children's would not resolve where the class is declared.
				for identifier in Self.identifiers(in: line) where functionNames.contains(identifier) && !childNames.contains(identifier) {
					return false
				}
				line = Self.replacing(path: path, with: MockLowering.sharedBuilderOverridesName, in: line)
				for child in function.children {
					guard let line2 = callingClass(of: child, from: function, in: line) else { return false }
					line = line2
				}
				// Every override the body reads is beneath its own.
				guard !Self.identifiers(in: line).contains(ReservedName.mockOverridesParameterName) else { return false }
				body.append(line)
			}
			// The names the body reads that a function around it binds are passed, the innermost binding of each.
			let ownNames = Set(function.record.bindings.map(\.name)).union(Self.parameterLabels(function.parameters))
			var passed = [(name: String, typeSource: String)]()
			var passedNames = Set<String>()
			for identifier in body.flatMap(Self.identifiers(in:)) where !ownNames.contains(identifier) && !passedNames.contains(identifier) {
				var ancestor = function.parent
				while let current = ancestor {
					if let binding = functions[current].record.bindings.first(where: { $0.name == identifier }) {
						passed.append(binding)
						passedNames.insert(identifier)
						break
					}
					// A name the walk did not record a type for cannot be passed.
					if functions[current].declaredNames.contains(identifier) {
						return false
					}
					if let parameter = Self.parameters(functions[current].parameters).first(where: { $0.name == identifier }) {
						passed.append(parameter)
						passedNames.insert(identifier)
						break
					}
					ancestor = functions[current].parent
				}
			}
			passed.sort { $0.name < $1.name }
			var parameters = function.parameters.isEmpty ? [] : [function.parameters]
			parameters.append(contentsOf: passed.map { "\($0.name): \($0.typeSource)" })
			parameters.append("\(MockLowering.sharedBuilderOverridesName): \(function.record.overrideParameterType)")
			let parameterList = parameters.joined(separator: ", ")
			let key = [parameterList, function.returnType] + body
			let classIndex: Int
			if let existing = classIndexByKey[key] {
				classIndex = existing
			} else {
				classIndex = classes.count
				classIndexByKey[key] = classIndex
				classes.append(FunctionClass(parameters: parameterList, returnType: function.returnType, body: body, firstMember: index))
			}
			functions[index].classIndex = classIndex
			functions[index].passed = passed
		}
		return true
	}

	/// `line` with each call of `child`'s function calling its class, passed what the class takes beyond the function's
	/// own arguments, or `nil` where the child's configuration is not beneath its parent's.
	private func callingClass(of child: Int, from parent: Function, in line: String) -> String? {
		let record = functions[child].record
		guard record.overridePath.hasPrefix("\(parent.record.overridePath).") else { return nil }
		let relativePath = MockLowering.sharedBuilderOverridesName + record.overridePath.dropFirst(parent.record.overridePath.count)
		let extra = functions[child].passed.map { "\($0.name): \($0.name)" } + ["\(MockLowering.sharedBuilderOverridesName): \(relativePath)"]
		return Self.replacingCalls(of: record.name, with: "\(Self.classTokenPrefix)\(functions[child].classIndex)_", adding: extra, in: line)
	}

	/// The body with every class declared once, before the first statement of the root that reaches it, in first-reach
	/// order, each named after its first-reached place.
	func spelledBody() -> [String] {
		// Names in first-reach order, apart from every name the root's statements bind.
		var takenNames = Set<String>()
		for item in rootItems {
			if case let .line(line) = item {
				takenNames.formUnion(Self.identifiers(in: line))
			}
		}
		var classNames = [Int: String]()
		var classOrderByRootFunction = [Int: [Int]]()
		var rootFunction = [Int](repeating: 0, count: functions.count)
		for index in functions.indices {
			rootFunction[index] = functions[index].parent.map { rootFunction[$0] } ?? index
			let classIndex = functions[index].classIndex
			guard classNames[classIndex] == nil else { continue }
			var name = functions[index].record.name
			while takenNames.contains(name) {
				name += "_"
			}
			takenNames.insert(name)
			classNames[classIndex] = name
			classOrderByRootFunction[rootFunction[index], default: []].append(classIndex)
		}
		func named(_ line: String) -> String {
			var line = line
			while let range = line.range(of: Self.classTokenPrefix) {
				let digits = line[range.upperBound...].prefix { $0.isNumber }
				let end = line.index(range.upperBound, offsetBy: digits.count + 1)
				line.replaceSubrange(range.lowerBound..<end, with: classNames[Int(digits) ?? 0] ?? "")
			}
			return line
		}
		var lines = [String]()
		var rootCalls = [(name: String, call: String, extra: [String])]()
		for item in rootItems {
			switch item {
			case var .line(line):
				for call in rootCalls {
					line = Self.replacingCalls(of: call.name, with: call.call, adding: call.extra, in: line)
				}
				lines.append(line)
			case let .function(index):
				for classIndex in classOrderByRootFunction[index] ?? [] {
					let functionClass = classes[classIndex]
					lines.append("\(bodyIndent)func \(classNames[classIndex] ?? "")(\(functionClass.parameters)) -> \(functionClass.returnType) {")
					lines.append(contentsOf: functionClass.body.map { "\(bodyIndent)\(ScopeGenerator.standardIndent)\(named($0))" })
					lines.append("\(bodyIndent)}")
				}
				rootCalls.append((functions[index].record.name, classNames[functions[index].classIndex] ?? "", ["\(MockLowering.sharedBuilderOverridesName): \(functions[index].record.overridePath)"]))
			}
		}
		return lines
	}

	// MARK: Text

	static func isIdentifierCharacter(_ character: Character) -> Bool {
		character == "_" || character.isLetter || character.isNumber
	}

	/// The identifiers `line` reads, leaving out a member after `.` and the contents of string literals.
	static func identifiers(in line: String) -> [String] {
		var identifiers = [String]()
		var current = ""
		var previous: Character = " "
		var inString = false
		for character in line {
			if character == "\"" {
				inString.toggle()
			}
			if !inString, isIdentifierCharacter(character), !(current.isEmpty && character.isNumber) {
				if current.isEmpty, previous == "." || previous == "$" {
					current = "."
				}
				current.append(character)
			} else {
				if !current.isEmpty, current.first != "." {
					identifiers.append(current)
				}
				current = ""
			}
			previous = character
		}
		if !current.isEmpty, current.first != "." {
			identifiers.append(current)
		}
		return identifiers
	}

	/// `line` with `path` read as a whole, not as the start of a longer name, replaced by `replacement`.
	static func replacing(path: String, with replacement: String, in line: String) -> String {
		var result = ""
		var rest = Substring(line)
		while let range = rest.range(of: path) {
			let before = range.lowerBound == rest.startIndex ? (result.last ?? " ") : rest[rest.index(before: range.lowerBound)]
			let after = range.upperBound == rest.endIndex ? " " : rest[range.upperBound]
			result += rest[..<range.lowerBound]
			if isIdentifierCharacter(before) || before == "." || isIdentifierCharacter(after) {
				result += rest[range]
			} else {
				result += replacement
			}
			rest = rest[range.upperBound...]
		}
		return result + rest
	}

	/// `line` with each call of `name` calling `replacement`, with `extra` arguments after its own.
	static func replacingCalls(of name: String, with replacement: String, adding extra: [String], in line: String) -> String {
		var result = ""
		var rest = Substring(line)
		let opening = "\(name)("
		while let range = rest.range(of: opening) {
			let before = range.lowerBound == rest.startIndex ? (result.last ?? " ") : rest[rest.index(before: range.lowerBound)]
			result += rest[..<range.lowerBound]
			guard !isIdentifierCharacter(before), before != "." else {
				result += rest[range]
				rest = rest[range.upperBound...]
				continue
			}
			var depth = 1
			var index = range.upperBound
			while index < rest.endIndex, depth > 0 {
				if rest[index] == "(" {
					depth += 1
				}
				if rest[index] == ")" {
					depth -= 1
				}
				if depth > 0 {
					index = rest.index(after: index)
				}
			}
			let arguments = rest[range.upperBound..<index]
			result += "\(replacement)(\(([arguments.isEmpty ? nil : String(arguments)].compactMap(\.self) + extra).joined(separator: ", ")))"
			rest = index < rest.endIndex ? rest[rest.index(after: index)...] : rest[index...]
		}
		return result + rest
	}

	/// The labels a parameter list declares.
	static func parameterLabels(_ parameters: String) -> Set<String> {
		Set(Self.parameters(parameters).map(\.name))
	}

	/// The parameters of a parameter list, each label with its type.
	static func parameters(_ parameters: String) -> [(name: String, typeSource: String)] {
		var result = [(name: String, typeSource: String)]()
		var depth = 0
		var current = ""
		for character in parameters + "," {
			if "(<[".contains(character) {
				depth += 1
			}
			if ")>]".contains(character) {
				depth -= 1
			}
			if character == ",", depth == 0 {
				if let colon = current.firstIndex(of: ":") {
					result.append((current[..<colon].trimmingCharacters(in: .whitespaces), current[current.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
				}
				current = ""
			} else {
				current.append(character)
			}
		}
		return result
	}
}
