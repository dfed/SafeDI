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

// MARK: - Sample values

/// The sample values the base corpus's value oracle hands generated code where a value is forwarded: to an
/// instantiator with forwarded properties the describer calls (`DifferentialValueSample`), and to a mock whose
/// required parameters are forwarded values, beside the mirror that forwards the same values
/// (`GraphFuzzerMockMirror`). Each is a Swift expression the probe executable evaluates, a fresh value each time.
///
/// A sample is built by hand from what the fixture declares: `nil` for an optional, a fixed value of a standard type,
/// an empty collection, a closure that does nothing, a plain type's `init()`, an erasing type around a sample of what
/// it erases, a SafeDI wrapper, and a graph's type through its initializer (or its extension's `instantiate(…)`) with
/// a sample of each property – the type that fulfills a protocol standing in for the protocol. The describer shows a
/// sample, every class instance the expression marks with `differentialValueSample(_:)`, without what it holds, so
/// what a sample's own properties hold never matters: a builder a sample holds is one the describer never calls and
/// generated code never reaches (`differentialValueUnreachableSample()`), except a forwarded `LazilyInstantiated`'s,
/// whose instance generated code reads for a receiver of the instance, and which builds a marked sample. A type has no
/// sample when it, or a property its initializer takes by value, is none of these: an existential with no fulfilling
/// type, a type of the graph whose initializer another module or package hides, or one that takes itself by value
/// through its properties. A graph split across modules gets no samples: the probe executable is no module of its
/// packages, so it cannot name a `package` declaration.
struct GraphFuzzerSampleValues {
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	init(fixture: GraphFuzzerFixture, model: GraphFuzzerMockMirrorModel) {
		self.model = model
		isAvailable = fixture.modules == nil
		var constructibleTypeNames = Set<String>()
		var plainTypeNames = Set<String>()
		var classTypeNames = Set<String>()
		var erasedTypeByErasingTypeName = [String: String]()
		for content in fixture.swiftFileContent {
			let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
			for (index, line) in lines.enumerated() {
				let indentation = line.prefix { $0 == "\t" }.count
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				let (modifier, declaration) = Self.splittingAccessModifier(of: trimmed)
				if declaration.hasPrefix("final class ") || declaration.hasPrefix("struct ") {
					let keyword = declaration.hasPrefix("struct ") ? "struct " : "final class "
					let name = String(declaration.dropFirst(keyword.count).prefix { $0.isLetter || $0.isNumber || $0 == "_" })
					guard Self.isVisibleToTheProbes(modifier) else { continue }
					if keyword == "final class " {
						classTypeNames.insert(name)
					}
					if declaration.hasSuffix("{}") {
						// No stored property: the implicit `init()`, internal, which the probes reach through `@testable`.
						if indentation == 0 {
							plainTypeNames.insert(name)
						}
						continue
					}
					guard let initializer = lines[(index + 1)...].lazy.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.contains("init(") || $0 == "}" }),
					      case let (initializerModifier, initializerDeclaration) = Self.splittingAccessModifier(of: initializer),
					      initializerDeclaration.hasPrefix("init("),
					      Self.isVisibleToTheProbes(initializerModifier)
					else { continue }
					if initializerDeclaration.hasPrefix("init() {") {
						// A nested helper type is named through the types around it, as the fixture spells it.
						plainTypeNames.insert(name)
					} else if indentation == 0, initializerDeclaration.hasPrefix("init(_ value: "), let end = initializerDeclaration.range(of: ") {") {
						erasedTypeByErasingTypeName[name] = String(initializerDeclaration[initializerDeclaration.index(initializerDeclaration.startIndex, offsetBy: "init(_ value: ".count)..<end.lowerBound])
					} else if indentation == 0 {
						constructibleTypeNames.insert(name)
					}
				} else if declaration.hasPrefix("static func instantiate("), Self.isVisibleToTheProbes(modifier),
				          // An extension's `instantiate(…)`, of the type the closest extension above it extends, when not nested.
				          let extensionLine = lines[..<index].last(where: { $0.hasPrefix("extension ") })
				{
					let extendedType = extensionLine.dropFirst("extension ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
					if !extendedType.contains(".") {
						constructibleTypeNames.insert(String(extendedType))
					}
				}
			}
		}
		self.constructibleTypeNames = constructibleTypeNames
		self.plainTypeNames = plainTypeNames
		self.classTypeNames = classTypeNames
		self.erasedTypeByErasingTypeName = erasedTypeByErasingTypeName
	}

	/// Whether the graph gets samples at all.
	let isAvailable: Bool

	/// An expression of a sample value of `type`, each class instance it holds by value marked as a sample, or `nil` when
	/// the type has none.
	func expression(ofType type: String) -> String? {
		guard isAvailable else { return nil }
		return expression(ofType: type, isMarked: true, visiting: [])
	}

	/// The sample of each type of the graph with forwarded properties that has one: its `ForwardedProperties`, the one
	/// forwarded property's value, or a tuple of them in label order, in the model's type order.
	var forwardedPropertiesSamples: [DifferentialValueSample] {
		guard isAvailable else { return [] }
		return model.typeOrder.compactMap { typeName -> DifferentialValueSample? in
			guard let type = model.types[typeName], !type.isExtension else { return nil }
			let forwardedProperties = type.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted()
			guard !forwardedProperties.isEmpty, let value = forwardedPropertiesExpression(of: forwardedProperties) else { return nil }
			return DifferentialValueSample(type: "\(typeName).ForwardedProperties", expression: value)
		}
	}

	/// An expression of `properties`' values as an instantiator takes them: the one property's value, or a tuple of
	/// them in label order, or `nil` when one of them has no sample.
	func forwardedPropertiesExpression(of properties: [GraphFuzzerMirrorProperty]) -> String? {
		guard isAvailable else { return nil }
		let values = properties.sorted().map { property in
			expression(ofType: property.type).map { (label: property.label, value: $0) }
		}
		guard values.allSatisfy({ $0 != nil }) else { return nil }
		let labeledValues = values.compactMap(\.self)
		return labeledValues.count == 1
			? labeledValues[0].value
			: "(\(labeledValues.map { "\($0.label): \($0.value)" }.joined(separator: ", ")))"
	}

	// MARK: Private

	private let model: GraphFuzzerMockMirrorModel
	/// The graph's types the probes can build through an initializer or an extension's `instantiate(…)` that takes a
	/// sample of each property.
	private let constructibleTypeNames: Set<String>
	/// The fixture's types with an `init()`: a class without stored properties, or a helper type that declares one.
	private let plainTypeNames: Set<String>
	/// The fixture's classes the probes can name, whose instances a sample marks.
	private let classTypeNames: Set<String>
	/// The type each erasing type, `AnyT<n>`, erases, which its unlabeled initializer takes.
	private let erasedTypeByErasingTypeName: [String: String]

	/// - Parameters:
	///   - isMarked: Whether each class instance the value is, or holds as an element, is marked as a sample: true for
	///     what generated code is handed, false for what a sample holds, which the describer never shows.
	///   - visiting: The graph's types being built by value around this one, which a type its properties take by value
	///     again cannot be.
	private func expression(ofType rawType: String, isMarked: Bool, visiting: Set<String>) -> String? {
		let type = rawType.trimmingCharacters(in: .whitespaces)
		if let signature = Self.functionSignature(of: type) {
			let body: String
			if signature.returnType == "Void" || signature.returnType == "()" {
				body = ""
			} else if let returnValue = expression(ofType: signature.returnType, isMarked: false, visiting: visiting) {
				body = " \(returnValue) "
			} else {
				return nil
			}
			return signature.parameterCount == 0
				? "{\(body.isEmpty ? " " : body)}"
				: "{ \(Array(repeating: "_", count: signature.parameterCount).joined(separator: ", ")) in\(body.isEmpty ? " " : body)}"
		} else if type.hasSuffix("?") {
			return "nil"
		} else if type == "Void" || type == "()" {
			return "()"
		} else if type.hasPrefix("("), type.hasSuffix(")") {
			let elements = GraphFuzzerMirrorTypes.tupleElements(of: type)
			guard !elements.isEmpty else { return nil }
			var values = [String]()
			for element in elements {
				guard let value = expression(ofType: element.type, isMarked: isMarked, visiting: visiting) else { return nil }
				values.append("\(element.label): \(value)")
			}
			return "(\(values.joined(separator: ", ")))"
		} else if type.hasPrefix("[") {
			return Self.isDictionaryLiteralType(type) ? "[:]" : "[]"
		} else if let (name, arguments) = GraphFuzzerMirrorTypes.generic(type) {
			return genericExpression(ofType: type, name: name, arguments: arguments, isMarked: isMarked, visiting: visiting)
		} else if let standardValue = Self.standardValues[type] {
			return standardValue
		} else {
			return namedTypeExpression(ofType: type, isMarked: isMarked, visiting: visiting)
		}
	}

	/// A wrapper is built without its generic arguments, which every place a sample is written in gives it: an expression
	/// cannot spell a generic argument that is a function type with attributes.
	private func genericExpression(ofType type: String, name: String, arguments: [String], isMarked: Bool, visiting: Set<String>) -> String? {
		let built: String
		switch name {
		case "Array", "Set", "Swift.Array", "Swift.Set":
			return "[]"
		case "Dictionary", "Swift.Dictionary":
			return "[:]"
		case "Instantiator", "SendableInstantiator":
			// A builder a sample holds, or one handed to generated code, which passes it on and never calls it.
			guard arguments.count == 1 else { return nil }
			let takesForwardedProperties = model.types[arguments[0]]?.dependencies.contains { $0.source == .forwarded } == true
			built = "\(name) { \(takesForwardedProperties ? "_ in " : "")differentialValueUnreachableSample() }"
		case "ErasedInstantiator", "SendableErasedInstantiator":
			guard arguments.count == 2 else { return nil }
			let takesForwardedProperties = arguments[0] != "()" && arguments[0] != "Void"
			built = "\(name) { \(takesForwardedProperties ? "_ in " : "")differentialValueUnreachableSample() }"
		case "LazilyInstantiated", "SendableLazilyInstantiated":
			guard arguments.count == 1 else { return nil }
			if isMarked {
				// Generated code reads the instance of a forwarded one for a receiver of the instance.
				guard let instance = expression(ofType: arguments[0], isMarked: true, visiting: visiting) else { return nil }
				built = "\(name) { \(instance) }"
			} else {
				built = "\(name) { differentialValueUnreachableSample() }"
			}
		default:
			guard plainTypeNames.contains(Self.lastComponent(of: name)) else { return nil }
			return "\(type)()"
		}
		return isMarked ? "differentialValueSample(\(built))" : built
	}

	private func namedTypeExpression(ofType type: String, isMarked: Bool, visiting: Set<String>) -> String? {
		let built: String
		if let declaration = model.types[type], constructibleTypeNames.contains(type) {
			guard !visiting.contains(type) else { return nil }
			var arguments = [String]()
			for dependency in declaration.dependencies {
				guard let value = expression(ofType: dependency.property.type, isMarked: false, visiting: visiting.union([type])) else { return nil }
				arguments.append("\(dependency.property.label): \(value)")
			}
			built = declaration.isExtension
				? "\(type).instantiate(\(arguments.joined(separator: ", ")))"
				: "\(type)(\(arguments.joined(separator: ", ")))"
		} else if let scopeTypeName = model.scopeTypeName(of: type), scopeTypeName != type {
			// A protocol a type of the graph fulfills, which an instance of that type is.
			return expression(ofType: scopeTypeName, isMarked: isMarked, visiting: visiting)
		} else if let erasedType = erasedTypeByErasingTypeName[type] {
			guard let erasedValue = expression(ofType: erasedType, isMarked: false, visiting: visiting) else { return nil }
			built = "\(type)(\(erasedValue))"
		} else if plainTypeNames.contains(Self.lastComponent(of: type)) {
			// A helper struct is described by what it holds, which is nothing.
			built = "\(type)()"
			guard classTypeNames.contains(Self.lastComponent(of: type)) else { return built }
		} else {
			return nil
		}
		return isMarked ? "differentialValueSample(\(built))" : built
	}

	/// The fixed value of each standard type a fixture spells.
	private static let standardValues = [
		"Int": "0",
		"Swift.Int": "0",
		"Double": "0",
		"Bool": "false",
		"String": "\"\"",
		"Swift.String": "\"\"",
		"Date": "Foundation.Date(timeIntervalSinceReferenceDate: 0)",
		"Foundation.Date": "Foundation.Date(timeIntervalSinceReferenceDate: 0)",
		"UUID": "Foundation.UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))",
		"Foundation.UUID": "Foundation.UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))",
	]

	private static func lastComponent(of type: String) -> String {
		String(type.split(separator: ".").last ?? Substring(type))
	}

	/// Whether `type`, spelled `[…]`, is a dictionary: a colon outside every bracket within it.
	private static func isDictionaryLiteralType(_ type: String) -> Bool {
		var depth = 0
		for character in type.dropFirst().dropLast() {
			switch character {
			case "[", "(", "<":
				depth += 1
			case "]", ")", ">":
				depth -= 1
			case ":" where depth == 0:
				return true
			default:
				break
			}
		}
		return false
	}

	/// The number of parameters and the return type of `type` when it is a function type, its attributes and isolation
	/// before its parameters, and `async` and `throws` after: `nil` for any other type.
	static func functionSignature(of type: String) -> (parameterCount: Int, returnType: String)? {
		var rest = Substring(type).drop { $0 == " " }
		while !rest.hasPrefix("(") {
			if rest.hasPrefix("@") {
				rest = rest.dropFirst().drop { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
				if rest.hasPrefix("(") {
					guard let group = balancedGroup(at: rest) else { return nil }
					rest = rest[group.end...]
				}
			} else if rest.hasPrefix("nonisolated(") {
				rest = rest.dropFirst("nonisolated".count)
				guard let group = balancedGroup(at: rest) else { return nil }
				rest = rest[group.end...]
			} else if rest.hasPrefix("sending ") {
				rest = rest.dropFirst("sending ".count)
			} else {
				return nil
			}
			rest = rest.drop { $0 == " " }
		}
		guard let parameters = balancedGroup(at: rest) else { return nil }
		rest = rest[parameters.end...].drop { $0 == " " }
		if rest.hasPrefix("async") {
			rest = rest.dropFirst("async".count).drop { $0 == " " }
		}
		if rest.hasPrefix("throws") {
			rest = rest.dropFirst("throws".count)
			if rest.hasPrefix("(") {
				guard let thrownType = balancedGroup(at: rest) else { return nil }
				rest = rest[thrownType.end...]
			}
			rest = rest.drop { $0 == " " }
		}
		guard rest.hasPrefix("->") else { return nil }
		let parameterList = parameters.inner.trimmingCharacters(in: .whitespaces)
		let parameterCount = parameterList.isEmpty ? 0 : GraphFuzzerMirrorTypes.generic("<\(parameterList)>")?.arguments.count ?? 1
		return (parameterCount, rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
	}

	/// The parenthesized group `text` begins with: what it holds, and where it ends.
	private static func balancedGroup(at text: Substring) -> (inner: Substring, end: Substring.Index)? {
		guard text.hasPrefix("(") else { return nil }
		var depth = 0
		var index = text.startIndex
		while index < text.endIndex {
			switch text[index] {
			case "(":
				depth += 1
			case ")":
				depth -= 1
				if depth == 0 {
					return (text[text.index(after: text.startIndex)..<index], text.index(after: index))
				}
			default:
				break
			}
			index = text.index(after: index)
		}
		return nil
	}

	/// The access modifier `line` begins with, `""` for none, and the rest of the line, past a global actor before it.
	private static func splittingAccessModifier(of line: String) -> (modifier: String, declaration: String) {
		let line = line.hasPrefix("@MainActor ") ? String(line.dropFirst("@MainActor ".count)) : line
		for modifier in ["public", "package", "internal", "open", "fileprivate", "private"] where line.hasPrefix(modifier + " ") {
			return (modifier, String(line.dropFirst(modifier.count + 1)))
		}
		return ("", line)
	}

	/// Whether the probe executable, which `@testable import`s the fixture's module and is no module of its package,
	/// can name a declaration with `modifier`.
	private static func isVisibleToTheProbes(_ modifier: String) -> Bool {
		modifier == "" || modifier == "public" || modifier == "internal" || modifier == "open"
	}
}
