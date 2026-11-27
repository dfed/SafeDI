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

extension SeamSignature {
	/// The places of a seam's holes as a graph of levels, one per level variant, in place of one list per place.
	///
	/// A place is a site of a hole beneath one owner level, reached from the seam's root along a route of levels. What a
	/// scope binds before the next property on a route is a fact of the scope's type and of that property, the same on every
	/// path that builds it, so it is held once, as a `Level`, with an edge to each level that can enclose it. Two builds of a
	/// type that bind otherwise (a builder function a lazy cycle closes on, a loop's rebindings) are two variants of one
	/// `LevelKey`.
	///
	/// A `Case` is the places of one owner level in one family (built in plain code, or inside a `@Sendable` function): the
	/// places of one `.place(sites:)` case of the seam's enums nested by type, which one emitted fill fills. Every list the
	/// per-place walk gave a place – its fields, the declarations it carries no field of, what a cycle hands it again, what a
	/// fill's field hides, its owner's stack – is answered for a case over the routes to its owner level in its family
	/// (`Query`), so the record grows with the seam's types and cases, never with its paths.
	///
	/// It lives as long as the signature that holds it.
	public struct Places: Codable, Sendable {
		public init(levels: [Level], cases: [Case], declarationLists: [[Declaration]] = []) {
			self.levels = levels
			self.cases = cases
			self.declarationLists = declarationLists
		}

		/// The levels, in the order the seam's places first reach them. The seam's root is the one level with no parent.
		public let levels: [Level]
		/// The declarations of the levels, one list for every level of one build of a type but for the property next on the
		/// route: each declaration as it is before any next property (`Declaration.child`), so a type with many properties
		/// that lead to places holds its declarations once, not once per such property.
		public let declarationLists: [[Declaration]]
		/// The cases, in the order the seam's places first reach them.
		public let cases: [Case]

		/// Which level of which type a level is. A build of one type before one property is one key, however many paths reach
		/// it.
		public struct LevelKey: Codable, Hashable, Sendable {
			public init(builtType: TypeDescription?, nextProperty: Property?, isSeamRoot: Bool, isInFill: Bool, filledType: TypeDescription?, filledCase: CalledCase? = nil) {
				self.builtType = builtType
				self.nextProperty = nextProperty
				self.isSeamRoot = isSeamRoot
				self.isInFill = isInFill
				self.filledType = filledType
				self.filledCase = filledCase
			}

			/// The type the scope builds, or `nil` for a fill of a seam the tree calls.
			public let builtType: TypeDescription?
			/// The next property on the way to the places: the next scope's, or, at an owner level, the hole's. `nil` where the
			/// next scope is a fill.
			public let nextProperty: Property?
			/// Whether the level is the seam's own root, whose first declarations are its parameters.
			public let isSeamRoot: Bool
			/// Whether the scope is a fill or in a fill's tree.
			public let isInFill: Bool
			/// For a fill, the type the level before it builds, which the fill fills a place of.
			public let filledType: TypeDescription?
			/// For a fill, the case of the called seam that holds the place it fills, so that a question about the routes to
			/// the place continues into that seam's graph; `nil` where the call's graph was not built, and for every other level.
			/// Two fills of places of different cases are different levels, however alike their trees.
			public let filledCase: CalledCase?
		}

		/// One entry of the stack a place's owner is built with: a property and the concrete type it is built for.
		public struct StackEntry: Codable, Hashable, Sendable {
			public init(property: Property, concreteType: TypeDescription) {
				self.property = property
				self.concreteType = concreteType
			}

			public let property: Property
			public let concreteType: TypeDescription
		}

		/// The `@Sendable` function a level's scope opens, which encloses what the level binds and everything beneath it: the
		/// scope's builder function, or a `@Sendable` fill.
		public struct SendableFunctionOpened: Codable, Hashable, Sendable {
			public init(property: Property, function: Hole.UncarriedDeclaration.SendableFunction) {
				self.property = property
				self.function = function
			}

			/// The property the function builds.
			public let property: Property
			public let function: Hole.UncarriedDeclaration.SendableFunction
		}

		/// For a fill's field bound from a parameter of the filled seam: what a diagnostic about the declaration it hides
		/// names (`Hole.DeclarationHiddenByField`), beside the hidden declaration, which the route above the fill decides.
		public struct FillFieldHiding: Codable, Hashable, Sendable {
			public init(calledSeam: TypeDescription, receivingSeam: TypeDescription) {
				self.calledSeam = calledSeam
				self.receivingSeam = receivingSeam
			}

