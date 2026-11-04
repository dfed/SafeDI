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

/// What a diagnostic about a seam parameter says about how visible the parameter's type is and what to change: one
/// formatter for a tier that cannot take a required parameter and for a caller that holds a value the tier it can
/// call omits, keyed by how the parameter's narrowest type is proven (`TypeAccessProof.Cause`), by what receives the
/// parameter, and by the error.
enum SeamAccessExplanation {
	/// Which parameter the explanation is about: a pass-through, one of the seam's own properties, or the builder for a
	/// type no declaration `seamModuleName` reads fulfills, `fulfilledType`, which the seam's tree builds or, when
	/// `isPassedUp`, the seam passes up.
	enum ParameterKind {
		case passThrough
		case ownForwarded
		case ownReceived
		case builder(fulfilledType: TypeDescription, seamModuleName: String?, isPassedUp: Bool)
	}

	/// A receive of the parameter, as the explanation names it.
	struct Receiver {
		let declaringType: TypeDescription
		let aliasProperty: Property?
		let isInstantiateMethodParameter: Bool
	}

	/// The sentence saying how visible `cause`'s type is, as far as SafeDI can tell. `receivers` lets an unproven type
	/// say what an alias receiving it mentions instead.
	static func causeSentence(_ cause: TypeAccessProof.Cause, receivers: [Receiver]) -> String {
		switch cause {
		case let .ownDeclaration(type, level):
			return "\(name(type))'s own `@Instantiable` declaration is `\(level.spelledOnGeneratedDeclaration)`."
		case let .plainDeclaration(type, level, declarations, namesModules):
			return plainDeclarationSentence(type: type, level: level, declarations: declarations, namesModules: namesModules)
		case let .declarationInExtensionOfRecordedType(type, ownLevel, extendedType, extendedTypeLevel, _, extendedTypeIsPlain, _):
			return if extendedTypeLevel < ownLevel {
				"\(name(type)) is `\(extendedTypeLevel.spelledOnGeneratedDeclaration)`: it is declared inside an extension of \(name(extendedType)), \(ownDeclarationPhrase(isPlain: extendedTypeIsPlain)) is `\(extendedTypeLevel.spelledOnGeneratedDeclaration)`."
			} else {
				"\(name(type)) is declared `\(ownLevel.spelledOnGeneratedDeclaration)`."
			}
		case let .declarationInExtension(type, level, extendedType, extensionIsSpelled, isExtensionBased, extendedTypeHasEntry, raisingProvers, _):
			let levelText = "\(name(type)) is `\(level.spelledOnGeneratedDeclaration)` as far as SafeDI can tell: "
			if isExtensionBased {
				return levelText + (raisingProvers.isEmpty
					? "it is declared `@Instantiable` on an extension that spells no access level, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely."
					: "it is declared `@Instantiable` on an extension that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `\(level.spelledOnGeneratedDeclaration)` (\(proverNames(raisingProvers))).")
			} else {
				let extensionText = extensionDescription(extendedType: extendedType, extensionIsSpelled: extensionIsSpelled, extendedTypeHasEntry: extendedTypeHasEntry)
				return levelText + (raisingProvers.isEmpty
					? "it is declared inside \(extensionText)."
					: "it is declared inside an extension of \(extendedType.map(name) ?? "another type"), and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `\(level.spelledOnGeneratedDeclaration)` (\(proverNames(raisingProvers))).")
			}
		case let .signatures(type, level, provers, mentioningModuleName, reason):
			let levelText = "\(name(type)) is `\(level.spelledOnGeneratedDeclaration)` as far as SafeDI can tell: "
			// A lone prover an extension bounds says why it proves less than its own level; several provers are listed,
			// whichever way each is capped, so what is said never depends on their source order.
			if provers.count == 1, let first = provers.first, let bound = first.cap?.extensionBound {
				return levelText + cappedProverClause(first, bound: bound, provedLevel: level, mentionedType: type)
			} else {
				// The mentions counted are those tied to the parameter: a mention elsewhere matches the type's name alone,
				// and could name another type of that name.
				let module = mentioningModuleName.map { "module `\($0)`" } ?? "this module"
				return levelText + "\(reasonClause(reason)), and every initializer, `instantiate(…)` and mock method that mentions it in \(module) or on a type that receives it is `\(level.spelledOnGeneratedDeclaration)` (\(proverNames(provers))); a mention on any other declaration matches it by name alone, so it does not count."
			}
		case let .unproven(type, reason):
			let aliasMentions = receivers.compactMap { receiver in
				receiver.aliasProperty.map { "\(name(receiver.declaringType))'s initializer mentions only `\($0.typeDescription.asSource)`" }
			}
			return "\(name(type)) is `internal` as far as SafeDI can tell: \(reasonClause(reason)), and no initializer, `instantiate(…)` or mock method SafeDI records mentions it\(aliasMentions.isEmpty ? "" : " (\(aliasMentions.joined(separator: "; ")))")."
		case let .enclosedBy(type, enclosingType, cause):
			// Swift caps a nested type at the type enclosing it, whose own sentence says how visible that is. Every cause's
			// sentence begins with the name of the type it proves, possessive only for its own `@Instantiable` declaration.
			let enclosingPredicate = causeSentence(cause, receivers: []).dropFirst(name(cause.type).count)
			return if case .ownDeclaration = cause {
				"\(name(type)) is nested in \(name(enclosingType)), whose\(enclosingPredicate.dropFirst(2))"
			} else {
				"\(name(type)) is nested in \(name(enclosingType)), which\(enclosingPredicate)"
			}
		}
	}

