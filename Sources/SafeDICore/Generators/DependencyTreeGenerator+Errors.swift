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

extension DependencyTreeGenerator {
	enum DependencyTreeGeneratorError: SourceLocatedError {
		/// No production declaration fulfills a type that properties instantiate. `fulfilledByMockOnlyDeclaration` is set
		/// when a `mockOnly` declaration fulfills it; `unreadImports` names, for each file that declares such a property,
		/// the modules it imports that the run read nothing of, or is `nil` when the run cannot tell.
		/// `viewDeclaringModule`, when set, is a module this module depends on through another, whose declaration of the
		/// type a module info's view carries, though the module lists only the module it reaches it through.
		case noInstantiableFound(TypeDescription, referencedBy: [LocatedProperty], fulfilledByMockOnlyDeclaration: Bool, unreadImports: UnreadImportsOfFiles?, viewDeclaringModule: ViewDeclaringModule?)
		case unfulfillableProperties([UnfulfillableProperty])
		/// Reported at the dependency of a root through which its tree calls a seam whose builder for a hole it cannot
		/// fill, with a note at the hole's declaration where its file can be read. See `UnfilledHole`.
		case unfilledHoles([UnfilledHole])
		/// Reported at each receive in a fill's tree, or each repeat of a property on a seam's path in it, that the fill
		/// cannot give inline's value, with a note at the declaration inline would read. See `FillFinding`.
		case fillFindings([FillFinding])
		/// Reported at each `@Instantiated` declaration in the tree of a seam whose module SafeDI does not know that no
		/// production declaration fulfills. See `HoleInSeamOfUnnamedModule`.
		case holesInSeamsOfUnnamedModule([HoleInSeamOfUnnamedModule])
		/// Reported at each `@Received` declaration whose dependency a closer ancestor hides, with a note at the
		/// hiding declaration. See `HiddenReceivedProperty`.
		case hiddenReceivedProperties([HiddenReceivedProperty])
		/// Reported at each `@Received(fulfilledByDependencyNamed:ofType:)` declaration whose label its own type declares
		/// with another type, with a note at that declaration. See `RenameContradictingOwnProperty`.
		case renamesContradictingOwnProperties([RenameContradictingOwnProperty])
		/// Reported at a `@Received` declaration in the tree of a dependency a mock builds beside the mocked type, which
		/// the mocked type's forwarded property fulfills but another receive of its label hides, with a note at that
		/// receive. See `ForwardedPropertyHiddenInPromotedTree`.
		case forwardedPropertyHiddenInPromotedTree(ForwardedPropertyHiddenInPromotedTree)
		/// Reported at a `@Received` declaration in a mock's tree – the mocked type's own, or that of a dependency the mock
		/// builds beside the mocked type – beneath a type in that tree that receives its label in a form no one declaration
		/// provides together with it, with a note at that receive. See `ReceivedPropertyHiddenInMockTree`.
		case receivedPropertyHiddenInMockTree(ReceivedPropertyHiddenInMockTree)
		/// Reported at the first receive of a label that a type a dependency cycle builds again receives in forms the one
		/// value SafeDI hands it cannot provide together, with a note at the declaration of the label the cycle builds the
		/// type again beneath. See `UnpassableCycleLabel`.
		case unpassableCycleLabel(UnpassableCycleLabel)
		case instantiableHasForwardedProperty(ForwardedPropertyViolation)
		/// Reported at the dependency declaration that closes the cycle – the `@Instantiated` or `@Received`
		/// property whose type is already on the instantiation stack, and which is not an `@Instantiated`
		/// instantiator – with a note at each member type’s `@Instantiable` declaration. See `DependencyCycle`.
		case constantDependencyCycleDetected(DependencyCycle, closingDependency: ClosingDependency)
		/// Reported at the `@Received` declaration that closes the chain: the one that receives `instantiated` back
		/// inside the tree `instantiated` creates, or inside the tree of a sibling that the chain reaches. The
		/// properties can be of any type, `Instantiator`s included. No notes; the chain is spelled out in the message.
		/// `requiredOnlyIfAvailableAliases` are the `onlyIfAvailable` aliases a receive in the chain requires, in chain order.
		/// `closedInSeamFill` is whether the receive is inside a fill of another module's seam and `instantiated` is declared
		/// in that seam's tree outside the fill (`markingCyclesClosedInSeamFills(_:)`).
		case dependencyReceivedInSameChainItIsInstantiated(instantiated: Property, receivedPropertyChain: [Property], declarationLocation: Dependency.DeclarationLocation?, lazilyInstantiatedProperties: [Property], requiredOnlyIfAvailableAliases: [RequiredOnlyIfAvailableAlias], closedInSeamFill: Bool = false)
		/// Reported at the hand-written `mock` method of a type whose `mock()` this module also generates.
		case handWrittenMockSharesGeneratedMockName(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isGeneratedForAdditionalMocksToGenerate: Bool)
		/// Reported at a hand-written `mock` method this module sees for a type another module generates a public mock
		/// for, which this module's mocks reach: `Type.mock()` would be ambiguous.
		case handWrittenMockSharesPublicMockName(TypeDescription, declaringModuleName: String?, declaredAt: [Dependency.DeclarationLocation?])
		/// Reported at the `generateMock:` argument of a `generateMock: .public` type whose public mock cannot be
		/// generated: an enclosing type is narrower than `public`, or a required parameter is (`PublicMockFinding`).
		case publicMockCannotBeGenerated([PublicMockFinding])
		/// Reported at each dependency that a `@Sendable` builder function would read from an `Instantiator`,
		/// `ErasedInstantiator`, or `LazilyInstantiated` declared outside it, with a note at that wrapper when a type
		/// in the tree declares it.
		case nonSendableWrapperCapturedBySendableBuilder([ScopeGenerator.NonSendableWrapperCapture])
		/// Reported at each declaration whose value a call of a seam's generated initializer would drop: the tier the
		/// call reaches omits the parameter it would pass, which the tree built inline would hand on. A note at each
		/// receive of the parameter inside the seam. `callingType` is the type at the root of the tree that makes the
		/// call.
		case seamTierOmitsProvidedValue([ProvidedValueOmission])
		/// A mock tree holds a value for a parameter that the tier of a public mock it calls omits
		/// (`leafTierOmitsProvidedValue`), so the call would pass `nil` where the tree built inline hands the value on.
		case publicMockTierOmitsProvidedValue([ScopeGenerator.PublicMockTierOmission])
		/// A mock tree calls another module's public mock that is generated under another mock condition.
		case publicMockUnderOtherMockCondition([ScopeGenerator.PublicMockCallUnderOtherMockCondition])
		/// Reported at the dependency of a tree this module generates that calls a seam of another module whose files
		/// this run read under a mock condition that module does not guard its mock-only declarations with. See
		/// `SeamModuleMockConditionDifference`.
		case seamModuleMockConditionDiffers([SeamModuleMockConditionDifference])
		/// Reported at an own root or seam whose generated initializer states no isolation and builds a seam another
		/// module generated main-actor. See `SeamCalledWithoutIsolation`.
		case seamCalledWithoutIsolation([SeamCalledWithoutIsolation])
		/// Reported at the hand-written mock of each type that generated mocks build both with that mock and
		/// without it, in ways one `SafeDIMockConfiguration` struct cannot describe. See `ConfigurationBuiltTwoWays`.
		case configurationBuiltTwoWays([ConfigurationBuiltTwoWays])
		/// Reported at each dependency of one declaration whose label `String` equates with an earlier dependency's.
		/// See `RepeatedDependencyLabel`.
		case repeatedDependencyLabels([RepeatedDependencyLabel])
		/// Reported at each `@Received(fulfilledByDependencyNamed:ofType:)` declaration spelled as the `@Instantiable` macro
		/// rejects. See `RejectedRename`.
		case rejectedRenames([RejectedRename])
		/// Reported at each parameter of a hand-written mock a generated mock calls that the generated call cannot pass. See
		/// `UnfulfilledMockParameter`.
		case unfulfilledMockParameters([UnfulfilledMockParameter])
		/// Reported at each declaration whose access keeps the generated code from constructing a type, or, when the
		/// declaration's file cannot be read, where this module refers to the construction. See `InaccessibleConstruction`.
		case inaccessibleConstructions([InaccessibleConstruction])
		/// Reported at the declaration of a seam whose generated initializer SafeDI cannot write. See `SeamError`.
		case seam(SeamError)
		/// An error located in source that building a seam's tree threw – an `ErasedInstantiator` whose first generic
		/// argument is not the built type's forwarded properties – collected with the seam errors so each is reported.
		case sourceLocated(any SourceLocatedError)
		/// Errors that validations independent of one another found – those of different roots, for example – each
		/// reported as it would be alone, in source order. See `reportingAll(of:)`.
		case independentErrors([DependencyTreeGeneratorError])

		/// An error reporting every one of `errors`, or `nil` when there are none. The errors are reported in source
		/// order, so neither which are reported nor their order depends on the order of the validations that found
		/// them, which follows the names of what they validate. Each validation must keep nothing from one that threw
		/// that would let it skip work the one that threw did not finish, or which errors are found would depend on
		/// that order too.
		static func reportingAll(of errors: [DependencyTreeGeneratorError]) -> DependencyTreeGeneratorError? {
			// An error that joins errors already is joined error by error, so that an error two joins share – one label
			// that the trees of two mock roots each find unpassable – is reported once.
			let errors = errors.flatMap { error -> [DependencyTreeGeneratorError] in
				if case let .independentErrors(errors) = error {
					errors
				} else {
					[error]
				}
			}
			return if errors.count > 1 {
				.independentErrors(errors)
			} else {
				errors.first
			}
		}

		/// The diagnostics of this error in the groups `independentErrors` joins, leaving out those of the constructions
		/// an `inaccessibleConstructions` error reports and of the parameters an `unfulfilledMockParameters` error
		/// reports, which `independentErrors` merges across the errors it joins. Every validation that finds either
		/// throws them as an error of its own, which `reportingAll(of:)` joins directly.
		private var sourceDiagnosticGroupsOfUnmergedFindings: [[SourceDiagnostic]] {
			if case .inaccessibleConstructions = self {
				[]
			} else if case .unfulfilledMockParameters = self {
				[]
			} else {
				[sourceDiagnostics]
			}
		}

		/// The parameters this error reports as unfulfilled, if it is an `unfulfilledMockParameters` error.
		private var reportedUnfulfilledMockParameters: [UnfulfilledMockParameter] {
			if case let .unfulfilledMockParameters(unfulfilledMockParameters) = self {
				unfulfilledMockParameters
			} else {
				[]
			}
		}

		/// The constructions this error reports as inaccessible, if it is an `inaccessibleConstructions` error.
		private var reportedInaccessibleConstructions: [InaccessibleConstruction] {
			if case let .inaccessibleConstructions(inaccessibleConstructions) = self {
				inaccessibleConstructions
			} else {
				[]
			}
		}

		var sourceDiagnostics: [SourceDiagnostic] {
			switch self {
			case let .independentErrors(errors):
				// The trees of several mock roots can each need one declaration to widen, or each call one hand-written mock
				// whose parameter they cannot pass, which is reported once.
				SourceDiagnostic.joiningInSourceOrder(
					errors.flatMap(\.sourceDiagnosticGroupsOfUnmergedFindings)
						+ InaccessibleConstruction.sourceDiagnosticGroups(of: errors.flatMap(\.reportedInaccessibleConstructions))
						+ UnfulfilledMockParameter.sourceDiagnosticGroups(of: errors.flatMap(\.reportedUnfulfilledMockParameters)),
				)
			case let .inaccessibleConstructions(inaccessibleConstructions):
				// A declaration that several constructions need to widen the same way is reported once.
				SourceDiagnostic.joiningInSourceOrder(InaccessibleConstruction.sourceDiagnosticGroups(of: inaccessibleConstructions))
			case let .seam(seamError):
				seamError.sourceDiagnostics
			case let .sourceLocated(error):
				error.sourceDiagnostics
			case let .seamModuleMockConditionDiffers(differences):
				differences
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .seamCalledWithoutIsolation(calls):
				calls
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .seamTierOmitsProvidedValue(omissions):
				// Each root's omissions arrive in generation order, and the roots in type order; they are reported in
				// source order. Two calls of one seam that drop one provider's value for the same receivers – the calls of
				// two types a tree builds – read the same, so the error is reported once.
				omissions
					.map { providedValueOmission in
						let omission = providedValueOmission.omission
						// A signature records no receiver of the seam's own property, which the call's leaf declares as
						// the seam declares it: that receive is the note.
						let ownReceive = omission.parameter.isPassThrough ? nil : omission.seam.dependencies.first { $0.property == omission.parameter.property }
						// The receives in the calling seam's tree that make the provider its parameter come first, then the
						// receives the call would pass `nil` to, each declaration once.
						let receivers = (omission.providerReceivers + omission.parameter.receivers)
							.map { NotedReceive(declaringType: $0.declaringType, property: $0.property, declarationLocation: $0.declarationLocation) }
							.uniqued()
							+ (ownReceive.map { [NotedReceive(declaringType: omission.seam.concreteInstantiable, property: $0.property, declarationLocation: $0.declarationLocation)] } ?? [])
						return [SourceDiagnostic(
							severity: .error,
							location: providedValueOmission.location,
							message: SeamAccessExplanation.providedValueMessage(omission, callingType: providedValueOmission.callingType, unreadableProviderModuleName: providedValueOmission.unreadableProviderModuleName),
						)] + SeamAccessExplanation.declarationNotes(for: omission.parameter.accessCause, neededLevel: SeamAccessExplanation.neededLevel(for: omission)) + receivers.map { receiver in
							SourceDiagnostic(
								severity: .note,
								location: receiver.declarationLocation,
								message: "`\(receiver.declaringType.asSource)` receives `\(receiver.property.asSource)` here.",
							)
						}
					}
					.uniqued()
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .nonSendableWrapperCapturedBySendableBuilder(captures):
				// The captures arrive in set order. Two whose errors read the same name the same wrapper on the same
				// type, so their notes, at that declaration, read the same too, and the diagnostics come out the same.
				captures
					.map { Self.sourceDiagnostics(of: $0, among: captures) }
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .repeatedDependencyLabels(repeatedDependencyLabels):
				repeatedDependencyLabels
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .rejectedRenames(rejectedRenames):
				rejectedRenames
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .unfulfilledMockParameters(unfulfilledMockParameters):
				SourceDiagnostic.joiningInSourceOrder(UnfulfilledMockParameter.sourceDiagnosticGroups(of: unfulfilledMockParameters))
			case let .configurationBuiltTwoWays(configurationsBuiltTwoWays):
				// Sorted by location so the order never depends on map iteration.
				configurationsBuiltTwoWays
					.flatMap(\.sourceDiagnostics)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .publicMockCannotBeGenerated(findings):
				SourceDiagnostic.joiningInSourceOrder(findings.map(\.sourceDiagnostics))
			case let .publicMockUnderOtherMockCondition(calls):
				// One diagnostic per dependency that leads to such a call, in source order.
				calls
					.map(\.sourceDiagnostic)
					.uniqued()
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .publicMockTierOmitsProvidedValue(omissions):
				// Two calls that drop one provider's value for the same receivers read the same, and are reported once.
				omissions
					.map(\.sourceDiagnostics)
					.uniqued()
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .handWrittenMockSharesPublicMockName(typeDescription, declaringModuleName, declaredAt):
				// Sorted by location so the order never depends on map iteration.
				declaredAt
					.map {
						SourceDiagnostic(
							severity: .error,
							location: $0,
							message: "`\(typeDescription.asSource)` has a public `mock()` generated by \(declaringModuleName.map { "`\($0)`" } ?? "its module"); a hand-written `mock` here makes every call ambiguous. Give it another name and pass it as `customMockName`.",
						)
					}
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .handWrittenMockSharesGeneratedMockName(typeDescription, declaredAt, isGeneratedForAdditionalMocksToGenerate):
				// Sorted by location so the order never depends on map iteration.
				declaredAt
					.map {
						SourceDiagnostic(
							severity: .error,
							location: $0,
							message: Self.handWrittenMockSharesGeneratedMockNameMessage(
								typeDescription: typeDescription,
								isGeneratedForAdditionalMocksToGenerate: isGeneratedForAdditionalMocksToGenerate,
							),
						)
					}
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .noInstantiableFound(typeDescription, referencedBy, fulfilledByMockOnlyDeclaration, unreadImports, viewDeclaringModule):
				// Sorted by location so the order never depends on map iteration.
				referencedBy.map { locatedProperty in
					SourceDiagnostic(
						severity: .error,
						location: locatedProperty.declarationLocation,
						message: Self.noInstantiableFoundMessage(
							typeDescription: typeDescription,
							referencingProperty: locatedProperty.property,
							fulfilledByMockOnlyDeclaration: fulfilledByMockOnlyDeclaration,
							unreadImports: unreadImports.map { unreadImports in
								(
									integration: unreadImports.integration,
									importsModuleNotRead: locatedProperty.declarationLocation.flatMap { unreadImports.importsModuleNotReadByFilePath[$0.filePath] },
								)
							},
							viewDeclaringModule: viewDeclaringModule,
						),
					)
				}
				.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .holesInSeamsOfUnnamedModule(holes):
				holes
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .fillFindings(fillFindings):
				fillFindings
					.sorted { $0.precedesInSourceOrder($1) }
					.flatMap(\.sourceDiagnostics)
			case let .unfilledHoles(unfilledHoles):
				unfilledHoles
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .unfulfillableProperties(unfulfillableProperties):
				unfulfillableProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .hiddenReceivedProperties(hiddenReceivedProperties):
				hiddenReceivedProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .renamesContradictingOwnProperties(renamesContradictingOwnProperties):
				renamesContradictingOwnProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .forwardedPropertyHiddenInPromotedTree(forwardedPropertyHiddenInPromotedTree):
				forwardedPropertyHiddenInPromotedTree.sourceDiagnostics
			case let .receivedPropertyHiddenInMockTree(receivedPropertyHiddenInMockTree):
				receivedPropertyHiddenInMockTree.sourceDiagnostics
			case let .unpassableCycleLabel(unpassableCycleLabel):
				Self.sourceDiagnostics(of: unpassableCycleLabel)
			case let .instantiableHasForwardedProperty(violation):
				violation.sourceDiagnostics
			case let .constantDependencyCycleDetected(cycle, closingDependency):
				cycle.sourceDiagnostics(summary: "Dependency cycle: \(cycle.asSource). \(closingDependency.remedy)\(Self.lazilyInstantiatedHint(for: cycle.lazilyInstantiatedProperties))")
			case let .dependencyReceivedInSameChainItIsInstantiated(instantiated, receivedPropertyChain, declarationLocation, lazilyInstantiatedProperties, requiredOnlyIfAvailableAliases, closedInSeamFill):
				[
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "Dependency cycle: "
							+ "@\(Dependency.Source.instantiatedRawValue) `\(instantiated.asSource)` -> "
							+ receivedPropertyChain
							.map { "@\(Dependency.Source.receivedRawValue) `\($0.asSource)`" }
							.joined(separator: " -> ")
							+ ". `\(instantiated.asSource)` is received while it is still being instantiated. "
							// An alias received only if available says how to break the cycle at that alias.
							+ Self.remedy(ofCycleClosedThrough: requiredOnlyIfAvailableAliases, closedInSeamFill: closedInSeamFill)
							+ Self.lazilyInstantiatedHint(for: lazilyInstantiatedProperties),
					),
				]
			}
		}