			/// The seam called, where the hidden declaration is no passing-up seam's: the type the level before the fill builds.
			public let calledSeam: TypeDescription
			/// The seam whose struct carries the field.
			public let receivingSeam: TypeDescription
		}

		/// Where a type above the seam can build the tree a declaration instantiates (`Hole.UncarriedDeclaration.isBuildableAboveSeam`).
		public struct Buildability: Codable, Hashable, Sendable {
			public init(labelsHeldAboveSeam: [String], placesInTree: [Int]) {
				self.labelsHeldAboveSeam = labelsHeldAboveSeam
				self.placesInTree = placesInTree
			}

			/// The labels the seam's caller would hold (`Hole.UncarriedDeclaration.labelsHeldAboveSeam`), sorted, so that the
			/// record encodes the same bytes on every run.
			public let labelsHeldAboveSeam: [String]
			/// The indices in `cases` of the cases of the places the tree holds or passes up, in the order the tree reaches them.
			public let placesInTree: [Int]
		}

		/// A declaration of a level, with everything any place beneath reads of it.
		public struct Declaration: Codable, Hashable, Sendable {
			public init(
				field: Hole.Field,
				isBoundBeforeNextProperty: Bool,
				builtAfter: Property?,
				reason: Hole.UncarriedDeclaration.Reason,
				isForwarded: Bool,
				cycleParameterOrigin: Hole.UncarriedDeclaration.CycleParameterOrigin?,
				alias: Hole.UncarriedDeclaration.AliasOrigin?,
				isBoundFromCallersArgument: Bool,
				isCycleParameter: Bool,
				isReboundByBuilderFunction: Bool,
				isFieldOfSeamParameter: Bool,
				fillFieldHiding: FillFieldHiding?,
				buildability: Buildability?,
			) {
				self.field = field
				self.isBoundBeforeNextProperty = isBoundBeforeNextProperty
				self.builtAfter = builtAfter
				self.reason = reason
				self.isForwarded = isForwarded
				self.cycleParameterOrigin = cycleParameterOrigin
				self.alias = alias
				self.isBoundFromCallersArgument = isBoundFromCallersArgument
				self.isCycleParameter = isCycleParameter
				self.isReboundByBuilderFunction = isReboundByBuilderFunction
				self.isFieldOfSeamParameter = isFieldOfSeamParameter
				self.fillFieldHiding = fillFieldHiding
				self.buildability = buildability
			}

			/// The field a place reads of the declaration where it carries one; its property, type and location are the
			/// declaration's wherever it is read.
			public let field: Hole.Field
			/// Whether the scope binds it before the next property. A declaration bound later holds no value there, but hides
			/// the farther declarations of its label.
			public let isBoundBeforeNextProperty: Bool
			/// For a declaration bound later: the property it is built after (`Hole.UncarriedDeclaration.builtAfter`).
			public let builtAfter: Property?
			/// For a declaration bound later: why (`Hole.UncarriedDeclaration.reason`).
			public let reason: Hole.UncarriedDeclaration.Reason
			/// Whether its type forwards it.
			public let isForwarded: Bool
			/// Where it is a parameter of a builder function a lazy cycle closes on: whose, and what the cycle passes it.
			public let cycleParameterOrigin: Hole.UncarriedDeclaration.CycleParameterOrigin?
			/// Where its type receives it under an alias: what fulfills it.
			public let alias: Hole.UncarriedDeclaration.AliasOrigin?
			/// Whether a public mock binds it at its root from the argument its caller passes.
			public let isBoundFromCallersArgument: Bool
			/// Whether it is a parameter of the scope's builder function that a lazy cycle closes on (`CycleParameter`).
			public let isCycleParameter: Bool
			/// Whether the scope's builder function wraps it again as a member of a loop of builders.
			public let isReboundByBuilderFunction: Bool
			/// For a fill's field, whether it is bound from a parameter of the filled seam.
			public let isFieldOfSeamParameter: Bool
			/// For a fill's field bound from a parameter of the filled seam: what names the declaration it hides.
			public let fillFieldHiding: FillFieldHiding?
			/// Where a type above the seam can build the tree it instantiates.
			public let buildability: Buildability?
			/// For a child of the level's scope: what decides, with the level's next property, whether it is bound before that
			/// property, after what it is built, and why (`Places.declaration(level:declaration:)`). `nil` for any other
			/// declaration, whose facts are the same before every next property.
			public private(set) var child: ChildFacts?