	/// Why SafeDI reads no access level of a type, as a clause of a sentence about it.
	private static func reasonClause(_ reason: TypeAccessProof.UnreadAccessReason) -> String {
		switch reason {
		case let .conditionalBlock(moduleName, namesModule):
			"it is declared inside an `#if` block\(namesModule ? " in \(moduleName.map { "module `\($0)`" } ?? "a module SafeDI knows no name of")" : ""), from which SafeDI takes no access level"
		case .unreadableSpelling:
			"SafeDI cannot read its spelling"
		}
	}

	/// The remedies for a tier of `seam` at `neededLevel` that cannot take `parameter`, whose type `cause` proves at
	/// `parameterLevel`, in the order a reader can follow them: the cause's own, the mention, declaring the seam
	/// narrower, the receive's own, and declaring the tree on a narrower type.
	static func tierRemedies(
		cause: TypeAccessProof.Cause?,
		neededLevel: AccessLevel,
		parameterLevel: AccessLevel,
		seam: TypeDescription,
		parameter: Property,
		receivers: [Receiver],
		parameterKind: ParameterKind,
	) -> String {
		var remedies = [String]()
		if case let .unproven(type, _)? = cause, case .passThrough = parameterKind {
			// A receive on the seam puts the type in an initializer the compiler checks, which then proves it.
			remedies.append("declare `@\(Dependency.Source.receivedRawValue) let \(parameter.label): \(type.asSource)` on \(name(seam)), so that its initializer, which the compiler checks, states how visible \(name(type)) is (the compiler may then require \(name(seam))'s initializer, and so the seam, to be narrower)")
		}
		remedies += causeRemedies(cause, neededLevel: neededLevel)
		let parameterLevelText = "`\(parameterLevel.spelledOnGeneratedDeclaration)`"
		remedies.append("declare \(name(seam)) \(parameterLevelText)")
		switch parameterKind {
		case .ownForwarded:
			break
		case .ownReceived:
			remedies.append("receive `\(parameter.label)` with `onlyIfAvailable: true` and an optional type")
		case let .builder(fulfilledType, seamModuleName, isPassedUp):
			remedies.append(fulfillRemedy(fulfilling: fulfilledType, seam: seam, seamModuleName: seamModuleName, isPassedUp: isPassedUp))
		case .passThrough:
			if let aliasProperty = receivers.first(where: { $0.aliasProperty != nil })?.aliasProperty, receivers.count == 1 {
				remedies.append("receive `\(aliasProperty.label)` with `onlyIfAvailable: true` and an optional type")
			} else if receivers.contains(where: \.isInstantiateMethodParameter) {
				remedies.append("build `\(parameter.label)` inside the tree")
			} else {
				remedies.append("build `\(parameter.label)` inside the tree or receive it with `onlyIfAvailable: true` and an optional type")
			}
		}
		remedies.append("declare the dependency tree on \(article(parameterLevel)) \(parameterLevelText) type that instantiates \(name(seam))")
		return joined(remedies)
	}

