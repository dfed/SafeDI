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
		public init(levels: [Level], cases: [Case]) {
			self.levels = levels
			self.cases = cases
		}

		/// The levels, in the order the seam's places first reach them. The seam's root is the one level with no parent.
		public let levels: [Level]
		/// The cases, in the order the seam's places first reach them.
		public let cases: [Case]

		/// Which level of which type a level is. A build of one type before one property is one key, however many paths reach
		/// it.
		public struct LevelKey: Codable, Hashable, Sendable {
			public init(builtType: TypeDescription?, nextProperty: Property?, isSeamRoot: Bool, isInFill: Bool, filledType: TypeDescription?) {
				self.builtType = builtType
				self.nextProperty = nextProperty
				self.isSeamRoot = isSeamRoot
				self.isInFill = isInFill
				self.filledType = filledType
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
		public struct SendableFunctionOpened: Codable, Sendable {
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
		public struct FillFieldHiding: Codable, Sendable {
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
		public struct Buildability: Codable, Sendable {
			public init(labelsHeldAboveSeam: Set<String>, placesInTree: [Int]) {
				self.labelsHeldAboveSeam = labelsHeldAboveSeam
				self.placesInTree = placesInTree
			}

			/// The labels the seam's caller would hold (`Hole.UncarriedDeclaration.labelsHeldAboveSeam`).
			public let labelsHeldAboveSeam: Set<String>
			/// The indices in `cases` of the cases of the places the tree holds or passes up, in the order the tree reaches them.
			public let placesInTree: [Int]
		}

		/// A declaration of a level, with everything any place beneath reads of it.
		public struct Declaration: Codable, Sendable {
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

			/// Whether it is a parameter of the seam, which a place inside a `@Sendable` function reads from its caller's scope.
			public var isSeamParameter: Bool {
				field.isSeamParameter
			}
		}

		/// What a scope between a closed-on level and one of its cycle-closing scopes declares, which the cycle hands the
		/// type built again (`Hole.CycleReentryDeclaration`, whose `closedOnDeclaringType` is the type that declares the
		/// level's own property, read from the route).
		public struct CycleReentry: Codable, Sendable {
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
				declarations: [Declaration],
				opensSendableFunction: SendableFunctionOpened?,
				cycleReentries: [CycleReentry],
				fillBaseStack: [StackEntry],
				fillOwnerType: TypeDescription?,
				pathSegment: [Property],
				pathTypes: [Hole.PathType],
				parents: [Int],
				declaredSegmentByParent: [[Hole.DeclaredProperty]],
			) {
				self.key = key
				self.declarations = declarations
				self.opensSendableFunction = opensSendableFunction
				self.cycleReentries = cycleReentries
				self.fillBaseStack = fillBaseStack
				self.fillOwnerType = fillOwnerType
				self.pathSegment = pathSegment
				self.pathTypes = pathTypes
				self.parents = parents
				self.declaredSegmentByParent = declaredSegmentByParent
			}

			public let key: LevelKey
			/// The declarations, in the order the scope binds them: for the seam's root, its parameters, then its children; for
			/// any other type, its forwarded properties, its loop's rebindings and its cycle parameters, then its children; for a
			/// fill, the declarations the filled seam's struct does not carry, then the fields it binds.
			public let declarations: [Declaration]
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
		}

		/// A place another seam's tree holds, which a call in this seam's tree presents: a reference to that seam's case,
		/// never a copy of its levels.
		public struct PassedUpReference: Codable, Sendable {
			public init(innerSeamType: TypeDescription, innerIsPublicMock: Bool, innerCaseIndex: Int) {
				self.innerSeamType = innerSeamType
				self.innerIsPublicMock = innerIsPublicMock
				self.innerCaseIndex = innerCaseIndex
			}

			/// The seam, or the public mock, whose signature holds the place's case.
			public let innerSeamType: TypeDescription
			/// Whether that is another module's public mock, whose plan the run holds in `PublicMockPlans`, rather than a seam.
			public let innerIsPublicMock: Bool
			/// The index of the case in that signature's `places.cases`.
			public let innerCaseIndex: Int
		}

		/// The places of one owner level in one family.
		public struct Case: Codable, Sendable {
			public init(ownerLevel: Int, isBuiltInSendableFunction: Bool, siteOpensSendableFunction: Bool, passedUp: PassedUpReference?) {
				self.ownerLevel = ownerLevel
				self.isBuiltInSendableFunction = isBuiltInSendableFunction
				self.siteOpensSendableFunction = siteOpensSendableFunction
				self.passedUp = passedUp
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
			public let passedUp: PassedUpReference?
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

		/// The declaration at `level`, index `declaration`.
		public func declaration(level: Int, declaration: Int) -> Declaration {
			levels[level].declarations[declaration]
		}
	}
}