			/// Whether it is a parameter of the seam, which a place inside a `@Sendable` function reads from its caller's scope.
			public var isSeamParameter: Bool {
				field.isSeamParameter
			}

			/// The declaration, as a child of its scope, with `child`.
			public func asChild(_ child: ChildFacts) -> Self {
				var declaration = self
				declaration.child = child
				return declaration
			}

			/// The declaration as `level`'s scope binds it before its next property, as the per-site walk decides it for a child
			/// of the scope on a site's path (`SeamBuilderParameters`): a child is bound before the next property where it is
			/// built before it and is no member of the next property's loop of builders; a builder at the next property, or a
			/// member of its loop, is building the place; a later child that builds a type or a place is built after the next
			/// property, and a later child that builds a type is so for the reason its receives give.
			func beforeNextProperty(of level: Level) -> Self {
				guard let child, let next = level.nextPosition else { return self }
				let isLoopMember = child.position < next && child.loop != nil && child.loop == level.nextLoop
				var builtAfter: Property?
				var reason = reason
				if child.position == next && child.isBuilder || isLoopMember {
					reason = .instantiatorBuildingSite
				} else if child.position > next, let nextProperty = level.key.nextProperty {
					if let builtType = child.builtType {
						builtAfter = nextProperty
						if child.receivesOnlyIfAvailable.contains(nextProperty) {
							reason = .receivesPathScopeOnlyIfAvailable(type: builtType)
						} else if let carrier = child.carriers.first(where: { $0 != nextProperty }) {
							reason = .requiresOtherCarrier(type: builtType, carrier: carrier)
						}
					} else if child.isPlace {
						builtAfter = nextProperty
					}
				}
				return Self(
					field: field,
					isBoundBeforeNextProperty: child.position < next && !isLoopMember,
					builtAfter: builtAfter,
					reason: reason,
					isForwarded: isForwarded,
					cycleParameterOrigin: cycleParameterOrigin,
					alias: alias,
					isBoundFromCallersArgument: isBoundFromCallersArgument,
					isCycleParameter: isCycleParameter,
					isReboundByBuilderFunction: isReboundByBuilderFunction,
					isFieldOfSeamParameter: isFieldOfSeamParameter,
					fillFieldHiding: fillFieldHiding,
					buildability: buildability,
				)
			}
		}

		/// What a child of a level's scope brings to the facts that depend on the level's next property.
		public struct ChildFacts: Codable, Hashable, Sendable {
			public init(position: Int, isBuilder: Bool, loop: Int?, builtType: TypeDescription?, isPlace: Bool, receivesOnlyIfAvailable: [Property], carriers: [Property]) {
				self.position = position
				self.isBuilder = isBuilder
				self.loop = loop
				self.builtType = builtType
				self.isPlace = isPlace
				self.receivesOnlyIfAvailable = receivesOnlyIfAvailable
				self.carriers = carriers
			}

			/// Its position among the scope's children, in the order the scope builds them.
			public let position: Int
			/// Whether it is a builder (`ScopeGenerator.isBuilder`).
			public let isBuilder: Bool
			/// The loop of received builders it is a member of (`ScopeGenerator.ReceivedBuilderLoops`), if any.
			public let loop: Int?
			/// The type it builds, where it builds one.
			public let builtType: TypeDescription?
			/// Whether it is a place.
			public let isPlace: Bool
			/// The properties of its siblings it receives only if available.
			public let receivesOnlyIfAvailable: [Property]
			/// The first two of its siblings that start as carriers and that it requires, in the scope's order: the first one
			/// other than the next property is the carrier it waits on.
			public let carriers: [Property]
		}