	/// The remedies the proof of a type gives before any other: what to declare, spell, or mention so the type is
	/// proven at `neededLevel`.
	/// - Parameter mockOnlyMockLetsMockBuildType: Whether a `mockOnly` mock of a type declared inside an `#if` block,
	///   which the remedies offer, also lets the mock that takes the parameter build the type, as a public mock builds a
	///   type it receives or forwards with its hand-written mock.
	static func causeRemedies(_ cause: TypeAccessProof.Cause?, neededLevel: AccessLevel, mockOnlyMockLetsMockBuildType: Bool = false) -> [String] {
		let level = "`\(neededLevel.spelledOnGeneratedDeclaration)`"
		guard let cause else { return [] }
		switch cause {
		case let .ownDeclaration(type, _):
			return ["declare \(name(type)) \(level)"]
		case let .plainDeclaration(type, _, declarations, namesModules):
			return plainDeclarationRemedies(type: type, declarations: declarations, namesModules: namesModules, neededLevel: neededLevel)
		case let .declarationInExtensionOfRecordedType(type, ownLevel, extendedType, extendedTypeLevel, spellsOwnLevel, _, _):
			return [exactExtensionRemedy(type: type, ownLevel: ownLevel, extendedType: extendedType, extendedTypeLevel: extendedTypeLevel, spellsOwnLevel: spellsOwnLevel, neededLevel: neededLevel)]
		case let .declarationInExtension(type, _, extendedType, _, isExtensionBased, _, _, isMockOnly):
			return [nonExactExtensionRemedy(type: type, extendedType: extendedType, isExtensionBased: isExtensionBased, isMockOnly: isMockOnly, neededLevel: neededLevel), mentionRemedy(of: [type], neededLevel: neededLevel)]
		case let .signatures(type, _, provers, _, reason):
			if provers.count == 1, let first = provers.first, let bound = first.cap?.extensionBound {
				switch bound {
				case let .exact(carrier, ownLevel, extendedType, extendedTypeLevel, spellsOwnLevel, _):
					return [exactExtensionRemedy(type: carrier, ownLevel: ownLevel, extendedType: extendedType, extendedTypeLevel: extendedTypeLevel, spellsOwnLevel: spellsOwnLevel, neededLevel: neededLevel), mentionRemedy(of: [type], neededLevel: neededLevel)]
				case let .nonExact(carrier, _, extendedType, _, isExtensionBased, _, raisingProvers, isMockOnly):
					// A carrier a mention raised is raised further by a wider one; one nothing raised is bounded by its
					// extension, which only spelling the extension, or a mention of the type itself, gets past.
					let mentionedTypes = raisingProvers.isEmpty && !isExtensionBased ? [type] : [carrier, type]
					return [nonExactExtensionRemedy(type: carrier, extendedType: extendedType, isExtensionBased: isExtensionBased, isMockOnly: isMockOnly, neededLevel: neededLevel), mentionRemedy(of: mentionedTypes, neededLevel: neededLevel)]
				}
			} else {
				// SafeDI reads no access level of the type, so widening its declaration changes nothing it proves: a mention
				// does, and so does a `mockOnly` mock in an extension that spells the level.
				return [mentionRemedy(of: [type], neededLevel: neededLevel)] + mockOnlyMockRemedies(of: type, reason: reason, neededLevel: neededLevel, letsMockBuildType: mockOnlyMockLetsMockBuildType)
			}
		case let .unproven(type, reason):
			return [mentionRemedy(of: [type], neededLevel: neededLevel)] + mockOnlyMockRemedies(of: type, reason: reason, neededLevel: neededLevel, letsMockBuildType: mockOnlyMockLetsMockBuildType)
		case let .enclosedBy(_, _, cause):
			// What makes the enclosing type visible makes the nested one, while a mock of the enclosing type builds no
			// nested one.
			return causeRemedies(cause, neededLevel: neededLevel)
		}
	}

	/// The `mockOnly` mock remedy for a type SafeDI reads no access level of for `reason`: a `mockOnly` extension of a type
	/// declared inside an `#if` block proves it at the level the extension spells, while a spelling SafeDI cannot read
	/// names no type an extension can extend.
	private static func mockOnlyMockRemedies(of type: TypeDescription, reason: TypeAccessProof.UnreadAccessReason, neededLevel: AccessLevel, letsMockBuildType: Bool) -> [String] {
		switch reason {
		case .conditionalBlock:
			[mockOnlyMockRemedy(of: type, neededLevel: neededLevel, letsMockBuildType: letsMockBuildType)]
		case .unreadableSpelling:
			[]
		}
	}

	/// A note at each declaration in `cause`'s plain declarations that keeps the type from `neededLevel` – the type's
	/// own, one enclosing it in its file, or the extension it takes its level from – with a fix-it that widens it, which
	/// an error reported elsewhere cannot carry: a fix-it edits the file its diagnostic points at. For a plain declaration
	/// inside an extension of a type whose plain declaration caps it, the notes are at that declaration; for a type
	/// nested in another, at the enclosing type's. Empty for any other cause.
	static func declarationNotes(for cause: TypeAccessProof.Cause?, neededLevel: AccessLevel) -> [SourceDiagnostic] {
		let level = neededLevel.spelledOnGeneratedDeclaration
		return (cause?.provingPlainDeclarations ?? []).flatMap { declaration in
			declaration.accessNeeds.compactMap { accessNeed -> SourceDiagnostic? in
				guard let type = accessNeed.declaration.declaredType,
				      TypeAccessProof.normalized(accessNeed.level) < neededLevel,
				      let location = accessNeed.access.declarationStartLocation
				else { return nil }
				let subject = if case .extensionDeclaringType = accessNeed.declaration {
					"The extension that declares \(name(type)) is `\(accessNeed.level.spelling)` here."
				} else {
					"\(name(type)) is declared `\(accessNeed.level.spelling)` here."
				}
				// A modifier is replaced, and one is inserted where the declaration begins when it spells none.
				let fixIt = accessNeed.access.modifierRange.map { SourceDiagnostic.FixIt(range: $0, replacement: level) }
					?? SourceDiagnostic.FixIt(
						range: Dependency.SourceRange(startLine: location.line, startColumn: location.column, endLine: location.line, endColumn: location.column),
						replacement: "\(level) ",
					)
				return SourceDiagnostic(
					severity: .note,
					location: location,
					message: subject,
					fixIts: [fixIt],
				)
			}
		}
	}

