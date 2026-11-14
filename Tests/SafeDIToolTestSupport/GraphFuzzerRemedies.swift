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

	/// The messages of the errors the tool reports at the remedy's site in the remedied graph: none when the remedy fixes
	/// what it answers and adds no error there.
	var errorsAtSite: [String] {
		GraphFuzzerRemedies.errors(at: remedy.site, in: outcome, of: remedy.fixture)
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

		/// The remedy `message` states, or `nil` for an error outside the families the oracle reads, or one whose remedy
		/// the oracle cannot apply as stated: an erased instantiator whose fulfilling type the error leaves to the user, a
		/// type built only through an `Instantiator`, or a cycle an alias received only if available closes.
		init?(message: String) {
			let unfulfilledPrefix = "@Received property `"
			let unfulfilledMarker = "` is not @Instantiated or @Forwarded in chain: "
			let onlyIfAvailableRemedy = " Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required."
			if message.hasPrefix(unfulfilledPrefix), let markerRange = message.range(of: unfulfilledMarker) {
				let receivedLabel = Self.property(spelled: message[message.index(message.startIndex, offsetBy: unfulfilledPrefix.count)..<markerRange.lowerBound], attribute: "@Received")?.label
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
				} else {
					return nil
				}
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

	/// The remedies the errors of `diagnostics` state for `fixture`, one per remedy of each site in the order the tool
	/// reports the sites: every error the tool reports at a site must state the same remedy, or, for a receive no type in
	/// its chain fulfills, the same declaration on its own root, which each root then declares. A site whose errors state
	/// other remedies, or one the oracle cannot apply as stated (`StatedRemedy`), gets none.
	static func remedies(of fixture: GraphFuzzerFixture, diagnostics: String) -> [GraphFuzzerRemedy] {
		sites(of: fixture, diagnostics: diagnostics).flatMap(\.remedies)
	}

	/// The number of sites of `diagnostics` whose errors are in a family the oracle reads – a receive no type in its chain
	/// fulfills, or a cycle – and that get no remedy: the oracle's blind spot, which the long run reports.
	static func unremediedSiteCount(of fixture: GraphFuzzerFixture, diagnostics: String) -> Int {
		sites(of: fixture, diagnostics: diagnostics).count(where: { site in
			site.remedies.isEmpty && site.errors.contains { error in
				error.message.hasPrefix("Dependency cycle: ") || error.message.contains("` is not @Instantiated or @Forwarded in chain: ")
			}
		})
	}

	/// Each property declaration `diagnostics` reports an error at, in the order of its first error, with its errors and
	/// the remedies they state.
	private static func sites(of fixture: GraphFuzzerFixture, diagnostics: String) -> [(errors: [ReportedError], remedies: [GraphFuzzerRemedy])] {
		guard let files = Files(fixture) else { return [] }
		var sites = [GraphFuzzerRemedy.Site]()
		var errorsBySite = [GraphFuzzerRemedy.Site: [ReportedError]]()
		for diagnosticLine in diagnostics.split(separator: "\n") {
			guard let error = ReportedError(diagnosticLine), let site = files.site(of: error) else { continue }
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
		guard let firstStatedRemedy = statedRemedies.first.flatMap(\.self),
		      let siteProperty = files.property(labeled: site.label, ofTypeNamed: site.typeName)
		else { return [] }
		let answeredErrors = errors.map(\.message)
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
		switch firstStatedRemedy {
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

		/// The property declaration `error` is reported at, or `nil` for an error at any other line.
		func site(of error: ReportedError) -> GraphFuzzerRemedy.Site? {
			guard let fileIndex = fileNames.firstIndex(of: error.fileName) else { return nil }
			let lines = Self.lines(of: contents[fileIndex])
			let lineIndex = error.line - 1
			guard lines.indices.contains(lineIndex), let property = Self.property(on: lines[lineIndex]),
			      let typeDeclaration = Self.typeDeclarations(in: lines).last(where: { $0.lines.contains(lineIndex) })
			else { return nil }
			return GraphFuzzerRemedy.Site(fileName: error.fileName, typeName: typeDeclaration.name, label: property.label)
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
	/// Runs SafeDITool over each remedy the errors of `outcome` state for `fixture` (`GraphFuzzerRemedies`), when the tool
	/// rejects a base corpus graph in one module: tool runs only, no compile. Remedies are not applied to a graph of
	/// another corpus, whose seams, holes and public mocks spell declarations the remedies do not edit.
	static func remedyRuns(of fixture: GraphFuzzerFixture, outcome: GraphFuzzerToolOutcome) async throws -> [GraphFuzzerRemedyRun] {
		guard GraphFuzzerGeneratorFeature.features(drawnIn: fixture).isEmpty, fixture.modules == nil, case let .rejected(diagnostics) = outcome else { return [] }
		var runs = [GraphFuzzerRemedyRun]()
		for remedy in GraphFuzzerRemedies.remedies(of: fixture, diagnostics: diagnostics) {
			try await runs.append(GraphFuzzerRemedyRun(remedy: remedy, outcome: toolOutcome(of: remedy.fixture)))
		}
		return runs
	}
}
