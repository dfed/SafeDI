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

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// How SafeDITool writes its scan cache and `.safedi` module info files and reads them back, verified on files written for real sources.
struct SafeDIToolBinaryFileTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Round trip

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_readsBackEverythingScanWrote_whenSourcesUseEveryCachedShape() async throws {
		let project = try await scannedKitchenSinkProject()

		#expect(try reflectedDescription(of: project.readCache()) == reflectedDescription(of: project.scannedModuleInfo))
	}

	@Test
	func binaryReader_readsBackEachStringsOwnBytes_whenStringsAreCanonicallyEquivalent() throws {
		// `String`'s `==` and hashing treat canonically equivalent spellings as one string, but Swift compares
		// identifiers byte for byte, so the two spellings of `café` are two different labels.
		var writer = BinaryWriter()
		writer.write([Self.precomposedCafe, Self.decomposedCafe])
		let encoded = writer.encoded

		let strings = try encoded.withUnsafeBytes { bytes in
			var reader = try BinaryReader(bytes: bytes)
			let strings: [String] = try reader.read()
			try reader.finish()
			return strings
		}

		#expect(strings.map { Array($0.utf8) } == [Array(Self.precomposedCafe.utf8), Array(Self.decomposedCafe.utf8)])
	}

	@Test
	func binaryWriter_writesSharedValueOnce_whenValueRepeats() throws {
		var writer = BinaryWriter()
		writer.write([BinaryShared(["a", "b"]), BinaryShared(["c"]), BinaryShared(["a", "b"])])
		let encoded = writer.encoded

		let values = try encoded.withUnsafeBytes { bytes in
			var reader = try BinaryReader(bytes: bytes)
			let values: [BinaryShared<[String]>] = try reader.read()
			try reader.finish()
			return values
		}

		// The string table (three strings), then three elements: the first two written in full, the third a reference
		// to the first.
		#expect(encoded == [3, 1, 97, 1, 98, 1, 99] + [3, 0, 2, 0, 1, 0, 1, 2, 1])
		#expect(values.map(\.value) == [["a", "b"], ["c"], ["a", "b"]])
	}

	@Test
	func binaryWriter_writesEachSpellingOfPlaces_whenPlacesDifferOnlyInAny() throws {
		// `==` calls `any Service` and `Service` equal, but each list of places reads back as written.
		let places = [TypeDescription.any(.simple(name: "Service")), .simple(name: "Service"), .any(.simple(name: "Service"))].map { type in
			BinaryShared([SeamSignature.Hole.Site(seamType: .simple(name: "Host"), path: [Property(label: "service", typeDescription: type)])])
		}
		var writer = BinaryWriter()
		writer.write(places)

		let readPlaces = try writer.encoded.withUnsafeBytes { bytes in
			var reader = try BinaryReader(bytes: bytes)
			let readPlaces: [BinaryShared<[SeamSignature.Hole.Site]>] = try reader.read()
			try reader.finish()
			return readPlaces
		}

		#expect(readPlaces.map { $0.value.map { $0.path.map(\.typeDescription.asSource) } } == [[["any Service"]], [["Service"]], [["any Service"]]])
	}

	@Test
	func binaryReader_throws_whenSharedValueReferenceComesBeforeTheValue() {
		// An empty string table, then a reference to the first shared value, which no value before it holds.
		let bytes: [UInt8] = [0, 1]

		#expect(throws: BinaryDecodingError.sharedValueReferenceOutOfRange(reference: 1, offset: 1)) {
			try bytes.withUnsafeBytes { bytes in
				var reader = try BinaryReader(bytes: bytes)
				let _: BinaryShared<[String]> = try reader.read()
			}
		}
	}

	@Test
	func binaryWriter_writesEachTypeDescriptionOnce_whenSharingTypeDescriptionsAndKeepsSpellingsEqualityIgnores() throws {
		// `==` calls `any Service` and `Service` equal, but each reads back as written.
		let types: [TypeDescription] = [
			.any(.simple(name: "Service")),
			.simple(name: "Service"),
			.any(.simple(name: "Service")),
			.simple(name: "Service"),
		]
		var writer = BinaryWriter()
		writer.write(BinarySharingSignatureValues(types))
		let encoded = writer.encoded

		let readTypes = try encoded.withUnsafeBytes { bytes in
			var reader = try BinaryReader(bytes: bytes)
			let readTypes: BinarySharingSignatureValues<[TypeDescription]> = try reader.read()
			try reader.finish()
			return readTypes.value
		}

		#expect(readTypes.map(\.asSource) == ["any Service", "Service", "any Service", "Service"])
		// The string table, then four elements: two written in full, then a reference to each.
		#expect(encoded.count == Self.encoded(Array(types.prefix(2))).count + 2 + 2)
	}

	@Test
	func binaryWriter_writesEachHoleFieldOnce_whenSharingSignatureValues() throws {
		let fields = try [false, true, false, true].map { isDistinct in try SeamSignature.Hole.Field.sample(isDistinct: isDistinct) }
		var writer = BinaryWriter()
		writer.write(BinarySharingSignatureValues(fields))
		let encoded = writer.encoded

		let readFields: BinarySharingSignatureValues<[SeamSignature.Hole.Field]> = try read(encoded)

		#expect(Self.encoded(readFields.value) == Self.encoded(fields))
		// The string table, then four elements: two written in full, then a reference to each.
		#expect(encoded.count == Self.encoded(Array(fields.prefix(2))).count + 2 + 2)
	}

	@Test
	func binaryWriter_writesEachUncarriedDeclarationReasonOnce_whenSharingSignatureValues() throws {
		let reasons = try [false, true, false, true].map { isDistinct in try SeamSignature.Hole.UncarriedDeclaration.Reason.sample(isDistinct: isDistinct) }
		var writer = BinaryWriter()
		writer.write(BinarySharingSignatureValues(reasons))
		let encoded = writer.encoded

		let readReasons: BinarySharingSignatureValues<[SeamSignature.Hole.UncarriedDeclaration.Reason]> = try read(encoded)

		#expect(Self.encoded(readReasons.value) == Self.encoded(reasons))
		// The string table, then four elements: two written in full, then a reference to each.
		#expect(encoded.count == Self.encoded(Array(reasons.prefix(2))).count + 2 + 2)
	}

	@Test
	func binaryReader_readsRepeatedPlaces_whenPlacesHoldTypeDescriptionNotSeenBefore() throws {
		// The first list of places is the first to name `Service`, so its type is read, and takes its index, before the
		// list does. The second list refers to the first.
		let site = SeamSignature.Hole.Site(seamType: .simple(name: "Service"), path: [])
		let places = [BinaryShared([site]), BinaryShared([site])]
		var writer = BinaryWriter()
		writer.write(BinarySharingSignatureValues(places))

		let readPlaces = try writer.encoded.withUnsafeBytes { bytes in
			var reader = try BinaryReader(bytes: bytes)
			let readPlaces: BinarySharingSignatureValues<[BinaryShared<[SeamSignature.Hole.Site]>]> = try reader.read()
			try reader.finish()
			return readPlaces.value
		}

		#expect(readPlaces.map(\.value) == [[site], [site]])
	}

	@Test
	func binaryReader_throws_whenSharedTypeDescriptionReferenceComesBeforeTheType() {
		// An empty string table, then one element whose type refers to the first shared value, which no value before it
		// holds.
		let bytes: [UInt8] = [0, 1, 1]

		#expect(throws: BinaryDecodingError.sharedValueReferenceOutOfRange(reference: 1, offset: 2)) {
			try bytes.withUnsafeBytes { bytes in
				var reader = try BinaryReader(bytes: bytes)
				let _: BinarySharingSignatureValues<[TypeDescription]> = try reader.read()
			}
		}
	}

	@Test
	func writingStringsInline_writesSameBytesForTwoValues_exactlyWhenWriterWithTableDoes() {
		// Merging module infos compares two entries for one module by the bytes a writer that writes each string in
		// place writes, which must tell the entries apart exactly when the bytes of the file do: the order in which
		// strings first appear, a string's own bytes, and every value besides strings.
		let values: [[String]] = [
			["Clock", "Calendar", "Clock"],
			["Calendar", "Clock", "Calendar"],
			["Clock", "Calendar", "Calendar"],
			["Clock", "Calendar"],
			[Self.precomposedCafe, Self.decomposedCafe],
			[Self.decomposedCafe, Self.precomposedCafe],
			[Self.precomposedCafe, Self.precomposedCafe],
			["ab", "c"],
			["a", "bc"],
			[],
		]
		func tableBytes(of value: [String]) -> [UInt8] {
			var writer = BinaryWriter()
			writer.write(value)
			return writer.encoded
		}
		func inlineBytes(of value: [String]) -> [UInt8] {
			var writer = BinaryWriter.writingStringsInline()
			writer.write(value)
			return writer.bytes
		}

		for first in values {
			for second in values {
				#expect((inlineBytes(of: first) == inlineBytes(of: second)) == (tableBytes(of: first) == tableBytes(of: second)))
				#expect((inlineBytes(of: first) == inlineBytes(of: second)) == (first.map { Array($0.utf8) } == second.map { Array($0.utf8) }))
			}
		}
	}

	@Test
	func binaryFileReadError_explains_whenBodyRefersToSharedValueNotYetRead() {
		let error = BinaryFileReadError(kind: .moduleInfo, reason: .malformedBody(.sharedValueReferenceOutOfRange(reference: 3, offset: 12)))

		#expect(error.description == "The module info file’s body refers to shared value 3 at byte 12, which no value before it holds.")
	}

	@Test
	func binaryReader_throws_whenFieldFlagsHoldAFlagNoFieldReads() throws {
		// A viewed module's identity has two optional fields, so a third flag is one it does not read.
		var writer = BinaryWriter()
		try writer.write(ViewedModuleIdentity.sample(isDistinct: false))
		var bytes = writer.encoded
		let flagsOffset = bytes.count - writer.bytes.count
		bytes[flagsOffset] |= 0b100

		#expect(throws: BinaryDecodingError.unreadFieldFlags(offset: flagsOffset)) {
			let _: ViewedModuleIdentity = try read(bytes)
		}
	}

	@Test
	func binaryFileReadError_explains_whenBodyHoldsFieldFlagNoFieldReads() {
		let error = BinaryFileReadError(kind: .moduleInfo, reason: .malformedBody(.unreadFieldFlags(offset: 7)))

		#expect(error.description == "The module info file’s body holds a field flag at byte 7 that no field reads.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesEachSpellingOfLabel_whenLabelsAreCanonicallyEquivalentAndGenerateReadsScanCache() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(first: First, second: Second) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: First
				    @Instantiated let second: Second
				}
				""",
				"""
				@Instantiable
				public struct First: Instantiable {
				    public init(\(Self.precomposedCafe): Service) {
				        self.\(Self.precomposedCafe) = \(Self.precomposedCafe)
				    }

				    @Instantiated let \(Self.precomposedCafe): Service
				}
				""",
				"""
				@Instantiable
				public struct Second: Instantiable {
				    public init(\(Self.decomposedCafe): Service) {
				        self.\(Self.decomposedCafe) = \(Self.decomposedCafe)
				    }

				    @Instantiated let \(Self.decomposedCafe): Service
				}
				""",
				"""
				@Instantiable
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let expectedRootFile = """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public init() {
		        func __safeDI_first() -> First {
		            let \(Self.precomposedCafe) = Service()
		            return First(\(Self.precomposedCafe): \(Self.precomposedCafe))
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let \(Self.decomposedCafe) = Service()
		            return Second(\(Self.decomposedCafe): \(Self.decomposedCafe))
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		"""
		// `String`'s `==` would call the two spellings equal, so compare bytes.
		#expect(try Array(#require(output.generatedFiles?["Root+SafeDI.swift"]).utf8) == Array(expectedRootFile.utf8))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_exercisesEveryTagOfEveryCachedEnumeration_whenSourcesUseEveryCachedShape() async throws {
		// The round trip above proves each tag reads back as the case that wrote it only for the tags these sources produce.
		let project = try await scannedKitchenSinkProject()
		var writtenTagsByType = [String: Set<UInt8>]()
		for case let value as any BinarySchemaMember in reflectedStructuresAndEnumerations(in: project.scannedModuleInfo)
			where Mirror(reflecting: value).displayStyle == .enum
		{
			var writer = BinaryWriter()
			writer.write(value)
			writtenTagsByType[String(reflecting: type(of: value)), default: []].insert(writer.bytes[0])
		}

		#expect(writtenTagsByType.count == 7)
		for schemaMember in BinaryFile.schemaMembers where writtenTagsByType[String(reflecting: schemaMember)] != nil {
			#expect(writtenTagsByType[String(reflecting: schemaMember)] == Set(0..<UInt8(Self.caseCount(of: schemaMember))), "\(schemaMember)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCacheSchema_listsEveryStoredPropertyOfEveryCachedStruct() async throws {
		// A stored property added to a cached type without being listed in its `binaryLayout` fails here, which
		// is the reminder to write and read it too. Listing it changes the schema fingerprint, so caches written
		// before the change are not read after it.
		let project = try await scannedKitchenSinkProject()
		// A module info file holds the module's declarations, as the cache does, and a view of other modules'.
		let moduleInfoFile = ModuleInfoFile(module: project.scannedModuleInfo.moduleInfo, moduleName: "Kitchen", seamSignatures: [], view: .empty)
		let moduleInfoFileWithView = ModuleInfoFile(
			module: project.scannedModuleInfo.moduleInfo,
			moduleName: "Sink",
			seamSignatures: [],
			view: ModuleInfoView(
				moduleGraph: [moduleInfoFile.ownIdentity],
				declarations: [moduleInfoFile.ownEntry],
				references: [ViewedModuleReference(moduleName: "Kitchen", checksum: 1)],
			),
		)
		var foundTypeNames = Set<String>()
		for value in Self.cachedStructuresAndEnumerations(in: project.scannedModuleInfo) + Self.cachedStructuresAndEnumerations(in: moduleInfoFileWithView) {
			let typeName = String(reflecting: type(of: value))
			foundTypeNames.insert(typeName)
			guard let schemaMember = value as? any BinarySchemaMember else {
				Issue.record("\(typeName) is cached but is not one of `BinaryFile.schemaMembers`")
				continue
			}
			if Mirror(reflecting: value).displayStyle == .struct {
				Self.expectLayoutListsEveryStoredProperty(of: schemaMember)
			}
		}

		// A kitchen sink of declarations computes no seam's signature, whose types `seamSignatureSchema_listsEveryStoredPropertyOfEverySignatureStruct` checks.
		#expect(Set(BinaryFile.schemaMembers.map { String(reflecting: $0) }) == foundTypeNames.union(Self.seamSignatureMembers.map { String(reflecting: $0) }))
	}

	@Test
	func moduleInfoDataWritingSeamSignaturesWithoutPositions_writesWhatModuleInfoDataWritesOfTheSignaturesWithoutPositions_whenTheSignaturesCarryPositions() throws {
		// A run writes the signatures it computed, which carry their declarations' positions, without making their
		// copies without positions: the bytes must be those the copies wrote.
		// A distinct sample holds a value in each optional field it declares, so its hole and receiver carry positions.
		var signatureWriter = BinaryWriter()
		try signatureWriter.write(TypeDescription.sample(isDistinct: true))
		try signatureWriter.write([SeamSignature.Parameter(property: Property.sample(isDistinct: true), isPassThrough: false, access: .public, isOnlyIfAvailable: false, receivers: [SeamSignature.Receiver.sample(isDistinct: true)])])
		signatureWriter.write([AccessLevel]())
		signatureWriter.write([SeamSignature.Parameter]())
		try signatureWriter.write([SeamSignature.Hole.sample(isDistinct: true)])
		signatureWriter.write([SeamSignature.Builder]())
		signatureWriter.write([SeamSignature.ScopeEnum]())
		signatureWriter.write([SeamSignature.CallRoute]())
		signatureWriter.write(Set<TypeDescription>())
		let signature: SeamSignature = try read(signatureWriter.encoded)
		let signatures = try [StoredSeamSignature(seamType: TypeDescription.sample(isDistinct: true), signature: signature), StoredSeamSignature.sample(isDistinct: false)]
		func file(holding seamSignatures: [StoredSeamSignature]) -> ModuleInfoFile {
			ModuleInfoFile(
				moduleName: "Module",
				packageName: nil,
				dependencyModuleNames: [],
				imports: [],
				mockImports: [],
				instantiables: [],
				configurations: [],
				filesWithUnexpectedNodes: nil,
				conditionalCompilationDecisions: [],
				instantiableTypeNamesInAnyClause: [],
				plainTypeDeclarations: [],
				seamSignatures: seamSignatures,
				view: .empty,
			)
		}
		// The body `moduleInfoData` wrote of copies of these signatures with every position `nil`, captured when SafeDITool
		// still made those copies. The comparison leaves out the header, whose schema fingerprint every layout change moves.
		let bodyWithoutPositions: [UInt8] = [
			0x04, 0x06, 0x4D, 0x6F, 0x64, 0x75, 0x6C, 0x65, 0x00, 0x08, 0x64, 0x69, 0x73, 0x74, 0x69, 0x6E,
			0x63, 0x74, 0x11, 0x5F, 0x5F, 0x73, 0x61, 0x66, 0x65, 0x44, 0x49, 0x5F, 0x64, 0x69, 0x73, 0x74,
			0x69, 0x6E, 0x63, 0x74, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x02, 0x00, 0x01, 0x01, 0x00, 0x01, 0x01, 0x01, 0x02, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
			0x01, 0x02, 0x01, 0x01, 0x00, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x03, 0x01,
			0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x02, 0x01, 0x01, 0x00, 0x01, 0x01, 0x01, 0x02, 0x01, 0x01,
			0x02, 0x00, 0x00, 0x01, 0x01, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x01, 0x02, 0x01, 0x01, 0x01,
			0x01, 0x01, 0x01, 0x02, 0x00, 0x02, 0x01, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
			0x01, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x01, 0x01, 0x00, 0x02, 0x00, 0x01, 0x01, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x02, 0x00, 0x00, 0x01, 0x02,
			0x02, 0x02, 0x02, 0x01, 0x01, 0x02, 0x02, 0x00, 0x02, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x00,
			0x02, 0x01, 0x02, 0x02, 0x02, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x01, 0x03, 0x02, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x00, 0x01, 0x02, 0x02, 0x02, 0x02, 0x01,
			0x02, 0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x02, 0x00, 0x02, 0x02,
			0x01, 0x02, 0x01, 0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
			0x00,
		]
		// A module info file's header is its first 30 bytes.
		let headerLength = 30
		// The samples carry positions, so writing them as they are writes other bytes.
		#expect(try Array(file(holding: signatures).moduleInfoData.dropFirst(headerLength)) != bodyWithoutPositions)
		#expect(try Array(file(holding: signatures).moduleInfoDataWritingSeamSignaturesWithoutPositions.dropFirst(headerLength)) == bodyWithoutPositions)
	}

	@Test
	func seamSignatureSchema_listsEveryStoredPropertyOfEverySignatureStruct() throws {
		// A stored property added to a type a seam's signature holds without being listed in its `binaryLayout` fails
		// here: every module that calls the seam reads the signature its module's run wrote, so a property left
		// unwritten would reach the callers empty.
		for member in Self.seamSignatureMembers {
			guard let sampleType = member as? any BinarySample.Type else {
				Issue.record("\(member) has no sample value")
				continue
			}
			let sample = try sampleType.sample(isDistinct: true)
			if Mirror(reflecting: sample).displayStyle == .struct, let schemaMember = sample as? any BinarySchemaMember {
				Self.expectLayoutListsEveryStoredProperty(of: schemaMember)
			}
		}
	}

	/// The types a module info file writes only inside the signature of a seam its module declares.
	private static let seamSignatureMembers: [any BinarySchemaMember.Type] = [
		StoredSeamSignature.self,
		SeamSignature.self,
		SeamSignature.Receiver.self,
		SeamSignature.NestedSeamCall.self,
		SeamSignature.Parameter.self,
		SeamSignature.Parameter.Deferral.self,
		SeamSignature.Hole.self,
		SeamSignature.Hole.Field.self,
		SeamSignature.Hole.Field.SeamParameterOrigin.self,
		SeamSignature.Hole.UncarriedDeclaration.self,
		SeamSignature.Hole.UncarriedDeclaration.Reason.self,
		SeamSignature.Hole.UncarriedDeclaration.SendableFunction.self,
		SeamSignature.Hole.UncarriedDeclaration.AliasOrigin.self,
		SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin.self,
		SeamSignature.Hole.UncarriedDeclaration.PresentedPlace.self,
		SeamSignature.Hole.CycleReentryDeclaration.self,
		SeamSignature.Hole.ReenteringCallDeclaration.self,
		SeamSignature.Hole.FieldOfReenteringPlace.self,
		SeamSignature.Hole.ReenteringPlaceField.self,
		SeamSignature.Hole.DeclarationHiddenByField.self,
		SeamSignature.Hole.PathType.self,
		SeamSignature.Hole.EnumPlace.self,
		SeamSignature.Hole.RouteStep.self,
		SeamSignature.Hole.RouteStep.Member.self,
		SeamSignature.Hole.RouteStep.Values.self,
		SeamSignature.Hole.RouteStep.InnerScope.self,
		SeamSignature.Hole.DeclaredProperty.self,
		SeamSignature.Hole.Site.self,
		SeamSignature.CallRoute.self,
		SeamSignature.HoleType.self,
		SeamSignature.ScopeEnum.self,
		SeamSignature.ScopeEnum.Key.self,
		SeamSignature.ScopeEnum.Values.self,
		SeamSignature.ScopeEnum.Case.self,
		SeamSignature.ScopeEnum.Case.Kind.self,
		SeamSignature.Builder.self,
		TypeAccessProof.Cause.self,
		TypeAccessProof.Prover.self,
		TypeAccessProof.MemberKind.self,
		ModuleIdentity.self,
		AccessRequirement.self,
	]

	@Test
	func binaryLayout_matchesBytesEachCachedStructWritesAndReads_whenEachFieldInTurnHoldsADistinctValue() throws {
		// The schema fingerprint describes each struct by its layout, so a layout that lists fields in another
		// order or of other types than the struct writes and reads them would let a file written one way be read
		// another. A struct whose fields all hold the same value would write the same bytes in either order, so
		// each field in turn holds a value that differs from every other field's.
		for schemaMember in BinaryFile.schemaMembers {
			try Self.expectStructureLayoutMatchesCoder(of: schemaMember)
		}
	}

	@Test
	func binaryLayout_matchesBytesEachCachedEnumerationWritesAndReads_whenEachAssociatedValueInTurnIsDistinct() throws {
		// The schema fingerprint describes each enum by the payload of each case, so a layout that lists an
		// associated value in another order or of another type than the enum writes and reads it would let a file
		// written one way be read another.
		for schemaMember in BinaryFile.schemaMembers {
			try Self.expectEnumerationLayoutMatchesCoder(of: schemaMember)
		}
	}

	@Test
	func schemaDescription_describesTypeOfEveryFieldAndPayloadInWriteOrder() {
		let lines = BinaryFile.schemaDescription.split(separator: "\n").map(String.init)

		#expect(lines.contains("SafeDICore.SafeDIConfiguration: additionalImportedModules: Swift.Array<Swift.String>, additionalDirectoriesToInclude: Swift.Array<Swift.String>, additionalMocksToGenerate: Swift.Array<Swift.String>, mockConditionalCompilation: Swift.Optional<Swift.String>, generatePlainDependencyTreeInitializers: Swift.Bool, declarationLocation: Swift.Optional<SafeDICore.Dependency.DeclarationLocation>, sourceFilePath: Swift.Optional<Swift.String>"))
		#expect(lines.contains("SafeDICore.Dependency.Source: instantiated(fulfillingTypeDescription: Swift.Optional<SafeDICore.TypeDescription>, erasedToConcreteExistential: Swift.Bool), received(onlyIfAvailable: Swift.Bool), aliased(fulfillingProperty: SafeDICore.Property, erasedToConcreteExistential: Swift.Bool, onlyIfAvailable: Swift.Bool), forwarded"))
	}

	@Test
	func schemaFingerprint_isChecksumOfSchemaDescription() {
		// The fingerprint is checked in, because describing the schema by reflection scans the runtime's
		// protocol conformance tables, which cost most of a small module's `generate`. A change to how a stored
		// type is written changes the description, and so fails here until the fingerprint is updated.
		let fingerprintOfSchemaDescription = Array(BinaryFile.schemaDescription.utf8).withUnsafeBytes(BinaryFile.checksum(of:))

		#expect(
			BinaryFile.schemaFingerprint == fingerprintOfSchemaDescription,
			"The layout of a type SafeDITool's files hold changed. Set `BinaryFile.schemaFingerprint` to 0x\(String(fingerprintOfSchemaDescription, radix: 16, uppercase: true)).",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_writesIdenticalCache_whenScanningUnchangedSourcesTwice() async throws {
		let project = try await scannedKitchenSinkProject()
		let firstCache = try Data(contentsOf: project.cacheURL)

		try await project.scan()

		#expect(try Data(contentsOf: project.cacheURL) == firstCache)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_writesConsultedConditionsSorted_whenFileConsultsSeveralConditions() async throws {
		// A set's iteration order is seeded per process, so two scans of the same file would write its
		// consulted conditions in different orders unless they are sorted.
		let project = try await scannedProject(files: [
			"Feature.swift": """
			#if ZETA
			import ZetaKit
			#elseif ETA
			import EtaKit
			#elseif THETA
			import ThetaKit
			#endif

			#if DELTA
			@Instantiable
			public struct Feature: Instantiable {
			    public init() {}
			}
			#elseif ALPHA && !GAMMA
			@Instantiable
			public struct OtherFeature: Instantiable {
			    public init() {}
			}
			#elseif EPSILON || BETA
			@Instantiable
			public struct LastFeature: Instantiable {
			    public init() {}
			}
			#endif
			""",
		])
		let fileScan = try #require(project.scannedModuleInfo.conditionSensitiveFileScans.first?.fileScan)
		#expect(fileScan.consultedCompilationConditions == ["ALPHA", "BETA", "DELTA", "EPSILON", "GAMMA"])
		#expect(fileScan.importOnlyConsultedCompilationConditions == ["ETA", "THETA", "ZETA"])

		for conditions in [fileScan.consultedCompilationConditions, fileScan.importOnlyConsultedCompilationConditions] {
			var setWriter = BinaryWriter()
			setWriter.write(conditions)
			var sortedWriter = BinaryWriter()
			sortedWriter.write(conditions.sorted())
			#expect(setWriter.encoded == sortedWriter.encoded)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesIdenticalCode_whetherOrNotItReadsScanCache() async throws {
		// The sources lie outside the project root, so scan names them by the absolute paths the CSV lists,
		// exactly as a fresh parse in `generate` does.
		let project = try await scannedProject(files: [
			"Root.swift": """
			import SafeDI

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(service: Service, factory: Instantiator<Feature>) {
			        self.service = service
			        self.factory = factory
			    }

			    @Instantiated let service: Service
			    @Instantiated let factory: Instantiator<Feature>
			}
			""",
			"Service.swift": """
			import Foundation

			@Instantiable(generateMock: true)
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
			"Feature.swift": """
			@Instantiable(generateMock: true)
			public struct Feature: Instantiable {
			    public init(service: Service, title: String) {
			        self.service = service
			        self.title = title
			    }

			    @Received let service: Service
			    @Forwarded let title: String
			}
			""",
		], sourcesInsideProjectRoot: false)
		// Empty every source but keep the modification time scan recorded, so `generate` succeeds only by reading the cache.
		var sourcesByPath = [String: String]()
		for path in project.sourcePaths {
			sourcesByPath[path] = try String(contentsOfFile: path, encoding: .utf8)
			let scannedModificationTime = try FileModificationTime(ofItemAtPath: path)
			try "".write(toFile: path, atomically: true, encoding: .utf8)
			try scannedModificationTime.apply(toItemAtPath: path)
		}
		try await project.generate()
		let codeFromCache = try project.generatedCode()

		for (path, source) in sourcesByPath {
			try source.write(toFile: path, atomically: true, encoding: .utf8)
		}
		// An empty cache cannot be read, so `generate` parses the sources afresh.
		try Data().write(to: project.cacheURL)
		try await project.generate()

		#expect(codeFromCache.count == 4)
		#expect(try project.generatedCode() == codeFromCache)
	}

	// MARK: Dumping

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_printsEverythingScanWroteAsJSON() async throws {
		let project = try await scannedKitchenSinkProject()

		let json = try Dump.parse([project.cacheURL.path]).json()

		let dumped = try JSONDecoder().decode(CachedScannedModuleInfo.self, from: Data(json.utf8))
		#expect(reflectedDescription(of: dumped) == reflectedDescription(of: project.scannedModuleInfo))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_runs_whenCacheIsReadable() async throws {
		let project = try await scannedKitchenSinkProject()

		try Dump.parse([project.cacheURL.path]).run()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFileIsShorterThanHeader() async throws {
		try await assertDumpThrows(
			"The file is 29 bytes long, shorter than a scan cache’s header.",
			whenCacheIs: { cache in cache.prefix(29) },
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFileIsJSONFromAnEarlierRelease() async throws {
		try await assertDumpThrows(
			"The file begins with neither `SDMI`, as a module info file does, nor `SDSC`, as a scan cache does. A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it.",
			whenCacheIs: { cache in try JSONEncoder().encode(CachedScannedModuleInfo(scanCacheData: cache)) },
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFormatVersionDiffers() async throws {
		try await assertDumpThrows(
			"The scan cache is in format version 3, but this SafeDITool reads format version 2.",
			whenCacheIs: { cache in
				var cache = cache
				cache[cache.startIndex + 4] = 3
				return cache
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenSchemaFingerprintDiffers() async throws {
		let expected = BinaryFile.schemaFingerprint
		try await assertDumpThrows(
			"The scan cache was written by a SafeDITool whose types are laid out differently: its schema fingerprint is 0x\(String(expected ^ 1, radix: 16)), but this SafeDITool’s is 0x\(String(expected, radix: 16)).",
			whenCacheIs: { cache in
				var cache = cache
				cache[cache.startIndex + 6] ^= 1
				return cache
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFileIsCutShort() async throws {
		let project = try await scannedKitchenSinkProject()
		let cache = try Data(contentsOf: project.cacheURL)
		try cache.dropLast().write(to: project.cacheURL)

		#expect(throws: BinaryFileReadError(kind: .scanCache, reason: .bodyLengthMismatch(recorded: UInt64(cache.count - 30), actual: cache.count - 31))) {
			try Dump.parse([project.cacheURL.path]).json()
		}
		#expect("\(BinaryFileReadError(kind: .scanCache, reason: .bodyLengthMismatch(recorded: 10, actual: 9)))" == "The scan cache’s header records a body of 10 bytes, but 9 bytes follow the header.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyIsCorrupted() async throws {
		try await assertDumpThrows(
			"The scan cache’s body does not match the checksum in its header.",
			whenCacheIs: { cache in
				var cache = cache
				cache[cache.endIndex - 1] ^= 0x10
				return cache
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyEndsBeforeItsValues() async throws {
		let project = try await scannedKitchenSinkProject()
		let body = Self.body(of: project.scannedModuleInfo)
		try BinaryFile.data(.scanCache, body: Array(body.dropLast())).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body ends unexpectedly at byte \(body.count - 1).", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyContinuesPastItsValues() async throws {
		let project = try await scannedKitchenSinkProject()
		let body = Self.body(of: project.scannedModuleInfo)
		try BinaryFile.data(.scanCache, body: body + [0]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body continues past its end at byte \(body.count).", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyHoldsIntegerLongerThan64Bits() async throws {
		let project = try await scannedKitchenSinkProject()
		// The string table's count, with a continuation bit on each of ten bytes.
		try BinaryFile.data(.scanCache, body: [UInt8](repeating: 0xFF, count: 10)).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body holds an integer longer than 64 bits at byte 0.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyCountsMoreElementsThanBytesRemain() async throws {
		let project = try await scannedKitchenSinkProject()
		// A string table of five strings, with no bytes left to hold them.
		try BinaryFile.data(.scanCache, body: [5]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body records a count of 5 at byte 0, more than the bytes that remain.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyRefersToStringOutsideItsTable() async throws {
		let project = try await scannedKitchenSinkProject()
		// An empty string table, then one import, with no field flags, whose attribute is the first string.
		try BinaryFile.data(.scanCache, body: [0, 1, 0, 0]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body refers to string 0 at byte 3, which its string table does not hold.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyHoldsInvalidTag() async throws {
		let project = try await scannedKitchenSinkProject()
		// An empty string table; no imports, mock imports, instantiables, or configurations; then 2 where a
		// `Bool` says whether files with unexpected nodes are listed.
		try BinaryFile.data(.scanCache, body: [0, 0, 0, 0, 0, 2]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body holds 2 at byte 5, which is not a tag of BooleanTag.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyNestsTooDeeply() async throws {
		let project = try await scannedKitchenSinkProject()
		// An empty string table; no imports or mock imports; then one instantiable, with no field flags, whose concrete
		// type is `optional` (tag 4) wrapped one level more deeply than SafeDITool reads.
		let body: [UInt8] = [0, 0, 0, 1, 0] + [UInt8](repeating: 4, count: BinaryReader.maximumNestingDepth + 1)
		try BinaryFile.data(.scanCache, body: body).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body nests values too deeply at byte \(5 + BinaryReader.maximumNestingDepth).", project: project)
	}

	// MARK: Nesting

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_readsBack_whenTypeNestsAsDeeplyAsSafeDIReads() async throws {
		// `Int` and 127 optionals nest 128 type descriptions deep.
		let deeplyNestedType = "Int" + String(repeating: "?", count: BinaryReader.maximumNestingDepth - 1)
		let project = try await scannedProject(files: [
			"Deep.swift": Self.deepSource(forwarding: deeplyNestedType),
		])

		// Counted rather than spelled: spelling a type recurses as deeply as it nests.
		var cachedType = try #require(project.readCache().moduleInfo.instantiables.first?.dependencies.first?.property.typeDescription)
		var optionalCount = 0
		while case let .optional(wrappedType) = cachedType {
			optionalCount += 1
			cachedType = wrappedType
		}
		#expect(optionalCount == BinaryReader.maximumNestingDepth - 1)
		#expect(cachedType == .simple(name: "Int"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_writesNoCache_whenTypeNestsMoreDeeplyThanSafeDIReads() async throws {
		// A cache no SafeDITool reads would only cost `generate` the time to read it before parsing afresh.
		let project = try await scannedProject(files: [
			"Deep.swift": Self.deepSource(forwarding: "Int" + String(repeating: "?", count: BinaryReader.maximumNestingDepth)),
		])

		#expect(!FileManager.default.fileExists(atPath: project.cacheURL.path))
		#expect(project.scannedModuleInfo.moduleInfo.instantiables.map(\.concreteInstantiable) == [.simple(name: "Deep")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeNestsMoreDeeplyThanDependentModulesRead() async {
		let deeplyNestedType = "Int" + String(repeating: "?", count: BinaryReader.maximumNestingDepth)
		await assertThrowsError("SafeDI cannot write `Deep` to a module info file: a type its declaration names nests more than 128 types deep, which is more than SafeDI reads back. To fix this, declare a typealias for part of that type, so that no type in the declaration nests more than 128 types deep.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.deepSource(forwarding: deeplyNestedType)],
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "Example", "--package-name", "Example"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func moduleInfoData_throwsErrorNamingOutermostTypeOfPlainTypeDeclaration_whenItsTypeNestsMoreDeeplyThanDependentModulesRead() {
		// A type declaration nests one type description for each type that encloses it. A debug build's parser reads no
		// declaration nested this deeply, so the declaration is made here rather than parsed.
		let typeNames = (0...BinaryReader.maximumNestingDepth).map { "Level\($0)" }
		let deeplyNestedType = typeNames.dropFirst().reduce(TypeDescription.simple(name: typeNames[0])) { enclosingType, typeName in
			.nested(name: typeName, parentType: enclosingType)
		}
		let moduleInfo = ModuleInfo(
			imports: [],
			mockImports: [],
			instantiables: [],
			configurations: [],
			filesWithUnexpectedNodes: nil,
			conditionalCompilationDecisions: [],
			instantiableTypeNamesInAnyClause: [],
			plainTypeDeclarations: [PlainTypeDeclaration(typeDescription: deeplyNestedType, access: AccessDeclaration(level: .internal), enclosingTypeAccess: [])],
		)

		#expect {
			try ModuleInfoFile(module: moduleInfo, moduleName: "Deep", seamSignatures: [], view: .empty).moduleInfoData
		} throws: { error in
			// Named by its outermost type: spelling the nested type recurses as deeply as it nests.
			"\(error)" == "SafeDI cannot write `Level0` to a module info file: a type its declaration names nests more than 128 types deep, which is more than SafeDI reads back. To fix this, declare a typealias for part of that type, so that no type in the declaration nests more than 128 types deep."
		}
	}

	// MARK: Module info

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func ownEntry_holdsNoPositionAndEveryFact_whenModuleRecordsPositions() async throws {
		// Cell 21: a view entry holds no line or column, so a position-only edit leaves every dependent's `.safedi`
		// unchanged, and keeps every fact a signature reads: which file holds each declaration, and whether each spells an
		// access modifier. A position field added later is caught here, and so is a fact stripped by mistake.
		let module = try await scannedKitchenSinkProject().scannedModuleInfo.moduleInfo
		let file = ModuleInfoFile(module: module, moduleName: "Kitchen", seamSignatures: [], view: .empty)
		func positions(in value: Any) -> [Any] {
			reflectedStructuresAndEnumerations(in: value).filter { $0 is Dependency.DeclarationLocation || $0 is Dependency.SourceRange }
		}
		func spelledAccessModifiers(in value: Any) -> [Bool] {
			reflectedStructuresAndEnumerations(in: value).compactMap { ($0 as? AccessDeclaration)?.spellsAccessModifier }
		}
		#expect(!positions(in: file.instantiables).isEmpty)
		#expect(!positions(in: file.plainTypeDeclarations).isEmpty)
		#expect(spelledAccessModifiers(in: file.instantiables).contains(true) && spelledAccessModifiers(in: file.instantiables).contains(false))

		let entry = file.ownEntry
		#expect(positions(in: entry).isEmpty)
		#expect(entry.instantiables.map(\.sourceFilePath) == file.instantiables.map(\.sourceFilePath))
		#expect(entry.plainTypeDeclarations.map(\.sourceFilePath) == file.plainTypeDeclarations.map(\.sourceFilePath))
		#expect(spelledAccessModifiers(in: entry.instantiables) == spelledAccessModifiers(in: file.instantiables))
		#expect(spelledAccessModifiers(in: entry.plainTypeDeclarations) == spelledAccessModifiers(in: file.plainTypeDeclarations))
		#expect(entry.imports == file.imports)
		#expect(entry.mockImports == file.mockImports)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dump_printsEverythingModuleInfoFileHoldsAsJSON() async throws {
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Upstream", "--package-name", "Example"],
		)

		let json = try Dump.parse([upstream.writtenModuleInfoOutputPath]).json()

		let dumped = try JSONDecoder().decode(ModuleInfo.self, from: Data(json.utf8))
		#expect(dumped.instantiables.map(\.concreteInstantiable) == [.simple(name: "UpstreamService")])
		#expect(try reflectedDescription(of: dumped) == reflectedDescription(of: upstream.writtenModuleInfo))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dump_printsEverySeamSignatureModuleInfoFileHoldsAsJSON() async throws {
		// `Badge`, `package`, receives `serviceBuilder` only if available, so `Host`'s `package` tier takes the builder of
		// its hole `service` under another label than its `public` tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service {}",
				"package struct Thing {}",
				"""
				@Instantiable
				package struct Badge: Instantiable {
				    package init(serviceBuilder: Thing?) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Received(onlyIfAvailable: true) let serviceBuilder: Thing?
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    init(service: any Service, badge: Badge) {
				        self.service = service
				        self.badge = badge
				    }

				    @Instantiated let service: any Service
				    @Instantiated let badge: Badge
				}
				""",
			])],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let seamModule = try #require(output.modules["Feature"])

		let json = try Dump.parse([#require(seamModule.moduleInfoOutputPath)]).json()

		let dumped = try JSONDecoder().decode(ModuleInfoFile.self, from: Data(json.utf8))
		let written = try #require(seamModule.moduleInfoFile)
		#expect(dumped.seamSignatures.first?.signature?.holes.map(\.narrowerTierBuilderLabels) == [[.package: "serviceBuilder_"]])
		#expect(reflectedDescription(of: dumped.seamSignatures) == reflectedDescription(of: written.seamSignatures))
	}

	@Test
	func encode_writesLabelsInSortedOrder_whenValuesBindLabelsLater() throws {
		let labels = (0..<24).map { "label\($0)" }
		let values = SeamSignature.ScopeEnum.Values(typeName: "Values", fields: [], labelsBoundLater: Set(labels))

		let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as? [String: Any]

		#expect(json?["labelsBoundLater"] as? [String] == labels.sorted())
	}

	@Test
	func encode_writesNarrowerTierLabelsWidestTierFirst_whenBuilderTakesLabelOnEveryTier() throws {
		let tiers: [AccessLevel] = [.open, .public, .package, .internal, .fileprivate, .private]
		let builder = SeamSignature.Builder(
			enumKey: .init(seamType: .simple(name: "Host"), holeType: .init(instantiatedType: .simple(name: "Service"), builtType: .simple(name: "Service")), isSendable: false),
			label: "serviceBuilder",
			internalName: "serviceBuilder",
			parameterType: .simple(name: "Service"),
			readableParameterType: .simple(name: "Service"),
			takesBuilderStruct: false,
			tierAccess: .open,
			accessCause: nil,
			narrowingInnerSeam: nil,
			narrowerTierLabels: Dictionary(uniqueKeysWithValues: tiers.reversed().map { ($0, "serviceBuilder_\($0)") }),
		)

		let encoded = try JSONEncoder().encode(builder)

		let decoded = try JSONDecoder().decode(SeamSignature.Builder.self, from: encoded)
		let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
		let pairs = try #require(json?["narrowerTierLabels"] as? [Any])
		#expect(pairs.enumerated().filter { $0.offset.isMultiple(of: 2) == false }.map { $0.element as? String } == tiers.map { "serviceBuilder_\($0)" })
		#expect(decoded.narrowerTierLabels == builder.narrowerTierLabels)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func moduleInfo_readsBackEverythingGenerateWrote_whenModuleAndItsDependenciesAreNamed() async throws {
		// Scan's cache never records a module, so only a module info file holds these fields with values: the module and
		// its dependencies, and each declaration's module and package, and its hand-written mock's.
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Pantry"],
		)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public struct Workshop: Instantiable {
				    public init() {}
				    public static func mock() -> Workshop {
				        Workshop()
				    }
				}
				""",
				"""
				@Instantiable(mockOnly: true)
				package extension Barn {
				    static func mock() -> Barn {
				        Barn()
				    }
				}
				""",
			],
			dependentModuleInfoPaths: [upstream.writtenModuleInfoOutputPath],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Kitchen", "--package-name", "Restaurant"],
		)

		#expect(try reflectedDescription(of: output.writtenModuleInfo) == reflectedDescription(of: output.generateOutput.module))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenDependentModuleInfoFileIsCorrupted() async throws {
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Upstream", "--package-name", "Example"],
		)
		var moduleInfo = try Data(contentsOf: URL(fileURLWithPath: upstream.writtenModuleInfoOutputPath))
		moduleInfo[moduleInfo.endIndex - 1] ^= 0x01
		try moduleInfo.write(to: URL(fileURLWithPath: upstream.writtenModuleInfoOutputPath))

		let upstreamModuleInfoPath = try upstream.writtenModuleInfoOutputPath
		await assertThrowsError("Could not read the SafeDI module info file at \(URL(fileURLWithPath: upstreamModuleInfoPath).path): The module info file’s body does not match the checksum in its header. A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.downstreamRootSource],
				dependentModuleInfoPaths: [upstream.writtenModuleInfoOutputPath],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenDependentModuleInfoFileIsJSONFromAnEarlierRelease() async throws {
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Upstream", "--package-name", "Example"],
		)
		try JSONEncoder().encode(upstream.writtenModuleInfo).write(to: URL(fileURLWithPath: upstream.writtenModuleInfoOutputPath))

		let upstreamModuleInfoPath = try upstream.writtenModuleInfoOutputPath
		await assertThrowsError("Could not read the SafeDI module info file at \(URL(fileURLWithPath: upstreamModuleInfoPath).path): The file is not a module info file: it does not begin with `SDMI`. A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.downstreamRootSource],
				dependentModuleInfoPaths: [upstream.writtenModuleInfoOutputPath],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	/// `café` with a precomposed `é` (U+00E9), the spelling Unicode Normalization Form C produces.
	private static let precomposedCafe = "caf\u{E9}"
	/// `café` with `e` followed by a combining acute accent (U+0301), the spelling Normalization Form D produces.
	private static let decomposedCafe = "cafe\u{301}"

	/// A type that forwards a value of `typeSource`.
	private static func deepSource(forwarding typeSource: String) -> String {
		"""
		@Instantiable
		public struct Deep: Instantiable {
		    public init(value: \(typeSource)) {
		        self.value = value
		    }

		    @Forwarded let value: \(typeSource)
		}
		"""
	}

	private static let upstreamServiceSource = """
	@Instantiable
	public struct UpstreamService: Instantiable {
	    public init() {}
	}
	"""

	private static let downstreamRootSource = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(upstreamService: UpstreamService) {
	        self.upstreamService = upstreamService
	    }

	    @Instantiated let upstreamService: UpstreamService
	}
	"""

	private var filesToDelete: [URL]

	private struct ScannedProject {
		let sourcePaths: [String]
		let swiftFileCSV: URL
		let projectRoot: URL
		let outputDirectory: URL
		let manifestFile: URL
		let scannedModuleInfo: CachedScannedModuleInfo

		var cacheURL: URL {
			scannedModuleInfoURL(forManifestPath: manifestFile.path)
		}

		func readCache() throws -> CachedScannedModuleInfo {
			try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: cacheURL))
		}

		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		@discardableResult
		func scan() async throws -> CachedScannedModuleInfo {
			try await performScan(
				inputSourcesFile: swiftFileCSV.path,
				projectFilePaths: ProjectFilePaths(projectRoot: projectRoot.path),
				outputDirectory: outputDirectory.path,
				manifestFile: manifestFile.path,
			)
		}

		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		func generate() async throws {
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			]).run()
		}

		/// Every file `generate` wrote, keyed by name.
		func generatedCode() throws -> [String: Data] {
			var generatedCode = [String: Data]()
			for fileName in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path) {
				generatedCode[fileName] = try Data(contentsOf: outputDirectory.appendingPathComponent(fileName))
			}
			return generatedCode
		}
	}

	/// The number of cases an enum's layout lists.
	/// The structs and enums `value` holds, as `reflectedStructuresAndEnumerations(in:)` finds them, except the storage
	/// of a property its layout lists as unwritten: a type held there that is no schema member, such as the box
	/// `Instantiable` keeps its rarely set fields in, holds fields written under their own names, so only the schema
	/// members it holds are cached values.
	private static func cachedStructuresAndEnumerations(in value: Any, isInsideUnwrittenProperty: Bool = false) -> [Any] {
		let mirror = Mirror(reflecting: value)
		let unwrittenProperties = unwrittenProperties(of: value)
		let nested = mirror.children.flatMap { child in
			cachedStructuresAndEnumerations(
				in: child.value,
				isInsideUnwrittenProperty: isInsideUnwrittenProperty || unwrittenProperties.contains(child.label ?? ""),
			)
		}
		guard mirror.displayStyle == .struct || mirror.displayStyle == .enum,
		      !isInsideUnwrittenProperty || value is any BinarySchemaMember
		else {
			return nested
		}
		return [value] + nested
	}

	/// The properties the layout of `value`'s type lists as unwritten, when it is a schema member's struct.
	private static func unwrittenProperties(of value: Any) -> [String] {
		func unwrittenProperties<Member: BinarySchemaMember>(ofMember _: Member) -> [String] {
			guard case let .structure(_, unwrittenProperties) = Member.binaryLayout else {
				return []
			}
			return unwrittenProperties
		}
		guard let member = value as? any BinarySchemaMember else {
			return []
		}
		return unwrittenProperties(ofMember: member)
	}

	private static func caseCount<Member: BinarySchemaMember>(of _: Member.Type) -> Int {
		switch Member.binaryLayout {
		case .structure:
			0
		case let .enumeration(cases):
			cases.count
		}
	}

	/// `value` with a string table holding the strings it writes.
	private static func encoded(_ value: some BinaryCodable) -> [UInt8] {
		var writer = BinaryWriter()
		writer.write(value)
		return writer.encoded
	}

	/// A sample value of `type` with a string table holding the strings it writes.
	private static func encodedSample(of type: any BinaryCodable.Type, isDistinct: Bool) throws -> [UInt8] {
		var writer = BinaryWriter()
		try writeSample(of: type, isDistinct: isDistinct, to: &writer)
		return writer.encoded
	}

	private static func expectLayoutListsEveryStoredProperty<Member: BinarySchemaMember>(of value: Member) {
		guard case let .structure(fields, unwrittenProperties) = Member.binaryLayout else {
			Issue.record("\(Member.self) is a struct, but its layout lists cases")
			return
		}
		let fieldNames = fields.map(\.name)
		let storedProperties = Mirror(reflecting: value).children.map { $0.label ?? "" }

		#expect(storedProperties.filter { !fieldNames.contains($0) }.sorted() == unwrittenProperties.sorted(), "\(Member.self)")
	}

	/// Writes each field of `Member` with a sample value, one field in turn distinct from the rest, reads the
	/// bytes back as `Member`, and expects it to write the same bytes and to hold the distinct value in that field.
	private static func expectStructureLayoutMatchesCoder<Member: BinarySchemaMember>(of _: Member.Type) throws {
		switch Member.binaryLayout {
		case let .structure(fields, _):
			for distinctField in fields {
				var writer = BinaryWriter()
				try writeFieldSamples(of: Member.self, fields: fields, to: &writer) { $0.name == distinctField.name }
				let bytes = writer.encoded
				let context = "\(Member.self) with a distinct \(distinctField.name)"
				let value: Member
				do {
					value = try read(bytes)
				} catch {
					Issue.record("\(context) does not read back: \(error)")
					continue
				}
				let fieldValue = try #require(value[keyPath: distinctField.keyPath] as? any BinaryCodable)

				#expect(encoded(value) == bytes, "\(context)")
				#expect(try encoded(fieldValue) == encodedSample(of: distinctField.type, isDistinct: true), "\(context)")
			}
		case .enumeration:
			break
		}
	}

	/// Writes each case of `Member` with a sample payload, one associated value in turn distinct from the rest,
	/// reads the bytes back as `Member`, and expects it to write the same bytes and to hold each associated value
	/// in the order and of the type the layout lists, with the distinct value where the layout puts it.
	private static func expectEnumerationLayoutMatchesCoder<Member: BinarySchemaMember>(of _: Member.Type) throws {
		switch Member.binaryLayout {
		case .structure:
			break
		case let .enumeration(cases):
			for (tag, layoutCase) in cases.enumerated() {
				for distinctIndex in layoutCase.payload.isEmpty ? [nil] : layoutCase.payload.indices.map(Optional.some) {
					var writer = BinaryWriter()
					writer.writeUnsigned(UInt64(tag))
					for (index, element) in layoutCase.payload.enumerated() {
						try writeSample(of: element.type, isDistinct: index == distinctIndex, to: &writer)
					}
					let bytes = writer.encoded
					let context = "\(Member.self).\(layoutCase.name)" + (distinctIndex.map { " with associated value \($0) distinct" } ?? "")
					let value: Member
					do {
						value = try read(bytes)
					} catch {
						Issue.record("\(context) does not read back: \(error)")
						continue
					}
					let payload = Self.payload(of: value, laidOutAs: layoutCase)

					#expect(encoded(value) == bytes, "\(context)")
					#expect(payload.map { String(reflecting: type(of: $0.value)) } == layoutCase.payload.map { String(reflecting: $0.type) }, "\(context)")
					#expect(zip(layoutCase.payload, payload).allSatisfy { element, child in element.label == nil || element.label == child.label }, "\(context)")
					if let distinctIndex {
						let distinctValue = try #require(payload[distinctIndex].value as? any BinaryCodable)
						#expect(try encoded(distinctValue) == encodedSample(of: layoutCase.payload[distinctIndex].type, isDistinct: true), "\(context)")
					}
				}
			}
		}
	}

	/// The associated values `value` holds, in declaration order: a lone unlabeled value as itself, and any other
	/// payload as a tuple.
	private static func payload(of value: some BinarySchemaMember, laidOutAs layoutCase: BinaryLayoutCase) -> [Mirror.Child] {
		if let caseChild = Mirror(reflecting: value).children.first {
			if layoutCase.payload.count == 1, layoutCase.payload[0].label == nil {
				[(label: nil, value: caseChild.value)]
			} else {
				Array(Mirror(reflecting: caseChild.value).children)
			}
		} else {
			[]
		}
	}

	/// The body of the scan cache that holds `scannedModuleInfo`.
	private static func body(of scannedModuleInfo: CachedScannedModuleInfo) -> [UInt8] {
		var writer = BinaryWriter()
		writer.write(scannedModuleInfo)
		return writer.encoded
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func assertDumpThrows(
		_ expectedDescription: String,
		whenCacheIs rewrite: (Data) throws -> Data,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let project = try await scannedKitchenSinkProject()
		try rewrite(Data(contentsOf: project.cacheURL)).write(to: project.cacheURL)

		try assertDumpThrows(expectedDescription, project: project, sourceLocation: sourceLocation)
	}

	private func assertDumpThrows(
		_ expectedDescription: String,
		project: ScannedProject,
		sourceLocation: SourceLocation = #_sourceLocation,
	) throws {
		let command = try Dump.parse([project.cacheURL.path])
		do {
			_ = try command.json()
			Issue.record("Did not throw error!", sourceLocation: sourceLocation)
		} catch {
			#expect(expectedDescription == "\(error)", sourceLocation: sourceLocation)
		}
	}

	/// A project whose cache holds every shape the cache can hold: each kind of type description, dependency
	/// source, declaration, and access level, a mock declared in an extension, declarations nested in types and in
	/// an extension, imports kept as segments, files whose scans consulted compilation conditions, a dependency only an
	/// inactive clause declares, and files reached through `additionalDirectoriesToInclude`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedKitchenSinkProject() async throws -> ScannedProject {
		let additionalDirectory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: additionalDirectory, withIntermediateDirectories: true)
		filesToDelete.append(additionalDirectory)
		try """
		@Instantiable
		public struct AdditionalService: Instantiable {
		    public init() {}
		}
		""".write(to: additionalDirectory.appendingPathComponent("AdditionalService.swift"), atomically: true, encoding: .utf8)
		try """
		#if FEATURE
		@Instantiable
		public struct AdditionalFeature: Instantiable {
		    public init() {}
		}
		#endif
		""".write(to: additionalDirectory.appendingPathComponent("AdditionalFeature.swift"), atomically: true, encoding: .utf8)

		return try await scannedProject(files: [
			"SafeDIConfiguration.swift": """
			import SafeDI

			#SafeDIConfiguration(
			    additionalImportedModules: ["Extra"],
			    additionalDirectoriesToInclude: ["\(additionalDirectory.path)"],
			    additionalMocksToGenerate: ["Other"],
			    mockConditionalCompilation: nil,
			)
			""",
			"Kitchen.swift": """
			@preconcurrency import Foundation
			import struct Swift.Int
			#if FEATURE
			import FeatureKit
			#endif

			@Instantiable(isRoot: true, fulfillingAdditionalTypes: [KitchenProtocol.self], generatedInitializerAttributes: "@available(macOS 10.15, *)", mockAttributes: "@MainActor", generateMock: true)
			public final class Kitchen: Instantiable {
			    public init(
			        pantry kitchenPantry: Pantry,
			        stove: any Stove,
			        timer: Timer? = nil,
			        storage: Pantry?,
			        recipe: Recipe.Ingredient<String>,
			        mixers: [any Mixer & Sendable],
			        oven: Oven!,
			        shape: some Shape,
			        kitchenType: Kitchen.Type,
			        stoveProtocol: Stove.Protocol,
			        handler: @escaping @Sendable (Int, String) async throws -> Void,
			        nothing: (),
			        lookup: [String: Int],
			        pair: (first: Int, String),
			        unknown: ~Copyable,
			        variadicHandler: @escaping (Int...) throws(CancellationError) -> Void,
			        ovenFactory: Instantiator<Oven>,
			    ) {
			        pantry = kitchenPantry
			        self.stove = stove
			        self.timer = timer
			        self.storage = storage
			        self.recipe = recipe
			        self.mixers = mixers
			        self.oven = oven
			        self.shape = shape
			        self.kitchenType = kitchenType
			        self.stoveProtocol = stoveProtocol
			        self.handler = handler
			        self.nothing = nothing
			        self.lookup = lookup
			        self.pair = pair
			        self.unknown = unknown
			        self.variadicHandler = variadicHandler
			        self.ovenFactory = ovenFactory
			    }

			    @Instantiated let pantry: Pantry
			    @Instantiated(fulfilledByType: "GasStove", erasedToConcreteExistential: true) let stove: any Stove
			    @Received(onlyIfAvailable: true) let timer: Timer?
			    @Received(fulfilledByDependencyNamed: "pantry", ofType: Pantry.self, erasedToConcreteExistential: false, onlyIfAvailable: true) let storage: Pantry?
			    @Forwarded let recipe: Recipe.Ingredient<String>
			    @Received let mixers: [any Mixer & Sendable]
			    @Received let oven: Oven!
			    @Received let shape: some Shape
			    @Received let kitchenType: Kitchen.Type
			    @Received let stoveProtocol: Stove.Protocol
			    @Received let handler: @Sendable (Int, String) async throws -> Void
			    @Received let nothing: ()
			    @Received let lookup: [String: Int]
			    @Received let pair: (first: Int, String)
			    @Received let unknown: ~Copyable
			    @Received let variadicHandler: (Int...) throws(CancellationError) -> Void
			    @Instantiated let ovenFactory: Instantiator<Oven>
			}

			extension Kitchen {
			    struct SafeDIScope_Kitchen {}
			}
			""",
			"Pantry.swift": """
			@Instantiable(generateMock: .public, customMockName: "customMock")
			public struct Pantry: Instantiable {
			    public init() {}
			    public init(shelves: Int) {}
			    public static func customMock() -> Pantry {
			        Pantry()
			    }
			}
			""",
			"Oven.swift": """
			@Instantiable(generateDependencyTree: true)
			public actor Oven: Instantiable {
			    public init(level: Void) {
			        self.level = level
			    }

			    @Forwarded let level: Void
			}
			""",
			"Timer.swift": """
			#if FEATURE
			@Instantiable
			public struct FeatureTimer: Instantiable {
			    public init() {}
			}
			#endif

			@Instantiable
			public struct Clock: Instantiable {
			    public init() {}
			    #if FEATURE
			    @Received let alarm: Alarm
			    #endif
			}

			@Instantiable
			extension Timer: Instantiable {
			    public static func instantiate() -> Timer {
			        Timer()
			    }
			}
			""",
			"Broken.swift": """
			@Instantiable
			public struct Broken: Instantiable {
			    public init() {}
			    let value: = 1
			}
			""",
			"Workshop.swift": """
			@Instantiable
			open class Workshop: Instantiable {
			    public init() {}
			    package static func mock() -> Workshop {
			        Workshop()
			    }
			}

			@Instantiable
			struct Shed: Instantiable {
			    public init() {}
			    private static func mock() -> Shed {
			        Shed()
			    }
			}

			@Instantiable(conformsElsewhere: true)
			extension Garage {
			    fileprivate static func instantiate() -> Garage {
			        Garage()
			    }
			}

			@Instantiable(mockOnly: true)
			package extension Barn {
			    static func mock() -> Barn {
			        Barn()
			    }
			}

			public enum Farm {
			    struct Field {
			        @Instantiable
			        public struct Scarecrow: Instantiable {
			            public init() {}
			        }
			    }
			}

			public extension Farm {
			    @Instantiable
			    struct Tractor: Instantiable {
			        public init() {}
			    }
			}
			""",
		])
	}

	/// Writes `files` and scans them.
	/// - Parameter sourcesInsideProjectRoot: Whether the project root is the directory that holds `files`, so
	///   that scan names them relative to it, or another directory, so that scan names them as the CSV does.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedProject(files: [String: String], sourcesInsideProjectRoot: Bool = true) async throws -> ScannedProject {
		let sourceDirectory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
		let projectRoot = if sourcesInsideProjectRoot {
			sourceDirectory
		} else {
			TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		}
		var filePaths = [String]()
		for (fileName, content) in files.sorted(by: { $0.key < $1.key }) {
			let file = sourceDirectory.appendingPathComponent(fileName)
			try content.write(to: file, atomically: true, encoding: .utf8)
			filePaths.append(file.path)
		}
		let swiftFileCSV = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try filePaths.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [sourceDirectory, swiftFileCSV, outputDirectory, manifestFile]

		let scannedModuleInfo = try await performScan(
			inputSourcesFile: swiftFileCSV.path,
			projectFilePaths: ProjectFilePaths(projectRoot: projectRoot.path),
			outputDirectory: outputDirectory.path,
			manifestFile: manifestFile.path,
		)
		// Scan writes no cache for a module it could not read back.
		let cacheURL = scannedModuleInfoURL(forManifestPath: manifestFile.path)
		if FileManager.default.fileExists(atPath: cacheURL.path) {
			filesToDelete.append(cacheURL)
		}
		return ScannedProject(
			sourcePaths: filePaths,
			swiftFileCSV: swiftFileCSV,
			projectRoot: projectRoot,
			outputDirectory: outputDirectory,
			manifestFile: manifestFile,
			scannedModuleInfo: scannedModuleInfo,
		)
	}
}

// MARK: - Samples

/// A type whose value tests can make from the type alone, so that each field of a layout can be written with a value
/// that differs from every other field's.
private protocol BinarySample: BinaryCodable {
	/// A value of this type. A distinct value and one that is not distinct are written as different bytes.
	static func sample(isDistinct: Bool) throws -> Self
}

/// Writes a sample value of `type`, which every type a cached struct or enum writes must provide.
private func writeSample(of type: any BinaryCodable.Type, isDistinct: Bool, to writer: inout BinaryWriter) throws {
	guard let sampleType = type as? any BinarySample.Type else {
		throw MissingSampleError(typeName: String(reflecting: type))
	}
	let sample = try sampleType.sample(isDistinct: isDistinct)
	writer.write(sample)
}

/// Writes a sample of each of `fields` as `Member`'s coder writes them: a struct that writes field flags writes them
/// first, and each optional and Boolean field as a flag.
private func writeFieldSamples<Member: BinarySchemaMember>(
	of _: Member.Type,
	fields: [BinaryLayoutField<Member>],
	to writer: inout BinaryWriter,
	isDistinct: (BinaryLayoutField<Member>) -> Bool,
) throws {
	if Member.writesFieldFlags {
		var flags = BinaryFieldFlags()
		let fieldsStart = writer.startFields()
		for field in fields {
			if let flaggedType = field.type as? any BinaryFlaggedSample.Type {
				try flaggedType.writeFlaggedSample(isDistinct: isDistinct(field), to: &writer, flags: &flags)
			} else {
				try writeSample(of: field.type, isDistinct: isDistinct(field), to: &writer)
			}
		}
		writer.finishFields(flags, startingAt: fieldsStart)
	} else {
		for field in fields {
			try writeSample(of: field.type, isDistinct: isDistinct(field), to: &writer)
		}
	}
}

/// A type a struct that writes field flags writes as a flag: a Boolean, or an optional's presence before its value.
private protocol BinaryFlaggedSample {
	static func writeFlaggedSample(isDistinct: Bool, to writer: inout BinaryWriter, flags: inout BinaryFieldFlags) throws
}

extension Bool: BinaryFlaggedSample {
	fileprivate static func writeFlaggedSample(isDistinct: Bool, to _: inout BinaryWriter, flags: inout BinaryFieldFlags) {
		flags.append(sample(isDistinct: isDistinct))
	}
}

extension Optional: BinaryFlaggedSample where Wrapped: BinarySample {
	fileprivate static func writeFlaggedSample(isDistinct: Bool, to writer: inout BinaryWriter, flags: inout BinaryFieldFlags) throws {
		try writer.writeOptional(sample(isDistinct: isDistinct), flaggedIn: &flags)
	}
}

/// The value `bytes`, which ``BinaryWriter/encoded`` produced, hold.
private func read<Value: BinaryCodable>(_ bytes: [UInt8]) throws -> Value {
	try bytes.withUnsafeBytes { bytes in
		var reader = try BinaryReader(bytes: bytes)
		let value: Value = try reader.read()
		try reader.finish()
		return value
	}
}

private struct MissingSampleError: Error, CustomStringConvertible {
	let typeName: String

	var description: String {
		"\(typeName) has no sample value: conform it to `BinarySample`"
	}
}

private struct TooFewCasesError: Error, CustomStringConvertible {
	let typeName: String

	var description: String {
		"\(typeName) has too few cases for a distinct sample value"
	}
}

extension BinarySample where Self: BinarySchemaMember {
	/// A struct whose fields all hold distinct values or all do not, or an enum's second case or first case,
	/// with an associated value that is not distinct, which keeps a sample of a type that contains itself finite.
	static func sample(isDistinct: Bool) throws -> Self {
		var writer = BinaryWriter()
		switch binaryLayout {
		case let .structure(fields, _):
			try writeFieldSamples(of: Self.self, fields: fields, to: &writer) { _ in isDistinct }
		case let .enumeration(cases):
			let tag = isDistinct ? 1 : 0
			guard cases.indices.contains(tag) else {
				throw TooFewCasesError(typeName: String(reflecting: Self.self))
			}
			writer.writeUnsigned(UInt64(tag))
			for element in cases[tag].payload {
				try writeSample(of: element.type, isDistinct: false, to: &writer)
			}
		}
		return try read(writer.encoded)
	}
}

extension String: BinarySample {
	fileprivate static func sample(isDistinct: Bool) -> String {
		isDistinct ? "distinct" : ""
	}
}

extension Int: BinarySample {
	fileprivate static func sample(isDistinct: Bool) -> Int {
		isDistinct ? 1 : 0
	}
}

extension UInt64: BinarySample {
	fileprivate static func sample(isDistinct: Bool) -> UInt64 {
		isDistinct ? 1 : 0
	}
}

extension Int64: BinarySample {
	fileprivate static func sample(isDistinct: Bool) -> Int64 {
		isDistinct ? 1 : 0
	}
}

extension Bool: BinarySample {
	fileprivate static func sample(isDistinct: Bool) -> Bool {
		isDistinct
	}
}

extension Optional: BinarySample where Wrapped: BinarySample {
	fileprivate static func sample(isDistinct: Bool) throws -> Wrapped? {
		isDistinct ? try Wrapped.sample(isDistinct: false) : nil
	}
}

extension BinarySharingSignatureValues: BinarySample where Value: BinarySample {
	fileprivate static func sample(isDistinct: Bool) throws -> BinarySharingSignatureValues<Value> {
		try BinarySharingSignatureValues(Value.sample(isDistinct: isDistinct))
	}
}

extension BinaryShared: BinarySample where Value: BinarySample {
	fileprivate static func sample(isDistinct: Bool) throws -> BinaryShared<Value> {
		try BinaryShared(Value.sample(isDistinct: isDistinct))
	}
}

extension Array: BinarySample where Element: BinarySample {
	fileprivate static func sample(isDistinct: Bool) throws -> [Element] {
		isDistinct ? [try Element.sample(isDistinct: false)] : []
	}
}

extension Dictionary: BinarySample where Key: BinarySample & Comparable, Value: BinarySample {
	fileprivate static func sample(isDistinct: Bool) throws -> [Key: Value] {
		isDistinct ? [try Key.sample(isDistinct: false): try Value.sample(isDistinct: false)] : [:]
	}
}

extension Set: BinarySample where Element: BinarySample & Comparable {
	fileprivate static func sample(isDistinct: Bool) throws -> Set<Element> {
		isDistinct ? [try Element.sample(isDistinct: false)] : []
	}
}

extension CachedScannedModuleInfo: BinarySample {}
extension AdditionalDirectory: BinarySample {}
extension ScannedInput: BinarySample {}
extension FileModificationStamp: BinarySample {}
extension CachedFileScan: BinarySample {}
extension FileScan: BinarySample {}
extension OutputFileDeclarations: BinarySample {}
extension ModuleInfo: BinarySample {}
extension ModuleInfoFile: BinarySample {}
extension ModuleInfoView: BinarySample {}
extension ViewedModuleIdentity: BinarySample {}
extension ViewedModule: BinarySample {}
extension ViewedModuleReference: BinarySample {}
extension ImportStatement: BinarySample {}
extension FileVisitor.ImportSegment: BinarySample {}
extension ConditionalCompilationDecision: BinarySample {}
extension KeptPlainTypeNames: BinarySample {}
extension SafeDIConfiguration: BinarySample {}
extension Instantiable: BinarySample {}
extension Instantiable.DeclarationType: BinarySample {}
extension Instantiable.DependencyLabelInUnselectedClause: BinarySample {}
extension PlainTypeDeclaration: BinarySample {}
extension ReservedTypeNameDeclaration: BinarySample {}
extension MockGeneration: BinarySample {}
extension AccessDeclaration: BinarySample {}
extension AccessLevel: BinarySample {}
extension Initializer: BinarySample {}
extension Initializer.Argument: BinarySample {}
extension Dependency: BinarySample {}
extension Dependency.Source: BinarySample {}
extension Dependency.SourceRange: BinarySample {}
extension Dependency.DeclarationLocation: BinarySample {}
extension Property: BinarySample {}
extension TypeDescription: BinarySample {}
extension TypeDescription.VoidSpelling: BinarySample {}
extension TypeDescription.TupleElement: BinarySample {}
extension UnorderedEquatingCollection: BinarySample where Element: BinarySample {}
extension StoredSeamSignature: BinarySample {}
extension SeamSignature: BinarySample {}
extension SeamSignature.Receiver: BinarySample {}
extension SeamSignature.NestedSeamCall: BinarySample {}
extension SeamSignature.Parameter: BinarySample {}
extension SeamSignature.Parameter.Deferral: BinarySample {}
extension SeamSignature.Hole: BinarySample {}
extension SeamSignature.Hole.Field: BinarySample {}
extension SeamSignature.Hole.Field.SeamParameterOrigin: BinarySample {}
extension SeamSignature.Hole.UncarriedDeclaration: BinarySample {}
extension SeamSignature.Hole.UncarriedDeclaration.Reason: BinarySample {}
extension SeamSignature.Hole.UncarriedDeclaration.SendableFunction: BinarySample {}
extension SeamSignature.Hole.UncarriedDeclaration.AliasOrigin: BinarySample {}
extension SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin: BinarySample {}
extension SeamSignature.Hole.UncarriedDeclaration.PresentedPlace: BinarySample {}
extension SeamSignature.Hole.CycleReentryDeclaration: BinarySample {}
extension SeamSignature.Hole.ReenteringCallDeclaration: BinarySample {}
extension SeamSignature.Hole.FieldOfReenteringPlace: BinarySample {}
extension SeamSignature.Hole.ReenteringPlaceField: BinarySample {}
extension SeamSignature.Hole.DeclarationHiddenByField: BinarySample {}
extension SeamSignature.Hole.PathType: BinarySample {}
extension SeamSignature.Hole.EnumPlace: BinarySample {}
extension SeamSignature.Hole.RouteStep: BinarySample {}
extension SeamSignature.Hole.RouteStep.Member: BinarySample {}
extension SeamSignature.Hole.RouteStep.Values: BinarySample {}
extension SeamSignature.Hole.RouteStep.InnerScope: BinarySample {}
extension SeamSignature.Hole.DeclaredProperty: BinarySample {}
extension SeamSignature.Hole.Site: BinarySample {}
extension SeamSignature.CallRoute: BinarySample {}
extension SeamSignature.HoleType: BinarySample {}
extension SeamSignature.ScopeEnum: BinarySample {}
extension SeamSignature.ScopeEnum.Key: BinarySample {}
extension SeamSignature.ScopeEnum.Values: BinarySample {}
extension SeamSignature.ScopeEnum.Case: BinarySample {}
extension SeamSignature.ScopeEnum.Case.Kind: BinarySample {}
extension SeamSignature.Builder: BinarySample {}
extension TypeAccessProof.Cause: BinarySample {}
extension TypeAccessProof.Prover: BinarySample {}
extension TypeAccessProof.MemberKind: BinarySample {}
extension ModuleIdentity: BinarySample {}
extension AccessRequirement: BinarySample {}