	/// What a call of a seam's tier that would drop the value `omission` names says: who provides it, which tier the
	/// caller reaches and why it omits the parameter, how visible the parameter's type is, and what to change.
	/// `unreadableProviderModuleName` is the module that declares the provider when the provider's file cannot be read.
	static func providedValueMessage(_ omission: ScopeGenerator.SeamTierOmission, callingType: TypeDescription, unreadableProviderModuleName: String?) -> String {
		let parameter = omission.parameter
		let seamCall = omission.seamCall
		let seam = name(omission.seam.concreteInstantiable)
		let label = "`\(parameter.property.label)`"
		// A provider whose file cannot be read is not where the error is reported, so its module is named.
		let providerModule = unreadableProviderModuleName.map { " in module `\($0)`" } ?? ""
		let provider = if let providerDeclaringType = omission.providerDeclaringType {
			"\(name(providerDeclaringType))\(providerModule) provides `\(omission.providerProperty.asSource)`"
		} else {
			"\(name(callingType)) takes `\(omission.providerProperty.asSource)` from its callers"
		}
		/// The module that makes a call, as the call's requirement lets SafeDI tell its package.
		func caller(moduleName: String?, requirement: AccessRequirement) -> String {
			let callerModule = moduleName.map { "module `\($0)`" } ?? "this module"
			return requirement == .packageUnverified ? "\(callerModule), which SafeDI cannot tell is in the same package," : callerModule
		}
		func inModule(_ moduleName: String?) -> String {
			moduleName.map { " in module `\($0)`" } ?? ""
		}
		let receiverNames = parameter.receivers.map(\.declaringType).uniqued().map(name).joinedAsList
		let receiversText = receiverNames.isEmpty ? seam : receiverNames
		let what: String
		if omission.isNoTierParameter, let nestedSeamCall = parameter.nestedSeamCall {
			// The nested seam's tier this seam's tree calls, which omits the parameter, so no tier of this seam takes it.
			let nestedTakes = nestedSeamCall.parameterTierAccess.map { "takes \(label) only on its `\($0.spelledOnGeneratedDeclaration)` initializer" } ?? "takes \(label) on none of its initializers"
			what = "no initializer SafeDI generated for \(seam) takes it: \(seam)'s dependency tree calls the `\(nestedSeamCall.tier.spelledOnGeneratedDeclaration)` initializer SafeDI generated for \(name(nestedSeamCall.seamType))\(inModule(nestedSeamCall.seamModuleName)), the narrowest one \(caller(moduleName: nestedSeamCall.callerModuleName, requirement: nestedSeamCall.requirement)) can call, which \(nestedTakes), so calling it would pass `nil` to \(nestedSeamCall.receivingTypes.map(name).joinedAsList), which the tree would hand \(label) were it built inline."
		} else if !parameter.isPassThrough {
			what = "the `\(seamCall.tier.spelledOnGeneratedDeclaration)` initializer SafeDI generated for \(seam)\(inModule(seamCall.seamModuleName)), the narrowest one \(caller(moduleName: seamCall.callerModuleName, requirement: seamCall.requirement)) can call, does not take it: \(seam) receives \(label) itself, only if available, on its `\(parameter.tierAccess.spelledOnGeneratedDeclaration)` initializer, so this call would pass `nil` to \(seam), which would be handed \(label) were its tree built inline."
		} else {
			what = "the `\(seamCall.tier.spelledOnGeneratedDeclaration)` initializer SafeDI generated for \(seam)\(inModule(seamCall.seamModuleName)), the narrowest one \(caller(moduleName: seamCall.callerModuleName, requirement: seamCall.requirement)) can call, does not take it: \(seam) takes \(label) only on its `\(parameter.tierAccess.spelledOnGeneratedDeclaration)` initializer, so this call would pass `nil` to \(receiversText), which the tree would hand \(label) were it built inline."
		}
		let neededLevel = neededLevel(for: omission)
		let causeText = parameter.accessCause.map { " " + causeSentence($0, receivers: parameter.receivers.map { Receiver(declaringType: $0.declaringType, aliasProperty: $0.aliasProperty, isInstantiateMethodParameter: $0.isInstantiateMethodParameter) }) } ?? ""
		var remedies = [String]()
		// A caller SafeDI cannot tell is in the seam's package needs `package` access, or `public` if it is not.
		let unverifiedPackage = seamCall.requirement == .packageUnverified && !omission.isNoTierParameter ? ", or `public` if the two modules are in different packages" : ""
		// Widening the seam's own initializer, for its own property, helps only where its other arguments' types are as
		// visible as the level needed.
		if case let .signatures(_, _, provers, _, _)? = parameter.accessCause, let first = provers.first, first.cap == nil,
		   parameter.isPassThrough || first.carrier != omission.seam.concreteInstantiable || parameter.otherInitializerArgumentsAccess >= neededLevel
		{
			remedies.append("widen \(first.name) to `\(neededLevel.spelledOnGeneratedDeclaration)`\(unverifiedPackage)")
		}
		remedies += causeRemedies(parameter.accessCause, neededLevel: neededLevel)
		remedies.append("stop providing \(label) on this path")
		return "\(provider), but \(what)\(causeText) \(joined(remedies))"
	}

