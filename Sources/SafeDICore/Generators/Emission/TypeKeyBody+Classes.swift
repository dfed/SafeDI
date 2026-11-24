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
	// MARK: Classes

	/// The type of a path declaration.
	func type(of value: PathValue) -> TypeDescription? {
		switch value {
		case .none:
			nil
		case let .statement(body, index):
			property(of: bodies[body].statements[index])?.typeDescription
		case let .forwarded(body, label):
			bodies[body].record?.parameterProperties.first(where: { $0.label == label })?.typeDescription
		case let .cycleParameter(body, label):
			bodies[body].record?.cycleParameters.first(where: { $0.label == label })?.typeDescription
		}
	}

	/// Partitions the places into classes: by what each builds and how, its reads, the shape of its body and the classes its
	/// body calls, and the form of the declaration each read resolves to.
	mutating func computeClasses() {
		let count = bodies.count
		let families = bodies.map(\.isInSendableFamily)
		var structuralKeys = [[String]: Int]()
		var classes = [Int](repeating: 0, count: count)
		for body in bodies.indices.dropFirst() {
			let key = structuralKey(of: body, isInSendableFamily: families[body])
			classes[body] = structuralKeys[key] ?? {
				let id = structuralKeys.count + 1
				structuralKeys[key] = id
				return id
			}()
		}
		var refined = refine(classes)
		// Places alike in every other way are one class only where each read resolves to declarations of one form, or none.
		var groupsByClass = [Int: [[String?]]]()
		var groupedClasses = [[Int]: Int]()
		var classesWithForms = [Int](repeating: 0, count: count)
		for body in bodies.indices.dropFirst() {
			let forms: [String?] = reads[body].map { label in type(of: resolution(of: label, atPlace: body))?.unwrapped.asSource }
			var groups = groupsByClass[refined[body], default: []]
			var groupIndex = groups.firstIndex { group in
				zip(group, forms).allSatisfy { $0 == nil || $1 == nil || $0 == $1 }
			}
			if let existing = groupIndex {
				groups[existing] = zip(groups[existing], forms).map { $0 ?? $1 }
			} else {
				groupIndex = groups.count
				groups.append(forms)
			}
			groupsByClass[refined[body]] = groups
			let key = [refined[body], groupIndex ?? 0]
			classesWithForms[body] = groupedClasses[key] ?? {
				let id = groupedClasses.count + 1
				groupedClasses[key] = id
				return id
			}()
		}
		refined = refine(classesWithForms)
		// Classes are numbered in the order the walk first reaches a member.
		var numbering = [Int: Int]()
		classByBody = [Int](repeating: 0, count: count)
		membersByClass = [[]]
		for body in bodies.indices.dropFirst() {
			let id = numbering[refined[body]] ?? {
				let id = membersByClass.count
				numbering[refined[body]] = id
				membersByClass.append([])
				return id
			}()
			classByBody[body] = id
			membersByClass[id].append(body)
		}
	}

	func structuralKey(of body: Int, isInSendableFamily: Bool) -> [String] {
		guard let record = bodies[body].record else { return [] }
		var key = [
			record.concreteType.asSource,
			record.target.callee,
			"\(record.isExtension)",
			record.lineEnd,
			"\(isInSendableFamily)",
			record.forwardedProperties.map(\.asSource).joined(separator: ","),
			reads[body].joined(separator: ","),
		]
		for argument in record.arguments {
			key.append("argument|\(argument.argumentLabel)|\(argument.label)|\(argument.property.asSource)")
		}
		key.append(contentsOf: record.constructionShape)
		// A place's own passed arguments are its function's parameters: only their names and types tell places apart, since
		// each call hands its own values, which the caller's key holds.
		for argument in record.passedArguments {
			key.append("parameter|\(argument.parameterName)|\(argument.type.asSource)")
		}
		for (index, statement) in bodies[body].statements.enumerated() {
			key.append(statementShape(statement))
			let passedArguments = passedArguments(ofStatementAt: index, inBody: body)
			key.append("passedArguments|\(passedArguments.count)")
			if case .closer = statement {
				key.append(contentsOf: passedArguments.map { $0.closerShape ?? $0.shape })
			} else {
				key.append(contentsOf: passedArguments.map(\.shape))
			}
		}
		return key
	}

	func statementShape(_ statement: Statement) -> String {
		switch statement {
		case let .built(child):
			guard let record = bodies[child].record else { return "" }
			return "call|\(record.property.asSource)|\(record.isErased)|\(record.isExtension)"
		case let .closer(record, _):
			return "call|\(record.property.asSource)|\(record.isErased)|\(record.isExtension)"
		case let .inline(record):
			let arguments = record.arguments.map { "\($0.argumentLabel):\($0.label):\($0.property.asSource)" }.joined(separator: ",")
			return "inline|\(record.property.asSource)|\(record.concreteType.asSource)|\(record.target.callee)|\(record.isErased)|\(record.isExtension)|\(record.lineEnd)|\(arguments)|\(record.constructionShape.joined(separator: ";"))"
		case let .alias(record):
			let reads = record.listedReads.map { "\($0.label):\($0.property.asSource)" }.joined(separator: ",")
			return "alias|\(record.text)|\(reads)"
		}
	}

	/// `classes` refined until alike places' bodies call alike places: a place's class joins the classes its body's calls
	/// reach. Each pass refines the last, since a body's key starts with its class, so the count of classes grows with
	/// every pass that changes the partition and the passes end within one per body.
	func refine(_ classes: [Int]) -> [Int] {
		var previousCount = Set(classes.dropFirst()).count
		var next = refinementPass(of: classes)
		while next.count != previousCount {
			previousCount = next.count
			next = refinementPass(of: next.classes)
		}
		return next.classes
	}

	/// One pass of `refine`: each place's class is joined by the classes its body's calls reach, with the count of classes.
	func refinementPass(of previous: [Int]) -> (classes: [Int], count: Int) {
		var interned = [[Int]: Int]()
		var next = [Int](repeating: 0, count: bodies.count)
		for body in bodies.indices.dropFirst() {
			var key = [previous[body]]
			for statement in bodies[body].statements {
				switch statement {
				case let .built(child):
					key.append(previous[child])
				case let .closer(_, target):
					key.append(previous[target])
				case .inline, .alias:
					key.append(0)
				}
			}
			next[body] = interned[key] ?? {
				let id = interned.count + 1
				interned[key] = id
				return id
			}()
		}
		return (next, interned.count)
	}
}
