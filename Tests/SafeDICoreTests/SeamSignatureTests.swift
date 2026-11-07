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

import Testing
@testable import SafeDICore

struct SeamSignatureTests {
	@Test
	func mirror_listsOnlyClassifiedStoredProperties_whenReflectingParameterAndReceiver() {
		// A stored property added to either type fails here until it is classified below, and the classification is
		// checked against the projections by the next two tests.
		#expect(Mirror(reflecting: Self.parameter).children.compactMap(\.label) == Self.parameterClassification.map(\.label))
		#expect(Mirror(reflecting: Self.receiver).children.compactMap(\.label) == Self.receiverClassification.map(\.label))
	}

	@Test
	func projections_changeExactlyAsClassified_whenOneStoredPropertyOfParameterChanges() {
		for (label, projection) in Self.parameterClassification {
			let changed = Self.parameter(changing: label)
			#expect((Self.callShape(of: changed) != Self.callShape(of: Self.parameter)) == (projection == .callShapeAndSettledContent), "\(label)")
			#expect((Self.settledContent(of: changed) != Self.settledContent(of: Self.parameter)) == (projection != .neither), "\(label)")
			// The guard hashes exactly the parameter's fields of the call shape.
			#expect((Self.signature(of: changed).guardTypeName != Self.signature(of: Self.parameter).guardTypeName) == (projection == .callShapeAndSettledContent), "\(label)")
		}
	}

	@Test
	func projections_changeExactlyAsClassified_whenOneStoredPropertyOfReceiverChanges() {
		for (label, projection) in Self.receiverClassification {
			let changed = Self.parameter(withReceiver: Self.receiver(changing: label))
			#expect((Self.callShape(of: changed) != Self.callShape(of: Self.parameter)) == (projection == .callShapeAndSettledContent), "\(label)")
			#expect((Self.settledContent(of: changed) != Self.settledContent(of: Self.parameter)) == (projection != .neither), "\(label)")
		}
	}

	@Test
	func guardTypeName_isUnchanged_whenOnlyTiersChange() {
		// Both sides derive the tiers from the parameters' tier accesses, which the guard hashes, and from the level of
		// the seam's own initializer, which both read from the seam's declaration.
		let signature = SeamSignature(seamType: .simple(name: "Screen"), parameters: [Self.parameter], tiers: [.public, .internal])
		let otherTiers = SeamSignature(seamType: .simple(name: "Screen"), parameters: [Self.parameter], tiers: [.internal])
		#expect(signature.callShape != otherTiers.callShape)
		#expect(signature.guardTypeName == otherTiers.guardTypeName)
	}

	// MARK: Private

	/// What a comparison for meaning sees of a stored property.
	private enum Projection {
		/// The call shape, and so the guard, and the settled content.
		case callShapeAndSettledContent
		/// The settled content alone.
		case settledContent
		/// Neither: diagnostic payload.
		case neither
	}

	private static let parameterClassification: [(label: String, projection: Projection)] = [
		("property", .callShapeAndSettledContent),
		("isPassThrough", .settledContent),
		("access", .settledContent),
		// Derived from the declarations the signature is computed from, as `access` is, which the settled content holds:
		// what a diagnostic says about the access.
		("accessCause", .neither),
		("tierAccess", .callShapeAndSettledContent),
		("isOnlyIfAvailable", .callShapeAndSettledContent),
		("receivers", .settledContent),
		// Derived from the nested seam calls the receivers come through, which the settled content holds by their tiers:
		// what a diagnostic about a parameter on no tier names.
		("nestedSeamCall", .neither),
		// Derived from the declarations the signature is computed from, as `access` is: whether a diagnostic offers to
		// widen the seam's own initializer.
		("otherInitializerArgumentsAccess", .neither),
	]

	private static let receiverClassification: [(label: String, projection: Projection)] = [
		("property", .settledContent),
		// Derived from the receiver's declaration – the alias whose fulfilling property the receiver is – so it changes
		// only with `property` and `declaringType`, which the settled content holds.
		("aliasProperty", .neither),
		("declaringType", .settledContent),
		("declarationLocation", .neither),
		("access", .settledContent),
		// Derived from the receiver's declaration – whether the declaring type is extension-based – so it changes only
		// with `declaringType`, which the settled content holds.
		("isInstantiateMethodParameter", .neither),
	]

	private static let receiver = SeamSignature.Receiver(
		property: Property(label: "user", typeDescription: .optional(.simple(name: "User"))),
		declaringType: .simple(name: "Reader"),
		declarationLocation: .init(filePath: "Reader.swift", line: 7, column: 5),
		access: .internal,
	)

	private static let parameter = parameter(withReceiver: receiver)

	private static func parameter(withReceiver receiver: SeamSignature.Receiver) -> SeamSignature.Parameter {
		SeamSignature.Parameter(property: Property(label: "user", typeDescription: .optional(.simple(name: "User"))), isPassThrough: true, access: .public, tierAccess: .internal, isOnlyIfAvailable: true, receivers: [receiver])
	}

	private static func parameter(changing label: String) -> SeamSignature.Parameter {
		let parameter = parameter
		return SeamSignature.Parameter(
			property: label == "property" ? Property(label: "name", typeDescription: .optional(.simple(name: "User"))) : parameter.property,
			isPassThrough: label == "isPassThrough" ? false : parameter.isPassThrough,
			access: label == "access" ? .package : parameter.access,
			tierAccess: label == "tierAccess" ? .package : parameter.tierAccess,
			isOnlyIfAvailable: label == "isOnlyIfAvailable" ? false : parameter.isOnlyIfAvailable,
			receivers: label == "receivers" ? [] : parameter.receivers,
			accessCause: label == "accessCause" ? .unproven(type: .simple(name: "User")) : parameter.accessCause,
			nestedSeamCall: label == "nestedSeamCall" ? SeamSignature.NestedSeamCall(seamType: .simple(name: "Service"), seamModuleName: "Base", tier: .public, requirement: .public, callerModuleName: "Mid", parameterTierAccess: .package, receivingTypes: [.simple(name: "Badge")]) : parameter.nestedSeamCall,
			otherInitializerArgumentsAccess: label == "otherInitializerArgumentsAccess" ? .package : parameter.otherInitializerArgumentsAccess,
		)
	}

	private static func receiver(changing label: String) -> SeamSignature.Receiver {
		SeamSignature.Receiver(
			property: label == "property" ? Property(label: "user", typeDescription: .simple(name: "User")) : receiver.property,
			declaringType: label == "declaringType" ? .simple(name: "Writer") : receiver.declaringType,
			declarationLocation: label == "declarationLocation" ? .init(filePath: "Reader.swift", line: 8, column: 5) : receiver.declarationLocation,
			access: label == "access" ? .public : receiver.access,
			aliasProperty: label == "aliasProperty" ? Property(label: "authToken", typeDescription: .simple(name: "Token")) : receiver.aliasProperty,
			isInstantiateMethodParameter: label == "isInstantiateMethodParameter" ? true : receiver.isInstantiateMethodParameter,
		)
	}

	private static func signature(of parameter: SeamSignature.Parameter) -> SeamSignature {
		SeamSignature(seamType: .simple(name: "Screen"), parameters: [parameter], tiers: [.public])
	}

	private static func callShape(of parameter: SeamSignature.Parameter) -> SeamSignature.CallShape {
		signature(of: parameter).callShape
	}

	private static func settledContent(of parameter: SeamSignature.Parameter) -> SeamSignature.SettledContent {
		signature(of: parameter).settledContent
	}
}