	/// The level at which the call `omission` describes needs the parameter it omits. A parameter on no tier records the
	/// level the nested seam's tier that omits it would have to take it at.
	static func neededLevel(for omission: ScopeGenerator.SeamTierOmission) -> AccessLevel {
		if omission.isNoTierParameter {
			omission.parameter.tierAccess
		} else {
			AccessLevel.level(satisfying: omission.seamCall.requirement)
		}
	}

	/// What a module must declare so that `seam` needs no builder for `fulfilledType`: a fulfilling declaration in a
	/// module `seamModuleName` reads, which `seam`'s tree builds, or, for a builder `seam` passes up, fills itself.
	static func fulfillRemedy(fulfilling fulfilledType: TypeDescription, seam: TypeDescription, seamModuleName: String?, isPassedUp: Bool) -> String {
		let module = seamModuleName.map { "module `\($0)`" } ?? "this module"
		let effect = isPassedUp ? "\(name(seam)) fills the builder itself" : "\(name(seam))'s tree builds it"
		return "make an @\(InstantiableVisitor.macroName) declaration that fulfills \(name(fulfilledType)) one \(module) reads, so \(effect)"
	}

	// MARK: Private

	private static func name(_ type: TypeDescription) -> String {
		"`\(type.asSource)`"
	}

	/// The last component of a type's name, without its generic arguments: its name within the type that encloses it.
	private static func shortName(_ type: TypeDescription) -> String {
		let enclosingPrefix = type.popNested.map { "\($0.asSource)." } ?? ""
		return "`\(type.strippingGenerics.asSource.dropFirst(enclosingPrefix.count))`"
	}

	private static func article(_ level: AccessLevel) -> String {
		switch level {
		case .internal:
			"an"
		case .open, .public, .package, .fileprivate, .private:
			"a"
		}
	}

	private static func proverNames(_ provers: [TypeAccessProof.Prover]) -> String {
		provers.map(\.name).joined(separator: ", ")
	}

	/// The member of `prover`, as the explanation names it: its initializer, `instantiate(…)` or mock method.
	private static func memberPhrase(_ prover: TypeAccessProof.Prover) -> String {
		switch prover.member {
		case .initializer:
			"\(name(prover.carrier))'s initializer"
		case .instantiateMethod:
			"\(name(prover.carrier))'s `instantiate(…)`"
		case let .mockMethod(mockName):
			"\(name(prover.carrier))'s `\(mockName)(…)`"
		}
	}

