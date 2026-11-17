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

// MARK: - Remedy oracle

/// A remedy an error of the tool states for a graph the tool rejects, which the remedy oracle applies to the graph's
/// declarations: each is a sentence of an error's text, read as a user would follow it.
enum GraphFuzzerRemedyKind: String, CaseIterable, Comparable {
	/// "Declare `@Instantiated let x: X` on `Root` or on another type in the chain to fix.", for a receive no type in its
	/// chain fulfills: `Root` declares the property, as the first place the error names. Every root the site's errors name
	/// declares it.
	case instantiateOnRoot = "instantiate-on-root"
	/// "Declare `@Instantiated let x: X` on `Root` or on another type in the chain, and add `onlyIfAvailable: true` to this
	/// property’s `@Received`, which then accepts the non-optional form, to fix.", for a required receive of `x: X?` no type
	/// in its chain fulfills: `Root` declares the property, as `instantiateOnRoot` has it, and the receive gets
	/// `onlyIfAvailable: true`.
	case instantiateOnRootAndReceiveOnlyIfAvailable = "instantiate-on-root-and-receive-only-if-available"
	/// "The non-optional `x: X` is available in chain. Did you mean to decorate this property with
	/// `@Received(onlyIfAvailable: true)`?": the receive of `x: X?` is decorated so.
	case receiveOnlyIfAvailable = "receive-only-if-available"
	/// "Did you mean `y: Y`?", or "Did you mean one of …?": the receive takes the label and type of each suggestion in
	/// turn, each a remedy of its own.
	case receiveSuggestedProperty = "receive-suggested-property"
	/// "Change `x: X` to an instantiator.", or "Change one of … to an instantiator.", for a cycle no instantiator defers: the
	/// dependency at the error's site, which closes the cycle, becomes the instantiator of what it builds.
	case instantiateAsInstantiator = "instantiate-as-instantiator"
	/// "Remove this @Received property", for a receive of a property still being built, or for an unfulfilled receive a
	/// declaration would leave still being built ("Declaring `@Instantiated let x: X` would close a dependency cycle …").
	case removeReceive = "remove-receive"
	/// "or receive it with `onlyIfAvailable: true` and an optional type so that it is not required", the same error's
	/// other remedy.
	case receiveOptionallyIfAvailable = "receive-optionally-if-available"
	/// "Give the parameter a default value", for a hand-written mock's parameter whose dependency the type declares only
	/// inside an `#if` clause this build does not select: the mock's parameter gets one, a call of its type's initializer.
	case defaultMockParameter = "default-mock-parameter"
	/// "or move the `mock` method inside `#if X`", the same error's other remedy, where it offers one: the mock's
	/// `#if DEBUG` block moves to the end of the clause the error is at.
	case moveMockIntoClause = "move-mock-into-clause"
	/// "If it names one type, keep one, and remove `P` from the others’ `fulfillingAdditionalTypes`", for a type two
	/// `@Instantiable` declarations fulfill: the declaration at the error's site keeps it, and every other declaration
	/// that lists it loses it from its `fulfillingAdditionalTypes`. Each declaration reports the error, so each is kept in
	/// turn, a remedy each.
	case keepOneFulfiller = "keep-one-fulfiller"
	/// "Decorate `X`, or an extension of it, with @Instantiable", for an `@Instantiated` property of a type no declaration
	/// fulfills: the empty class the fixture declares gets `@Instantiable`, and the conformance and public initializer the
	/// macro then requires of it, which the error does not state.
	case decorateType = "decorate-type"
	/// "Declare `x` on `T`, and this property, as `SendableInstantiator<X>` to fix.", for a receive inside a `@Sendable`
	/// function of a wrapper that is not `Sendable`: the declaration the error names, and the receive where the error says
	/// "and this property", take the `Sendable` wrapper it spells. Where the error names no declaring type ("where it is
	/// declared and where it is received as `Instantiator<X>`"), every property of that label and type takes it, in every
	/// type of the graph: more than the chain the error names where another branch declares the same label and type.
	case declareAsSendableWrapper = "declare-as-sendable-wrapper"
	/// "Declare `@Forwarded let x: X` on a type below `Root` in the chain, and pass the value to the `Instantiator` that
	/// builds that type", for an unfulfilled receive of a type SafeDI cannot build as a constant: the receiver, a type
	/// below the root, forwards the property in place of receiving it. A type that built the receiver as a constant, or
	/// through an erased instantiator that took nothing, then reports the declaration that builds it instead ("Declare it
	/// as `Instantiator<T>`."), which the remedy follows too, a run of the tool for each set of declarations the run
	/// before it states (`GraphFuzzerRemedies.followingForwardedReceive`). Only a property whose new error states
	/// "Declare it as `…`" is retyped; any other new error is left alone.
	case forwardReceive = "forward-receive"
	/// "Receive `x` the same way in every type of the tree, or declare it on `Seam` as the form that provides the others:
	/// `@Received let x: X`.", for a seam whose tree receives one label in forms of one type: the seam declares the
	/// property the error spells, in place of its own property of that label where it has one. A seam graph's only remedy
	/// (`GraphFuzzerRemedies.Reading`). The error's forms must each be received as an adopter would: one that is optional
	/// is received only if available, since a required receive of an optional is not a shape anyone writes, so a site
	/// whose error names such a form, or a form the oracle cannot read, gets no remedy.
	case declareProvidingFormOnSeam = "declare-providing-form-on-seam"
	/// "Give `x: Y` on `T` a different label to fix.", for a receive of `x` that a closer declaration of the label with
	/// another type hides: `T`'s property takes the label `xRelabeled`, with its initializer parameter and assignment,
	/// so the receive reaches the declaration above it. A hidden receive that is a required optional is not a shape anyone
	/// writes, and gets no remedy; nor does a hiding declaration that `T` renames, or whose new label `T` already declares.
	case relabelHidingDeclaration = "relabel-hiding-declaration"

	/// The words a failure line of a remedy of this kind begins with (`GraphFuzzerRemedyRun.failureLine`), which a known
	/// issue's signature reads.
	var failureLinePrefix: String {
		"The \(rawValue) remedy, "
	}

	static func < (lhs: GraphFuzzerRemedyKind, rhs: GraphFuzzerRemedyKind) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// A property as a remedy reads or writes it: its attribute, label and type, as the fixture spells them.
struct GraphFuzzerRemedyProperty: Hashable {
	let attribute: String
	let label: String
	let type: String
}

/// A remedy applied: the graph with the remedy's edit, and the site whose errors it answers.
struct GraphFuzzerRemedy: Equatable {
	/// A property's declaration, where the tool reports an error: the file, the type that declares it there, and its label,
	/// which a remedy that renames the property changes.
	struct Site: Hashable, CustomStringConvertible {
		let fileName: String
		let typeName: String
		let label: String

		var description: String {
			"`\(typeName).\(label)` in \(fileName)"
		}
	}

	let kind: GraphFuzzerRemedyKind
	/// The site, as the remedied graph declares it.
	let site: Site
	/// The messages of the errors at the site that the remedy answers.
	let answeredErrors: [String]
	/// What the remedy does, in words.
	let description: String
	/// The graph with the remedy applied.
	let fixture: GraphFuzzerFixture
}

/// The remedied graph's outcome.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct GraphFuzzerRemedyRun {
	let remedy: GraphFuzzerRemedy
	let outcome: GraphFuzzerToolOutcome
	/// The messages of the errors the remedy introduced and its follow-up runs left, at the declarations that build the
	/// type of the remedy's site (`GraphFuzzerRemedies.errorsIntroducedByForwarding`): a `forwardReceive` remedy's, whose
	/// own site, once it forwards, has no receive left for an error to be at.
	var introducedErrors = [String]()

	/// The messages of the errors the tool reports at the remedy's site in the remedied graph, and of those the remedy
	/// introduced elsewhere and left (`introducedErrors`): none when the remedy fixes what it answers and adds no error.
	var errorsAtSite: [String] {
		GraphFuzzerRemedies.errors(at: remedy.site, in: outcome, of: remedy.fixture) + introducedErrors
	}

	/// The line a failure lists for this run, or `nil` when the remedy leaves no error at its site.
	var failureLine: String? {
		let errorsAtSite = errorsAtSite
		guard !errorsAtSite.isEmpty else { return nil }
		return "\(remedy.kind.failureLinePrefix)which \(remedy.description), leaves at \(remedy.site): \(errorsAtSite.joined(separator: " | "))"
	}
}