		/// What a scope between a closed-on level and one of its cycle-closing scopes declares, which the cycle hands the
		/// type built again (`Hole.CycleReentryDeclaration`, whose `closedOnDeclaringType` is the type that declares the
		/// level's own property, read from the route).
		public struct CycleReentry: Codable, Hashable, Sendable {
			public init(property: Property, declaringType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, parameterTakingType: TypeDescription?, closedOnProperty: Property, closedOnBuiltType: TypeDescription, reenteringType: TypeDescription) {
				self.property = property
				self.declaringType = declaringType
				self.declarationLocation = declarationLocation
				self.parameterTakingType = parameterTakingType
				self.closedOnProperty = closedOnProperty
				self.closedOnBuiltType = closedOnBuiltType
				self.reenteringType = reenteringType
			}

			public let property: Property
			public let declaringType: TypeDescription
			public let declarationLocation: Dependency.DeclarationLocation?
			public let parameterTakingType: TypeDescription?
			public let closedOnProperty: Property
			public let closedOnBuiltType: TypeDescription
			public let reenteringType: TypeDescription
		}

		/// One level variant: what its scope binds, in binding order, and the levels that can enclose it.
		public struct Level: Codable, Sendable {
			public init(
				key: LevelKey,
				declarationList: Int,
				nextPosition: Int?,
				nextLoop: Int?,
				opensSendableFunction: SendableFunctionOpened?,
				cycleReentries: [CycleReentry],
				fillBaseStack: [StackEntry],
				fillOwnerType: TypeDescription?,
				pathSegment: [Property],
				pathTypes: [Hole.PathType],
				parents: [Int],
				declaredSegmentByParent: [[Hole.DeclaredProperty]],
				closesOn: StackEntry? = nil,
			) {
				self.key = key
				self.declarationList = declarationList
				self.nextPosition = nextPosition
				self.nextLoop = nextLoop
				self.opensSendableFunction = opensSendableFunction
				self.cycleReentries = cycleReentries
				self.fillBaseStack = fillBaseStack
				self.fillOwnerType = fillOwnerType
				self.pathSegment = pathSegment
				self.pathTypes = pathTypes
				self.parents = parents
				self.declaredSegmentByParent = declaredSegmentByParent
				self.closesOn = closesOn
			}

			public let key: LevelKey
			/// The index in `Places.declarationLists` of its declarations, in the order the scope binds them: for the seam's
			/// root, its parameters, then its children; for any other type, its forwarded properties, its loop's rebindings and
			/// its cycle parameters, then its children; for a fill, the declarations the filled seam's struct does not carry,
			/// then the fields it binds. `Places.declaration(level:declaration:)` reads one before the level's next property.
			public let declarationList: Int
			/// The position among the scope's children of the next property, where the scope builds it as a child.
			public let nextPosition: Int?
			/// The loop of received builders the next property is a member of, if any.
			public let nextLoop: Int?
			/// The `@Sendable` function the scope opens, or `nil` where it opens none.
			public let opensSendableFunction: SendableFunctionOpened?
			/// Where a cycle-closing scope in the scope's tree calls its builder function, what a scope between binds, first per
			/// label.
			public let cycleReentries: [CycleReentry]
			/// For a fill, the stack of the filled seam's path its tree is built beneath, innermost first; empty otherwise.
			public let fillBaseStack: [StackEntry]
			/// For a fill, the owner of the hole it fills, which declares the next level's property.
			public let fillOwnerType: TypeDescription?
			/// The properties from the enclosing level to this one, as a site's path spells them: the level's property, or, for
			/// a fill, the way to the hole it fills. Empty for the seam's root.
			public let pathSegment: [Property]
			/// The types from the enclosing level to this one, as `Hole.typesToOwner` lists them.
			public let pathTypes: [Hole.PathType]
			/// The levels that can enclose this one, in the order the places first reach them through each.
			public let parents: [Int]
			/// For each of `parents`, the properties the code declares on the way from it, which a diagnostic prints.
			public let declaredSegmentByParent: [[Hole.DeclaredProperty]]
			/// For the level of a scope whose next property is a call that closes a cycle (a builder function the call refers to,
			/// never a child built anew), the entry the call closes on: the nearest build above with that entry on the route. `nil`
			/// on every other level. These levels lead to no place: they are added after every place's and call's, so that the
			/// route a question about a place walks never meets them, and say where a cycle re-enters a scope.
			public let closesOn: StackEntry?
		}

		/// A place another seam's tree holds, which a call in this seam's tree presents: a reference to that seam's case,
		/// never a copy of its levels.
		public struct CalledCase: Codable, Hashable, Sendable {
			public init(seamType: TypeDescription, isPublicMock: Bool, caseIndex: Int) {
				self.seamType = seamType
				self.isPublicMock = isPublicMock
				self.caseIndex = caseIndex
			}