	/// Why the widest member that mentions a type proves less than its own level: the entry it is recorded on caps it.
	private static func cappedProverClause(_ prover: TypeAccessProof.Prover, bound: ExtensionBound, provedLevel: AccessLevel, mentionedType: TypeDescription) -> String {
		switch bound {
		case let .exact(carrier, ownLevel, extendedType, extendedTypeLevel, spellsOwnLevel, extendedTypeIsPlain):
			let ownTerm = spellsOwnLevel
				? "and \(shortName(carrier)) is declared `\(ownLevel.spelledOnGeneratedDeclaration)`"
				: "and \(shortName(carrier)) spells none"
			return extendedTypeLevel < ownLevel
				? "\(memberPhrase(prover)), which mentions it, is declared inside an extension of \(name(extendedType)), \(ownDeclarationPhrase(isPlain: extendedTypeIsPlain)) is `\(extendedTypeLevel.spelledOnGeneratedDeclaration)`."
				: "\(memberPhrase(prover)), which mentions it, is declared inside an extension of \(name(extendedType)) that spells no access level, \(ownTerm)."
		case let .nonExact(carrier, carrierLevel, extendedType, extensionIsSpelled, isExtensionBased, extendedTypeHasEntry, raisingProvers, _):
			if isExtensionBased {
				return raisingProvers.isEmpty
					? "\(name(carrier)) is declared `@Instantiable` on an extension that spells no access level, so its `instantiate(…)` proves its parameter types only at `\(provedLevel.spelledOnGeneratedDeclaration)` whatever access the method spells, and no initializer, `instantiate(…)` or mock method SafeDI records mentions \(name(carrier)) or \(name(mentionedType)) more widely."
					: "\(memberPhrase(prover)), which mentions it, is declared on an extension that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions \(name(carrier)) is `\(carrierLevel.spelledOnGeneratedDeclaration)` (\(proverNames(raisingProvers)))."
			} else {
				let extensionText = extensionDescription(extendedType: extendedType, extensionIsSpelled: extensionIsSpelled, extendedTypeHasEntry: extendedTypeHasEntry)
				return raisingProvers.isEmpty
					? "\(name(carrier)) is declared inside \(extensionText), so \(memberPhrase(prover)) proves its parameter types only at `\(provedLevel.spelledOnGeneratedDeclaration)`."
					: "\(memberPhrase(prover)), which mentions it, is declared inside an extension of \(extendedType.map(name) ?? "another type") that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions \(name(carrier)) is `\(carrierLevel.spelledOnGeneratedDeclaration)` (\(proverNames(raisingProvers)))."
			}
		}
	}

	/// An extension SafeDI does not read as bounding the declarations inside it, and why.
	private static func extensionDescription(extendedType: TypeDescription?, extensionIsSpelled: Bool, extendedTypeHasEntry: Bool) -> String {
		guard let extendedType else { return "an extension" }
		if extensionIsSpelled {
			return "an extension of \(name(extendedType)), a nested type, whose spelled access level bounds nothing SafeDI can count"
		} else if extendedTypeHasEntry {
			return "an extension of \(name(extendedType)) that spells no access level, which SafeDI counts as `internal`, since it reads \(name(extendedType))'s access only from an `@Instantiable` type declaration of \(name(extendedType)) in the same module that is outside every extension, or inside an extension of a type it reads the same way"
		} else {
			return "an extension of \(name(extendedType)) that spells no access level, and \(name(extendedType)) is declared inside an `#if` block, from which SafeDI takes no access level"
		}
	}

	/// What to declare for a type inside an extension of a type whose own declaration bounds it.
	private static func exactExtensionRemedy(type: TypeDescription, ownLevel: AccessLevel, extendedType: TypeDescription, extendedTypeLevel: AccessLevel, spellsOwnLevel: Bool, neededLevel: AccessLevel) -> String {
		let level = "`\(neededLevel.spelledOnGeneratedDeclaration)`"
		if extendedTypeLevel < neededLevel, extendedTypeLevel < ownLevel || ownLevel >= neededLevel {
			return "declare \(name(extendedType)) \(level)"
		} else if !spellsOwnLevel, extendedTypeLevel >= neededLevel {
			return "declare \(shortName(type)) \(level), or spell the extension's access level (`\(neededLevel.spelledOnGeneratedDeclaration) extension \(extendedType.asSource) { … }`)"
		} else {
			return "declare \(shortName(type)) \(level)"
		}
	}

	/// What to spell for a declaration inside an extension SafeDI does not read as bounding it, or an extension-based
	/// one: conditional, since SafeDI cannot tell whether the extended type can be that visible. A `mockOnly` extension
	/// declares no conformance, so it spells the level as it is.
	private static func nonExactExtensionRemedy(type: TypeDescription, extendedType: TypeDescription?, isExtensionBased: Bool, isMockOnly: Bool, neededLevel: AccessLevel) -> String {
		let levelSpelling = neededLevel.spelledOnGeneratedDeclaration
		if isExtensionBased, isMockOnly {
			return "if \(name(type)) can be `\(levelSpelling)`, spell the extension's access level as `@\(InstantiableVisitor.macroName)(mockOnly: true) \(levelSpelling) extension \(type.asSource)`"
		} else if isExtensionBased {
			return "if \(name(type)) can be `\(levelSpelling)`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) \(levelSpelling) extension \(type.asSource)`, declaring the `Instantiable` conformance on \(name(type))'s own declaration or in a separate `extension \(type.asSource): Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares \(name(type)), apply `@Instantiable` to its declaration instead"
		}
		guard let extendedType else { return "declare \(shortName(type)) outside every extension" }
		let declareInBody = "declare \(shortName(type)) in \(name(extendedType))'s body or at top level"
		guard extendedType.popNested == nil else { return declareInBody }
		return "if \(name(extendedType)) can be `\(levelSpelling)`, spell the extension's access level (`\(levelSpelling) extension \(extendedType.asSource) { … }`, dropping the modifier on \(shortName(type)) that Swift then reports as redundant; the compiler rejects a level wider than \(name(extendedType))'s), or \(declareInBody)"
	}