		/// What each integration whose modules are listed by hand does to list a module an error has just named.
		static let listModuleRemedy = "list its `<name>_safedi` target in this target’s `safedi_deps` under Bazel, list its module in the `dependencies:` of this target’s `SafeDI.preCompileScript` under Tuist, or list its `.safedi` file in the file you pass to `--dependent-module-info-file-path` in a custom build."

		/// The last remedy for a type no `@Instantiable` declaration a seam's caller can see fulfills: what each
		/// integration does to read the module that declares one.
		static let fulfillingDeclarationInAnotherModuleRemedy = "or, if such a declaration is in another module, make that module one SafeDI reads for this target: add its target to this target’s `dependencies` in `Package.swift`, declare that module with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target’s `safedi_deps` under Bazel, or give its target `SafeDI.preCompileScript` and list its module in the `dependencies:` of this target’s `SafeDI.preCompileScript` under Tuist."

		/// How to break a cycle closed by a receive of a property that is still being built.
		fileprivate static let onlyIfAvailableRemedy = "Remove this @\(Dependency.Source.receivedRawValue) property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required."

		/// How to break a cycle that a receive closes through `requiredOnlyIfAvailableAliases`: at each alias, or, where the
		/// receive requires none, as `onlyIfAvailableRemedy` says. A receive inside a fill of another module's seam that closes
		/// a cycle on a property the seam's tree declares outside the fill is only removed: received only if available, the
		/// fill would read a value the seam's tree binds only after it calls the fill's builder, which that builder's values
		/// struct cannot carry, an error of its own (`SeamBuilderParameters`' `declarationBoundAfterSite` finding). Any other
		/// cycle keeps both remedies, as the same graph built inline does.
		private static func remedy(ofCycleClosedThrough requiredOnlyIfAvailableAliases: [RequiredOnlyIfAvailableAlias], closedInSeamFill: Bool) -> String {
			if !requiredOnlyIfAvailableAliases.isEmpty {
				requiredOnlyIfAvailableAliases.map(\.hint).joined(separator: " ")
			} else if closedInSeamFill {
				"Remove this @\(Dependency.Source.receivedRawValue) property."
			} else {
				onlyIfAvailableRemedy
			}
		}

		/// What a fill of a hole of another module's seam declares: where each receive of a type the fill's tree builds is
		/// declared, and the properties that tree instantiates and that the seam's tree instantiates outside its fills, as
		/// declared and as cycle validation sees them.
		struct SeamFillDeclarations {
			let receiveLocations: Set<Dependency.DeclarationLocation>
			let instantiatedProperties: Set<Property>
			let seamTreeInstantiatedProperties: Set<Property>

			/// The declarations of the fill of each hole of each seam in `holesBySeamType` that `typeDescriptionToScopeMap`
			/// builds: the tree of the scope the hole's owner instantiates its property with. A hole the map does not fill has none.
			static func ofFills(ofHolesOf holesBySeamType: [TypeDescription: [SeamSignature.Hole]], in typeDescriptionToScopeMap: [TypeDescription: Scope]) -> [SeamFillDeclarations] {
				var fills = [SeamFillDeclarations]()
				for (seamType, holes) in holesBySeamType where !holes.isEmpty {
					// The edges by which the seam's tree enters a fill, which the walk of the seam's tree does not follow.
					let fillEdges = holes.compactMap { hole in typeDescriptionToScopeMap[hole.ownerType].map { (owner: $0, property: hole.property) } }
					let seamTreeInstantiatedProperties = typeDescriptionToScopeMap[seamType].map { seamScope in
						declarations(inTreeOf: seamScope, entering: { scope, property in !fillEdges.contains { $0.owner === scope && $0.property == property } }).instantiatedProperties
					} ?? []
					for hole in holes {
						var fillScope: Scope?
						for case let .instantiated(property, childScope, _) in typeDescriptionToScopeMap[hole.ownerType]?.propertiesToGenerate ?? [] where property == hole.property {
							fillScope = childScope
						}
						guard let fillScope else { continue }
						let fillDeclarations = declarations(inTreeOf: fillScope, entering: { _, _ in true })
						fills.append(SeamFillDeclarations(
							receiveLocations: fillDeclarations.receiveLocations,
							instantiatedProperties: fillDeclarations.instantiatedProperties,
							seamTreeInstantiatedProperties: seamTreeInstantiatedProperties,
						))
					}
				}
				return fills
			}