			/// The seam, or the public mock, whose signature holds the place's case.
			public let seamType: TypeDescription
			/// Whether that is another module's public mock, whose plan the run holds in `PublicMockPlans`, rather than a seam.
			public let isPublicMock: Bool
			/// The index of the case in that signature's `places.cases`.
			public let caseIndex: Int
		}

		/// What a run holds of the seam or public mock a passed-up case refers to (`CalledCase`): its place graph, and its
		/// places, which name the places of a case in a message about a declaration bound on the path to a call that presents
		/// them (`Hole.UncarriedDeclaration.Reason.boundByPassingUpSeam`). In memory only: a file stores the reference.
		public struct Called: Sendable {
			public init(places: SeamSignature.Places, holes: [Hole], caseIndexByHole: [Int]) {
				self.places = places
				self.holes = holes
				self.caseIndexByHole = caseIndexByHole
			}

			public let places: SeamSignature.Places
			/// The places of the seam's signature or the public mock's plan, and the case in `places` of each
			/// (`SeamSignature.holes`, `SeamSignature.caseIndexByHole`).
			public let holes: [Hole]
			public let caseIndexByHole: [Int]

			/// The first place, in builder order, of the case at `caseIndex`, which names the case's places; `nil` where no
			/// place is of that case.
			public func hole(ofCaseAt caseIndex: Int) -> Hole? {
				zip(caseIndexByHole, holes).first { $0.0 == caseIndex }?.1
			}
		}

		/// The places of one owner level in one family.
		public struct Case: Codable, Sendable {
			public init(
				ownerLevel: Int,
				isBuiltInSendableFunction: Bool,
				siteOpensSendableFunction: Bool,
				passedUp: CalledCase?,
				firstCasePresentingSamePlaces: Int? = nil,
				isPassedOnSendable: Bool = false,
				calledCopyDeclarations: [Hole.UncarriedDeclaration] = [],
				uncarriedReplacedOnPathsToCalls: [Hole.UncarriedDeclaration] = [],
				reenteringCallDeclarations: [Hole.ReenteringCallDeclaration] = [],
				reenteringPlaceFields: [Hole.ReenteringPlaceField] = [],
				namingRoute: [Int] = [],
				narrowestAccess: Access? = nil,
			) {
				self.namingRoute = namingRoute
				self.narrowestAccess = narrowestAccess
				self.ownerLevel = ownerLevel
				self.isBuiltInSendableFunction = isBuiltInSendableFunction
				self.siteOpensSendableFunction = siteOpensSendableFunction
				self.passedUp = passedUp
				self.firstCasePresentingSamePlaces = firstCasePresentingSamePlaces
				self.isPassedOnSendable = isPassedOnSendable
				self.calledCopyDeclarations = calledCopyDeclarations
				self.uncarriedReplacedOnPathsToCalls = uncarriedReplacedOnPathsToCalls
				self.reenteringCallDeclarations = reenteringCallDeclarations
				self.reenteringPlaceFields = reenteringPlaceFields
			}

			/// The index in `levels` of the owner level of every place of the case, whose next property is the hole's; for a
			/// passed-up place, the level of the call that presents it.
			public let ownerLevel: Int
			/// Whether the places are built inside a `@Sendable` function: the family of the builder that builds them. Only the
			/// routes of that family lead to the case.
			public let isBuiltInSendableFunction: Bool
			/// Whether the places are held in a `Sendable` wrapper, built in a `@Sendable` function of their own.
			public let siteOpensSendableFunction: Bool
			/// For a place a call presents, the inner seam's case it stands for.
			public let passedUp: CalledCase?
			/// For a case of a call that presents places a case before it in `cases` presents too, the first such case: another
			/// call that presents them, or the same call through another case of the seam it calls. `nil` for that first case, and
			/// for a case of the seam's own places. The cases that name one first case, and it, are every call of the seam's tree
			/// that presents the places, so a reader finds them in this graph alone, whichever call each seam's hole is filed
			/// under: two seams that call each other can each present a place first through the other, and then the references
			/// of those two cases lead to each other and never to the seam that holds the place.
			public let firstCasePresentingSamePlaces: Int?
			/// The levels, root first, of the route of the case's first place in builder-label order: the place a name made from a
			/// path, or a diagnostic that names one place, names, as each did when a seam held a hole per site. Stored, since the
			/// order of the places is the generated code's, which the levels' parents do not keep.
			public let namingRoute: [Int]