	/// How `type`'s plain declarations prove it: `level`, the narrowest of theirs, in the module of each when
	/// `namesModules`.
	private static func plainDeclarationSentence(type: TypeDescription, level: AccessLevel, declarations: [PlainTypeDeclaration], namesModules: Bool) -> String {
		let levelsByModule = declarationLevelsByModule(declarations)
		guard namesModules else {
			return "\(name(type)) is declared `\(level.spelledOnGeneratedDeclaration)`."
		}
		let declared = levelsByModule.map { "`\($0.level.spelledOnGeneratedDeclaration)` in \($0.moduleName.map { "module `\($0)`" } ?? "a module SafeDI knows no name of")" }
		guard declared.count > 1 else {
			return "\(name(type)) is declared \(declared.first ?? "`\(level.spelledOnGeneratedDeclaration)`")."
		}
		return "\(name(type)) is declared \(declared.joinedAsList), and SafeDI takes the \(declared.count > 2 ? "narrowest" : "narrower")."
	}

	/// What to declare so that `type`'s plain declarations prove it at `neededLevel`: widen each that is narrower – in
	/// its module, when `namesModules` – or, where another module declares the type at that level, name that module's.
	private static func plainDeclarationRemedies(type: TypeDescription, declarations: [PlainTypeDeclaration], namesModules: Bool, neededLevel: AccessLevel) -> [String] {
		let levelsByModule = declarationLevelsByModule(declarations)
		let narrowerModuleNames = levelsByModule.filter { $0.level < neededLevel }.map(\.moduleName)
		let modules = if !namesModules || narrowerModuleNames.isEmpty {
			""
		} else if narrowerModuleNames.allSatisfy({ $0 != nil }) {
			" in \(narrowerModuleNames.count > 1 ? "modules" : "module") \(narrowerModuleNames.compactMap { $0.map { "`\($0)`" } }.joinedAsList)"
		} else {
			" in \(narrowerModuleNames.map { $0.map { "module `\($0)`" } ?? "a module SafeDI knows no name of" }.uniqued().joinedAsList)"
		}
		var remedies = ["declare \(name(type)) `\(neededLevel.spelledOnGeneratedDeclaration)`\(modules)"]
		if let wideEnough = levelsByModule.first(where: { $0.level >= neededLevel }), let moduleName = wideEnough.moduleName {
			remedies.append("spell the type with its module where it is mentioned (`\(moduleName).\(type.asSource)`), so that it names that module's declaration")
		}
		if namesModules, narrowerModuleNames.contains(nil) {
			// SafeDI takes the level of a declaration in a module it knows no name of as declared, whichever package that
			// module is in.
			remedies.append("name the module that declares \(name(type)) where SafeDI runs on it (`module_name` under Bazel, `--module-name` otherwise)")
		}
		return remedies
	}

	/// The module and level of each of `declarations`, in their order, as the proof counts the level. Each is its
	/// module's only one: the compiler rejects a second declaration of a type in one module, and a `private` one, which
	/// another file's may share a name with, is never among a type's declarations (`isVisibleOutsideItsFile`).
	private static func declarationLevelsByModule(_ declarations: [PlainTypeDeclaration]) -> [(moduleName: String?, level: AccessLevel)] {
		declarations.map { ($0.moduleName, TypeAccessProof.normalized($0.levelBeforeExtendedTypeCap)) }
	}

	/// The `mockOnly` mock that proves `type`, which is declared inside an `#if` block, at `neededLevel`: its extension
	/// spells the level, which bounds the type an extension-based declaration declares.
	private static func mockOnlyMockRemedy(of type: TypeDescription, neededLevel: AccessLevel, letsMockBuildType: Bool) -> String {
		let level = neededLevel.spelledOnGeneratedDeclaration
		return "give \(name(type)) a `\(level)` `mockOnly` mock (`@\(InstantiableVisitor.macroName)(mockOnly: true) \(level) extension \(type.asSource) { \(level) static func mock() -> \(type.asSource) }`), which proves \(name(type)) `\(level)`\(letsMockBuildType ? " and lets the mock build it" : "")"
	}

