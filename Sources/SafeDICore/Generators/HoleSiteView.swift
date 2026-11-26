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

/// What a hole's site emits from, read from the hole its tree's `SeamHoles` holds at the site's path when the site's
/// generator is made: the names, types and values its code spells, and nothing that names the path. A generator two
/// paths share holds one view, so `SeamHoles.positionClass(at:)` keeps two sites apart wherever their views differ.
struct HoleSiteView: Sendable {
	init(_ hole: SeamSignature.Hole) {
		internalName = hole.internalName
		wrapperFunctionName = hole.wrapperFunctionName
		builtType = hole.builtType
		builderLabel = hole.builderLabel
		place = hole.enumPlace.flatMap { enumPlace in
			enumPlace.memberValuesTypeName.map { Place(enumPlace, memberValuesTypeName: $0, builtType: hole.builtType) }
		}
	}

	/// The name the seam's initializer gives the builder of the site's hole type.
	let internalName: String
	/// The name of the function the site builds its wrapper around, where its hole names one.
	let wrapperFunctionName: String?
	/// What the builder returns (`SeamSignature.Hole.builtType`).
	let builtType: TypeDescription
	/// The label of the builder the site's place is built by.
	let builderLabel: String
	/// The site's case nested by type, once its member is known: `nil` in a tree built before the place's case is, where
	/// the site generates nothing.
	let place: Place?

	/// The case nested by type a site calls a member of.
	struct Place: Sendable {
		init(_ enumPlace: SeamSignature.Hole.EnumPlace, memberValuesTypeName: String, builtType: TypeDescription) {
			values = enumPlace.values
			self.memberValuesTypeName = memberValuesTypeName
			enumType = enumPlace.enumType(qualifiedBy: nil)
			caseName = enumPlace.caseName
			isBuiltBySendableBuilder = enumPlace.isBuiltBySendableBuilder
			let lastStep = enumPlace.route.last
			if let member = lastStep?.member {
				parent = lastStep?.innerScope.map { .fillLevelStruct(name: $0.name) } ?? .level(name: member.bindingName, type: member.levelType)
			} else {
				// A level is spelled over the type the builder builds, its innermost generic argument
				// (`ReservedName.levelType(ofEnum:built:)`), which every level of the route spells alike.
				let members = enumPlace.route.lazy.compactMap(\.member)
				let levelBuiltType = members.compactMap(\.levelType.genericArgumentsOfThisAndEnclosingTypes.last).first ?? builtType
				parent = .builder(levelType: ReservedName.levelType(ofEnum: .simple(name: enumPlace.rootEnumTypeName ?? enumPlace.enumTypeName, generics: []), built: levelBuiltType))
			}
		}

		/// The values the site hands its member: what its owner binds before it.
		let values: [SeamSignature.Hole.Field]
		/// The payload struct of the place's case.
		let memberValuesTypeName: String
		/// The enum that holds the place's case, unqualified.
		let enumType: TypeDescription
		let caseName: String
		let isBuiltBySendableBuilder: Bool
		/// The struct the site calls its member on.
		let parent: Parent

		enum Parent: Sendable {
			/// The builder itself, the struct of the root level, of `levelType`.
			case builder(levelType: TypeDescription)
			/// The level the last case on the site's route returned, bound as `name`.
			case level(name: String, type: TypeDescription)
			/// The struct of a fill's own level, which the fill is handed as `name`, typed by no binding of the tree.
			case fillLevelStruct(name: String)
		}
	}
}
