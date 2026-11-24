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

extension MockLowering {
	/// The alternative a built place's record tries before its construction, where the mock walk hooked the construction
	/// (`ConstructionHook`) with a read of the place's override, or `nil` where the hook says something the record cannot:
	/// a read the walk cannot name as a value path, another construction, or a call of the builder other than with the
	/// construction's arguments.
	/// - Parameters:
	///   - hook: The walk's hook of the place.
	///   - construction: The construction the record calls, spelled.
	///   - argumentValues: The values the construction passes, spelled, in its order.
	///   - erasedType: The type the place's value is erased to, where the property is erased.
	static func constructionAlternative(
		of hook: ConstructionHook,
		construction: String,
		argumentValues: [String],
		erasedType: TypeDescription?,
	) -> ConstructionAlternative? {
		guard hook.construction == nil || hook.construction == construction,
		      let closure = overrideReadPath(hook.builder)
		else { return nil }
		let bindingName = ReservedName.configurationBuilderPropertyName
		let call = "\(bindingName)(\(argumentValues.joined(separator: ", ")))"
		let resultWrapper: TypeDescription?
		if hook.call == call {
			resultWrapper = nil
		} else if let erasedType, hook.call == "\(erasedType.asSource)(\(call))" {
			resultWrapper = erasedType
		} else {
			return nil
		}
		return ConstructionAlternative(
			closure: closure,
			bindingName: bindingName,
			requiresAbsent: [],
			use: .calledWithConstructionArguments,
			resultWrapper: resultWrapper,
		)
	}

	/// The value path of an override read spelled `safeDIOverrides.<member>.<member>…`, or `nil` for any other read, such
	/// as a local a `@Sendable` function's extractor bound it to.
	static func overrideReadPath(_ read: String) -> ValuePath? {
		let parts = read.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
		guard parts.count > 1, parts[0] == ReservedName.mockOverridesParameterName, !parts.contains(where: \.isEmpty) else { return nil }
		var path = ValuePath.rootDeclaration(parts[0])
		for member in parts.dropFirst() {
			path = .member(member, of: path)
		}
		return path
	}
}

extension ArgumentSource {
	/// This source read under `name` where it reads the declaration of `label`: what a read becomes where a mock binds the
	/// label apart (`ScopeGenerator.builtPlaceRecord(of:…readNames:…)`).
	func renamed(from label: String, to name: String) -> ArgumentSource {
		switch self {
		case let .binding(boundLabel) where boundLabel == label:
			.binding(label: name)
		case let .lazyInstance(boundLabel, throughOptional) where boundLabel == label:
			.lazyInstance(label: name, throughOptional: throughOptional)
		case .binding,
		     .lazyInstance,
		     .nil,
		     .forwardedSpread,
		     .wrapper,
		     .optionalWrapper,
		     .builderArgument,
		     .spelledArgument:
			self
		}
	}
}