	/// How an explanation names the declaration of a type that bounds the types declared in extensions of it.
	private static func ownDeclarationPhrase(isPlain: Bool) -> String {
		isPlain ? "whose own declaration" : "whose own `@Instantiable` declaration"
	}

	private static func mentionRemedy(of types: [TypeDescription], neededLevel: AccessLevel) -> String {
		"mention \(types.map(name).joined(separator: " or ")) in a `\(neededLevel.spelledOnGeneratedDeclaration)` initializer, `instantiate(…)` or mock method SafeDI records"
	}

	/// `remedies` as one sentence: separated by semicolons, the last after "or", the first capitalized.
	static func joined(_ remedies: [String]) -> String {
		guard var sentence = remedies.first else { return "" }
		if remedies.count > 1 {
			sentence = remedies.dropLast().joined(separator: "; ") + "; or " + (remedies.last ?? "")
		}
		return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
	}
}

extension Array where Element: Hashable {
	/// The elements in order, each once.
	func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}

extension SeamAccessExplanation {
	/// An extension's bound on a declaration: an extension of a type whose own declaration bounds what it declares
	/// exactly, or one SafeDI does not read as bounding it, or an extension-based declaration.
	enum ExtensionBound {
		case exact(carrier: TypeDescription, ownLevel: AccessLevel, extendedType: TypeDescription, extendedTypeLevel: AccessLevel, spellsOwnLevel: Bool, extendedTypeIsPlain: Bool)
		case nonExact(carrier: TypeDescription, carrierLevel: AccessLevel, extendedType: TypeDescription?, extensionIsSpelled: Bool, isExtensionBased: Bool, extendedTypeHasEntry: Bool, raisingProvers: [TypeAccessProof.Prover], isMockOnly: Bool)
	}
}

extension TypeAccessProof.Cause {
	/// The cause as an extension's bound, or `nil` when no extension bounds the type.
	var extensionBound: SeamAccessExplanation.ExtensionBound? {
		switch self {
		case let .declarationInExtensionOfRecordedType(type, ownLevel, extendedType, extendedTypeLevel, spellsOwnLevel, extendedTypeIsPlain, _):
			.exact(carrier: type, ownLevel: ownLevel, extendedType: extendedType, extendedTypeLevel: extendedTypeLevel, spellsOwnLevel: spellsOwnLevel, extendedTypeIsPlain: extendedTypeIsPlain)
		case let .declarationInExtension(type, level, extendedType, extensionIsSpelled, isExtensionBased, extendedTypeHasEntry, raisingProvers, isMockOnly):
			.nonExact(carrier: type, carrierLevel: level, extendedType: extendedType, extensionIsSpelled: extensionIsSpelled, isExtensionBased: isExtensionBased, extendedTypeHasEntry: extendedTypeHasEntry, raisingProvers: raisingProvers, isMockOnly: isMockOnly)
		case .ownDeclaration, .plainDeclaration, .signatures, .unproven, .enclosedBy:
			nil
		}
	}

	/// The type the cause proves.
	var type: TypeDescription {
		switch self {
		case let .ownDeclaration(type, _),
		     let .plainDeclaration(type, _, _, _),
		     let .declarationInExtensionOfRecordedType(type, _, _, _, _, _, _),
		     let .declarationInExtension(type, _, _, _, _, _, _, _),
		     let .signatures(type, _, _, _, _),
		     let .unproven(type, _),
		     let .enclosedBy(type, _, _):
			type
		}
	}

	/// The plain declarations that prove the cause's type: its own, those of the type the extension it is declared in
	/// extends, or those that prove the type enclosing it; empty for any other cause.
	var provingPlainDeclarations: [PlainTypeDeclaration] {
		switch self {
		case let .plainDeclaration(_, _, declarations, _):
			declarations
		case let .declarationInExtensionOfRecordedType(_, _, _, _, _, _, extendedTypeDeclarations):
			extendedTypeDeclarations
		case let .enclosedBy(_, _, cause):
			cause.provingPlainDeclarations
		case .ownDeclaration, .declarationInExtension, .signatures, .unproven:
			[]
		}
	}

	/// Whether the cause's remedies leave out a `mockOnly` mock of its type, which lets a mock build the type: they
	/// offer one, which also proves the type, for a type SafeDI reads no access level of because it is declared inside
	/// an `#if` block, and none for a spelling SafeDI cannot read, which no extension can extend. For a nested type,
	/// they offer one of the type that encloses it at most.
	var leavesOutMockOnlyMockOfType: Bool {
		switch self {
		case .ownDeclaration, .plainDeclaration, .declarationInExtensionOfRecordedType, .declarationInExtension, .enclosedBy:
			true
		case .signatures, .unproven:
			false
		}
	}
}