/// Reads the remedies the tool's errors state for a graph it rejects, and applies each to the graph's declarations as the
/// fuzzer writes them (`GraphFuzzerGenerator`): a property line `@Attribute let label: Type` in a `final class`'s body,
/// and an initializer on one line that takes each property under its label, in the properties' order, before any
/// default-valued parameter, and assigns each in its body. An edit keeps the initializer in step, as the macro requires.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerRemedies {
	/// An error the tool reports, read from one line of its diagnostics.
	struct ReportedError {
		let fileName: String
		/// One-based, as the tool reports it.
		let line: Int
		let message: String

		init?(_ diagnosticLine: Substring) {
			guard let errorMarker = diagnosticLine.range(of: ": error: ") else { return nil }
			let location = diagnosticLine[..<errorMarker.lowerBound].split(separator: ":", omittingEmptySubsequences: false)
			guard location.count >= 3, let line = Int(location[location.count - 2]) else { return nil }
			let path = location.dropLast(2).joined(separator: ":")
			guard let fileName = path.split(separator: "/").last, fileName.hasSuffix(".swift") else { return nil }
			self.fileName = String(fileName)
			self.line = line
			message = String(diagnosticLine[errorMarker.upperBound...])
		}
	}

	/// The remedy an error states, read from its message, before it is applied.
	enum StatedRemedy: Equatable {
		case instantiateOnRoot(property: GraphFuzzerRemedyProperty, root: String, receivingOnlyIfAvailable: Bool)
		case receiveOnlyIfAvailable(label: String)
		case receiveSuggestedProperty(label: String, suggestions: [GraphFuzzerRemedyProperty])
		case instantiateAsInstantiator(hopLabels: [String])
		case removeOrReceiveOptionallyIfAvailable
		case defaultMockParameterOrMoveMock(typeName: String, mockName: String, parameter: GraphFuzzerRemedyProperty, offersMove: Bool)
		case keepOneFulfiller(fulfilledType: String)
		case decorateType(typeName: String)
		/// `declaringType` is `nil`, and `receivedAs` the wrapper's type, where the error names no declaring type.
		case declareAsSendableWrapper(label: String, declaringType: String?, sendableType: String, retypesReceive: Bool, receivedAs: String?)
		case forwardReceive(label: String)
		case declareProvidingFormOnSeam(collision: SeamLabelCollision, property: GraphFuzzerRemedyProperty)
		case relabelHidingDeclaration(hiddenLabel: String, hidingProperty: GraphFuzzerRemedyProperty, declaringType: String)

		/// The remedy `message` states, or `nil` for an error outside the families the oracle reads, or one whose remedy
		/// the oracle cannot apply as stated: an erased instantiator whose fulfilling type the error leaves to the user, or a
		/// cycle an alias received only if available closes.
		init?(message: String) {
			let unfulfilledPrefix = "@Received property `"
			let unfulfilledMarker = "` is not @Instantiated or @Forwarded in chain: "
			let onlyIfAvailableRemedy = " Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required."
			if message.hasPrefix(unfulfilledPrefix), let markerRange = message.range(of: unfulfilledMarker) {
				let spelledReceivedProperty = message[message.index(message.startIndex, offsetBy: unfulfilledPrefix.count)..<markerRange.lowerBound]
				let receivedLabel = Self.property(spelled: spelledReceivedProperty, attribute: "@Received")?.label
				// Chain types spell no period followed by a space, so the hint begins after the first.
				guard let receivedLabel, let hintStart = message[markerRange.upperBound...].range(of: ". ") else { return nil }
				let hint = message[hintStart.upperBound...]
				let instantiatePrefix = "Declare `@Instantiated let "
				let instantiateRootMarker = "` on `"
				let instantiateSuffix = "` or on another type in the chain to fix."
				let instantiateReceivingOnlyIfAvailableSuffix = "` or on another type in the chain, and add `onlyIfAvailable: true` to this property’s `@Received`, which then accepts the non-optional form, to fix."
				if hint.hasPrefix("Declaring `@Instantiated let "), hint.hasSuffix(onlyIfAvailableRemedy.dropFirst()) {
					self = .removeOrReceiveOptionallyIfAvailable
				} else if hint.hasPrefix("The non-optional `"), hint.hasSuffix("Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?") {
					self = .receiveOnlyIfAvailable(label: receivedLabel)
				} else if hint.hasPrefix("Did you mean "), hint.hasSuffix("`?") {
					let list = hint.dropFirst("Did you mean ".count).dropLast("?".count)
					let items = list.hasPrefix("one of ") ? Self.backtickedItems(in: list.dropFirst("one of ".count)) : Self.backtickedItems(in: list)
					let suggestions = items.compactMap { Self.property(spelled: $0, attribute: "@Received") }
					guard !suggestions.isEmpty, suggestions.count == items.count else { return nil }
					self = .receiveSuggestedProperty(label: receivedLabel, suggestions: suggestions)
				} else if hint.hasPrefix(instantiatePrefix),
				          let suffix = [instantiateSuffix, instantiateReceivingOnlyIfAvailableSuffix].first(where: { hint.hasSuffix($0) }),
				          let rootMarker = hint.range(of: instantiateRootMarker, options: .backwards, range: hint.startIndex..<hint.index(hint.endIndex, offsetBy: -suffix.count))
				{
					let spelledProperty = hint[hint.index(hint.startIndex, offsetBy: instantiatePrefix.count)..<rootMarker.lowerBound]
					let root = hint[rootMarker.upperBound..<hint.index(hint.endIndex, offsetBy: -suffix.count)]
					guard let property = Self.property(spelled: spelledProperty, attribute: "@Instantiated"), !root.contains("`") else { return nil }
					self = .instantiateOnRoot(property: property, root: String(root), receivingOnlyIfAvailable: suffix == instantiateReceivingOnlyIfAvailableSuffix)
				} else if hint.contains(" Declare `@Forwarded let \(spelledReceivedProperty)` on a type below `") {
					// "… SafeDI builds it only through an `Instantiator` …" or "No @Instantiable declaration fulfills …", each
					// followed by "Declare `@Forwarded let x: X` on a type below `Root` in the chain, and pass the value to the
					// `Instantiator` that builds that type".
					self = .forwardReceive(label: receivedLabel)
				} else {
					return nil
				}
			} else if let collision = SeamLabelCollision(message: message) {
				// "SafeDI cannot generate the dependency tree of `S`: its tree receives `x` as … Receive `x` the same way in
				// every type of the tree, or declare it on `S` as the form that provides the others: `@Received let x: X`."
				let remedyPrefix = "Receive `\(collision.label)` the same way in every type of the tree, or declare it on `\(collision.seam)` as the form that provides the others: `@Received let \(collision.label): "
				guard collision.remedy.hasPrefix(remedyPrefix), collision.remedy.hasSuffix("`.") else { return nil }
				let type = collision.remedy.dropFirst(remedyPrefix.count).dropLast("`.".count)
				guard !type.isEmpty, !type.contains("`") else { return nil }
				self = .declareProvidingFormOnSeam(collision: collision, property: GraphFuzzerRemedyProperty(attribute: "@Received", label: collision.label, type: String(type)))
			} else if message.hasPrefix(unfulfilledPrefix), let hiddenRange = message.range(of: Self.hiddenMarker) {
				// "@Received property `x: X` is hidden in chain: … `T` declares `x: Y` with the same label, so the types below
				// `T` receive `x: Y` instead. Give `x: Y` on `T` a different label to fix."
				let spelledHiddenProperty = message[message.index(message.startIndex, offsetBy: unfulfilledPrefix.count)..<hiddenRange.lowerBound]
				let givePrefix = " Give `"
				let onMarker = "` on `"
				let suffix = Self.hiddenSuffix
				guard let hiddenLabel = Self.property(spelled: spelledHiddenProperty, attribute: "@Received")?.label,
				      message.hasSuffix(suffix),
				      let giveRange = message.range(of: givePrefix, options: .backwards),
				      let onRange = message.range(of: onMarker, options: .backwards, range: giveRange.upperBound..<message.endIndex)
				else { return nil }
				let declaringType = message[onRange.upperBound..<message.index(message.endIndex, offsetBy: -suffix.count)]
				guard let hidingProperty = Self.property(spelled: message[giveRange.upperBound..<onRange.lowerBound], attribute: ""),
				      hidingProperty.label == hiddenLabel,
				      !declaringType.contains("`")
				else { return nil }
				self = .relabelHidingDeclaration(hiddenLabel: hiddenLabel, hidingProperty: hidingProperty, declaringType: String(declaringType))
			} else if message.hasPrefix(Self.multipleFulfillersPrefix) {
				// "Found multiple @Instantiable types or extensions that fulfill `P`. … If it names one type, keep one, and
				// remove `P` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
				let named = message.dropFirst(Self.multipleFulfillersPrefix.count)
				guard let nameEnd = named.range(of: "`. ") else { return nil }
				let fulfilledType = named[..<nameEnd.lowerBound]
				guard message.contains(" keep one, and remove `\(fulfilledType)` from the others’ `fulfillingAdditionalTypes`") else { return nil }
				self = .keepOneFulfiller(fulfilledType: String(fulfilledType))
			} else if message.hasPrefix(Self.unfulfilledInstantiatedTypePrefix) {
				// "No @Instantiable type or extension fulfills `X`, which @Instantiated property `x: X` instantiates. Decorate
				// `X`, or an extension of it, with @Instantiable, or …"
				let named = message.dropFirst(Self.unfulfilledInstantiatedTypePrefix.count)
				guard let nameEnd = named.range(of: "`, which ") else { return nil }
				let typeName = named[..<nameEnd.lowerBound]
				guard message.contains(" Decorate `\(typeName)`, or an extension of it, with @Instantiable") else { return nil }
				self = .decorateType(typeName: String(typeName))
			} else if message.contains(Self.sendableCaptureMarker) {
				// "… Declare `x` on `T`, and this property, as `W` to fix. …", "… Declare `x` on `T` as `W` to fix. …", or
				// "… Declare `x` as `W` where it is declared and where it is received as `V` to fix. …".
				let declarePrefix = " Declare `"
				guard let fixEnd = message.range(of: "` to fix. "),
				      let fixStart = message.range(of: declarePrefix, options: .backwards, range: message.startIndex..<fixEnd.lowerBound)
				else { return nil }
				let fix = message[fixStart.upperBound..<fixEnd.lowerBound]
				let onMarker = "` on `"
				let asMarker = "` as `"
				let andThisPropertyMarker = "`, and this property, as `"
				let whereMarker = "` where it is declared and where it is received as `"
				if let whereRange = fix.range(of: whereMarker), let asRange = fix.range(of: asMarker), asRange.upperBound <= whereRange.lowerBound {
					self = .declareAsSendableWrapper(
						label: String(fix[..<asRange.lowerBound]),
						declaringType: nil,
						sendableType: String(fix[asRange.upperBound..<whereRange.lowerBound]),
						retypesReceive: true,
						receivedAs: String(fix[whereRange.upperBound...]),
					)
				} else if let onRange = fix.range(of: onMarker) {
					let label = String(fix[..<onRange.lowerBound])
					let rest = fix[onRange.upperBound...]
					if let andRange = rest.range(of: andThisPropertyMarker) {
						self = .declareAsSendableWrapper(label: label, declaringType: String(rest[..<andRange.lowerBound]), sendableType: String(rest[andRange.upperBound...]), retypesReceive: true, receivedAs: nil)
					} else if let asRange = rest.range(of: asMarker) {
						self = .declareAsSendableWrapper(label: label, declaringType: String(rest[..<asRange.lowerBound]), sendableType: String(rest[asRange.upperBound...]), retypesReceive: false, receivedAs: nil)
					} else {
						return nil
					}
				} else {
					return nil
				}
			} else if message.contains(GraphFuzzerOracle.guardedMockParameterErrorMarker) {
				// "`T.mock(x:)` takes `x: X`, which `T` declares only inside `#if C`, inactive in this build, so generated code
				// cannot call the mock. Give the parameter a default value, or move the `mock` method inside `#if C`."
				let takesMarker = "` takes `"
				let whichMarker = "`, which `"
				let defaultRemedy = " Give the parameter a default value"
				guard message.hasPrefix("`"),
				      let takesRange = message.range(of: takesMarker),
				      let whichRange = message.range(of: whichMarker, range: takesRange.upperBound..<message.endIndex),
				      let remedyRange = message.range(of: defaultRemedy, options: .backwards),
				      let parameter = Self.property(spelled: message[takesRange.upperBound..<whichRange.lowerBound], attribute: ""),
				      let typeNameEnd = message.range(of: GraphFuzzerOracle.guardedMockParameterErrorMarker, range: whichRange.upperBound..<message.endIndex)
				else { return nil }
				let typeName = message[whichRange.upperBound..<typeNameEnd.lowerBound]
				let mockPrefix = "`\(typeName)."
				let mock = message[..<takesRange.lowerBound]
				guard mock.hasPrefix(mockPrefix), let mockNameEnd = mock.firstIndex(of: "(") else { return nil }
				let mockName = mock[mock.index(mock.startIndex, offsetBy: mockPrefix.count)..<mockNameEnd]
				let remedy = message[remedyRange.upperBound...]
				guard remedy == "." || (remedy.hasPrefix(", or move the `\(mockName)` method inside `") && remedy.hasSuffix("`.")) else { return nil }
				self = .defaultMockParameterOrMoveMock(typeName: String(typeName), mockName: String(mockName), parameter: parameter, offersMove: remedy != ".")
			} else if message.hasPrefix("Dependency cycle: ") {
				if message.contains(onlyIfAvailableRemedy) {
					self = .removeOrReceiveOptionallyIfAvailable
				} else if let changeStart = message.range(of: " Change ", options: .backwards), let changeEnd = message.range(of: " to an instantiator.", range: changeStart.upperBound..<message.endIndex) {
					var hops = message[changeStart.upperBound..<changeEnd.lowerBound]
					if hops.hasPrefix("one of ") {
						hops = hops.dropFirst("one of ".count)
					}
					let hopLabels = Self.backtickedItems(in: hops).compactMap { Self.property(spelled: $0, attribute: "@Instantiated")?.label }
					guard !hopLabels.isEmpty else { return nil }
					self = .instantiateAsInstantiator(hopLabels: hopLabels)
				} else {
					return nil
				}
			} else {
				return nil
			}
		}

		/// What follows the property in the error of a receive a closer declaration of its label hides.
		static let hiddenMarker = "` is hidden in chain: "
		static let hiddenSuffix = "` a different label to fix."
		/// What begins the error two `@Instantiable` declarations that fulfill one type each report.
		static let multipleFulfillersPrefix = "Found multiple @Instantiable types or extensions that fulfill `"
		/// What begins the error of an `@Instantiated` property whose type no declaration fulfills.
		static let unfulfilledInstantiatedTypePrefix = "No @Instantiable type or extension fulfills `"
		/// What follows the property in the error of a receive, inside a `@Sendable` function, of a wrapper that is not
		/// `Sendable`.
		static let sendableCaptureMarker = "` cannot be received inside a `@Sendable` function in chain: "

		/// The items a list in backticks names: "`a: A`, `b: B`" or "`a: A`", or none when the list is spelled otherwise.
		private static func backtickedItems(in list: Substring) -> [Substring] {
			guard list.hasPrefix("`"), list.hasSuffix("`"), list.count > 1 else { return [] }
			return list.dropFirst().dropLast().components(separatedBy: "`, `").map { Substring($0) }
		}

		/// The property `label: Type` spells, with `attribute`, or `nil` when it spells no plain label, such as a label in
		/// backticks.
		private static func property(spelled spelling: Substring, attribute: String) -> GraphFuzzerRemedyProperty? {
			guard let separator = spelling.range(of: ": ") else { return nil }
			let label = spelling[..<separator.lowerBound]
			guard !label.isEmpty, label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
			return GraphFuzzerRemedyProperty(attribute: attribute, label: String(label), type: String(spelling[separator.upperBound...]))
		}
	}

	/// The error of a seam whose tree receives one label in forms its generated initializer cannot take as one parameter,
	/// read from its message whatever remedy it states: the seam, the label, each form with the type that receives it, and
	/// the remedy's sentences.
	struct SeamLabelCollision: Equatable {
		struct Form: Equatable {
			let label: String
			let type: String
			let receivingType: String
		}

		let seam: String
		let label: String
		let forms: [Form]
		let remedy: String

		init?(message: String) {
			let prefix = "SafeDI cannot generate the dependency tree of `"
			let labelMarker = "`: its tree receives `"
			let formsMarker = "` as "
			let formsEnd = ", and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. "
			guard message.hasPrefix(prefix),
			      let labelRange = message.range(of: labelMarker),
			      let formsRange = message.range(of: formsMarker, range: labelRange.upperBound..<message.endIndex),
			      let formsEndRange = message.range(of: formsEnd, range: formsRange.upperBound..<message.endIndex)
			else { return nil }
			seam = String(message[message.index(message.startIndex, offsetBy: prefix.count)..<labelRange.lowerBound])
			label = String(message[labelRange.upperBound..<formsRange.lowerBound])
			remedy = String(message[formsEndRange.upperBound...])
			// "`x: X?` on `A` and `x: X` on `B`"
			let spelledForms = message[formsRange.upperBound..<formsEndRange.lowerBound]
			guard spelledForms.hasPrefix("`"), spelledForms.hasSuffix("`") else { return nil }
			var forms = [Form]()
			for spelledForm in spelledForms.dropFirst().dropLast().components(separatedBy: "` and `") {
				let parts = spelledForm.components(separatedBy: "` on `")
				guard parts.count == 2, let separator = parts[0].range(of: ": "), parts[0][..<separator.lowerBound] == label else { return nil }
				forms.append(Form(label: label, type: String(parts[0][separator.upperBound...]), receivingType: parts[1]))
			}
			guard forms.count >= 2, !seam.contains("`"), !label.contains("`") else { return nil }
			self.forms = forms
		}
	}

	/// Which errors of a rejected graph the oracle reads, by the graph's corpus, or `nil` for a graph it does not read: a
	/// graph split across modules, or one of the public mock corpus.
	enum Reading: Equatable {
		/// Every family `StatedRemedy` reads: a base corpus graph.
		case everyFamily
		/// Only a seam's label collision (`declareProvidingFormOnSeam`): a seam corpus graph, whose other declarations
		/// (holes, nested types, extensions) the other remedies do not edit.
		case seamLabelCollisions

		init?(of fixture: GraphFuzzerFixture) {
			guard fixture.modules == nil else { return nil }
			switch GraphFuzzerGeneratorFeature.features(drawnIn: fixture) {
			case []:
				self = .everyFamily
			case [.generateDependencyTree]:
				self = .seamLabelCollisions
			default:
				return nil
			}
		}

		func reads(_ error: ReportedError) -> Bool {
			switch self {
			case .everyFamily:
				true
			case .seamLabelCollisions:
				SeamLabelCollision(message: error.message) != nil
			}
		}
	}

	/// The remedies the errors of `diagnostics` state for `fixture`, one per remedy of each site in the order the tool
	/// reports the sites: every error the tool reports at a site must state the same remedy, or, for a receive no type in
	/// its chain fulfills, the same declaration on its own root, which each root then declares. A site whose errors state
	/// other remedies, or one the oracle cannot apply as stated (`StatedRemedy`), gets none.
	static func remedies(of fixture: GraphFuzzerFixture, diagnostics: String) -> [GraphFuzzerRemedy] {
		sites(of: fixture, diagnostics: diagnostics).flatMap(\.remedies)
	}

	/// The number of sites of `diagnostics` whose errors are in a family the oracle reads – a receive no type in its chain
	/// fulfills, or a cycle – and that get no remedy: the oracle's blind spot, which the long run reports.
	///
	/// An error of such a family at a line the oracle cannot place (`Files.site(of:)`: a declaration that is no `final
	/// class`'s, or an attribute on two lines) counts as a site of its own, so that a draw the oracle cannot read shows
	/// in the count.
	static func unremediedSiteCount(of fixture: GraphFuzzerFixture, diagnostics: String) -> Int {
		guard let reading = Reading(of: fixture) else { return 0 }
		func isOfAFamilyTheOracleReads(_ error: ReportedError) -> Bool {
			guard reading == .everyFamily else { return reading.reads(error) }
			return error.message.hasPrefix("Dependency cycle: ")
				|| error.message.contains("` is not @Instantiated or @Forwarded in chain: ")
				|| error.message.hasPrefix(StatedRemedy.multipleFulfillersPrefix)
				|| error.message.hasPrefix(StatedRemedy.unfulfilledInstantiatedTypePrefix)
				|| error.message.contains(StatedRemedy.sendableCaptureMarker)
				|| (error.message.hasPrefix("@Received property `") && error.message.contains(StatedRemedy.hiddenMarker) && error.message.hasSuffix(StatedRemedy.hiddenSuffix))
		}
		let unremediedCount = sites(of: fixture, diagnostics: diagnostics).count(where: { site in
			site.remedies.isEmpty && site.errors.contains(where: isOfAFamilyTheOracleReads)
		})
		guard let files = Files(fixture) else { return unremediedCount }
		let unplacedCount = diagnostics.split(separator: "\n").count(where: { diagnosticLine in
			guard let error = ReportedError(diagnosticLine) else { return false }
			return files.site(of: error) == nil && isOfAFamilyTheOracleReads(error)
		})
		return unremediedCount + unplacedCount
	}

	/// Each property declaration `diagnostics` reports an error at, in the order of its first error, with its errors and
	/// the remedies they state.
	private static func sites(of fixture: GraphFuzzerFixture, diagnostics: String) -> [(errors: [ReportedError], remedies: [GraphFuzzerRemedy])] {
		guard let reading = Reading(of: fixture), let files = Files(fixture) else { return [] }
		var sites = [GraphFuzzerRemedy.Site]()
		var errorsBySite = [GraphFuzzerRemedy.Site: [ReportedError]]()
		for diagnosticLine in diagnostics.split(separator: "\n") {
			guard let error = ReportedError(diagnosticLine), reading.reads(error), let site = files.site(of: error) else { continue }
			if errorsBySite[site] == nil {
				sites.append(site)
			}
			errorsBySite[site, default: []].append(error)
		}
		return sites.map { site in
			let errors = errorsBySite[site] ?? []
			return (errors, remedies(at: site, answering: errors, in: files, of: fixture))
		}
	}

	/// `remedy`, a `forwardReceive` remedy, with the declarations the errors of `diagnostics`, the tool's on the remedied
	/// graph, state for what builds a type that now forwards a property: "… cannot build `T`, which has @Forwarded
	/// properties that only an instantiator is passed. Declare it as `Instantiator<T>`.", and an erased instantiator's
	/// "The first generic argument of … Declare it as `ErasedInstantiator<X, AnyT>`.". Each such property takes the type
	/// its error states. An error `originalDiagnostics`, the tool's on the graph before the remedy, reports too is not the
	/// remedy's to follow. Returns `nil` when no error states such a declaration, or one cannot be applied.
	///
	/// "New" is read from the message alone, so an error of either form that the remedy exposed without causing, at a
	/// declaration that builds another type, is followed too; any other new error is left as it is.
	static func followingForwardedReceive(_ remedy: GraphFuzzerRemedy, diagnostics: String, originalDiagnostics: String) -> GraphFuzzerRemedy? {
		guard var files = Files(remedy.fixture) else { return nil }
		let originalMessages = Set(originalDiagnostics.split(separator: "\n").compactMap { ReportedError($0)?.message })
		let declarationMarker = " Declare it as `"
		var declarations = [String]()
		var retypedSites = Set<GraphFuzzerRemedy.Site>()
		for diagnosticLine in diagnostics.split(separator: "\n") {
			guard let error = ReportedError(diagnosticLine),
			      !originalMessages.contains(error.message),
			      isForwardedBuilderError(error.message),
			      error.message.hasSuffix("`."),
			      let declarationStart = error.message.range(of: declarationMarker, options: .backwards),
			      let site = files.site(of: error),
			      retypedSites.insert(site).inserted
			else { continue }
			let declaredType = String(error.message[declarationStart.upperBound...].dropLast("`.".count))
			guard files.edit(typeNamed: site.typeName, { properties in
				properties.map { $0.label == site.label ? GraphFuzzerRemedyProperty(attribute: $0.attribute, label: $0.label, type: declaredType) : $0 }
			}) else { return nil }
			declarations.append("declares \(site) as `\(declaredType)`")
		}
		guard !declarations.isEmpty else { return nil }
		return GraphFuzzerRemedy(
			kind: remedy.kind,
			site: remedy.site,
			answeredErrors: remedy.answeredErrors,
			description: "\(remedy.description), and \(declarations.joined(separator: ", and "))",
			fixture: GraphFuzzerFixture(seed: remedy.fixture.seed, swiftFileContent: files.contents),
		)
	}

	/// Whether `message` is the error of a declaration that builds a type with `@Forwarded` properties otherwise than
	/// through an instantiator that is passed them.
	private static func isForwardedBuilderError(_ message: String) -> Bool {
		message.contains(", which has @Forwarded properties that only an instantiator is passed.") || message.hasPrefix("The first generic argument of `")
	}

	/// The messages of the errors `outcome`, the last of a `forwardReceive` remedy's runs, still reports at a declaration
	/// that builds the type of the remedy's site, and that `originalDiagnostics`, the tool's on the graph before the
	/// remedy, did not report: what forwarding introduced and the declarations the tool stated did not clear.
	static func errorsIntroducedByForwarding(_ remedy: GraphFuzzerRemedy, outcome: GraphFuzzerToolOutcome, originalDiagnostics: String) -> [String] {
		guard case let .rejected(diagnostics) = outcome else { return [] }
		let originalMessages = Set(originalDiagnostics.split(separator: "\n").compactMap { ReportedError($0)?.message })
		return diagnostics.split(separator: "\n").compactMap { diagnosticLine in
			guard let message = ReportedError(diagnosticLine)?.message,
			      !originalMessages.contains(message),
			      isForwardedBuilderError(message),
			      message.contains(" cannot build `\(remedy.site.typeName)`, ") || message.contains(" properties of `\(remedy.site.typeName)`, which it builds.")
			else { return nil }
			return message
		}
	}

	/// The messages of the errors `outcome` reports at `site` of `fixture`.
	static func errors(at site: GraphFuzzerRemedy.Site, in outcome: GraphFuzzerToolOutcome, of fixture: GraphFuzzerFixture) -> [String] {
		guard case let .rejected(diagnostics) = outcome, let files = Files(fixture) else { return [] }
		return diagnostics.split(separator: "\n").compactMap { diagnosticLine in
			guard let error = ReportedError(diagnosticLine), files.site(of: error) == site else { return nil }
			return error.message
		}
	}

	private static func remedies(at site: GraphFuzzerRemedy.Site, answering errors: [ReportedError], in files: Files, of fixture: GraphFuzzerFixture) -> [GraphFuzzerRemedy] {
		let statedRemedies = errors.map { StatedRemedy(message: $0.message) }
		guard let firstStatedRemedy = statedRemedies.first.flatMap(\.self) else { return [] }
		let answeredErrors = errors.map(\.message)
		if case let .keepOneFulfiller(fulfilledType) = firstStatedRemedy {
			// The site is a declaration, not a property: the declaration keeps the type, and the others lose it.
			var editedFiles = files
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }),
			      fulfilledType == site.label,
			      editedFiles.removeFulfilledType(fulfilledType, fromEveryTypeBut: site.typeName)
			else { return [] }
			return [GraphFuzzerRemedy(
				kind: .keepOneFulfiller,
				site: site,
				answeredErrors: answeredErrors,
				description: "removes `\(fulfilledType)` from the `fulfillingAdditionalTypes` of every declaration but `\(site.typeName)`",
				fixture: GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: editedFiles.contents),
			)]
		}
		if case let .declareProvidingFormOnSeam(collision, property) = firstStatedRemedy {
			// The site is the seam's declaration, with the label: the seam declares the providing form, in place of its own
			// form of the label where it declares one.
			func isReceivedAsAnAdopterWould(_ form: SeamLabelCollision.Form) -> Bool {
				guard form.type.hasSuffix("?") else { return true }
				guard let receive = files.property(labeled: form.label, ofTypeNamed: form.receivingType) else { return false }
				return receive.type == form.type && receive.attribute.hasPrefix("@Received(") && receive.attribute.contains("onlyIfAvailable: true")
			}
			func declaringProperty(_ properties: [GraphFuzzerRemedyProperty]) -> [GraphFuzzerRemedyProperty]? {
				guard properties.contains(where: { $0.label == property.label }) else { return properties + [property] }
				return properties.map { $0.label == property.label ? property : $0 }
			}
			var editedFiles = files
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }),
			      collision.seam == site.typeName,
			      collision.label == site.label,
			      collision.forms.allSatisfy(isReceivedAsAnAdopterWould),
			      editedFiles.edit(typeNamed: collision.seam, declaringProperty)
			else { return [] }
			return [GraphFuzzerRemedy(
				kind: .declareProvidingFormOnSeam,
				site: site,
				answeredErrors: answeredErrors,
				description: "declares `\(property.attribute) let \(property.label): \(property.type)` on `\(collision.seam)`",
				fixture: GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: editedFiles.contents),
			)]
		}
		guard let siteProperty = files.property(labeled: site.label, ofTypeNamed: site.typeName) else { return [] }
		func remedy(_ kind: GraphFuzzerRemedyKind, _ description: String, label: String? = nil, editing edits: [(typeName: String, edit: ([GraphFuzzerRemedyProperty]) -> [GraphFuzzerRemedyProperty]?)]) -> GraphFuzzerRemedy? {
			var editedFiles = files
			for (typeName, edit) in edits {
				guard editedFiles.edit(typeNamed: typeName, edit) else { return nil }
			}
			return GraphFuzzerRemedy(
				kind: kind,
				site: GraphFuzzerRemedy.Site(fileName: site.fileName, typeName: site.typeName, label: label ?? site.label),
				answeredErrors: answeredErrors,
				description: description,
				fixture: GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: editedFiles.contents),
			)
		}
		func replacingSiteProperty(with property: GraphFuzzerRemedyProperty) -> ([GraphFuzzerRemedyProperty]) -> [GraphFuzzerRemedyProperty]? {
			{ properties in
				// A label the type declares otherwise would be declared twice, which the macro rejects.
				guard !properties.contains(where: { $0.label == property.label && $0.label != site.label }) else { return nil }
				return properties.map { $0.label == site.label ? property : $0 }
			}
		}
		func mockRemedy(_ kind: GraphFuzzerRemedyKind, _ description: String, editing edit: (inout Files) -> Bool) -> GraphFuzzerRemedy? {
			var editedFiles = files
			guard edit(&editedFiles) else { return nil }
			return GraphFuzzerRemedy(
				kind: kind,
				site: site,
				answeredErrors: answeredErrors,
				description: description,
				fixture: GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: editedFiles.contents),
			)
		}
		switch firstStatedRemedy {
		case .keepOneFulfiller, .declareProvidingFormOnSeam:
			// Answered above: its site is no property.
			return []
		case let .decorateType(typeName):
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }), siteProperty.attribute == "@Instantiated", siteProperty.type == typeName else { return [] }
			return [mockRemedy(.decorateType, "decorates `\(typeName)` with `@Instantiable`") { files in
				files.decorateEmptyClass(named: typeName)
			}].compactMap(\.self)
		case let .declareAsSendableWrapper(label, declaringType, sendableType, retypesReceive, receivedAs):
			// The wrapper the error would have retyped is the `Sendable` wrapper without `Sendable`.
			// An alias that receives the property names its type too (`ofType:`), and its own property and the aliases of
			// it are typed after it: the error's "where it is received" covers them, which the oracle does not edit.
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }),
			      sendableType.hasPrefix("Sendable"),
			      !files.contents.contains(where: { $0.contains("fulfilledByDependencyNamed: \"\(label)\"") })
			else { return [] }
			let wrapperType = receivedAs ?? String(sendableType.dropFirst("Sendable".count))
			func retyping(_ properties: [GraphFuzzerRemedyProperty]) -> [GraphFuzzerRemedyProperty]? {
				// The property keeps its attribute, and an optional receive stays optional.
				guard properties.contains(where: { $0.label == label && [wrapperType, GraphFuzzerSpelling.optionalForm(of: wrapperType)].contains($0.type) }) else { return nil }
				return properties.map { property in
					guard property.label == label else { return property }
					if property.type == wrapperType {
						return GraphFuzzerRemedyProperty(attribute: property.attribute, label: label, type: sendableType)
					} else if property.type == GraphFuzzerSpelling.optionalForm(of: wrapperType) {
						return GraphFuzzerRemedyProperty(attribute: property.attribute, label: label, type: GraphFuzzerSpelling.optionalForm(of: sendableType))
					} else {
						return property
					}
				}
			}
			var typeNames: [String]
			let description: String
			if let declaringType {
				typeNames = [declaringType]
				if retypesReceive, site.typeName != declaringType {
					guard label == site.label else { return [] }
					typeNames.append(site.typeName)
					description = "declares `\(label)` on `\(declaringType)`, and \(site), as `\(sendableType)`"
				} else {
					description = "declares `\(label)` on `\(declaringType)` as `\(sendableType)`"
				}
			} else {
				typeNames = files.namesOfTypes(declaringPropertyLabeled: label, typed: [wrapperType, GraphFuzzerSpelling.optionalForm(of: wrapperType)])
				guard typeNames.contains(site.typeName) else { return [] }
				description = "declares `\(label)` as `\(sendableType)` on \(typeNames.map { "`\($0)`" }.joined(separator: ", ")), which declare or receive it as `\(wrapperType)`"
			}
			return [remedy(.declareAsSendableWrapper, description, editing: typeNames.map { ($0, retyping) })].compactMap(\.self)
		case let .forwardReceive(label):
			// Each error at the site may name another root; all state the same declaration, which the receiver takes.
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }), label == site.label, siteProperty.attribute == "@Received" else { return [] }
			return [remedy(
				.forwardReceive,
				"receives `\(label)` with `@Forwarded`",
				editing: [(site.typeName, replacingSiteProperty(with: GraphFuzzerRemedyProperty(attribute: "@Forwarded", label: label, type: siteProperty.type)))],
			)].compactMap(\.self)
		case let .defaultMockParameterOrMoveMock(typeName, mockName, parameter, offersMove):
			// One mock reports each of its parameters once, at the clause that declares its dependency.
			guard errors.count == 1, let clauseLine = errors.first?.line, typeName == site.typeName, parameter.label == site.label else { return [] }
			let defaultValue = "\(parameter.type)()"
			let defaulted = mockRemedy(.defaultMockParameter, "gives `\(parameter.label): \(parameter.type)` of `\(typeName).\(mockName)` the default value `\(defaultValue)`") { files in
				files.giveDefaultValue(defaultValue, toParameterLabeled: parameter.label, ofMockNamed: mockName, ofTypeNamed: typeName)
			}
			guard offersMove else { return [defaulted].compactMap(\.self) }
			let moved = mockRemedy(.moveMockIntoClause, "moves `\(typeName).\(mockName)` into the clause at line \(clauseLine)") { files in
				files.moveMock(named: mockName, ofTypeNamed: typeName, intoClauseAtLine: clauseLine)
			}
			return [defaulted, moved].compactMap(\.self)
		case let .instantiateOnRoot(property, _, receivingOnlyIfAvailable):
			// Each error at the site may name another root, whose own walk reached the receive.
			var roots = [String]()
			for statedRemedy in statedRemedies {
				guard case let .instantiateOnRoot(otherProperty, root, otherReceivingOnlyIfAvailable)? = statedRemedy,
				      otherProperty == property,
				      otherReceivingOnlyIfAvailable == receivingOnlyIfAvailable
				else { return [] }
				if !roots.contains(root) {
					roots.append(root)
				}
			}
			guard !roots.contains(site.typeName) else { return [] }
			var description = "declares `\(property.attribute) let \(property.label): \(property.type)` on \(roots.map { "`\($0)`" }.joined(separator: " and "))"
			var edits: [(typeName: String, edit: ([GraphFuzzerRemedyProperty]) -> [GraphFuzzerRemedyProperty]?)] = roots.map { root in
				(root, { properties in properties.contains { $0.label == property.label } ? nil : properties + [property] })
			}
			guard receivingOnlyIfAvailable else {
				return [remedy(.instantiateOnRoot, description, editing: edits)].compactMap(\.self)
			}
			guard let attribute = onlyIfAvailableAttribute(of: siteProperty) else { return [] }
			let receive = GraphFuzzerRemedyProperty(attribute: attribute, label: site.label, type: siteProperty.type)
			description += " and decorates \(site) with `\(attribute)`"
			edits.append((site.typeName, replacingSiteProperty(with: receive)))
			return [remedy(.instantiateOnRootAndReceiveOnlyIfAvailable, description, editing: edits)].compactMap(\.self)
		case let .relabelHidingDeclaration(hiddenLabel, hidingProperty, declaringType):
			// Each error at the site may name another chain; all must name the same declaration.
			let newLabel = "\(hiddenLabel)Relabeled"
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }),
			      hiddenLabel == site.label,
			      siteProperty.attribute.hasPrefix("@Received"),
			      !(siteProperty.type.hasSuffix("?") && !siteProperty.attribute.contains("onlyIfAvailable: true")),
			      !files.contents.contains(where: { $0.contains("fulfilledByDependencyNamed: \"\(hiddenLabel)\"") })
			else { return [] }
			return [remedy(.relabelHidingDeclaration, "gives `\(hidingProperty.label): \(hidingProperty.type)` on `\(declaringType)` the label `\(newLabel)`", editing: [(declaringType, { properties in
				guard properties.contains(where: { $0.label == hiddenLabel && $0.type == hidingProperty.type }),
				      !properties.contains(where: { $0.label == newLabel })
				else { return nil }
				return properties.map { $0.label == hiddenLabel ? GraphFuzzerRemedyProperty(attribute: $0.attribute, label: newLabel, type: $0.type) : $0 }
			})])].compactMap(\.self)
		case let .receiveOnlyIfAvailable(label):
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }), label == site.label, siteProperty.attribute == "@Received" else { return [] }
			let property = GraphFuzzerRemedyProperty(attribute: "@Received(onlyIfAvailable: true)", label: label, type: siteProperty.type)
			return [remedy(.receiveOnlyIfAvailable, "decorates \(site) with `\(property.attribute)`", editing: [(site.typeName, replacingSiteProperty(with: property))])].compactMap(\.self)
		case let .receiveSuggestedProperty(label, suggestions):
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }), label == site.label, siteProperty.attribute == "@Received" else { return [] }
			return suggestions.compactMap { suggestion in
				remedy(.receiveSuggestedProperty, "receives `\(suggestion.label): \(suggestion.type)` in place of \(site)", label: suggestion.label, editing: [(site.typeName, replacingSiteProperty(with: suggestion))])
			}
		case let .instantiateAsInstantiator(hopLabels):
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }), hopLabels.contains(site.label), let instantiatorType = instantiatorType(of: siteProperty) else { return [] }
			let property = GraphFuzzerRemedyProperty(attribute: siteProperty.attribute, label: site.label, type: instantiatorType)
			return [remedy(.instantiateAsInstantiator, "declares \(site) as `\(instantiatorType)`", editing: [(site.typeName, replacingSiteProperty(with: property))])].compactMap(\.self)
		case .removeOrReceiveOptionallyIfAvailable:
			guard statedRemedies.allSatisfy({ $0 == firstStatedRemedy }), siteProperty.attribute.hasPrefix("@Received") else { return [] }
			let removal = remedy(.removeReceive, "removes \(site)", editing: [(site.typeName, { properties in properties.filter { $0.label != site.label } })])
			guard let attribute = onlyIfAvailableAttribute(of: siteProperty) else { return [removal].compactMap(\.self) }
			let property = GraphFuzzerRemedyProperty(attribute: attribute, label: site.label, type: GraphFuzzerSpelling.optionalForm(of: siteProperty.type))
			let optionalReceive = remedy(.receiveOptionallyIfAvailable, "declares \(site) as `\(property.attribute) let \(property.label): \(property.type)`", editing: [(site.typeName, replacingSiteProperty(with: property))])
			return [removal, optionalReceive].compactMap(\.self)
		}
	}

	/// The attribute of `property`, a receive or a rename, with `onlyIfAvailable: true` added, or `nil` when it already
	/// receives only if available or is no receive.
	private static func onlyIfAvailableAttribute(of property: GraphFuzzerRemedyProperty) -> String? {
		guard property.attribute.hasPrefix("@Received"), !property.attribute.contains("onlyIfAvailable") else { return nil }
		return property.attribute == "@Received" ? "@Received(onlyIfAvailable: true)" : "\(property.attribute.dropLast()), onlyIfAvailable: true)"
	}

	/// The instantiator of what `property`, an `@Instantiated` dependency that builds its value once, builds: an
	/// `Instantiator`, or an `ErasedInstantiator` for an erased one, `Sendable` when its wrapper is. `nil` for a property
	/// that is already an instantiator, or that the fuzzer does not spell.
	private static func instantiatorType(of property: GraphFuzzerRemedyProperty) -> String? {
		let erasedAttributePrefix = "@Instantiated(fulfilledByType: "
		let isErased = property.attribute.hasPrefix(erasedAttributePrefix) && property.attribute.hasSuffix(", erasedToConcreteExistential: true)")
		guard property.attribute == "@Instantiated" || isErased, !property.type.contains("Instantiator<") else { return nil }
		let lazyWrapper = [(prefix: "SendableLazilyInstantiated<", isSendable: true), (prefix: "LazilyInstantiated<", isSendable: false)]
			.first { property.type.hasPrefix($0.prefix) && property.type.hasSuffix(">") }
		let builtType = lazyWrapper.map { String(property.type.dropFirst($0.prefix.count).dropLast()) } ?? property.type
		let sendablePrefix = lazyWrapper?.isSendable == true ? "Sendable" : ""
		// A type built once has no forwarded properties, which the macro and the tool require of a constant.
		return isErased ? "\(sendablePrefix)ErasedInstantiator<(), \(builtType)>" : "\(sendablePrefix)Instantiator<\(builtType)>"
	}

	/// A graph's files, by the names the harness gives them, which a remedy edits.
	struct Files {
		private(set) var contents: [String]
		private let fileNames: [String]

		init?(_ fixture: GraphFuzzerFixture) {
			let fileNames = fixture.fileNames
			guard fileNames.count == fixture.swiftFileContent.count else { return nil }
			contents = fixture.swiftFileContent
			self.fileNames = fileNames
		}

		/// The property declaration `error` is reported at, or the declaration that fulfills a type another fulfills too
		/// (`fulfillerSite(of:)`), or `nil` for an error at any other line.
		func site(of error: ReportedError) -> GraphFuzzerRemedy.Site? {
			if let fulfillerSite = fulfillerSite(of: error) {
				return fulfillerSite
			}
			if let seamSite = seamSite(of: error) {
				return seamSite
			}
			guard let fileIndex = fileNames.firstIndex(of: error.fileName) else { return nil }
			let lines = Self.lines(of: contents[fileIndex])
			let lineIndex = error.line - 1
			guard lines.indices.contains(lineIndex),
			      let typeDeclaration = Self.typeDeclarations(in: lines).last(where: { $0.lines.contains(lineIndex) })
			else { return nil }
			if let property = Self.property(on: lines[lineIndex]) {
				return GraphFuzzerRemedy.Site(fileName: error.fileName, typeName: typeDeclaration.name, label: property.label)
			} else if lines[lineIndex].trimmingCharacters(in: .whitespaces).hasPrefix("#"),
			          case let .defaultMockParameterOrMoveMock(typeName, _, parameter, _)? = StatedRemedy(message: error.message),
			          typeName == typeDeclaration.name
			{
				// An error at an `#if` clause that declares a dependency a mock's parameter takes: the site is that dependency,
				// which the message names, so that the same error after an edit that moves the clause is at the same site.
				return GraphFuzzerRemedy.Site(fileName: error.fileName, typeName: typeDeclaration.name, label: parameter.label)
			} else {
				return nil
			}
		}

		/// The declaration `error` is reported at when it is the error of a type two declarations fulfill: the `final
		/// class` whose `@Instantiable` attribute is on the error's line, with the fulfilled type as the site's label.
		func fulfillerSite(of error: ReportedError) -> GraphFuzzerRemedy.Site? {
			guard case let .keepOneFulfiller(fulfilledType)? = StatedRemedy(message: error.message),
			      let fileIndex = fileNames.firstIndex(of: error.fileName)
			else { return nil }
			let lines = Self.lines(of: contents[fileIndex])
			let lineIndex = error.line - 1
			guard lines.indices.contains(lineIndex), lines[lineIndex].hasPrefix("@Instantiable"),
			      let typeDeclaration = Self.typeDeclarations(in: lines).first(where: { $0.lines.lowerBound == lineIndex + 2 })
			else { return nil }
			return GraphFuzzerRemedy.Site(fileName: error.fileName, typeName: typeDeclaration.name, label: fulfilledType)
		}

		/// The seam's declaration `error` is reported at when it is the error of a seam whose tree receives one label in
		/// forms its initializer cannot take as one parameter, whatever remedy the error states: the `final class` whose
		/// `@Instantiable` attribute is on the error's line, with the label as the site's label, so that the error after a
		/// remedy that leaves it, stating another remedy, is at the same site.
		func seamSite(of error: ReportedError) -> GraphFuzzerRemedy.Site? {
			guard let collision = SeamLabelCollision(message: error.message), let fileIndex = fileNames.firstIndex(of: error.fileName) else { return nil }
			let lines = Self.lines(of: contents[fileIndex])
			let lineIndex = error.line - 1
			guard lines.indices.contains(lineIndex), lines[lineIndex].hasPrefix("@Instantiable"),
			      let typeDeclaration = Self.typeDeclarations(in: lines).first(where: { $0.lines.lowerBound == lineIndex + 2 }),
			      typeDeclaration.name == collision.seam
			else { return nil }
			return GraphFuzzerRemedy.Site(fileName: error.fileName, typeName: typeDeclaration.name, label: collision.label)
		}

		/// Removes `fulfillingAdditionalTypes: [fulfilledType.self]` from the `@Instantiable` attribute of every `final
		/// class` but the one named `typeName`. Returns `false`, editing nothing, when no other declaration lists it so, or
		/// the one named `typeName` does not.
		mutating func removeFulfilledType(_ fulfilledType: String, fromEveryTypeBut typeName: String) -> Bool {
			let argument = "fulfillingAdditionalTypes: [\(fulfilledType).self]"
			var editedContents = contents
			var keptCount = 0
			var removedCount = 0
			for fileIndex in contents.indices {
				var lines = Self.lines(of: contents[fileIndex])
				for typeDeclaration in Self.typeDeclarations(in: lines) {
					let attributeIndex = typeDeclaration.lines.lowerBound - 2
					guard attributeIndex >= 0, lines[attributeIndex].hasPrefix("@Instantiable("), lines[attributeIndex].hasSuffix(")") else { continue }
					var arguments = GraphFuzzerOracle.topLevelParameters(String(lines[attributeIndex].dropFirst("@Instantiable(".count).dropLast()))
						.map { $0.trimmingCharacters(in: .whitespaces) }
					guard let argumentIndex = arguments.firstIndex(of: argument) else { continue }
					guard typeDeclaration.name != typeName else {
						keptCount += 1
						continue
					}
					arguments.remove(at: argumentIndex)
					lines[attributeIndex] = arguments.isEmpty ? "@Instantiable" : "@Instantiable(\(arguments.joined(separator: ", ")))"
					removedCount += 1
				}
				editedContents[fileIndex] = lines.joined(separator: "\n")
			}
			guard keptCount == 1, removedCount > 0 else { return false }
			contents = editedContents
			return true
		}

		/// Makes the empty `final class` named `typeName`, which the fuzzer writes on one line, `@Instantiable`: the
		/// attribute, the conformance, and a public initializer that takes nothing. Returns `false`, editing nothing, when
		/// no file declares the class so.
		mutating func decorateEmptyClass(named typeName: String) -> Bool {
			for fileIndex in contents.indices {
				var lines = Self.lines(of: contents[fileIndex])
				for (declaration, conformances) in [("public final class \(typeName) {}", "Instantiable"), ("public final class \(typeName): Sendable {}", "Instantiable, Sendable")] {
					guard let lineIndex = lines.firstIndex(of: declaration) else { continue }
					lines.replaceSubrange(lineIndex...lineIndex, with: [
						"@Instantiable",
						"public final class \(typeName): \(conformances) {",
						"\tpublic init() {}",
						"}",
					])
					contents[fileIndex] = lines.joined(separator: "\n")
					return true
				}
			}
			return false
		}

		/// The names of the `final class`es that declare a property labeled `label` of one of `types`, in the files' order.
		func namesOfTypes(declaringPropertyLabeled label: String, typed types: [String]) -> [String] {
			contents.flatMap { content in
				let lines = Self.lines(of: content)
				return Self.typeDeclarations(in: lines).filter { typeDeclaration in
					typeDeclaration.lines.contains { lineIndex in
						Self.property(on: lines[lineIndex]).map { $0.label == label && types.contains($0.type) } ?? false
					}
				}.map(\.name)
			}
		}

		/// The property labeled `label` that the `final class` named `typeName` declares, in the first file that declares it.
		func property(labeled label: String, ofTypeNamed typeName: String) -> GraphFuzzerRemedyProperty? {
			guard let (fileIndex, typeDeclaration) = typeDeclaration(named: typeName) else { return nil }
			let lines = Self.lines(of: contents[fileIndex])
			return typeDeclaration.lines.lazy.compactMap { Self.property(on: lines[$0]) }.first { $0.label == label }
		}

		/// The first file that declares the `final class` named `typeName`, with that declaration.
		private func typeDeclaration(named typeName: String) -> (fileIndex: Int, declaration: (name: String, lines: Range<Int>))? {
			contents.indices.lazy.compactMap { fileIndex in
				Self.typeDeclarations(in: Self.lines(of: contents[fileIndex])).first { $0.name == typeName }.map { (fileIndex, $0) }
			}.first
		}

		/// Replaces the properties of the `final class` named `typeName` with what `edit` makes of them, keeping its
		/// initializer in step: it takes each property, in order, before the parameters that are not properties, and
		/// assigns each in its body. Returns `false`, editing nothing, when no file declares the type in the fuzzer's form or
		/// `edit` returns `nil`.
		mutating func edit(typeNamed typeName: String, _ edit: ([GraphFuzzerRemedyProperty]) -> [GraphFuzzerRemedyProperty]?) -> Bool {
			guard let (fileIndex, typeDeclaration) = typeDeclaration(named: typeName) else { return false }
			var lines = Self.lines(of: contents[fileIndex])
			let propertyLineIndices = typeDeclaration.lines.filter { Self.property(on: lines[$0]) != nil }
			let properties = propertyLineIndices.compactMap { Self.property(on: lines[$0]) }
			guard let initializerIndex = typeDeclaration.lines.first(where: { Self.droppingAccessModifier(from: lines[$0].trimmingCharacters(in: .whitespaces)).hasPrefix("init(") }),
			      let editedProperties = edit(properties)
			else { return false }
			let initializerLine = lines[initializerIndex]
			let indentation = String(initializerLine.prefix { $0 == "\t" || $0 == " " })
			guard let parametersStart = initializerLine.range(of: "init("),
			      let parametersEnd = initializerLine.range(of: initializerLine.hasSuffix(") {}") ? ") {}" : ") {", options: .backwards),
			      parametersStart.upperBound <= parametersEnd.lowerBound
			else { return false }
			let hasEmptyBody = initializerLine.hasSuffix(") {}")
			let propertyLabels = Set(properties.map(\.label))
			let otherParameters = GraphFuzzerOracle.topLevelParameters(String(initializerLine[parametersStart.upperBound..<parametersEnd.lowerBound]))
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { parameter in !propertyLabels.contains(parameter.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)) }
			// The body's lines, through the line that closes it, and those that assign no property.
			var regionEnd = initializerIndex
			var otherBodyLines = [String]()
			if !hasEmptyBody {
				guard let bodyEnd = lines[(initializerIndex + 1)...].firstIndex(of: indentation + "}") else { return false }
				otherBodyLines = lines[(initializerIndex + 1)..<bodyEnd].filter { line in
					!properties.contains { line.trimmingCharacters(in: .whitespaces) == "self.\($0.label) = \($0.label)" }
				}
				regionEnd = bodyEnd
			}
			if let lastPropertyLineIndex = propertyLineIndices.last {
				regionEnd = max(regionEnd, lastPropertyLineIndex)
			}
			let parameters = editedProperties.map { "\($0.label): \(GraphFuzzerSpelling.escapingType(of: $0.type))" } + otherParameters
			let initializerPrefix = String(initializerLine[..<parametersStart.upperBound])
			let body = editedProperties.map { "\(indentation)\tself.\($0.label) = \($0.label)" } + otherBodyLines
			var region = [String]()
			if body.isEmpty {
				region.append("\(initializerPrefix)\(parameters.joined(separator: ", "))) {}")
			} else {
				region.append("\(initializerPrefix)\(parameters.joined(separator: ", "))) {")
				region += body
				region.append(indentation + "}")
			}
			if !editedProperties.isEmpty {
				region.append("")
				region += editedProperties.map { "\(indentation)\($0.attribute) let \($0.label): \($0.type)" }
			}
			lines.replaceSubrange(initializerIndex...regionEnd, with: region)
			contents[fileIndex] = lines.joined(separator: "\n")
			return true
		}

		/// Gives the parameter labeled `label` of the method named `mockName` that the `final class` named `typeName`
		/// declares on one line the default value `defaultValue`. Returns `false`, editing nothing, when the type declares
		/// no such method, or its parameter already has a default value.
		mutating func giveDefaultValue(_ defaultValue: String, toParameterLabeled label: String, ofMockNamed mockName: String, ofTypeNamed typeName: String) -> Bool {
			guard let (fileIndex, typeDeclaration) = typeDeclaration(named: typeName) else { return false }
			var lines = Self.lines(of: contents[fileIndex])
			let methodPrefix = "static func \(mockName)("
			guard let mockIndex = typeDeclaration.lines.first(where: { lines[$0].contains(methodPrefix) }),
			      let parametersStart = lines[mockIndex].range(of: methodPrefix),
			      let parametersEnd = lines[mockIndex].range(of: ") -> ", options: .backwards),
			      parametersStart.upperBound <= parametersEnd.lowerBound
			else { return false }
			var parameters = GraphFuzzerOracle.topLevelParameters(String(lines[mockIndex][parametersStart.upperBound..<parametersEnd.lowerBound]))
				.map { $0.trimmingCharacters(in: .whitespaces) }
			guard let parameterIndex = parameters.firstIndex(where: { $0.hasPrefix("\(label): ") }), !parameters[parameterIndex].contains(" = ") else { return false }
			parameters[parameterIndex] += " = \(defaultValue)"
			lines[mockIndex] = lines[mockIndex][..<parametersStart.upperBound] + parameters.joined(separator: ", ") + lines[mockIndex][parametersEnd.lowerBound...]
			contents[fileIndex] = lines.joined(separator: "\n")
			return true
		}

		/// Moves the `#if DEBUG` block that holds the method named `mockName` of the `final class` named `typeName`, with the
		/// empty line before it, to the end of the `#if` clause that begins on the one-based `clauseLine` of the type's
		/// file. Returns `false`, editing nothing, when the type declares no such block as the fuzzer writes one, the line
		/// begins no clause, or the block is inside the clause already.
		mutating func moveMock(named mockName: String, ofTypeNamed typeName: String, intoClauseAtLine clauseLine: Int) -> Bool {
			guard let (fileIndex, typeDeclaration) = typeDeclaration(named: typeName) else { return false }
			var lines = Self.lines(of: contents[fileIndex])
			let clauseIndex = clauseLine - 1
			guard typeDeclaration.lines.contains(clauseIndex),
			      let mockIndex = typeDeclaration.lines.first(where: { lines[$0].contains("static func \(mockName)(") }),
			      mockIndex > 0
			else { return false }
			let indentation = String(lines[clauseIndex].prefix { $0 == "\t" || $0 == " " })
			func isClauseBoundary(_ line: String) -> Bool {
				line == indentation + "#else" || line == indentation + "#endif" || line.hasPrefix(indentation + "#elseif ")
			}
			// The clause ends at the next directive of its block: one at its indentation, since a nested block's are deeper.
			guard lines[clauseIndex].hasPrefix(indentation + "#"),
			      lines[mockIndex - 1] == indentation + "#if DEBUG",
			      let clauseEnd = lines[(clauseIndex + 1)...].firstIndex(where: isClauseBoundary),
			      let blockEnd = lines[mockIndex...].firstIndex(of: indentation + "#endif"),
			      clauseEnd < mockIndex
			else { return false }
			let blockStart = mockIndex > 1 && lines[mockIndex - 2].isEmpty ? mockIndex - 2 : mockIndex - 1
			let block = (blockStart == mockIndex - 1 ? [""] : []) + lines[blockStart...blockEnd]
			lines.removeSubrange(blockStart...blockEnd)
			lines.insert(contentsOf: block, at: clauseEnd)
			contents[fileIndex] = lines.joined(separator: "\n")
			return true
		}

		private static func lines(of content: String) -> [String] {
			content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		}

		/// The property a line declares, or `nil` for any other line.
		private static func property(on line: String) -> GraphFuzzerRemedyProperty? {
			guard case let .property(attribute, label, type)? = GraphFuzzerSourceLine.lines(of: line).first else { return nil }
			return GraphFuzzerRemedyProperty(attribute: attribute, label: label, type: type)
		}

		/// Each `final class` the lines declare, with the indices of the lines of its body.
		private static func typeDeclarations(in lines: [String]) -> [(name: String, lines: Range<Int>)] {
			lines.indices.compactMap { index in
				let line = lines[index]
				let declaration = droppingAccessModifier(from: line.trimmingCharacters(in: .whitespaces))
				guard declaration.hasPrefix("final class "), line.hasSuffix(" {") else { return nil }
				let name = declaration.dropFirst("final class ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
				let indentation = line.prefix { $0 == "\t" || $0 == " " }
				guard let end = lines[(index + 1)...].firstIndex(of: indentation + "}") else { return nil }
				return (String(name), (index + 1)..<end)
			}
		}

		private static func droppingAccessModifier(from line: String) -> Substring {
			for modifier in ["public ", "package ", "internal "] where line.hasPrefix(modifier) {
				return line.dropFirst(modifier.count)
			}
			return Substring(line)
		}
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerOracle {
	/// What the error says that a mock tree reports for a hand-written mock's parameter whose dependency the type
	/// declares only inside an `#if` clause the build does not select, which the base corpus counts the rejections of
	/// (`addingGuardedMockParameterShapes` draws the shape) and whose remedies the remedy oracle applies. It ends the
	/// name of the type and begins the clause.
	static let guardedMockParameterErrorMarker = "` declares only inside `"

	/// Runs SafeDITool over each remedy the errors of `outcome` state for `fixture` (`GraphFuzzerRemedies`), when the tool
	/// rejects a base or seam corpus graph in one module: tool runs only, no compile. A seam corpus graph gets only the
	/// remedy of a seam's label collision, since its holes, nested types and extensions spell declarations the other
	/// remedies do not edit, and a public mock corpus graph none (`GraphFuzzerRemedies.Reading`).
	/// How many runs of the tool may follow a `forwardReceive` remedy, each applying the declarations the run before it
	/// stated. The base corpus's graphs need three at most (a builder on each of three roots, a run each); a remedy that
	/// still has an error to follow after these fails with it (`errorsIntroducedByForwarding`).
	static let maximumForwardedReceiveFollowingRunCount = 6

	static func remedyRuns(of fixture: GraphFuzzerFixture, outcome: GraphFuzzerToolOutcome) async throws -> [GraphFuzzerRemedyRun] {
		guard GraphFuzzerRemedies.Reading(of: fixture) != nil, case let .rejected(diagnostics) = outcome else { return [] }
		var runs = [GraphFuzzerRemedyRun]()
		for remedy in GraphFuzzerRemedies.remedies(of: fixture, diagnostics: diagnostics) {
			var remedy = remedy
			var remedyOutcome = try await toolOutcome(of: remedy.fixture)
			if remedy.kind == .forwardReceive {
				// A type that now forwards a property is built only by an instantiator that is passed it, which the tool's
				// next errors state for what built it otherwise. Each root reports the first error its own walk finds, so a
				// run can state the declarations of some builders only, and the next run states more.
				for _ in 0..<maximumForwardedReceiveFollowingRunCount {
					guard case let .rejected(remediedDiagnostics) = remedyOutcome,
					      let followingRemedy = GraphFuzzerRemedies.followingForwardedReceive(remedy, diagnostics: remediedDiagnostics, originalDiagnostics: diagnostics)
					else { break }
					remedy = followingRemedy
					remedyOutcome = try await toolOutcome(of: remedy.fixture)
				}
			}
			let introducedErrors = remedy.kind == .forwardReceive
				? GraphFuzzerRemedies.errorsIntroducedByForwarding(remedy, outcome: remedyOutcome, originalDiagnostics: diagnostics)
				: []
			runs.append(GraphFuzzerRemedyRun(remedy: remedy, outcome: remedyOutcome, introducedErrors: introducedErrors))
		}
		return runs
	}
}
