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

/// Where an argument generated code passes comes from, with one spelling for each.
indirect enum ArgumentSource: Hashable, Sendable {
	/// The nearest declaration of `label`: a binding, or a parameter of the enclosing function.
	case binding(label: String)
	/// The instance of the `LazilyInstantiated` bound as `label`, read through the optional where the wrapper is optional.
	case lazyInstance(label: String, throughOptional: Bool)
	/// `nil`: the value is unavailable where the argument is passed.
	case `nil`
	/// A value a wrapper forwards, `spreadName`: the value itself where it is the only one, and otherwise its element named
	/// `label`.
	case forwardedSpread(label: String, isOnly: Bool, spreadName: String)
	/// A wrapper of type `wrapperType` made of `value`, which it returns: what a call hands a fill that reads a
	/// `LazilyInstantiated` where the caller declares only its instance.
	case wrapper(of: ArgumentSource, wrapperType: TypeDescription)
	/// The optional `value` mapped into a wrapper of type `wrapperType`, as `wrapper(of:wrapperType:)` makes one.
	case optionalWrapper(of: ArgumentSource, wrapperType: TypeDescription)
	/// What a call of another module's public mock passes a builder: the call of the builder's root level function, or the
	/// struct the caller passes up (`ScopeGenerator.publicMockBuilderStructValuesByLabel`), held as spelled until seam
	/// and public mock calls are planned.
	case builderArgument(String)
	/// A value the enclosing code already spelled, passed as it is: what a seam call or a public mock's call passes for one
	/// of the seam's holes (`holeArgumentValuesByLabel`), held as spelled until seam and public mock calls are planned.
	case spelledArgument(String)

	var spelled: String {
		switch self {
		case let .binding(label):
			label
		case let .lazyInstance(label, throughOptional):
			"\(label)\(throughOptional ? "?." : ".")\(Dependency.lazilyInstantiatedInstancePropertyName)"
		case .nil:
			"nil"
		case let .forwardedSpread(label, isOnly, spreadName):
			isOnly ? spreadName : "\(spreadName).\(label)"
		case let .wrapper(value, wrapperType):
			"\(wrapperType.asSource)({ \(value.spelled) })"
		case let .optionalWrapper(value, wrapperType):
			"\(value.spelled).map { value in \(wrapperType.asSource)({ value }) }"
		case let .builderArgument(value),
		     let .spelledArgument(value):
			value
		}
	}
}

/// An argument of a call: its label, and where its value comes from.
struct CallArgument: Hashable, Sendable {
	let label: String
	let source: ArgumentSource

	/// `label: value`, with the label spelled as an argument label.
	var spelled: String {
		"\(label.spelledAsArgumentLabel): \(source.spelled)"
	}
}

extension Set<Property> {
	/// Where a receive of `property`, bound as `label`, reads it from, where this set holds the by-value properties in scope
	/// only as the instance of a `LazilyInstantiated`: the wrapper's instance; the instance through an optional wrapper, for
	/// a receive of the optional form where the set holds that form, which only a fill that takes the wrapper optionally adds
	/// (`Scope.Fill.optionalLazilyInstantiatedLabels`); or `nil` where it reads no instance.
	func lazilyInstantiatedInstanceSource(of property: Property, boundAs label: String) -> ArgumentSource? {
		if contains(property.asUnwrappedProperty) {
			.lazyInstance(label: label, throughOptional: false)
		} else if property.typeDescription.isOptional, contains(property) {
			.lazyInstance(label: label, throughOptional: true)
		} else {
			nil
		}
	}
}

extension Initializer {
	/// The arguments a construction with this initializer passes, given `dependencies`: `nil` for an unavailable
	/// property, the instance of a received property in scope only as a `LazilyInstantiated`'s, and otherwise the
	/// argument's own label, each in the initializer's order. An argument with a default value that no dependency
	/// fulfills is left out.
	/// - Parameter lazilyInstantiatedInstanceProperties: The received properties that are in scope only as the
	///   instance of a `LazilyInstantiated` property. Their arguments read that instance.
	func createInitializerArgumentList(
		given dependencies: [Dependency],
		unavailableProperties: Set<Property>? = nil,
		lazilyInstantiatedInstanceProperties: Set<Property> = [],
	) throws(GenerationError) -> String {
		try createInitializerArguments(given: dependencies, unavailableProperties: unavailableProperties, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties)
			.map(\.argument.spelled)
			.joined(separator: ", ")
	}

	/// The arguments `createInitializerArgumentList` spells, each with the dependency it passes.
	func createInitializerArguments(
		given dependencies: [Dependency],
		unavailableProperties: Set<Property>? = nil,
		lazilyInstantiatedInstanceProperties: Set<Property> = [],
	) throws(GenerationError) -> [(argument: CallArgument, dependency: Dependency)] {
		try createDependencyAndArgumentBinding(given: dependencies).map {
			(
				argument: Self.argument($0.argument, passing: $0.dependency, unavailableProperties: unavailableProperties, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties),
				dependency: $0.dependency,
			)
		}
	}

	/// The argument list of a generated call of this hand-written mock that a fill makes: each argument one of `dependencies`
	/// is passed to, as `createInitializerArgumentList` spells it, and each argument without a default value that none of
	/// them is passed to, passed the value of its own name, in declaration order. Such an argument takes a dependency only
	/// an `#if` clause the build does not select declares, in a build that compiles no generated mock, since
	/// `DependencyTreeGenerator.validateHandWrittenMocksTakeOnlyFulfilledParameters` reports it in every other build: the
	/// call is never compiled, as the same call outside a fill is not.
	func createHandWrittenMockArgumentList(
		given dependencies: [Dependency],
		unavailableProperties: Set<Property>?,
		lazilyInstantiatedInstanceProperties: Set<Property>,
	) -> String {
		var parts = [String]()
		for argument in arguments {
			if let dependency = dependencies.first(where: argument.isFulfilled(by:)) {
				parts.append(Self.argument(argument, passing: dependency, unavailableProperties: unavailableProperties, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties).spelled)
			} else if !argument.hasDefaultValue {
				parts.append(CallArgument(label: argument.label, source: .binding(label: argument.innerLabel)).spelled)
			}
		}
		return parts.joined(separator: ", ")
	}

	/// `argument` of a generated call, passed `dependency`: `nil` where it is unavailable, the instance of a received
	/// property held as a `LazilyInstantiated` property's instance, and the property of its label otherwise. It reads the
	/// argument's labels alone, so a dependency is read alike whichever function's argument it is passed to: the
	/// initializer's, or a hand-written mock's.
	static func argument(
		_ argument: Argument,
		passing dependency: Dependency,
		unavailableProperties: Set<Property>?,
		lazilyInstantiatedInstanceProperties: Set<Property>,
	) -> CallArgument {
		let source: ArgumentSource = if let unavailableProperties, unavailableProperties.contains(dependency.property) {
			.nil
		} else if !lazilyInstantiatedInstanceProperties.isEmpty,
		          dependency.source.isReceived,
		          let instanceSource = lazilyInstantiatedInstanceProperties.lazilyInstantiatedInstanceSource(of: dependency.property, boundAs: argument.innerLabel)
		{
			instanceSource
		} else {
			.binding(label: argument.innerLabel)
		}
		return CallArgument(label: argument.label, source: source)
	}
}
