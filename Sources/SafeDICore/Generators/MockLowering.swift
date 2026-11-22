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

/// Stage D1's shadow: while `observer` is set, which only the tests do, `generateMockCode` lowers each mock root again from
/// its finished generator tree (`ScopeGenerator.lowerMockRoot(context:)`) and hands the observer how that lowering compares
/// with the code the emitter generated. What the tool returns is always the emitter's: the lowering reads only finished
/// generators and the module's frozen maps, and writes nothing they hold, so setting the observer changes no output.
public enum MockLoweringShadow {
	/// Called once per mock root the module generates code for, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (Comparison) -> Void)?

	/// How the lowering of one mock root compares with the code the emitter generated for it.
	public struct Comparison: Sendable, Equatable {
		/// The mocked type, as the generated code spells it.
		public let mockedType: String
		public let outcome: Outcome

		public init(mockedType: String, outcome: Outcome) {
			self.mockedType = mockedType
			self.outcome = outcome
		}
	}

	public enum Outcome: Sendable, Equatable {
		/// The lowering's code is the emitter's, byte for byte.
		case identical
		/// The lowering's code differs from the emitter's, first at `line` (counted from 1): `emitted` is the emitter's line
		/// there and `lowered` the lowering's, `nil` past either one's end.
		case differs(line: Int, emitted: String?, lowered: String?)
		/// The lowering met a construct whose rule it does not lower yet.
		case unsupported(MockLowering.Rule)
	}

	/// How `lowered` compares with `emitted`, byte for byte, line by line.
	public static func outcome(comparing lowered: MockLowering.Result, with emitted: String) -> Outcome {
		switch lowered {
		case let .unsupported(rule):
			return .unsupported(rule)
		case let .lowered(loweredCode):
			guard !loweredCode.utf8.elementsEqual(emitted.utf8) else { return .identical }
			let emittedLines = emitted.split(separator: "\n", omittingEmptySubsequences: false)
			let loweredLines = loweredCode.split(separator: "\n", omittingEmptySubsequences: false)
			let index = zip(emittedLines, loweredLines).enumerated()
				.first { !$0.element.0.utf8.elementsEqual($0.element.1.utf8) }?.offset
				?? min(emittedLines.count, loweredLines.count)
			return .differs(
				line: index + 1,
				emitted: index < emittedLines.count ? String(emittedLines[index]) : nil,
				lowered: index < loweredLines.count ? String(loweredLines[index]) : nil,
			)
		}
	}
}

/// Stage D1's lowering of a mock root's code from its finished generator tree, which replaces the mock emitter once it
/// generates every root's code byte for byte (`/mnt/project-files/designs/generator-architecture/d1-design-note.md`).
public enum MockLowering {
	/// A rule of mock generation, as the lowering reports one it does not lower yet: the first such construct it meets in
	/// a root decides the root's outcome, so a gap is counted, never guessed at.
	public enum Rule: String, Sendable, CaseIterable {
		/// A public mock (`generateMock: .public`): its tiers, builders and calls.
		case publicMock = "public mock"
		/// A hand-written mock, of the mocked type or of a type its tree builds.
		case handWrittenMock = "hand-written mock"
		/// A default-valued parameter of a construction.
		case defaultValuedParameter = "default-valued parameter"
		/// A parameter of `mock()` other than the overrides: forwarded, received or instantiated values the mock cannot build.
		case flatParameter = "flat parameter"
		/// A receive or override only if available.
		case onlyIfAvailable = "only if available"
		/// An alias, or a receive the walk does not trace to a sibling.
		case alias
		/// `fulfilledByType:`, `erasedToConcreteExistential:`, or a property typed other than the type it builds.
		case erasure
		/// An instantiator, `LazilyInstantiated` or other wrapper, or a type that forwards values.
		case wrapper
		/// A cycle-closing node.
		case cycle
		/// Two nodes of one label.
		case siblingLabelCollision = "sibling label collision"
	}

	public enum Result: Sendable, Equatable {
		case lowered(String)
		case unsupported(Rule)
	}
}

extension ScopeGenerator {
	/// This mock root's code, lowered from its finished generator tree, or the first rule it meets that the lowering does
	/// not lower yet.
	func lowerMockRoot(context: MockContext) async -> MockLowering.Result {
		guard case let .root(instantiable, _) = scopeData, instantiable.generateMock != .public else { return .unsupported(.publicMock) }
		guard propertiesToGenerate.isEmpty,
		      instantiable.dependencies.isEmpty,
		      (instantiable.mockInitializer ?? instantiable.initializer)?.arguments.contains(where: \.hasDefaultValue) == false
		else { return await lowerMockRootWithTree(of: instantiable, context: context) }
		return .lowered(Self.mockWithoutTree(of: instantiable, context: context))
	}

	/// The mock of a type whose `mock()` takes no parameter and builds nothing but the type: one call of its hand-written
	/// mock, its `instantiate()` or its initializer.
	private static func mockWithoutTree(of instantiable: Instantiable, context: MockContext) -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		let returnType = (instantiable.mockCallReturnType ?? instantiable.concreteInstantiable).asSource
		let argumentList = (instantiable.mockInitializer ?? instantiable.initializer)?
			.createMockInitializerArgumentList(given: instantiable.dependencies) ?? ""
		let construction = if instantiable.mockInitializer != nil {
			"\(typeName).\(instantiable.customMockName ?? InstantiableVisitor.mockMethodName)(\(argumentList))"
		} else if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}
		let code = """
		extension \(typeName) {
		    \(mockAttributesPrefix)static func mock() -> \(returnType) {
		        \(construction)
		    }
		}
		"""
		return if let mockConditionalCompilation = context.mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
	}
}