			// What the calls on the paths to the places, and the fills those paths run through, add to the places, stored per
			// case: they come from calls and fills, which the levels do not hold, and each is bounded by the declarations, not by
			// the paths. Each is the union over the case's places in site order, the first of each equal entry.

			/// Whether a call that presents a place of the case is made inside a `@Sendable` function, or takes the builder
			/// `@Sendable` (`Hole.isSendable`), on any route.
			public let isPassedOnSendable: Bool
			/// The declarations the calls that present the places add to them, and those the copies of the places that the seams
			/// called inside fills on their paths leave uncarried (`SiteAdditions.presenting`, `calledCopyDeclarations`),
			/// appended to the places' own uncarried declarations.
			public let calledCopyDeclarations: [Hole.UncarriedDeclaration]
			/// For a declaration a public mock's root binds from its caller's argument (`isBoundFromCallersArgument`), the
			/// declaration a path to a call that presents the place binds of its label, which stands in its place, by label.
			public let uncarriedReplacedOnPathsToCalls: [Hole.UncarriedDeclaration]
			/// `Hole.reenteringCallDeclarations` of the places.
			public let reenteringCallDeclarations: [Hole.ReenteringCallDeclaration]
			/// `Hole.reenteringPlaceFields` of the places.
			public let reenteringPlaceFields: [Hole.ReenteringPlaceField]
			/// The narrowest access of a builder of the places (`Hole.tierAccess`), with the cause of the first place in site
			/// order that has it (`Hole.accessCause`): what a builder that reaches the case is no wider than. Every place of
			/// a case has one owner level, so one owner type and one property, and so one access; the fold keeps the case's
			/// answer a fact of its places, not of its first. `nil` while no place was added.
			public let narrowestAccess: Access?

			/// The access of a builder of a case's places, and what proves it.
			public struct Access: Codable, Hashable, Sendable {
				public init(level: AccessLevel, cause: TypeAccessProof.Cause?) {
					self.level = level
					self.cause = cause
				}

				public let level: AccessLevel
				public let cause: TypeAccessProof.Cause?
			}
		}

		/// What the places of a case read of a label, on one or more of the routes to the case.
		public enum Answer: Hashable, Sendable {
			/// The scope struct carries the declaration at `level`, index `declaration`, as a field.
			case field(level: Int, declaration: Int)
			/// The declaration is bound after the next property on the route, so it hides the farther declarations of its label
			/// but holds no value there.
			case uncarried(level: Int, declaration: Int)
			/// The declaration is bound outside the innermost `@Sendable` function on the route, the one `functionLevel` opens,
			/// or, where it is `siteFunction`, the `Sendable` wrapper the place is held in.
			case boundOutsideSendableFunction(level: Int, declaration: Int, functionLevel: Int)
			/// Nothing on the route declares the label, or its nearest declaration is a parameter of the seam outside a
			/// `@Sendable` function: a fill reads its caller's own declaration.
			case callersOwn

			/// The `functionLevel` of the `Sendable` wrapper a place is held in.
			public static let siteFunction = -1
		}

		/// A declaration a route reaches, or none: what a fill's field hides, or the nearest declaration of a label at all.
		public enum Reached: Hashable, Sendable {
			case declaration(level: Int, declaration: Int)
			case none
		}

		/// The declaration at `level`, index `declaration`, as the level's scope binds it before its next property.
		public func declaration(level: Int, declaration: Int) -> Declaration {
			declarationLists[levels[level].declarationList][declaration].beforeNextProperty(of: levels[level])
		}

		/// The declarations of `level`, as its scope binds them before its next property.
		public func declarations(ofLevel level: Int) -> [Declaration] {
			declarationLists[levels[level].declarationList].map { $0.beforeNextProperty(of: levels[level]) }
		}

		/// The declarations of `level` as they are before any next property: their labels, properties and order, which no
		/// next property changes.
		public func declarationsBeforeAnyNextProperty(ofLevel level: Int) -> [Declaration] {
			declarationLists[levels[level].declarationList]
		}
	}
}