			/// Where each receive of a type in the tree `root` builds is declared, and the properties that tree instantiates, as
			/// declared and as cycle validation sees them, walking into the child a scope instantiates a property with only where
			/// `entering` says.
			private static func declarations(inTreeOf root: Scope, entering: (_ scope: Scope, _ property: Property) -> Bool) -> (receiveLocations: Set<Dependency.DeclarationLocation>, instantiatedProperties: Set<Property>) {
				var receiveLocations = Set<Dependency.DeclarationLocation>()
				var instantiatedProperties = Set<Property>()
				// A tree can be as deep as the module has types, so the walk keeps its own stack.
				var reachedScopes: Set<Scope> = [root]
				var scopesToVisit = [root]
				while let scope = scopesToVisit.popLast() {
					for dependency in scope.instantiable.dependencies {
						switch dependency.source {
						case .received, .aliased:
							if let declarationLocation = dependency.declarationLocation {
								receiveLocations.insert(declarationLocation)
							}
						case .instantiated, .forwarded:
							break
						}
					}
					for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
						instantiatedProperties.insert(property)
						instantiatedProperties.insert(property.asValidatedForDependencyCycles)
						if entering(scope, property), reachedScopes.insert(childScope).inserted {
							scopesToVisit.append(childScope)
						}
					}
				}
				return (receiveLocations, instantiatedProperties)
			}
		}

		/// This error with each cycle that a receive inside one of `fills` closes, on a property the fill's seam's tree
		/// instantiates outside its fills and that fill's tree does not, marked `closedInSeamFill`, so that it states only the
		/// remedy that leads to no other error. A property only the caller's tree declares keeps both remedies: the fill reads
		/// the caller's value, as inline. A receive is known by its declaration, and a property by its label and type, so a
		/// type that fills a hole and is also built outside any fill, and a property the caller declares that the seam's tree
		/// also declares off the fill's path, lose the second remedy, a deliberate loss the seam rules record.
		func markingCyclesClosedInSeamFills(_ fills: [SeamFillDeclarations]) -> Self {
			if case let .independentErrors(errors) = self {
				.independentErrors(errors.map { $0.markingCyclesClosedInSeamFills(fills) })
			} else if case let .dependencyReceivedInSameChainItIsInstantiated(instantiated, receivedPropertyChain, declarationLocation?, lazilyInstantiatedProperties, requiredOnlyIfAvailableAliases, _) = self {
				.dependencyReceivedInSameChainItIsInstantiated(
					instantiated: instantiated,
					receivedPropertyChain: receivedPropertyChain,
					declarationLocation: declarationLocation,
					lazilyInstantiatedProperties: lazilyInstantiatedProperties,
					requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases,
					closedInSeamFill: fills.contains { $0.receiveLocations.contains(declarationLocation) && $0.seamTreeInstantiatedProperties.contains(instantiated) && !$0.instantiatedProperties.contains(instantiated) },
				)
			} else {
				self
			}
		}

		/// A sentence to end a cycle diagnostic with when lazily instantiated properties are on the cycle, or an
		/// empty string when none are. Cycle validation sees such a property as the constant it stands for, so the
		/// path in the diagnostic names that constant; this says so, and why the property does not break the cycle.
		private static func lazilyInstantiatedHint(for lazilyInstantiatedProperties: [Property]) -> String {
			guard !lazilyInstantiatedProperties.isEmpty else { return "" }
			let validatedAs = lazilyInstantiatedProperties
				.map { "`\($0.asSource)` is validated as `\($0.asValidatedForDependencyCycles.asSource)`" }
				.joined(separator: ", ")
			return " A lazily instantiated dependency is created once, so it cannot break a dependency cycle: \(validatedAs)."
		}

		/// Whether each file that instantiates a type no declaration fulfills imports a module the run read nothing of, and
		/// how the run learns of the modules it reads.
		struct UnreadImportsOfFiles {
			let integration: UnreadImports.Integration
			/// Whether each file imports a module the run read nothing of, by the file's path, for each file whose imports
			/// the run knows.
			let importsModuleNotReadByFilePath: [String: Bool]
		}

		/// - Parameter unreadImports: How the run learns of the modules it reads, with whether the file that declares
		///   `referencingProperty` imports a module the run read nothing of (`nil` when the run does not know what the file
		///   imports, as for another module's file), or `nil` when the run cannot tell which modules it could have read (the
		///   Xcode project plugin's, or one run by hand).
		private static func noInstantiableFoundMessage(
			typeDescription: TypeDescription,
			referencingProperty: Property,
			fulfilledByMockOnlyDeclaration: Bool,
			unreadImports: (integration: UnreadImports.Integration, importsModuleNotRead: Bool?)?,
			viewDeclaringModule: ViewDeclaringModule?,
		) -> String {
			let typeName = typeDescription.asSource
			let reference = "`\(typeName)`, which @\(Dependency.Source.instantiatedRawValue) property `\(referencingProperty.asSource)` instantiates"
			if let viewDeclaringModule {
				// A module info's view names the module, though it fulfills no type of this module's trees: list it.
				return "No @\(InstantiableVisitor.macroName) declaration of a module this module lists fulfills \(reference). `\(typeName)` is declared in `\(viewDeclaringModule.moduleName)`, which this module reaches only through `\(viewDeclaringModule.throughModuleName)`. Add `\(viewDeclaringModule.moduleName)` beside `\(viewDeclaringModule.throughModuleName)` among this module’s SafeDI dependencies: \(listModuleRemedy)"
			} else if fulfilledByMockOnlyDeclaration {
				return "No production @\(InstantiableVisitor.macroName) declaration fulfills \(reference). A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @\(InstantiableVisitor.macroName) declaration that fulfills `\(typeName)`."
			} else {
				// The usual cause, a declaration SafeDI reads that is not decorated, leads.
				var message = "No @\(InstantiableVisitor.macroName) type or extension fulfills \(reference). \(fulfillingDeclarationRemedy(typeName: typeName))."
				if let unreadImports {
					// A file that imports only modules the run read names no type of a module the run could be given.
					if unreadImports.importsModuleNotRead ?? true {
						message += " " + fulfillingDeclarationInModuleNotReadRemedy(typeName: typeName, integration: unreadImports.integration)
					}
				} else {
					message += " " + fulfillingDeclarationInTargetNotReadRemedy(typeName: typeName)
				}
				return message
			}
		}

		/// The remedy for a type, named `typeName`, that no `@Instantiable` declaration fulfills: a declaration that fulfills
		/// it, as a decorated type or extension, or as a type that lists it among the types it fulfills, which a protocol needs.
		static func fulfillingDeclarationRemedy(typeName: String) -> String {
			"Decorate `\(typeName)`, or an extension of it, with @\(InstantiableVisitor.macroName), or list `\(typeName)` in the `fulfillingAdditionalTypes` of an @\(InstantiableVisitor.macroName) type that conforms to it"
		}

		/// The sentences that say how `integration` gives the run the module that declares a type that fulfills the type
		/// named `typeName`, when that module is one the run read nothing of. They name none of the modules the file
		/// imports: a file imports the SDK's and the toolchain's modules too, which SafeDI cannot tell from the user's.
		private static func fulfillingDeclarationInModuleNotReadRemedy(typeName: String, integration: UnreadImports.Integration) -> String {
			switch integration {
			case .moduleInfo:
				"If a declaration that fulfills `\(typeName)` is in another module, run SafeDI on that module and list it among this module’s SafeDI dependencies: under Bazel, declare it with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target’s `safedi_deps`; under Tuist, give its target `SafeDI.preCompileScript` and list it in the `dependencies:` of this target’s `SafeDI.preCompileScript`; in a custom build, list its `.safedi` file in the file you pass to `--dependent-module-info-file-path`."
			case .targetGraph:
				"If a declaration that fulfills `\(typeName)` is in another target, add that target to this target’s `dependencies` in `Package.swift`: SafeDI reads only the targets this target depends on. For a target of a package fetched from a URL, add the package’s checkout directory to `additionalDirectoriesToInclude` in a `#\(SafeDIConfigurationVisitor.macroName)` instead."
			}
		}

		/// The sentence that says how a run that cannot tell which modules it could have read (the Xcode project plugin's,
		/// or one run by hand) reads the target that declares a type that fulfills the type named `typeName`.
		private static func fulfillingDeclarationInTargetNotReadRemedy(typeName: String) -> String {
			"If a declaration that fulfills `\(typeName)` is in another target, add that target’s folder to `additionalDirectoriesToInclude` in this target’s `#\(SafeDIConfigurationVisitor.macroName)`, or, in a SafeDITool run by hand, list the `.safedi` file of its module in the file you pass to `--dependent-module-info-file-path`."
		}

		/// An `error:` line that names the type declaring the wrapper, since Xcode drops notes from build-tool
		/// output, and a `note:` at that declaration so command-line builds can navigate to it. The remedy names
		/// every type that declares a wrapper `captures` reports captured at the same receive: each named declaration
		/// feeds that receive, and changing all of them clears every one of these errors.
		private static func sourceDiagnostics(of capture: ScopeGenerator.NonSendableWrapperCapture, among captures: [ScopeGenerator.NonSendableWrapperCapture]) -> [SourceDiagnostic] {
			let wrapperProperty = capture.wrapperProperty
			let label = wrapperProperty.label
			let wrapperType = wrapperProperty.typeDescription.unwrapped
			// Each wrapper's `Sendable` twin is spelled with `Sendable` before its name.
			let sendableWrapperType = "Sendable\(wrapperType.asSource)"
			// A lazily instantiated property can also be received as its instance; the others only as themselves.
			let receivesWrapper = !capture.receivedProperty.propertyType.isConstant
			let capturedProperty: String
			let fix: String
			if let declaringType = capture.wrapperDeclaringType {
				capturedProperty = "`\(wrapperProperty.asSource)` on `\(declaringType.asSource)`"
				// In source order, each type once. A wrapper the tree receives from outside it is left to that capture's
				// own error, whose remedy names no declaration.
				let declaringTypes = captures
					.filter { $0.declarationLocation == capture.declarationLocation && $0.receivedProperty == capture.receivedProperty }
					.compactMap { other in other.wrapperDeclaringType.map { WrapperDeclaration(typeName: $0.asSource, location: other.wrapperDeclarationLocation) } }
					.sorted(by: WrapperDeclaration.precedesInSourceOrder)
					.map { "`\($0.typeName)`" }
					.uniqued()
					.joinedAsList
				fix = receivesWrapper
					? "Declare `\(label)` on \(declaringTypes), and this property, as `\(sendableWrapperType)` to fix."
					: "Declare `\(label)` on \(declaringTypes) as `\(sendableWrapperType)` to fix."
			} else {
				capturedProperty = "`\(wrapperProperty.asSource)`, which the tree of `\(capture.chain[0].asSource)` receives from outside it"
				fix = "Declare `\(label)` as `\(sendableWrapperType)` where it is declared and where it is received as `\(wrapperType.asSource)` to fix."
			}
			let requirement = if wrapperProperty.propertyType.isLazilyInstantiated {
				// The constant a lazily instantiated property stands for has the type of its instance.
				"A `\(Dependency.sendableLazilyInstantiatedType)` requires its instance type, `\(wrapperProperty.asUnwrappedProperty.asValidatedForDependencyCycles.typeDescription.asSource)`, to be `Sendable`."
			} else {
				"`\(sendableWrapperType)` builds `\(wrapperType.asInstantiatedType.asSource)` in a `@Sendable` function, so what the tree of `\(wrapperType.asInstantiatedType.asSource)` receives from outside that function must be `Sendable` too."
			}
			// A builder that is not a `Sendable` wrapper is built in a `@Sendable` function because a cycle builds it
			// again inside one.
			let sendableBuilderReason = if capture.sendableBuilder.propertyType.isSendable {
				""
			} else {
				" (a `@Sendable` builder function in the tree of `\(capture.sendableBuilder.typeDescription.asInstantiatedType.asSource)` builds it again)"
			}
			// A seam's generated initializer that takes the property as a `@Sendable` closure captures what the call passes, as
			// the `@Sendable` builder function inside the seam's tree that reads it would built inline.
			let capturingFunction = if let seamType = capture.capturingSeamType {
				"`\(seamType.asSource)`’s generated initializer takes `\(capture.receivedProperty.label)` as a `@Sendable` closure, because a `@Sendable` function inside `\(seamType.asSource)`’s tree reads it, and that closure"
			} else if capture.capturingFillIsPassedOn {
				"The function SafeDI generates to fill the builder for `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` is passed to the initializer SafeDI generates for a type with `generateDependencyTree: true` from inside a `@Sendable` function, or to one that takes it `@Sendable`, so it is `@Sendable` too, and it"
			} else if let fillSeamType = capture.capturingFillSeamType {
				"`\(fillSeamType.asSource)`’s tree builds `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` inside a `@Sendable` function, so the function SafeDI generates to fill its builder is `@Sendable` too, and it"
			} else {
				"SafeDI builds `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` in a `@Sendable` function\(sendableBuilderReason), which"
			}
			let error = SourceDiagnostic(
				severity: .error,
				location: capture.declarationLocation,
				message: "@\(Dependency.Source.receivedRawValue) property `\(capture.receivedProperty.asSource)` cannot be received inside a `@Sendable` function in chain: \(capture.chain.map(\.asSource).joined(separator: " -> ")). "
					+ "\(capturingFunction) cannot capture \(capturedProperty), because `\(wrapperType.asSource)` is not `Sendable`. "
					+ "\(fix) \(requirement)",
			)
			return if capture.wrapperDeclaringType != nil {
				[
					error,
					SourceDiagnostic(
						severity: .note,
						location: capture.wrapperDeclarationLocation,
						message: "`\(wrapperProperty.asSource)` is declared here",
					),
				]
			} else {
				[error]
			}
		}

		/// A type that declares a wrapper a `@Sendable` builder function captures, and where.
		private struct WrapperDeclaration {
			let typeName: String
			let location: Dependency.DeclarationLocation?

			/// Orders declarations by location, and by type name where neither precedes the other: where two have no
			/// location, as another module’s declarations that a module info file carries have none.
			static func precedesInSourceOrder(_ lhs: Self, _ rhs: Self) -> Bool {
				Dependency.DeclarationLocation.precedesInSourceOrder(lhs.location, rhs.location) || (!Dependency.DeclarationLocation.precedesInSourceOrder(rhs.location, lhs.location) && lhs.typeName < rhs.typeName)
			}
		}

		private static func handWrittenMockSharesGeneratedMockNameMessage(
			typeDescription: TypeDescription,
			isGeneratedForAdditionalMocksToGenerate: Bool,
		) -> String {
			let typeName = typeDescription.asSource
			return if isGeneratedForAdditionalMocksToGenerate {
				"`\(typeName)` cannot have a hand-written `mock()` method because this module generates a `mock()` method for it (it is listed in `additionalMocksToGenerate`), and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@\(InstantiableVisitor.macroName)` that declares it, or remove `\(typeName)` from `additionalMocksToGenerate`."
			} else {
				"`\(typeName)` cannot have a hand-written `mock()` method because it is decorated with `@\(InstantiableVisitor.macroName)(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@\(InstantiableVisitor.macroName)` that declares it."
			}
		}

		/// A type that generated mocks build with its hand-written mock for one property and without it for another,
		/// where the two constructions read different `SafeDIMockConfiguration` structs.
		struct ConfigurationBuiltTwoWays {
			let concreteType: TypeDescription
			/// Where the hand-written mock is declared. Several map entries can carry the same mock.
			let mockDeclarationLocations: [Dependency.DeclarationLocation?]
			/// The first node, in mock root order, that the hand-written mock builds.
			let builtByMock: BuiltConstruction
			/// The first node, in mock root order, built without the hand-written mock.
			let builtWithoutMock: BuiltConstruction

			// D1 lane hook (lane D): what the diagnostic reads of a node, which the emitter's nodes and the lowering's
			// records both give (`MockLowering+OneWay.swift`).
			/// A node a generated mock builds: the property, the type that declares it, the mock whose tree holds it, and
			/// the construction it is built with.
			struct BuiltConstruction {
				let property: Property
				/// The concrete type whose scope declares the property, as generated code spells it: the mock root's at the
				/// top of the tree.
				let parent: String
				let mockRoot: TypeDescription
				let customMockName: String?
				let isExtensionBased: Bool
			}

			var sourceDiagnostics: [SourceDiagnostic] {
				let typeName = "`\(concreteType.asSource)`"
				let mockName = "`\(builtByMock.customMockName ?? InstantiableVisitor.mockMethodName)`"
				// Built without its mock, a type declared by an extension calls its `instantiate(…)` method, whose
				// default-valued parameters are fields of the struct, as an initializer's are.
				let construction = if builtWithoutMock.isExtensionBased {
					"`\(InstantiableVisitor.instantiateMethodName)(…)` method"
				} else {
					"initializer"
				}
				let message = "Generated mocks build \(typeName) with its hand-written \(mockName) method for \(Self.describe(builtByMock)),"
					+ " and with its \(construction) for \(Self.describe(builtWithoutMock))."
					+ " The two take different parameters, but both properties are configured with one `\(concreteType.asSource).\(ScopeGenerator.mockConfigurationStructName)`."
					+ " Make \(mockName) return \(typeName), so that it builds both properties, or give \(mockName) exactly the parameters of \(typeName)’s \(construction), in the same order."
				return mockDeclarationLocations.map {
					SourceDiagnostic(severity: .error, location: $0, message: message)
				}
			}

			/// The property a node builds, the type that declares it, and the generated mock that builds it.
			private static func describe(_ builtNode: BuiltConstruction) -> String {
				"`\(builtNode.property.asSource)` on `\(builtNode.parent)` in `\(builtNode.mockRoot.asSource).\(InstantiableVisitor.mockMethodName)()`"
			}
		}

		/// A declaration whose access keeps the code SafeDI generates in one module from constructing a type: the type,
		/// a type that encloses it, the method that constructs it, or an extension one of those takes its level from.
		struct InaccessibleConstruction: Hashable {
			/// The type the generated code constructs.
			let constructedType: TypeDescription
			/// The name the declaring module gives `constructedType`, when this run spells it with the module's name because
			/// another module declares a type of that name (`Instantiable.declaredName`). Widening such a type can make the
			/// two compete in this module, so the error leads with a remedy that keeps it from this module, when there is one.
			let constructedTypeDeclaredName: TypeDescription?
			/// The declaration that must widen, with the level it has.
			let accessNeed: AccessNeed
			/// What the generated code needs of the declaration.
			let requirement: AccessRequirement
			/// The module the generated code compiles in.
			let emittingModule: ModuleIdentity
			/// The module that declares the declaration.
			let declaringModule: ModuleIdentity
			/// Where the declaration begins, when its file can be read where it is recorded, so an editor can open it.
			let readableDeclarationLocation: Dependency.DeclarationLocation?
			/// Where this module refers to what leads to the construction.
			let referenceLocation: Dependency.DeclarationLocation?
			/// Where the constructed type is declared.
			let constructedTypeDeclarationLocation: Dependency.DeclarationLocation?
			/// In a production tree, the type another module declares whose module could construct the declaration
			/// instead, were the type declared with `generateDependencyTree: true`, which the fix offers.
			var seamRemedy: SeamRemedy?
			/// In a production tree of a module SafeDI cannot name, the seam another module declares whose tree the module
			/// builds inline, which leads to the construction.
			var inlineSeam: InlineSeam?

			/// In a mock's tree, what the outermost type another module declares on the path to the construction offers
			/// (`Construction.publicMockCandidate`), which the fix says.
			var publicMockCandidate: PublicMockCandidate?
			/// The type whose mock makes the construction, with where it is declared, or `nil` for production code.
			var mockRoot: MockRoot?

			/// A type another module declares, and that module, which would build the type's tree, and construct the
			/// declaration there, were the type declared with `generateDependencyTree: true`: see
			/// `DependencyTreeGenerator.seamRemedy(offeredBy:toWiden:declaredIn:extendedTypes:)`.
			struct SeamRemedy: Hashable {
				let type: TypeDescription
				let moduleName: String
			}

			/// A seam another module declares that a production tree builds inline because SafeDI cannot name the module
			/// the tree is generated in – a run given no module name, as a target the Xcode project plugin builds is – so
			/// the tree cannot call the initializer generated for the seam, with where the module refers to what leads to
			/// the seam.
			struct InlineSeam: Hashable {
				let type: TypeDescription
				let referenceLocation: Dependency.DeclarationLocation?
			}

			/// The type whose mock makes a construction.
			struct MockRoot: Hashable {
				let type: TypeDescription
				let declarationLocation: Dependency.DeclarationLocation?
			}

			/// The diagnostics of `inaccessibleConstructions`, each in a group of its own: one error for each declaration to
			/// widen (`merging(_:)`), and one for each seam that the trees build inline (`InlineSeam`) where a construction in
			/// its tree is inaccessible, at the earliest reference to it in source order, which says why the tree is built
			/// inline and names the first declaration in source order in the seam's tree that keeps it from compiling, of
			/// a type other than the seam where there is one. Neither depends on the order of `inaccessibleConstructions`.
			static func sourceDiagnosticGroups(of inaccessibleConstructions: [InaccessibleConstruction]) -> [[SourceDiagnostic]] {
				var inlineSeamErrors = [TypeDescription: (referenceLocation: Dependency.DeclarationLocation?, namedConstruction: InaccessibleConstruction)]()
				for case let (inaccessibleConstruction, inlineSeam?) in inaccessibleConstructions.map({ ($0, $0.inlineSeam) }) {
					inlineSeamErrors[inlineSeam.type] = inlineSeamErrors[inlineSeam.type].map { error in
						(
							referenceLocation: Dependency.DeclarationLocation.precedesInSourceOrder(inlineSeam.referenceLocation, error.referenceLocation) ? inlineSeam.referenceLocation : error.referenceLocation,
							namedConstruction: inaccessibleConstruction.isNamedBefore(error.namedConstruction, inTreeOf: inlineSeam.type) ? inaccessibleConstruction : error.namedConstruction,
						)
					} ?? (referenceLocation: inlineSeam.referenceLocation, namedConstruction: inaccessibleConstruction)
				}
				return merging(inaccessibleConstructions).map { [$0.sourceDiagnostic] }
					+ inlineSeamErrors.map { seamType, error in
						[error.namedConstruction.inlineSeamDiagnostic(of: seamType, at: error.referenceLocation)]
					}
			}

			/// Whether an error about the seam `seamType`, built inline, names this construction rather than `other`: one of
			/// a type other than the seam before one of the seam itself, then the one whose declaration to widen comes first
			/// in source order, then the one whose constructed type is declared first. Two constructions that tie need one
			/// declaration to widen for one type, and the error reads the same whichever it names.
			private func isNamedBefore(_ other: InaccessibleConstruction, inTreeOf seamType: TypeDescription) -> Bool {
				// Whether the construction is of the seam, then where the declaration begins, then where the type is declared, each
				// in source order with a missing location first.
				let (isOfSeam, otherIsOfSeam) = (constructedType == seamType, other.constructedType == seamType)
				guard isOfSeam == otherIsOfSeam else { return otherIsOfSeam }
				let locationPairs = [
					(accessNeed.access.declarationStartLocation, other.accessNeed.access.declarationStartLocation),
					(constructedTypeDeclarationLocation, other.constructedTypeDeclarationLocation),
				]
				return locationPairs.first { $0.0 != $0.1 }.map { Dependency.DeclarationLocation.precedesInSourceOrderWithMissingFirst($0.0, $0.1) } ?? false
			}

			/// The error about the seam `seamType`, which a production tree builds inline because SafeDI cannot name the
			/// module the tree is generated in, at `referenceLocation`, where this module refers to what leads to the seam,
			/// naming the declaration this construction needs to widen and the level it has, in a sentence of its own, since
			/// the declaration's subject phrase can be an enclosing type's or an extension's. It leads with the remedy every
			/// such run can apply, widening the tree's declarations as the error at each declaration says, and then says how
			/// SafeDI comes to know the seam's module. Only a run that names no module reports this, which is one of the Xcode
			/// project plugin or a SafeDITool run by hand: the Swift package plugin's target graph, Bazel's required
			/// `module_name`, and the Tuist script's `--module-name` name every module. A run by hand needs only the seam's
			/// module named, since a run that names no module calls the initializer of a seam a module info file records. A
			/// single `error:` line, since Xcode drops notes from build-tool output.
			private func inlineSeamDiagnostic(
				of seamType: TypeDescription,
				at referenceLocation: Dependency.DeclarationLocation?,
			) -> SourceDiagnostic {
				let seamName = "`\(seamType.asSource)`"
				let reachedDeclaration = "\(declarationPhrases.subject) is `\(accessNeed.level.spelling)`, so that tree cannot be built here."
				return SourceDiagnostic(
					severity: .error,
					location: referenceLocation,
					message: "\(seamName) is declared with `generateDependencyTree: true`, but SafeDI does not know which module declares \(seamName), so this run builds \(seamName)’s tree inline. \(reachedDeclaration) Make the types in \(seamName)’s tree and their initializers `\(AccessLevel.package.spelling)`, \(DependencyTreeGenerator.DependencyTreeGeneratorError.unverifiedPackageAccessNeed), or `\(AccessLevel.public.spelling)` where their module and this one are in different packages. For this module to call the initializer SafeDI generates for \(seamName) instead, SafeDI must know \(seamName)’s module. \(DependencyTreeGenerator.DependencyTreeGeneratorError.xcodeProjectPluginCannotNameModules) In a SafeDITool run by hand, list the `.safedi` file of \(seamName)’s module, written with `--module-name` and `--module-info-output`, in the file you pass to `--dependent-module-info-file-path`.",
				)
			}

			/// `inaccessibleConstructions`, in no particular order, with those that need one declaration to widen the
			/// same way – the constructions of several roots' trees, or of several types the declaration encloses –
			/// merged into the one with the earliest reference in source order, or, of those with one reference, the one
			/// whose constructed type is declared first. An error at a reference therefore names the type that reference
			/// constructs, and neither which roots reach the declaration nor the order in which they are checked changes
			/// what is reported.
			static func merging(_ inaccessibleConstructions: [InaccessibleConstruction]) -> [InaccessibleConstruction] {
				var mergedByDeclaration = [MergeKey: InaccessibleConstruction]()
				for inaccessibleConstruction in inaccessibleConstructions {
					let key = MergeKey(
						access: inaccessibleConstruction.accessNeed.access,
						requirement: inaccessibleConstruction.requirement,
						declaringModule: inaccessibleConstruction.declaringModule,
					)
					mergedByDeclaration[key] = mergedByDeclaration[key].map { $0.merged(with: inaccessibleConstruction) } ?? inaccessibleConstruction
				}
				return Array(mergedByDeclaration.values)
			}

			/// What identifies the declaration an inaccessible construction needs to widen, and how. The access
			/// declaration records where the declaration begins, which no other declaration shares.
			private struct MergeKey: Hashable {
				let access: AccessDeclaration
				let requirement: AccessRequirement
				let declaringModule: ModuleIdentity
			}

			/// Of this construction and `other`, which needs the same declaration to widen the same way, the one an error
			/// about the declaration reports. Two constructions whose types are declared at one location construct one
			/// type and report the same error. The error offers a seam only when both offer the same one: declaring one
			/// type a seam must keep every construction it reports out of this module.
			private func merged(with other: InaccessibleConstruction) -> InaccessibleConstruction {
				let otherIsReportedFirst = if other.referenceLocation == referenceLocation {
					if other.constructedTypeDeclarationLocation == constructedTypeDeclarationLocation {
						// The trees of two mock roots reach the construction through one reference: the error names the mock
						// declared first.
						Dependency.DeclarationLocation.precedesInSourceOrder(other.mockRoot?.declarationLocation, mockRoot?.declarationLocation)
					} else {
						Dependency.DeclarationLocation.precedesInSourceOrder(other.constructedTypeDeclarationLocation, constructedTypeDeclarationLocation)
					}
				} else {
					Dependency.DeclarationLocation.precedesInSourceOrder(other.referenceLocation, referenceLocation)
				}
				var merged = otherIsReportedFirst ? other : self
				merged.seamRemedy = seamRemedy == other.seamRemedy ? seamRemedy : nil
				return merged
			}

			/// How an error names the declaration that must widen (`subject`), says what the generated code cannot do
			/// without it (`inability`), and names it in the fix (`fixedDeclaration`).
			private var declarationPhrases: (subject: String, inability: String, fixedDeclaration: String) {
				let constructedTypeName = "`\(constructedType.asSource)`"
				func name(of member: AccessNeed.Member) -> String {
					switch member {
					case .initializer:
						"\(constructedTypeName)’s initializer"
					case .instantiateMethod:
						"`\(constructedType.asSource).\(InstantiableVisitor.instantiateMethodName)()`"
					case let .mockMethod(name):
						"`\(constructedType.asSource).\(name)()`"
					}
				}
				let subject: String
				let inability: String
				let fixedDeclaration: String
				switch accessNeed.declaration {
				case let .type(type):
					if type == constructedType || type == constructedTypeDeclaredName {
						subject = constructedTypeName
						inability = "construct it"
						fixedDeclaration = constructedTypeName
					} else {
						subject = "`\(type.asSource)`, which encloses \(constructedTypeName),"
						inability = "construct \(constructedTypeName)"
						fixedDeclaration = "`\(type.asSource)`"
					}
				case let .extensionDeclaringType(type):
					subject = type == constructedType
						? "The extension that declares \(constructedTypeName)"
						: "The extension that declares `\(type.asSource)`, which encloses \(constructedTypeName),"
					inability = "construct \(constructedTypeName)"
					fixedDeclaration = "the extension"
				case let .extensionDeclaringMember(member):
					subject = "The extension that declares \(name(of: member))"
					inability = "call \(name(of: member))"
					fixedDeclaration = "the extension"
				case let .member(member):
					subject = name(of: member)
					inability = "call it"
					fixedDeclaration = member == .initializer ? "the initializer" : name(of: member)
				}
				return (subject, inability, fixedDeclaration)
			}

			/// A single `error:` line, since Xcode drops notes from build-tool output. When the declaration's file can
			/// be read, it is reported there, with a fix-it that gives the declaration the level the generated code
			/// needs. Otherwise – in a build that hands SafeDITool another module's declarations but not its files,
			/// such as a sandboxed Bazel action, or a `.safedi` file from another machine – it is reported where this
			/// module refers to the construction, and names the module that must change.
			var sourceDiagnostic: SourceDiagnostic {
				let (subject, inability, fixedDeclaration) = declarationPhrases
				let module = emittingModule.moduleName.map { "module `\($0)`" } ?? "this module"
				// A mock's construction names the mock, whose tree the user did not write.
				let emitter = mockRoot.map { "the mock of `\($0.type.asSource)`, generated in \(module)," } ?? "\(module),"
				let reason = switch requirement {
				case .internal:
					if let mockRoot {
						"the mock of `\(mockRoot.type.asSource)`, which SafeDI generates in another file of \(module), cannot \(inability)"
					} else {
						"the code SafeDI generates in another file of \(module) cannot \(inability)"
					}
				case .package:
					"\(emitter) another module of the same package, cannot \(inability) in the code SafeDI generates"
				case .public:
					// Across a named module SafeDI is told no package of, SafeDI cannot say the two are in different packages.
					if ModuleIdentity.namesOfModulesWithoutPackage(emitter: emittingModule, declarer: declaringModule).isEmpty {
						"\(emitter) in another package, cannot \(inability) in the code SafeDI generates"
					} else {
						"\(emitter) which SafeDI is not told is in the same package, cannot \(inability) in the code SafeDI generates"
					}
				case .packageUnverified:
					"\(emitter) which SafeDI cannot tell is in the same package, cannot \(inability) in the code SafeDI generates"
				}
				let level = AccessLevel.spelling(satisfying: requirement)
				// Reported in this module, the error names the module whose declaration must change.
				let declaringModuleName = readableDeclarationLocation == nil ? declaringModule.moduleName.map { " in module `\($0)`" } ?? "" : ""
				// A type another module declares could have that module build its tree, which reaches the declaration.
				let seamRemedyClause = seamRemedy.map { "declare `\($0.type.asSource)` with `generateDependencyTree: true`, so that module `\($0.moduleName)` generates its tree and this module calls the initializer it generates" }
				let seamRemedyText = seamRemedyClause.map { ", or \($0)" } ?? ""
				// A mock could call a public mock of the type another module declares instead of building its tree.
				let publicMockRemedyClause: String? = if case let .withoutMock(type, declaringModuleName, needsPublicDeclaration, isSeam)? = publicMockCandidate {
					(needsPublicDeclaration
						? "declare `\(type.asSource)` `public` with `generateMock: .public`"
						: "give `\(type.asSource)` a public mock: `generateMock: .public`, or a hand-written public `mock`")
						// A seam's tree is one a mock builds inline, which the user may not expect.
						+ (isSeam ? ": mocks build the tree of a type with `generateDependencyTree: true` inline, and this mock would call the mock \(declaringModuleName.map { "`\($0)`" } ?? "its module") generates instead" : "")
				} else {
					nil
				}
				let publicMockRemedy = publicMockRemedyClause.map { ", or \($0)" } ?? ""
				// Widening one of several types of a name lets the module name it, and widening a second makes them
				// compete, so the remedy that keeps the type out of this module comes first, and no fix-it widens it.
				if let constructedTypeDeclaredName, let leadingRemedy = publicMockRemedyClause ?? seamRemedyClause {
					return SourceDiagnostic(
						severity: .error,
						location: readableDeclarationLocation ?? referenceLocation,
						message: "\(subject) is `\(accessNeed.level.spelling)`\(declaringModuleName), so \(reason). \(leadingRemedy.prefix(1).uppercased())\(leadingRemedy.dropFirst()). Making \(fixedDeclaration) `\(level)` instead also needs a new name, if \(module) can then name another type called `\(constructedTypeDeclaredName.asSource)`.",
					)
				}
				let fix = switch requirement {
				case .internal, .package:
					"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix\(seamRemedyText)\(publicMockRemedy)."
				case .public:
					// Across a named module SafeDI is told no package of, a `package` declaration needs `public` unless the
					// module belongs in the other's package, which the declaration's level makes the likelier fix. A
					// narrower declaration needs widening either way, so `public`, which its fix-it inserts, comes first.
					if let packageNameRemedy = ModuleIdentity.packageNameRemedy(emitter: emittingModule, declarer: declaringModule, declaredLevel: accessNeed.level) {
						"\(packageNameRemedy.prefix(1).uppercased())\(packageNameRemedy.dropFirst()), or make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix\(seamRemedyText)\(publicMockRemedy)."
					} else if let packageNameAndAccessRemedy = ModuleIdentity.packageNameAndAccessRemedy(emitter: emittingModule, declarer: declaringModule, declaredLevel: accessNeed.level), seamRemedyClause == nil, publicMockRemedyClause == nil {
						"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix, or, \(packageNameAndAccessRemedy)."
					} else if let packageNameAndAccessRemedy = ModuleIdentity.packageNameAndAccessRemedy(emitter: emittingModule, declarer: declaringModule, declaredLevel: accessNeed.level) {
						// A remedy after the package-name remedy would read as part of its "if" clause, so three or more
						// remedies are joined with semicolons.
						SeamAccessExplanation.joined(["make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix", packageNameAndAccessRemedy] + [seamRemedyClause, publicMockRemedyClause].compactMap(\.self))
					} else {
						"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix\(seamRemedyText)\(publicMockRemedy)."
					}
				case .packageUnverified:
					"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix, \(DependencyTreeGeneratorError.unverifiedPackageAccessNeed), or `\(AccessLevel.public.spelling)` if the two modules are in different packages\(seamRemedyText)\(publicMockRemedy)."
				}
				let message: String
				// Only a mock's construction has a `.publicMockOfUnknownModule` candidate, and it is explained with its mock root.
				if case let .publicMockOfUnknownModule(type, emittingModuleIsUnknown)? = publicMockCandidate, let mockRoot {
					// `publicMockNotCallableFromThisView`: the type's public mock is the fix, which SafeDI cannot call here.
					let typeName = "`\(type.asSource)`"
					let mockReason = "the mock of `\(mockRoot.type.asSource)`, which builds \(typeName)’s tree here, cannot \(inability): \(typeName) has a public `mock()`, but SafeDI does not know which module declares \(typeName), so this run cannot call it"
					// Whether a mock can call the public mock depends on the declaring module's name alone: a run that names no
					// module calls the public mock of a module whose module info names it, and naming this run would not name
					// the declaring module. A Swift package target's run reads that name from the target graph. A run that
					// names its module reaches such a type only through a directory a `#SafeDIConfiguration` adds, or a file
					// no target of the plugin's graph lists, since every module info names its module.
					if emittingModuleIsUnknown {
						// Widening works as for any construction, so that remedy and its fix-it come first.
						message = "\(subject) is `\(accessNeed.level.spelling)`\(declaringModuleName), so \(mockReason). \(fix) To call `\(type.asSource).mock()` instead, build these mocks in a Swift package target, or, in a SafeDITool run by hand, list the `.safedi` file of \(typeName)’s module, written with `--module-name` and `--module-info-output`, in the file you pass to `--dependent-module-info-file-path`."
					} else {
						let access = "\(subject.hasPrefix("The ") ? "the " + subject.dropFirst(4) : subject) is `\(accessNeed.level.spelling)`"
						return SourceDiagnostic(
							severity: .error,
							location: readableDeclarationLocation ?? referenceLocation,
							message: "\(typeName) has a public `mock()`, but SafeDI does not know which module declares \(typeName), so this run cannot call it, and \(access): it is declared in a directory a `#SafeDIConfiguration` adds, or in a file no target of the plugin’s graph lists. Declare it in a file of a module SafeDI knows.",
						)
					}
				} else {
					message = "\(subject) is `\(accessNeed.level.spelling)`\(declaringModuleName), so \(reason). \(fix)"
				}

				if let readableDeclarationLocation {
					// A modifier is replaced, and one is inserted where the declaration begins when it spells none.
					let fixIt = accessNeed.access.modifierRange.map { SourceDiagnostic.FixIt(range: $0, replacement: level) }
						?? SourceDiagnostic.FixIt(range: .insertionPoint(at: readableDeclarationLocation), replacement: "\(level) ")
					return SourceDiagnostic(severity: .error, location: readableDeclarationLocation, message: message, fixIts: [fixIt])
				} else {
					return SourceDiagnostic(severity: .error, location: referenceLocation, message: message)
				}
			}
		}

		/// A receive a diagnostic notes: the type that declares it, the property it receives, and where.
		private struct NotedReceive: Hashable {
			let declaringType: TypeDescription
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A value a call of a seam's generated initializer would drop (`ScopeGenerator.SeamTierOmission`), as reported.
		struct ProvidedValueOmission {
			let omission: ScopeGenerator.SeamTierOmission
			/// The type at the root of the tree that makes the call.
			let callingType: TypeDescription
			/// Where the error is reported: the provider's declaration, or, when its file cannot be read, where the
			/// module refers to what leads to the call.
			let location: Dependency.DeclarationLocation?
			/// The module that declares the provider, when the provider's file cannot be read and that module is known.
			let unreadableProviderModuleName: String?
		}

		/// A call of the initializer SafeDI generated for a seam of another module, whose signature this run computed
		/// from that module's files as it parsed them, under its own mock condition, while the module computed it under
		/// another: a mock method in a block that only one of the conditions selects can prove a parameter's type, so
		/// the two signatures can differ. Reported at the dependency that calls the seam.
		struct SeamModuleMockConditionDifference {
			let seam: TypeDescription
			let seamModule: ModuleIdentity
			let seamModuleMockCondition: MockCondition
			let callingModule: ModuleIdentity
			let callingModuleMockCondition: MockCondition
			/// The first dependency, in source order, that instantiates the seam in a tree this module generates.
			let callingDependencyLocation: Dependency.DeclarationLocation?

			var sourceDiagnostic: SourceDiagnostic {
				func name(of module: ModuleIdentity) -> String {
					module.moduleName.map { "`\($0)`" } ?? "this module"
				}
				func spelling(of mockCondition: MockCondition) -> String {
					mockCondition.conditionalCompilation.map { "`\($0)`" } ?? "no condition"
				}
				let seamModuleName = name(of: seamModule)
				let callingModuleName = name(of: callingModule)
				return SourceDiagnostic(
					severity: .error,
					location: callingDependencyLocation,
					message: "\(callingModuleName) calls the initializer SafeDI generated for `\(seam.asSource)` in module \(seamModuleName), whose signature SafeDI computes from \(seamModuleName)’s declarations as \(seamModuleName) reads them, mock-only declarations under \(seamModuleName)’s mock condition included. \(seamModuleName) guards its mocks with \(spelling(of: seamModuleMockCondition)) and \(callingModuleName) with \(spelling(of: callingModuleMockCondition)), so \(callingModuleName) cannot read them as \(seamModuleName) does. Use the same `mockConditionalCompilation` in both modules.",
				)
			}
		}

		/// An own root or seam whose generated initializer states no isolation, and the first seam of another module it
		/// builds whose initializers that module generated main-actor, as its `defaultIsolation` declares.
		struct SeamCalledWithoutIsolation {
			let callingType: TypeDescription
			let callingDeclarationLocation: Dependency.DeclarationLocation?
			let seam: TypeDescription
			let seamModule: ModuleIdentity

			var sourceDiagnostic: SourceDiagnostic {
				let seamModuleName = seamModule.moduleName.map { "`\($0)`" } ?? "another module"
				return SourceDiagnostic(
					severity: .error,
					location: callingDeclarationLocation,
					message: "The initializer SafeDI generates for `\(callingType.asSource)` calls the initializer module \(seamModuleName) generates for `\(seam.asSource)`, which is `@MainActor` because \(seamModuleName) declares `defaultIsolation: MainActor.self` in its `#\(SafeDIConfigurationVisitor.macroName)`, but the initializer SafeDI generates for `\(callingType.asSource)` states no isolation. Declare `defaultIsolation: MainActor.self` in this module’s `#\(SafeDIConfigurationVisitor.macroName)`, or write `generatedAttributes: \"@MainActor\"` on `\(callingType.asSource)`.",
				)
			}
		}

		/// A seam whose generated initializer SafeDI cannot write, reported at the seam's declaration with a note at
		/// each receive involved.
		struct SeamError {
			/// A receive in the seam's tree, as the seam's signature sees it.
			struct Receiver: Hashable {
				/// The property the receive takes from outside the seam: the received property, or an alias's
				/// fulfilling property.
				let property: Property
				/// The type that declares the receive.
				let declaringType: TypeDescription
				let declarationLocation: Dependency.DeclarationLocation?
				/// The alias's own property when the receive is an alias's fulfilling property, else `nil`.
				let aliasProperty: Property?
				/// Whether the receive is a parameter of an extension's `instantiate(…)` method, which has no
				/// only-if-available form.
				let isInstantiateMethodParameter: Bool

				var asExplanationReceiver: SeamAccessExplanation.Receiver {
					SeamAccessExplanation.Receiver(declaringType: declaringType, aliasProperty: aliasProperty, isInstantiateMethodParameter: isInstantiateMethodParameter)
				}
			}

			/// Which of the seam's own properties an omitted parameter is, or `none` for a pass-through.
			enum OwnParameter: Equatable {
				case none
				case forwarded
				case required
			}

			/// What a label collision's message says to do.
			enum LabelCollisionRemedy: Equatable {
				/// The forms are of different types (`User` beside `Name`, or beside `Instantiator<User>`, which no form
				/// of `User` provides): rename one, or instantiate one inside the tree.
				case rename
				/// The forms name two wrapper kinds: receive one kind everywhere.
				case receiveOneWrapperKind
				/// Receive the label the same way everywhere; no form the inlined validation accepts provides the others
				/// (a required optional by-value receive beside a wrapper: the wrapper's instance is non-optional).
				case receiveTheSameWay
				/// Receive the label the same way everywhere, or declare the form that provides the others on the seam,
				/// spelled as a receiver spells it: the wrapper of the one kind received, else the by-value property.
				case declareProvidingForm(String)
				/// Receive the label the same way everywhere, or declare on the seam the by-value form a type of its tree
				/// requires: the providing form would be a wrapper only the seam itself receives, which no declaration the
				/// seam's module sees outside the seam provides, so nothing proves a caller holds it.
				case declareRequiredForm(String)
			}

			/// Why the seam's generated initializer cannot take the parameters its tree needs. Each case names the
			/// parameters involved, which `parameterLabels(namedBy:about:)` reads; no other kind names one.
			enum ParameterKind {
				/// Two receives of one label with different types, which the seam's generated initializer cannot both
				/// take as parameters: it passes each dependency to its receivers by label, as a root's does.
				case parametersShareLabel(label: String, receivers: [Receiver], remedy: LabelCollisionRemedy)
				/// A tier of the generated initializer is wider than the access SafeDI can prove for a required
				/// parameter's type (`TypeAccessProof`), so it cannot take the parameter, and cannot leave it out either:
				/// a pass-through some receiver requires, or the seam's own required `@Received` or `@Forwarded`
				/// property. `tier` is the widest tier, at the seam type's access; `parameterLevel` is the parameter's own
				/// tier access, and `cause` how its narrowest type is proven.
				case tierOmitsRequiredParameter(parameter: Property, tier: AccessLevel, parameterLevel: AccessLevel, receivers: [Receiver], ownParameter: OwnParameter, cause: TypeAccessProof.Cause?)
				/// The seam declares an initializer that can be called with the argument labels of a tier of the generated
				/// initializer, whose parameters are `parameters`: a call with those labels resolves to the hand-written
				/// initializer or is ambiguous, whatever the types. The macro cannot report it: it cannot see the
				/// pass-throughs.
				case initializerCollides(parameters: [SeamSignature.Parameter], builderLabels: [String], handWrittenInitializer: Initializer)
			}

			enum Kind {
				/// The seam's generated initializer cannot take the parameters its tree needs, for the reason given.
				case parameters(ParameterKind)
				/// The signatures of `seams`, which reach one another, changed on every pass up to the limit
				/// (`seamSignatureComputationLimit(forComponentOf:)`), which the argument in `seamSignatures` says no
				/// input reaches: a guard against a shape the argument misses, which is then reported rather than
				/// computed with a stale signature.
				case signaturesDidNotSettle(seams: [TypeDescription])
				/// The seam's signature, computed over the declarations the modules that call it see, differs from the one
				/// computed over what this run sees, and `declaration` is one the callers cannot see: the build system's
				/// target graph attributes it to no module, since it is in a directory this module's configuration adds.
				case treeReachesDeclarationCallersCannotSee(declaration: TypeDescription)
				/// As `treeReachesDeclarationCallersCannotSee`, where what the callers cannot see is the plain declaration
				/// (`PlainTypeDeclaration`) that proves the type of a parameter they would take otherwise: without it, they
				/// count the type as one SafeDI reads no declaration of, which is `public`. Reported at the declaration.
				case treeReachesPlainDeclarationCallersCannotSee(declaration: PlainTypeDeclaration)
				/// A tier of the generated initializer is wider than `hole`'s builder, which every tier takes, as far as the
				/// proof of the builder's type (`Hole.accessCause`) goes. Not a `ParameterKind`: a builder is no member of
				/// `SeamSignature.parameters`, whose labels are what `parameterLabels(namedBy:about:)` names.
				case tierOmitsBuilder(hole: SeamSignature.Hole, builder: SeamSignature.Builder, tier: AccessLevel)
				/// A builder narrower than a tier only because of an inner seam whose enum it holds.
				case tierOmitsBuilderHoldingInnerSeam(builder: SeamSignature.Builder, innerSeam: TypeDescription, tier: AccessLevel)
				/// `place` and `reference`, places of one builder, forward different values, so no one builder a person writes
				/// can fill both: the builder takes what its places forward. A plugin check, since two spellings of one type
				/// are not decidable from one declaration. Reported at `place`'s `forwardingLocation`.
				case placesForwardOtherValues(place: SeamSignature.Hole, reference: SeamSignature.Hole, isSendable: Bool)
			}

			let seam: Instantiable
			let kind: Kind

			/// `` `label: Type` on `Owner` forwards `Value` ``, or `forwards nothing`, for a place of a builder.
			private static func forwardedValueClause(of place: SeamSignature.Hole) -> String {
				let forwarded = place.forwardedType.map { "forwards `\($0.strippingEscaping.asSource)`" } ?? "forwards nothing"
				return "`\(place.property.asSource)` on `\(place.ownerType.asSource)` \(forwarded)"
			}

			/// How to make `place` forward what `reference` forwards, by the kinds of the two: an erased instantiator that
			/// forwards a written type beside a plain or lazy place takes `()`, beside an `Instantiator<T>` takes
			/// `T.ForwardedProperties`, and two erased instantiators take one first generic argument; any of them can name
			/// another type in its `fulfilledByType`, which gives it a builder of its own.
			private static func forwardedValueRemedy(of place: SeamSignature.Hole, beside reference: SeamSignature.Hole) -> String {
				let (erasedPlace, otherPlace) = place.property.propertyType.isErasedInstantiator && place.forwardedType != nil ? (place, reference) : (reference, place)
				switch otherPlace.property.propertyType {
				case .constant, .lazilyInstantiated, .sendableLazilyInstantiated:
					return "Declare `\(erasedPlace.property.label)`’s first generic argument `()`, or name another type in its `fulfilledByType`."
				case .instantiator, .sendableInstantiator:
					let forwardedProperties = TypeDescription.nested(name: Dependency.forwardedPropertiesType, parentType: otherPlace.builtType, generics: [])
					let wrapperName = erasedPlace.property.propertyType.isSendable ? Dependency.sendableErasedInstantiatorType : Dependency.erasedInstantiatorType
					let declaredType = TypeDescription.simple(name: wrapperName, generics: [forwardedProperties, erasedPlace.builtType])
					return "Declare `\(erasedPlace.property.label)` as `\(declaredType.asSource)`, or name another type in its `fulfilledByType`."
				case .erasedInstantiator, .sendableErasedInstantiator:
					return "Give both the same first generic argument, or name another type in the `fulfilledByType` of one."
				}
			}

			/// What requires `tier`, the tier an omission is reported at: the seam's access, in a clause of the error's first
			/// sentence, or its `generateMock: .public`, which no narrower seam removes, in a sentence of its own.
			private func tierRequirement(_ tier: AccessLevel) -> (isRequiredByPublicMock: Bool, requiredByClause: String, publicMockSentence: String) {
				if seam.generateMock == .public, tier == .public {
					(true, "", " " + SeamAccessExplanation.publicMockRequirementSentence(seam: seam.concreteInstantiable))
				} else {
					(false, ", which `\(seam.concreteInstantiable.asSource)`’s `\(tier.spelledOnGeneratedDeclaration)` access requires,", "")
				}
			}

			var sourceDiagnostics: [SourceDiagnostic] {
				let seamName = "`\(seam.concreteInstantiable.asSource)`"
				let message: String
				let receivers: [Receiver]
				var location = seam.declarationLocation
				// The plain declarations that keep a parameter's type narrower than its tier, each with a fix-it.
				var declarationNotes = [SourceDiagnostic]()
				switch kind {
				case let .parameters(.parametersShareLabel(label, labelReceivers, remedy)):
					receivers = labelReceivers
					message = Self.labelCollisionMessage(seamName: seamName, label: label, receivers: labelReceivers, remedy: remedy)
				case let .parameters(.tierOmitsRequiredParameter(parameter, tier, parameterLevel, parameterReceivers, ownParameter, cause)):
					receivers = parameterReceivers
					let treeReceivers = parameterReceivers.filter { $0.declaringType != seam.concreteInstantiable }
					// Who takes the parameter: the seam's own initializer, the seam itself, or the receivers in its tree.
					let receiverNames = treeReceivers.map { receiver in
						receiver.isInstantiateMethodParameter
							? "`\(receiver.declaringType.asSource)`’s `instantiate(…)`"
							: "`\(receiver.declaringType.asSource)`"
					}.uniqued()
					let takers: String = switch ownParameter {
					case .forwarded:
						"\(seamName)’s own initializer takes"
					case .required:
						receiverNames.isEmpty ? "\(seamName) receives" : "\(([seamName] + receiverNames).joinedAsList) receive"
					case .none:
						// A pass-through the seam's own alias receives names the seam; one only the seam's own aliases
						// receive, the seam too.
						if let receiver = parameterReceivers.first, parameterReceivers.count == 1, let aliasProperty = receiver.aliasProperty {
							"`\(receiver.declaringType.asSource)` receives through its alias `\(aliasProperty.label)` (`fulfilledByDependencyNamed: \"\(parameter.label)\"`)"
						} else {
							receiverNames.count > 1 ? "\(receiverNames.joinedAsList) receive" : "\(receiverNames.first ?? seamName) receives"
						}
					}
					let parameterKind: SeamAccessExplanation.ParameterKind = switch ownParameter {
					case .none:
						.passThrough
					case .forwarded:
						.ownForwarded
					case .required:
						.ownReceived
					}
					let (isRequiredByPublicMock, requiredBy, publicMockRequirement) = tierRequirement(tier)
					let causeText = cause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: treeReceivers.map(\.asExplanationReceiver)) } ?? ""
					let remedies = SeamAccessExplanation.tierRemedies(
						cause: cause,
						neededLevel: tier,
						parameterLevel: parameterLevel,
						seam: seam.concreteInstantiable,
						parameter: parameter,
						receivers: treeReceivers.map(\.asExplanationReceiver),
						parameterKind: parameterKind,
						seamAccessIsRequiredByPublicMock: isRequiredByPublicMock,
					)
					message = "SafeDI cannot generate the dependency tree of \(seamName): its generated `\(tier.spelledOnGeneratedDeclaration)` initializer\(requiredBy) cannot take `\(parameter.asSource)`, which \(takers), and cannot pass `nil` for it, since it is required.\(publicMockRequirement)\(causeText) \(remedies)"
					declarationNotes = SeamAccessExplanation.declarationNotes(for: cause, neededLevel: tier)
				case let .signaturesDidNotSettle(seams):
					receivers = []
					message = "SafeDI cannot generate the dependency tree of \(seamName): the generated initializers of \(seams.map { "`\($0.asSource)`" }.joined(separator: ", ")), which reach one another, took a parameter from one another on every pass up to the limit. This is a defect in SafeDI; report it with these types’ declarations."
				case let .treeReachesDeclarationCallersCannotSee(declaration):
					receivers = []
					message = "SafeDI cannot generate the dependency tree of \(seamName): the initializer SafeDI generates for it depends on `\(declaration.asSource)`, which is declared in a directory this module’s `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `\(declaration.asSource)` in a file of this module, or of a module it depends on."
				case let .treeReachesPlainDeclarationCallersCannotSee(declaration):
					receivers = []
					location = declaration.access.declarationStartLocation ?? location
					let typeName = "`\(declaration.typeDescription.asSource)`"
					message = "SafeDI cannot generate the dependency tree of \(seamName): the initializer SafeDI generates for it takes its parameters at the access this declaration of \(typeName) proves, which is in a directory this module’s `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see it, so they would count \(typeName) as `public`, and their calls would not match the initializer. Declare \(typeName) in a file of this module, or of a module it depends on."
				case let .tierOmitsBuilderHoldingInnerSeam(builder, innerSeam, tier):
					receivers = []
					let (_, requiredBy, publicMockRequirement) = tierRequirement(tier)
					let causeText = builder.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: []) } ?? ""
					message = "SafeDI cannot generate the dependency tree of \(seamName): its generated `\(tier.spelledOnGeneratedDeclaration)` initializer\(requiredBy) cannot take `\(builder.label(inTierAt: tier)): \(builder.readableParameterType.asSource)`, whose builder struct holds the builders of `\(innerSeam.asSource)`, a seam visible only at `\(builder.tierAccess.spelledOnGeneratedDeclaration)` access.\(publicMockRequirement)\(causeText) Declare \(seamName) at `\(builder.tierAccess.spelledOnGeneratedDeclaration)` access, or make `\(innerSeam.asSource)` `\(tier.spelledOnGeneratedDeclaration)`."
				case let .tierOmitsBuilder(hole, builder, tier):
					// Explained as a required parameter's omission is, by the shared formatter, with the builder's remedy in
					// the place of a pass-through's.
					receivers = []
					let module = seam.moduleName.map { "module `\($0)`" } ?? "this module"
					let (isRequiredByPublicMock, requiredBy, publicMockRequirement) = tierRequirement(tier)
					let causeText = hole.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: []) } ?? ""
					let remedies = SeamAccessExplanation.tierRemedies(
						cause: hole.accessCause,
						neededLevel: tier,
						parameterLevel: hole.tierAccess,
						seam: seam.concreteInstantiable,
						parameter: Property(label: builder.label(inTierAt: tier), typeDescription: builder.readableParameterType),
						receivers: [],
						parameterKind: .builder(fulfilledType: hole.instantiatedType, seamModuleName: seam.moduleName, isPassedUp: hole.innerSeamType != nil),
						seamAccessIsRequiredByPublicMock: isRequiredByPublicMock,
					)
					message = "SafeDI cannot generate the dependency tree of \(seamName): its generated `\(tier.spelledOnGeneratedDeclaration)` initializer\(requiredBy) cannot take `\(builder.label(inTierAt: tier)): \(builder.readableParameterType.asSource)`, the builder for `\(hole.ownerType.asSource)`’s `\(hole.property.asSource)`, which no @Instantiable declaration that \(module) can see fulfills.\(publicMockRequirement)\(causeText) \(remedies)"
					declarationNotes = SeamAccessExplanation.declarationNotes(for: hole.accessCause, neededLevel: tier)
				case let .placesForwardOtherValues(place, reference, isSendable):
					receivers = []
					location = place.forwardingLocation ?? location
					message = "\(Self.forwardedValueClause(of: place)), and \(Self.forwardedValueClause(of: reference)). \(seamName) takes one \(isSendable ? "`@Sendable` " : "")builder for both, since `\(place.instantiatedType.asSource)` fills each and each returns `\(place.builtType.asSource)`, and a builder’s places must forward the same values. \(Self.forwardedValueRemedy(of: place, beside: reference))"
				case let .parameters(.initializerCollides(parameters, builderLabels, handWrittenInitializer)):
					receivers = []
					let handWrittenSignature = "init(\(handWrittenInitializer.arguments.map { "\($0.label):" }.joined()))"
					let generatedLabels = parameters.map(\.property.label) + builderLabels
					let generatedSignature = "init(\(generatedLabels.map { "\($0):" }.joined()))"
					// Reported at the hand-written initializer, which the remedy calls "this initializer".
					location = handWrittenInitializer.access.declarationStartLocation ?? location
					// A tier that takes no argument is `init()` whatever the module sets, so only the hand-written initializer
					// can give way; a labelled tier collides only where the module generates the plain initializer.
					let remedy = if generatedLabels.isEmpty {
						"Remove this initializer, or give it a parameter that has no default value, so that `\(seam.concreteInstantiable.asSource)()` can mean only the generated initializer."
					} else {
						"Rename this initializer’s argument labels; remove it; or, while code you write still calls it, remove `\(SafeDIConfigurationVisitor.generatePlainDependencyTreeInitializersArgumentLabel): true` from this module’s `#\(SafeDIConfigurationVisitor.macroName)`."
					}
					message = "SafeDI cannot generate the dependency tree of \(seamName): it declares `\(handWrittenSignature)`, which can be called with the argument labels of its generated initializer, `\(generatedSignature)`. Because the labels match, a call meant for one initializer can run the other instead, or the code can fail to compile. \(remedy)"
				}
				// The notes follow the receivers in the order the tree declares them, which no name decides.
				return [SourceDiagnostic(severity: .error, location: location, message: message)]
					+ declarationNotes
					+ Self.receiverNotes(receivers)
			}

			/// The message of `parametersShareLabel`, which a caller also reports for a fill whose tree receives a parameter of
			/// the seam in a form no one parameter takes together with the parameter's: the seam's tree, as the caller fills it,
			/// receives `label` as `receivers` do.
			static func labelCollisionMessage(seamName: String, label: String, receivers: [Receiver], remedy: LabelCollisionRemedy) -> String {
				"SafeDI cannot generate the dependency tree of \(seamName): its tree receives `\(label)` as \(receivedForms(of: receivers)), and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. \(labelCollisionRemedyText(seamName: seamName, label: label, remedy: remedy))"
			}

			/// The forms `receivers` receive a label in, each with its type, as a sentence lists them.
			static func receivedForms(of receivers: [Receiver]) -> String {
				receivers.map { "`\($0.property.asSource)` on `\($0.declaringType.asSource)`" }.joined(separator: " and ")
			}

			/// The remedy `remedy` names for a tree of `seamName` that receives `label` in two forms.
			static func labelCollisionRemedyText(seamName: String, label: String, remedy: LabelCollisionRemedy) -> String {
				switch remedy {
				case .rename:
					"Rename one of the properties, or @\(Dependency.Source.instantiatedRawValue) one of them inside the tree."
				case .receiveOneWrapperKind:
					"Receive `\(label)` as one wrapper kind in every type of the tree."
				case .receiveTheSameWay:
					"Receive `\(label)` the same way in every type of the tree."
				case let .declareProvidingForm(providingForm):
					"Receive `\(label)` the same way in every type of the tree, or declare it on \(seamName) as the form that provides the others: `@\(Dependency.Source.receivedRawValue) let \(label): \(providingForm)`."
				case let .declareRequiredForm(requiredForm):
					"Receive `\(label)` the same way in every type of the tree, or declare it on \(seamName) as the form its tree requires: `@\(Dependency.Source.receivedRawValue) let \(label): \(requiredForm)`."
				}
			}

			/// A note at each of `receivers`, in their order.
			static func receiverNotes(_ receivers: [Receiver]) -> [SourceDiagnostic] {
				receivers.map { receiver in
					SourceDiagnostic(
						severity: .note,
						location: receiver.declarationLocation,
						message: "`\(receiver.declaringType.asSource)` receives `\(receiver.property.asSource)` here.",
					)
				}
			}
		}

		/// A constant or lazily instantiated `@Instantiated` dependency whose type has `@Forwarded` properties, which
		/// only an instantiator is passed.
		struct ForwardedPropertyViolation {
			let dependency: Dependency
			/// The type the dependency builds.
			let instantiable: Instantiable
			/// The type with which the dependency can instead build `instantiable`.
			let suggestedPropertyType: TypeDescription
			/// The `Sendable` form of `suggestedPropertyType`, which the advice names besides it when the declaration of
			/// `parent` does not say whether `parent` is `Sendable`, or `nil` when it does.
			let sendableAlternative: TypeDescription?
			let forwardedDeclarations: [LocatedProperty]
			/// The type that declares the dependency.
			let parent: TypeDescription

			/// An `error:` line at the dependency, and a `note:` at each `@Forwarded` declaration.
			var sourceDiagnostics: [SourceDiagnostic] {
				[
					SourceDiagnostic(
						severity: .error,
						location: dependency.declarationLocation,
						message: "`\(dependency.property.asSource)` on `\(parent.asSource)` cannot build `\(instantiable.concreteInstantiable.asSource)`, which has @\(Dependency.Source.forwardedRawValue) properties that only an instantiator is passed. Declare it as `\(suggestedPropertyType.asSource)`\(sendableAlternative.map { ", or as `\($0.asSource)` if `\(parent.asSource)` is Sendable" } ?? "").",
					),
				] + forwardedDeclarations.map {
					SourceDiagnostic(
						severity: .note,
						location: $0.declarationLocation,
						message: "@\(Dependency.Source.forwardedRawValue) property `\($0.property.asSource)` is declared here",
					)
				}
			}
		}

		/// A dependency of a declaration whose label `String` equates with an earlier dependency's label, which generation,
		/// keying a declaration's dependencies by label, cannot tell apart. The `@Instantiable` macro rejects the ways one
		/// clause can do this that the compiler accepts, but every build runs SafeDITool before the compiler expands the
		/// macro, so SafeDITool reports them too, plainly. A dependency declared once in each clause of an `#if` that only
		/// the compiler decides is another way, which the macro and the compiler accept.
		struct RepeatedDependencyLabel {
			/// The type that declares both dependencies.
			let declaringType: TypeDescription
			let earlierDependency: Dependency
			let laterDependency: Dependency

			/// An `error:` line at the later dependency.
			var sourceDiagnostic: SourceDiagnostic {
				SourceDiagnostic(
					severity: .error,
					location: laterDependency.declarationLocation,
					message: message,
				)
			}

			private var message: String {
				let earlierName = earlierDependency.property.label.spelledWithoutBackticks
				let laterName = laterDependency.property.label.spelledWithoutBackticks
				return if laterName == "_" {
					"`\(declaringType.asSource)` has more than one dependency named `_`. SafeDI names an `instantiate(…)` dependency by its parameter’s name, and the @\(InstantiableVisitor.macroName) macro rejects a dependency parameter named `_`. Name the parameter."
				} else if !earlierName.utf8.elementsEqual(laterName.utf8) {
					"`\(declaringType.asSource)` has dependencies `\(earlierName)` (\(earlierName.codePoints)) and `\(laterName)` (\(laterName.codePoints)), which look the same but are encoded differently, so SafeDI cannot tell them apart. The @\(InstantiableVisitor.macroName) macro rejects such names. Rename one of them."
				} else {
					// One wording for both causes, since a dependency does not record whether an `#if` encloses it: a copy-paste,
					// which the compiler rejects too, and one declaration in each clause of an `#if` only the compiler decides.
					"`\(declaringType.asSource)` declares the dependency `\(laterName)` more than once. Declare it once: if each clause of an `#if` that only the compiler decides, such as `#if os(iOS)`, declares it, declare it outside the `#if`, since SafeDI reads every clause."
				}
			}
		}

		/// A parameter without a default value of a hand-written mock that a generated mock calls – the mocked type's own,
		/// or that of a type a mock's tree, or a fill a call in it declares, builds with its mock – which no dependency the
		/// type declares under this build's conditions fulfills, so the generated call cannot pass it. The macro checks a
		/// mock against the dependencies of every `#if` clause, since the compiler has chosen among them, so such a
		/// parameter is one only a clause SafeDITool's evaluation did not select declares a dependency of (`clause`), which
		/// the error points at. Otherwise it is input the macro rejects, a parameter that names no dependency, which is
		/// reported plainly at the mock. No fix-it: either remedy the message names can be the one wanted.
		struct UnfulfilledMockParameter {
			/// The type whose hand-written mock takes the parameter.
			let declaringType: TypeDescription
			/// The hand-written mock.
			let mockInitializer: Initializer
			/// The mock's name: `mock`, or the type's `customMockName`.
			let mockMethodName: String
			let parameter: Initializer.Argument
			/// Where the mock declares `parameter` among its parameters, which orders the errors at one location.
			let parameterPosition: Int
			/// The outermost clause the evaluation did not select around a dependency of the parameter's label.
			let clause: Instantiable.DependencyLabelInUnselectedClause?
			/// Whether moving the mock into `clause` compiles under every condition, which the message then offers.
			let offersMoveIntoClause: Bool
			let mockDeclarationLocation: Dependency.DeclarationLocation?

			/// The parameters of `instantiable`'s hand-written mock, in declaration order, that no dependency it declares
			/// fulfills and that have no default value.
			static func parameters(ofMockOf instantiable: Instantiable) -> [UnfulfilledMockParameter] {
				guard let mockInitializer = instantiable.mockInitializer else { return [] }
				let positionedParameters = mockInitializer.argumentsWithoutDefaultFulfilledByNone(of: instantiable.dependencies)
				let unfulfilledParameters = positionedParameters.map(\.argument)
				let clauses = unfulfilledParameters.map { parameter in
					instantiable.dependencyLabelsInUnselectedClauses.first { $0.label == parameter.innerLabel }
				}
				return zip(positionedParameters, clauses).map { positionedParameter, clause in
					UnfulfilledMockParameter(
						declaringType: instantiable.concreteInstantiable,
						mockInitializer: mockInitializer,
						mockMethodName: instantiable.customMockName ?? InstantiableVisitor.mockMethodName,
						parameter: positionedParameter.argument,
						parameterPosition: positionedParameter.position,
						clause: clause,
						offersMoveIntoClause: canMoveMock(of: instantiable, intoClauseOf: clauses, unfulfilledParameters: unfulfilledParameters),
						mockDeclarationLocation: instantiable.mockDeclarationLocation,
					)
				}
			}

			/// Whether the hand-written mock of `instantiable`, moved into the clause that declares the dependencies of its
			/// `unfulfilledParameters` (whose clauses are `clauses`), compiles wherever that clause is compiled and where it
			/// is not: one clause declares each of them itself, rather than in a block nested in it, and every other
			/// parameter without a default value takes a dependency declared outside every `#if`. Where the clause is not
			/// compiled, the type has no hand-written mock and generated mocks build it with its initializer, which a
			/// `mockOnly` type does not have.
			private static func canMoveMock(
				of instantiable: Instantiable,
				intoClauseOf clauses: [Instantiable.DependencyLabelInUnselectedClause?],
				unfulfilledParameters: [Initializer.Argument],
			) -> Bool {
				guard !instantiable.mockOnly,
				      let firstClause = clauses.first ?? nil,
				      clauses.allSatisfy({ $0?.clauseLocation == firstClause.clauseLocation && $0?.clause == firstClause.clause && $0?.isDeclaredDirectlyInClause == true }),
				      let mockInitializer = instantiable.mockInitializer
				else { return false }
				let unfulfilledLabels = Set(unfulfilledParameters.map(\.innerLabel))
				return mockInitializer.arguments.allSatisfy { argument in
					argument.hasDefaultValue
						|| unfulfilledLabels.contains(argument.innerLabel)
						|| !instantiable.dependencyLabelsInsideConditionalBlocks.contains(argument.innerLabel)
				}
			}

			/// The diagnostics of `unfulfilledMockParameters`, which several mock roots can each find, in one group per
			/// location: each parameter once, however many roots found it, and the parameters at one location in the order
			/// the mock declares them, never by their labels. Neither depends on the order of `unfulfilledMockParameters`.
			static func sourceDiagnosticGroups(of unfulfilledMockParameters: [UnfulfilledMockParameter]) -> [[SourceDiagnostic]] {
				// One declaration's mock reads the same to every root, so a parameter found twice is reported once, keyed by
				// where it is reported and which parameter of which type's mock it is.
				struct Key: Hashable {
					let location: Dependency.DeclarationLocation?
					let declaringType: TypeDescription
					let parameter: Initializer.Argument
				}
				var reportedKeys = Set<Key>()
				var parametersByLocation = [Dependency.DeclarationLocation?: [UnfulfilledMockParameter]]()
				for unfulfilledMockParameter in unfulfilledMockParameters where reportedKeys.insert(Key(
					location: unfulfilledMockParameter.location,
					declaringType: unfulfilledMockParameter.declaringType,
					parameter: unfulfilledMockParameter.parameter,
				)).inserted {
					parametersByLocation[unfulfilledMockParameter.location, default: []].append(unfulfilledMockParameter)
				}
				// Each group's location is its own, so `joiningInSourceOrder` orders the groups by location alone.
				return parametersByLocation.values.map { parametersAtLocation in
					parametersAtLocation
						.sorted { ($0.declaringType, $0.parameterPosition) < ($1.declaringType, $1.parameterPosition) }
						.map(\.sourceDiagnostic)
				}
			}

			/// Where the error is reported: at the clause, or at the mock when no clause declares a dependency of the
			/// parameter's label.
			private var location: Dependency.DeclarationLocation? {
				clause?.clauseLocation ?? mockDeclarationLocation
			}

			/// An `error:` line at `location`.
			private var sourceDiagnostic: SourceDiagnostic {
				SourceDiagnostic(
					severity: .error,
					location: location,
					message: message,
				)
			}

			private var message: String {
				let typeName = declaringType.asSource
				let argumentLabels = mockInitializer.arguments.map { "\($0.label.spelledWithoutBackticks):" }.joined()
				let mockMethod = "`\(typeName).\(mockMethodName)(\(argumentLabels))`"
				let parameterSpelling = "`\(parameter.asProperty.asSource)`"
				return if let clause {
					if offersMoveIntoClause {
						"\(mockMethod) takes \(parameterSpelling), which `\(typeName)` declares only inside `\(clause.clause)`, inactive in this build, so generated code cannot call the mock. Give the parameter a default value, or move the `\(mockMethodName)` method inside `\(clause.clause)`."
					} else {
						"\(mockMethod) takes \(parameterSpelling), which `\(typeName)` declares only inside `\(clause.clause)`, inactive in this build, so generated code cannot call the mock. Give the parameter a default value."
					}
				} else {
					"\(mockMethod) takes \(parameterSpelling), which is not a dependency of `\(typeName)`, so generated code cannot call the mock. The @\(InstantiableVisitor.macroName) macro requires a default value for such a parameter: give it one."
				}
			}
		}

		/// A `@Received(fulfilledByDependencyNamed:ofType:)` declaration spelled as the `@Instantiable` macro rejects: a
		/// rename of another rename of the same declaration, or a rename of a dependency to itself. Every build runs
		/// SafeDITool before the compiler expands the macro, so SafeDITool reports them too, plainly, wherever its
		/// evaluation of `#if` blocks forms one – also where the macro, which cannot tell which clauses are active,
		/// accepts it: two renames in two `#if` blocks that are both active, or in two clauses of a block only the
		/// compiler decides, such as `#if os(iOS)`, every clause of which SafeDITool reads.
		struct RejectedRename {
			enum Spelling {
				/// The rename is fulfilled by `sourceLabel`, which `declaringType` also renames.
				case renameOfRename(sourceLabel: String, declaringType: TypeDescription)
				/// The rename is fulfilled by its own label with its own type.
				case renameOfItselfWithSameType
				/// The rename is fulfilled by its own label with its own type made non-optional, or kept, only if available.
				case renameOfItselfOnlyIfAvailable
			}

			let property: Property
			let spelling: Spelling
			let declarationLocation: Dependency.DeclarationLocation?

			/// An `error:` line at the rename.
			var sourceDiagnostic: SourceDiagnostic {
				SourceDiagnostic(
					severity: .error,
					location: declarationLocation,
					message: message,
				)
			}

			private var message: String {
				switch spelling {
				case let .renameOfRename(sourceLabel, declaringType):
					"`\(property.asSource)` is renamed from `\(sourceLabel.spelledWithoutBackticks)`, which `\(declaringType.asSource)` also renames. The @\(InstantiableVisitor.macroName) macro rejects a rename of another rename of the same declaration. Rename the property the renames start from instead. SafeDITool also rejects such renames where `#if` blocks that are active together declare them, or clauses of a condition only the compiler decides, such as `os(iOS)`, which SafeDITool reads together; there, give the rename `\(sourceLabel.spelledWithoutBackticks)` another label."
				case .renameOfItselfWithSameType:
					"`\(property.asSource)` is renamed from itself with the same type, which renames nothing. The @\(InstantiableVisitor.macroName) macro rejects this rename. Receive it with @\(Dependency.Source.receivedRawValue) instead."
				case .renameOfItselfOnlyIfAvailable:
					"`\(property.asSource)` is renamed from itself only if available. The @\(InstantiableVisitor.macroName) macro rejects this spelling of @\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true). Receive it with @\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) instead."
				}
			}
		}

		/// A property together with where it is declared.
		struct LocatedProperty: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A `@Received(fulfilledByDependencyNamed:ofType:onlyIfAvailable: true)` property that a type receives without
		/// `onlyIfAvailable`. That receive needs the alias created, so the type is built after `fulfillingProperty`.
		struct RequiredOnlyIfAvailableAlias: Hashable {
			let property: Property
			let fulfillingProperty: Property

			/// The sentences that end the error for a cycle the receive closes, in place of the general remedy, and say
			/// how to break it: received only if available, the alias is `nil` where its fulfilling property is not
			/// built first, as the manual describes.
			var hint: String {
				"`\(property.asSource)` renames `\(fulfillingProperty.asSource)` only if available, so a type that receives `\(property.label)` without `onlyIfAvailable` must be built after `\(fulfillingProperty.asSource)`. Receive `\(property.label)` with `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)` to be passed `nil` where `\(fulfillingProperty.asSource)` cannot be built first."
			}
		}

		struct UnfulfillableProperty: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The range of the declared identifier, which a fix-it renames when exactly one near-match has the same type.
			let identifierRange: Dependency.SourceRange?
			/// The range of the declared type, which a fix-it rewrites when exactly one near-match has the same label.
			let typeAnnotationRange: Dependency.SourceRange?
			/// The range of a bare `@Received` attribute, which a fix-it rewrites to `@Received(onlyIfAvailable: true)`.
			let bareAttributeRange: Dependency.SourceRange?
			let instantiable: Instantiable
			/// The types that instantiate `instantiable`, innermost first, excluding `root`.
			let parentStack: [TypeDescription]
			let root: TypeDescription
			let suggestedAlternatives: [Property]
			/// Whether an `@Instantiated` declaration of `property` could fulfill it, which decides whether the hint
			/// suggests one.
			let instantiatedDeclaration: InstantiatedDeclaration
			/// Where `property` is received inside a `@Sendable` function that a `Sendable` wrapper of the chain builds the
			/// receiver in, the declarations that fulfill it without that function capturing them; `nil` elsewhere.
			let sendableBoundaryAdvice: SendableBoundaryAdvice?
			/// The declarations of `property`'s label, of forms that do not provide it, that the tree of a type whose mock is
			/// generated holds above the receiver, so a declaration of `property` above the mocked type would leave the
			/// receive hidden in that mock: the advice relabels them too. Each once, in the order the walk meets them.
			let declarationsHidingReceiveInMocks: [HidingDeclaration]
			/// Whether `property`'s type is at least as accessible as `instantiable`, so `instantiable` can forward it: a type's
			/// `ForwardedProperties` typealias is as accessible as the type, and cannot name a less accessible type. Set on the
			/// failure path, from the access proof, where the hint would advise forwarding (`withForwardingAccess(proof:)`).
			var receiverCanForwardProperty = true

			/// This property, with `receiverCanForwardProperty` read from `proof` where its hint would advise forwarding: the
			/// type the receiver's declaration names is at least as accessible as the receiver, compared as Swift compares
			/// a `ForwardedProperties` typealias with its type.
			func withForwardingAccess(proof: TypeAccessProof) -> Self {
				switch instantiatedDeclaration {
				case .typeHasForwardedProperties, .typeIsNotInstantiable:
					var property = self
					let propertyTypeAccess = proof.access(
						ofParameterTyped: self.property.typeDescription,
						mentionedFrom: .declaration(instantiable),
						admittedModules: [instantiable.moduleName],
					).level
					property.receiverCanForwardProperty = AccessLevel.normalized(propertyTypeAccess) >= AccessLevel.normalized(instantiable.effectiveTypeAccess)
					return property
				case .possible, .closesCycle, .closesCycleThrough:
					return self
				}
			}

			/// A declaration of a label that a receive beneath it in some tree is hidden by.
			struct HidingDeclaration: Hashable {
				let property: Property
				let declaringType: TypeDescription

				var asSource: String {
					"`\(property.asSource)` on `\(declaringType.asSource)`"
				}
			}

			/// The repairs of a receive of a non-optional `Instantiator` or `LazilyInstantiated` inside a `@Sendable`
			/// function, which cannot capture a declaration of it made outside the function. Each is listed only where it
			/// passes the checks it would meet (`DependencyTreeGenerator.sendableBoundaryAdvice`).
			struct SendableBoundaryAdvice: Hashable {
				/// The innermost `Sendable` wrapper on the chain, as declared, whose `@Sendable` function builds the receiver.
				let boundary: Property
				/// The type that declares `boundary`.
				let boundaryDeclaringType: TypeDescription
				/// The type `boundary` builds.
				let builtType: TypeDescription
				/// The property's `Sendable` twin, which a `@Sendable` function can capture, where declaring it on
				/// `boundaryDeclaringType` passes; `nil` otherwise.
				let sendableForm: TypeDescription?
				/// The types the function builds on the chain, outermost first, where declaring the property on one of them
				/// passes; empty otherwise.
				let typesInsideFunction: [TypeDescription]

				/// The hint for a receive of `property`, or `nil` where neither repair passes and the hint is today's.
				func hint(for property: Property) -> String? {
					var repairs = [String]()
					if let sendableForm {
						repairs.append("`@\(Dependency.Source.instantiatedRawValue) let \(property.label): \(sendableForm.asSource)` on `\(boundaryDeclaringType.asSource)` and receive this property as `\(sendableForm.asSource)`")
					}
					if !typesInsideFunction.isEmpty {
						repairs.append("`@\(Dependency.Source.instantiatedRawValue) let \(property.asSource)` on \(typesInsideFunction.map { "`\($0.asSource)`" }.joined(separator: " or on "))")
					}
					guard !repairs.isEmpty else { return nil }
					let article = property.propertyType.isLazilyInstantiated ? "a" : "an"
					var hint = "`\(boundary.asSource)` on `\(boundaryDeclaringType.asSource)` builds `\(builtType.asSource)` in a `@Sendable` function, which cannot capture \(article) `\(property.typeDescription.asSource)` declared outside it. Declare \(repairs.joined(separator: ", or declare "))"
					if repairs.count > 1 {
						hint.append(", to fix.")
					} else {
						hint.append(" to fix.")
					}
					return hint
				}
			}

			/// Whether an `@Instantiated` declaration of a received property's non-optional form could fulfill it. The
			/// macro rejects an optional `@Instantiated` property, so the hint always suggests the non-optional form, which
			/// fulfills a receive of the optional one only if available.
			enum InstantiatedDeclaration: Hashable {
				/// It could, as far as SafeDI checks: the non-optional form is not a constant, or a declaration without
				/// `@Forwarded` properties fulfills its type.
				case possible
				/// The non-optional form is a constant of a type whose declaration has `@Forwarded` properties, which only
				/// an `Instantiator` can build.
				case typeHasForwardedProperties
				/// The non-optional form is a constant of a type no `@Instantiable` declaration fulfills.
				case typeIsNotInstantiable
				/// The tree of the type the non-optional form builds requires that form, or its optional form, from above
				/// it, so wherever it is declared, that tree receives it while it is still being built: a dependency cycle.
				case closesCycle
				/// The tree of the type the non-optional form builds requires the property the chain's root declares for the
				/// receiver's chain, a constant or lazily instantiated one no type of the chain declares again, whose tree
				/// holds the receiver: declared on the root, the two siblings require each other; declared on any type of the
				/// chain, that tree receives the root's property while it is still being built. A dependency cycle either way.
				case closesCycleThrough(Property)

				/// Whether an `@Instantiated` declaration of `property`'s non-optional form could fulfill it, among the
				/// declarations of `fulfillingInstantiables`.
				static func of(_ property: Property, among fulfillingInstantiables: [TypeDescription: Instantiable]) -> Self {
					let suggestedProperty = property.asUnwrappedProperty
					guard suggestedProperty.propertyType.isConstant else { return .possible }
					guard let fulfillingInstantiable = fulfillingInstantiables[suggestedProperty.typeDescription.asInstantiatedType] else {
						return .typeIsNotInstantiable
					}
					return fulfillingInstantiable.dependencies.contains { $0.source == .forwarded } ? .typeHasForwardedProperties : .possible
				}
			}

			/// The one suggested alternative, where it is the optional form of the property, the property's type is the
			/// receiver's own constant type, and the receiver's mock is generated and builds the receiver itself (it forwards
			/// nothing): the mock promotes the receive and builds it as the receiver, whose tree receives it still being built,
			/// a dependency cycle a required receive of the suggestion closes. Received only if available, it is passed `nil`
			/// there, and production hands it the value the suggestion names.
			private var suggestedReceiveOnlyIfAvailableClosingNoCycleInMock: Property? {
				guard suggestedAlternatives.count == 1,
				      case let suggestedAlternative = suggestedAlternatives[0],
				      suggestedAlternative.label == property.label,
				      suggestedAlternative.typeDescription.isOptional,
				      suggestedAlternative.typeDescription.unwrapped == property.typeDescription,
				      property.propertyType.isConstant,
				      instantiable.generatesMock,
				      instantiable.instantiableTypes.contains(property.typeDescription.asInstantiatedType),
				      !instantiable.dependencies.contains(where: { $0.source == .forwarded })
				else { return nil }
				return suggestedAlternative
			}

			/// A single `error:` line. The suggestion or fix hint is folded into it rather than emitted as a
			/// `note:` because it belongs at the same location, and Xcode drops notes from build-tool output.
			var sourceDiagnostics: [SourceDiagnostic] {
				let chain = ([instantiable.concreteInstantiable] + parentStack + [root]).reversed()
				let summary = "@\(Dependency.Source.receivedRawValue) property `\(property.asSource)` is not @\(Dependency.Source.instantiatedRawValue) or @\(Dependency.Source.forwardedRawValue) in chain: \(chain.map(\.asSource).joined(separator: " -> "))"
				// A diagnostic carries at most one fix-it – Xcode offers no Apply at all for a diagnostic with several –
				// and a fix-it is offered only when it is exactly the repair the hint names.
				let hint: String
				let fixIts: [SourceDiagnostic.FixIt]
				if property.typeDescription.isOptional,
				   let nonOptionalAlternative = suggestedAlternatives.first(where: { alternative in
				   	alternative.label == property.label
				   		&& alternative.typeDescription == property.typeDescription.unwrapped
				   })
				{
					let onlyIfAvailableAttribute = "@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)"
					hint = "The non-optional `\(nonOptionalAlternative.asSource)` is available in chain. Did you mean to decorate this property with `\(onlyIfAvailableAttribute)`?"
					// The range is recorded only for a bare attribute, so rewriting it never discards arguments the user wrote.
					fixIts = if let bareAttributeRange {
						[SourceDiagnostic.FixIt(range: bareAttributeRange, replacement: onlyIfAvailableAttribute)]
					} else {
						[]
					}
				} else if suggestedAlternatives.isEmpty {
					// The macro rejects an optional `@Instantiated` property, so the hint suggests the non-optional form. A
					// required receive of the optional form does not accept a declaration of the non-optional one; a receive
					// only if available reads either, so for an optional receive the hint also has it received so.
					let suggestedProperty = property.asUnwrappedProperty
					let typeName = suggestedProperty.typeDescription.asSource
					let fulfilledTypeName = suggestedProperty.typeDescription.asInstantiatedType.asSource
					let instantiatedDeclarationEnd = if property.typeDescription.isOptional {
						", and add `onlyIfAvailable: true` to this property’s `@\(Dependency.Source.receivedRawValue)`, which then accepts the non-optional form, to fix."
					} else {
						" to fix."
					}
					// A declaration of the property above a mocked type whose tree declares the label in another form would leave
					// the receive hidden in that mock, so the advice relabels those declarations too.
					var possibleDeclarationEnd = instantiatedDeclarationEnd
					if let lastHidingDeclaration = declarationsHidingReceiveInMocks.last {
						let relabeling = if declarationsHidingReceiveInMocks.count == 1 {
							"give \(lastHidingDeclaration.asSource) a different label"
						} else {
							"give \(declarationsHidingReceiveInMocks.dropLast().map(\.asSource).joined(separator: ", ")) and \(lastHidingDeclaration.asSource) different labels"
						}
						possibleDeclarationEnd = if property.typeDescription.isOptional {
							", \(relabeling)\(instantiatedDeclarationEnd)"
						} else {
							", and \(relabeling), to fix."
						}
					}
					// A forwarded property can be optional, and fulfills a required receive of exactly its type.
					let forwardingRemedy = "`@\(Dependency.Source.forwardedRawValue) let \(property.asSource)` on a type below `\(root.asSource)` in the chain, and pass the value to the `Instantiator` that builds that type"
					hint = if suggestedProperty.propertyType.isErasedInstantiator {
						// The `@Instantiated` macro requires an erased instantiator to name the type it builds.
						"Declare `@\(Dependency.Source.instantiatedRawValue)(fulfilledByType:) let \(suggestedProperty.asSource)`, naming the type it builds, on `\(root.asSource)` or on another type in the chain\(instantiatedDeclarationEnd)"
					} else {
						switch instantiatedDeclaration {
						case .possible:
							sendableBoundaryAdvice?.hint(for: property)
								?? "Declare `@\(Dependency.Source.instantiatedRawValue) let \(suggestedProperty.asSource)` on `\(root.asSource)` or on another type in the chain\(possibleDeclarationEnd)"
						case .closesCycle:
							// The remedies of the cycle error a declaration would lead to.
							"Declaring `@\(Dependency.Source.instantiatedRawValue) let \(suggestedProperty.asSource)` would close a dependency cycle wherever it is declared, because the tree of `\(suggestedProperty.typeDescription.asInstantiatedType.asSource)` requires `\(suggestedProperty.label)`, which is still being built there. \(DependencyTreeGeneratorError.onlyIfAvailableRemedy)"
						case let .closesCycleThrough(requiredProperty):
							// The remedies of the cycle error a declaration would lead to, wherever it is declared.
							"Declaring `@\(Dependency.Source.instantiatedRawValue) let \(suggestedProperty.asSource)` would close a dependency cycle wherever it is declared, because the tree of `\(suggestedProperty.typeDescription.asInstantiatedType.asSource)` receives `\(requiredProperty.asSource)`, which requires `\(suggestedProperty.label)`. \(DependencyTreeGeneratorError.onlyIfAvailableRemedy)"
						case .typeHasForwardedProperties:
							if receiverCanForwardProperty {
								"`\(typeName)` has @\(Dependency.Source.forwardedRawValue) properties, so SafeDI builds it only through an `Instantiator`, never as an @\(Dependency.Source.instantiatedRawValue) constant. Declare \(forwardingRemedy), to fix."
							} else {
								"`\(typeName)` has @\(Dependency.Source.forwardedRawValue) properties, so SafeDI builds it only through an `Instantiator`, never as an @\(Dependency.Source.instantiatedRawValue) constant. `\(instantiable.concreteInstantiable.asSource)` can forward it only once `\(typeName)` is at least as accessible as `\(instantiable.concreteInstantiable.asSource)`."
							}
						case .typeIsNotInstantiable:
							// A declaration that fulfills the type leads, as for an `@Instantiated` property of a type no declaration
							// fulfills, and names the type as a declaration fulfills it, which spells an existential without `any`.
							"No @\(InstantiableVisitor.macroName) declaration fulfills `\(fulfilledTypeName)`, so SafeDI cannot instantiate it. \(DependencyTreeGeneratorError.fulfillingDeclarationRemedy(typeName: fulfilledTypeName)), and declare `@\(Dependency.Source.instantiatedRawValue) let \(suggestedProperty.asSource)` on `\(root.asSource)` or on another type in the chain\(instantiatedDeclarationEnd)\(receiverCanForwardProperty ? " Or declare \(forwardingRemedy)." : "")"
						}
					}
					fixIts = []
				} else if suggestedAlternatives.count == 1, let suggestedReceive = suggestedReceiveOnlyIfAvailableClosingNoCycleInMock {
					// Received as required, the suggested optional form of the receiver's own type is still being built when the
					// receiver's mock builds the receiver, so the suggestion receives it only if available. That edits the
					// attribute and the type, which one fix-it cannot span without rewriting what lies between them.
					hint = "Did you mean `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) let \(suggestedReceive.asSource)`? Received as required, `\(suggestedReceive.asSource)` is still being built when the mock of `\(instantiable.concreteInstantiable.asSource)` builds `\(instantiable.concreteInstantiable.asSource)`."
					fixIts = []
				} else if suggestedAlternatives.count == 1 {
					let suggestedAlternative = suggestedAlternatives[0]
					hint = "Did you mean `\(suggestedAlternative.asSource)`?"
					// The suggestion list mixes same-type and same-label near-matches, and a single-token edit repairs the
					// property only when exactly one of label and type differs: a differing label is renamed and a differing
					// type is rewritten. Both differing gets no fix-it, and neither differing cannot happen, since the property
					// would then be fulfilled. A rename is offered only when the type is exactly what fulfillment compares
					// after normalization – a module-qualified spelling is not unified by normalization, so a rename there
					// would leave the property unfulfilled.
					fixIts = if suggestedAlternative.label != property.label,
					            suggestedAlternative.typeDescription == property.typeDescription,
					            let identifierRange
					{
						[SourceDiagnostic.FixIt(range: identifierRange, replacement: suggestedAlternative.label)]
					} else if suggestedAlternative.label == property.label,
					          let typeAnnotationRange
					{
						[SourceDiagnostic.FixIt(range: typeAnnotationRange, replacement: suggestedAlternative.typeDescription.asSource)]
					} else {
						[]
					}
				} else {
					hint = "Did you mean one of \(suggestedAlternatives.map { "`\($0.asSource)`" }.joined(separator: ", "))?"
					// Several candidates leave the choice to the user.
					fixIts = []
				}
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "\(summary). \(hint)",
						fixIts: fixIts,
					),
				]
			}
		}

		/// A property an ancestor declares, which the generated code names by its label everywhere below that ancestor.
		struct LabelDeclaration: Hashable {
			init(
				property: Property,
				lazilyInstantiatedInstanceProperty: Property?,
				declarationLocation: Dependency.DeclarationLocation?,
				declaringType: TypeDescription,
				isForwarded: Bool,
				replacing replacedDeclaration: LabelDeclaration?,
			) {
				let identity = Identity(
					property: property,
					lazilyInstantiatedInstanceProperty: lazilyInstantiatedInstanceProperty,
					declarationLocation: declarationLocation,
					declaringType: declaringType,
					isForwarded: isForwarded,
				)
				let enclosingDeclarations: [LabelDeclaration] = if let replacedDeclaration {
					([replacedDeclaration] + replacedDeclaration.enclosingDeclarations).filter { $0.storage.identity != identity }
				} else {
					[]
				}
				storage = Storage(identity: identity, enclosingDeclarations: enclosingDeclarations)
			}

			var property: Property {
				storage.identity.property
			}

			/// The by-value property with which types further down the tree receive the instance of `property`,
			/// when `property` is lazily instantiated and offers one.
			var lazilyInstantiatedInstanceProperty: Property? {
				storage.identity.lazilyInstantiatedInstanceProperty
			}

			var declarationLocation: Dependency.DeclarationLocation? {
				storage.identity.declarationLocation
			}

			var declaringType: TypeDescription {
				storage.identity.declaringType
			}

			/// Whether `declaringType` is forwarded `property`, which the tree is then handed rather than builds.
			var isForwarded: Bool {
				storage.identity.isForwarded
			}

			/// The declarations of the label that the scopes `declaringType` is built inside make on this path, which this one
			/// hides, closest first: the declaration it replaced, then those that one hides, without any equal to this one, since
			/// a type a cycle builds again beneath itself declares the label again, one declaration named once. What a hidden
			/// receive's error names beside this declaration; no part of which declaration this is, so `==` and `hash(into:)`
			/// leave it out, and the walk's memo of trees built again and the matching of a seam's chain with a root's compare
			/// the closest declaration alone.
			var enclosingDeclarations: [LabelDeclaration] {
				storage.enclosingDeclarations
			}

			/// What makes the declaration the one it is, which `==` and `hash(into:)` compare.
			private struct Identity: Hashable {
				let property: Property
				let lazilyInstantiatedInstanceProperty: Property?
				let declarationLocation: Dependency.DeclarationLocation?
				let declaringType: TypeDescription
				let isForwarded: Bool
			}

			/// What the declaration holds, behind one reference: a walk copies the closest declaration of every label into the
			/// context of each scope that builds a child, so a copy is one retain rather than one for each field. Each holds
			/// every declaration it hides itself, never through the one it replaced, so releasing a declaration never releases a
			/// chain of them nested one inside another.
			private final class Storage: Sendable {
				init(identity: Identity, enclosingDeclarations: [LabelDeclaration]) {
					self.identity = identity
					self.enclosingDeclarations = enclosingDeclarations
				}

				let identity: Identity
				let enclosingDeclarations: [LabelDeclaration]
			}

			private let storage: Storage

			/// Whether a receive that resolves to any of `acceptedProperties` resolves to this declaration: the declaration is
			/// one of them, or a lazily instantiated declaration whose instance is.
			func fulfills(anyOf acceptedProperties: Set<Property>) -> Bool {
				acceptedProperties.contains(property) || lazilyInstantiatedInstanceProperty.map(acceptedProperties.contains) ?? false
			}

			static func == (lhs: LabelDeclaration, rhs: LabelDeclaration) -> Bool {
				lhs.storage.identity == rhs.storage.identity
			}

			func hash(into hasher: inout Hasher) {
				hasher.combine(storage.identity)
			}
		}

		/// A received dependency the generated code cannot pass, because a closer ancestor declares another property
		/// with the same label – for example, an alias that retypes the dependency and keeps its label – and the generated
		/// code names a dependency by its label.
		struct HiddenReceivedProperty: Hashable {
			/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The closest declaration of the label, whose property differs from `property`.
			let hidingDeclaration: LabelDeclaration
			/// The declarations of the label above `hidingDeclaration` that hide the receive too, closest first: each one of
			/// `hidingDeclaration.enclosingDeclarations` before the first that provides the receive, so relabeling every
			/// declaration the error names leaves none between the receive and what provides it.
			let enclosingHidingDeclarations: [LabelDeclaration]
			let receiver: TypeDescription
			/// The types of the properties the chain's scopes are built for (`ScreenProtocol`, `Instantiator<Screen>`),
			/// innermost first, excluding `root`.
			let parentStack: [TypeDescription]
			let root: TypeDescription

			/// An `error:` line that names each hiding declaration, since Xcode drops notes from build-tool output, and
			/// a `note:` at each hiding declaration so command-line builds can navigate to it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let chain = ([receiver] + parentStack + [root]).reversed()
				let hidingProperty = hidingDeclaration.property.asSource
				let declaringType = hidingDeclaration.declaringType.asSource
				let hidingDeclarations = [hidingDeclaration] + enclosingHidingDeclarations
				var message = "@\(Dependency.Source.receivedRawValue) property `\(property.asSource)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). `\(declaringType)` declares `\(hidingProperty)` with the same label, so the types below `\(declaringType)` receive `\(hidingProperty)` instead"
				if enclosingHidingDeclarations.isEmpty {
					message += ". Give `\(hidingProperty)` on `\(declaringType)` a different label to fix."
				} else {
					let enclosing = enclosingHidingDeclarations.map { "`\($0.declaringType.asSource)` declares `\($0.property.asSource)`" }
					let relabeled = hidingDeclarations.map { "`\($0.property.asSource)` on `\($0.declaringType.asSource)`" }
					message += ", and above `\(declaringType)`, \(enclosing.joinedAsList) with the same label too. Give \(relabeled.joinedAsList) each a different label to fix."
				}
				return [SourceDiagnostic(severity: .error, location: declarationLocation, message: message)] + hidingDeclarations.map {
					SourceDiagnostic(
						severity: .note,
						location: $0.declarationLocation,
						message: "`\($0.property.asSource)` is declared here",
					)
				}
			}
		}

		/// A rename whose `fulfilledByDependencyNamed:` label its own type also declares – as a property it instantiates
		/// or forwards, or as another rename – with a type that the rename's `ofType:` does not name. A rename refers to
		/// the property of that name on its own type, so it cannot name a property of another type further up the tree.
		struct RenameContradictingOwnProperty: Hashable {
			/// The rename, as declared.
			let aliasProperty: Property
			/// The property the rename's `fulfilledByDependencyNamed:` and `ofType:` name.
			let fulfillingProperty: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The property of the rename's label that `renamingType` declares.
			let ownProperty: Property
			let ownPropertyDeclarationLocation: Dependency.DeclarationLocation?
			let renamingType: TypeDescription

			/// An `error:` line that names the type's own property, since Xcode drops notes from build-tool output, and a
			/// `note:` at that property's declaration so command-line builds can navigate to it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let ownPropertyTypeLiteral = ownProperty.typeDescription.asTypeLiteralSource
				let ownProperty = ownProperty.asSource
				let fulfillingProperty = fulfillingProperty.asSource
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:) property `\(aliasProperty.asSource)` renames `\(fulfillingProperty)`, but `\(renamingType.asSource)` declares `\(ownProperty)`, and a rename refers to the property of that name on its own type. Write `ofType: \(ownPropertyTypeLiteral)` to rename `\(ownProperty)`, or give `\(ownProperty)` on `\(renamingType.asSource)` a different label to rename `\(fulfillingProperty)` from further up the tree.",
					),
					SourceDiagnostic(
						severity: .note,
						location: ownPropertyDeclarationLocation,
						message: "`\(ownProperty)` is declared here",
					),
				]
			}
		}

		/// A receive of a property the mocked type forwards, in the tree of a dependency the mock builds beside the
		/// mocked type, that a closer receive of the property's label in another form hides. The mock binds that form
		/// under a name of its own, since the forwarded parameter keeps the label, and passes it to its receiver under
		/// the label, inside the function that also builds the types beneath the receiver.
		struct ForwardedPropertyHiddenInPromotedTree {
			/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			let mockedType: TypeDescription
			let forwardedProperty: Property
			/// The other form of the label, which a type above the receiver receives.
			let hidingProperty: Property
			let hidingDeclarationLocation: Dependency.DeclarationLocation?
			/// The types from the one that receives `hidingProperty` to the one that receives `property`.
			let chain: [TypeDescription]

			/// An `error:` line that names the hiding receive, as `HiddenReceivedProperty`'s does, and a `note:` at it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let property = property.asSource
				let hidingProperty = hidingProperty.asSource
				let hidingType = chain[0].asSource
				let receivingType = chain[chain.count - 1].asSource
				let forwardedProperty = forwardedProperty.asSource
				let mockedType = mockedType.asSource
				// Giving the forwarded property another label leaves the receive hidden wherever `hidingType` holds a
				// form of the label the mock cannot derive from the receiver's, so the remedy separates the two receives.
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue) property `\(property)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). In the mock of `\(mockedType)`, `\(receivingType)` is passed the `\(forwardedProperty)` that `\(mockedType)` forwards, but `\(hidingType)` receives `\(hidingProperty)` with the same label, so the types below `\(hidingType)` receive `\(hidingProperty)` instead. Receive `\(property)` on `\(receivingType)` and `\(hidingProperty)` on `\(hidingType)` under different labels to fix.",
					),
					SourceDiagnostic(
						severity: .note,
						location: hidingDeclarationLocation,
						message: "`\(hidingProperty)` is received here",
					),
				]
			}
		}

		/// An `error:` line at the first receive of `unpassableCycleLabel`'s label, which names every form the type built again
		/// and the types it builds receive, and a `note:` at the declaration of the label it is built again beneath.
		private static func sourceDiagnostics(of unpassableCycleLabel: UnpassableCycleLabel) -> [SourceDiagnostic] {
			let receiver = unpassableCycleLabel.receiver
			let redeclaration = unpassableCycleLabel.redeclaration
			let label = receiver.property.label
			let builtType = "`\(unpassableCycleLabel.builtType.asSource)`"
			let forms = unpassableCycleLabel.forms.map { "`\($0.asSource)`" }.joinedAsList
			return [
				SourceDiagnostic(
					severity: .error,
					location: receiver.declarationLocation,
					message: "@\(Dependency.Source.receivedRawValue) property `\(receiver.property.asSource)` is received in chain: \(receiver.chain.map(\.asSource).joined(separator: " -> ")). A dependency cycle builds \(builtType) again beneath `\(redeclaration.declaringType.asSource)`, which declares `\(redeclaration.property.asSource)` with the same label, and SafeDI hands each \(builtType) one value of `\(label)`. \(builtType) and the types it builds receive `\(label)` as \(forms), which one value cannot carry together. Receive \(forms) under different labels to fix.",
				),
				SourceDiagnostic(
					severity: .note,
					location: redeclaration.declarationLocation,
					message: "`\(redeclaration.property.asSource)` is declared here",
				),
			]
		}

		/// A required receive in a mock's tree, beneath or beside a required receive of its label, on a type in that tree,
		/// in a form no one declaration provides together with it. In production both receives resolve to
		/// the closest declaration of the label above the tree: above the mocked type for its own tree, and above the tree
		/// of a dependency the mock promotes, which is built above the mocked type.
		struct ReceivedPropertyHiddenInMockTree {
			/// The tree of a mock that holds both receives.
			enum Tree {
				/// The mocked type's own tree.
				case mockedType
				/// The tree of a dependency the mock promotes, of the given type.
				case promotedDependency(TypeDescription)
			}

			/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			let mockedType: TypeDescription
			let tree: Tree
			/// The other form of the label, which `hidingType` receives.
			let hidingProperty: Property
			let hidingDeclarationLocation: Dependency.DeclarationLocation?
			let hidingType: TypeDescription
			/// Whether the type that receives `property` is `hidingType`, which declares both receives.
			let isHiddenOnItsOwnType: Bool
			/// The types from the type at the top of `tree` to the one that receives `property`.
			let chain: [TypeDescription]

			/// An `error:` line in the words of `HiddenReceivedProperty`'s, which names the hiding receive, and a `note:` at it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let property = property.asSource
				let hidingProperty = hidingProperty.asSource
				let hidingType = hidingType.asSource
				let mockedType = mockedType.asSource
				let receivingTypes = isHiddenOnItsOwnType
					? "`\(hidingType)` and the types below it"
					: "the types below `\(hidingType)`"
				let (treeClause, builtType) = switch tree {
				case .mockedType:
					("", mockedType)
				case let .promotedDependency(promotedType):
					("`\(promotedType.asSource)` stands for a dependency built above `\(mockedType)`, and ", promotedType.asSource)
				}
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue) property `\(property)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). In the mock of `\(mockedType)`, \(treeClause)`\(hidingType)` receives `\(hidingProperty)` with the same label, so \(receivingTypes) receive `\(hidingProperty)` instead, as they do wherever `\(builtType)` is built. Receive `\(property)` and `\(hidingProperty)` under different labels to fix.",
					),
					SourceDiagnostic(
						severity: .note,
						location: hidingDeclarationLocation,
						message: "`\(hidingProperty)` is received here",
					),
				]
			}
		}

		/// The dependency declaration that closes a dependency cycle no instantiator defers, or that receives a property
		/// still being built, at which the cycle is reported.
		enum ClosingDependency {
			/// A dependency the declaring type instantiates, closing a cycle along which no dependency is an instantiator:
			/// `hops`, the instantiated dependencies along the cycle as validation sees them (a lazily instantiated
			/// dependency as the constant it stands for), outermost first, the closing dependency among them.
			case instantiated(hops: [Property])
			/// A dependency `receiver` receives, as declared, while the property it is fulfilled by is still being built.
			case received(Property, receiver: TypeDescription)

			/// The sentence that tells the user how to break the cycle at this declaration.
			var remedy: String {
				switch self {
				case let .instantiated(hops):
					"SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @\(Dependency.Source.instantiatedRawValue) instantiator, such as an `\(Dependency.instantiatorType)` or `\(Dependency.erasedInstantiatorType)`, which builds its type each time it is called. Change \(hops.count == 1 ? "" : "one of ")\(hops.map { "`\($0.asSource)`" }.joined(separator: ", ")) to an instantiator."
				case let .received(property, receiver):
					"`\(receiver.asSource)` receives `\(property.asSource)`, which is still being built when `\(receiver.asSource)` is built. \(DependencyTreeGeneratorError.onlyIfAvailableRemedy)"
				}
			}
		}

		/// A dependency cycle. The error is reported at the dependency declaration that closes the cycle – the edge
		/// whose target type is already on the instantiation stack when validation reaches it – because that is the
		/// property the user changes (to an `Instantiator`, or from `@Received` to `@Instantiated`) to break the cycle.
		/// Each member type gets a note at its `@Instantiable` declaration so every file involved is navigable.
		struct DependencyCycle {
			/// The location of the dependency declaration whose target type is already on the instantiation stack.
			let declarationLocation: Dependency.DeclarationLocation?
			/// A type in the cycle together with the location of the `@Instantiable` declaration fulfilling it.
			struct Member: Hashable {
				let typeDescription: TypeDescription
				/// `nil` when no `@Instantiable` is registered for the type.
				let declarationLocation: Dependency.DeclarationLocation?
			}

			/// The property types in the cycle, innermost first.
			let members: [Member]
			/// The lazily instantiated properties on the cycle as they are declared, outermost first.
			/// Validation sees each as the constant it stands for, which is what `members` holds.
			let lazilyInstantiatedProperties: [Property]

			var asSource: String {
				members
					.map { "`\($0.typeDescription.asSource)`" }
					.reversed()
					.joined(separator: " -> ")
			}

			func sourceDiagnostics(summary: String) -> [SourceDiagnostic] {
				var notedDeclarationLocations = Set<Dependency.DeclarationLocation>()
				let notes: [SourceDiagnostic] = members.reversed().compactMap { member in
					guard let declarationLocation = member.declarationLocation,
					      notedDeclarationLocations.insert(declarationLocation).inserted
					else { return nil }
					return SourceDiagnostic(
						severity: .note,
						location: declarationLocation,
						message: "`\(member.typeDescription.asInstantiatedType.asSource)` is part of the cycle",
					)
				}
				return [SourceDiagnostic(severity: .error, location: declarationLocation, message: summary)] + notes
			}
		}
	}
}
