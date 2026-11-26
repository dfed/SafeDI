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

/// The places a module info file holds of its module's seams: a place a seam passes up from a seam it calls is stored
/// as that seam's record of the place and what the call adds (`StoredPassedUpPlace`), so a module's file does not hold
/// again what the files of the modules beneath it hold.
struct SafeDIToolStoredPlacesTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Reading back

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesWhatARunComputingEverySignatureGenerates_whenPlacesArePassedUpThroughAChainOfModules(viewsReferToModules: Bool) async throws {
		let read = try await chainOutput(layerCount: 4, viewsReferToModules: viewsReferToModules, compiles: true)
		let computed = try await chainOutput(layerCount: 4, viewsReferToModules: viewsReferToModules, discardsStoredSeamSignatures: true)
		for moduleName in read.moduleNames {
			#expect(read.modules[moduleName]?.generatedFiles == computed.modules[moduleName]?.generatedFiles, "\(moduleName)")
		}
		// The top seam passes up the place of every seam beneath it, each stored as the record beneath.
		let topPlaces = try #require(read.modules["Layer3"]?.moduleInfoFile?.seamSignatures).storedPlaces.placesBySeam
		#expect(topPlaces.map { $0.map { $0.isPassedUp } } == [[false, true, true, true]] || topPlaces.map { $0.map { $0.isPassedUp } } == [[true, true, true, false]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsPlacesInsideOneFile_whenViewsCopyModulesAndOnlyDirectDependenciesAreGiven() async throws {
		// A view that copies the modules beneath holds their seams' places, so a run given only the file of the module it
		// depends on, as the Tuist plugin gives it, reads every record there.
		let read = try await chainOutput(layerCount: 4, viewsReferToModules: false, passesModulesBeneath: false)
		let computed = try await chainOutput(layerCount: 4, viewsReferToModules: false, passesModulesBeneath: false, discardsStoredSeamSignatures: true)
		#expect(read.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
		#expect(try #require(read.modules["Layer3"]?.moduleInfoFile?.seamSignatures).storedPlaces.placesBySeam.joined().contains { $0.isPassedUp })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsPlaceOfSeamInSameModule_whenSeamPassesUpPlaceOfSeamItsModuleDeclares() async throws {
		let modules = Self.chainModules(layerCount: 2, layersPerModule: 2)
		let read = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		let computed = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, discardsStoredSeamSignatures: true, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		#expect(read.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
		let places = try #require(read.modules["Layer0"]?.moduleInfoFile?.seamSignatures).storedPlaces
		#expect(places.lowerSeams.map(\.moduleName) == [""])
		#expect(places.placesBySeam.joined().contains { $0.isPassedUp })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesPlaceWhole_whenSeamsOfOneModuleCallOneAnotherInCycle() async throws {
		// `First` and `Second` each pass up the place of `Third` that the other passes up. The two settle on places neither
		// of whose routes extends the other's, and a record that named the other seam's would lead a read in a circle.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Base", swiftFileContent: [
				"public protocol Gauge {}",
				Self.instantiable("Third", isSeam: true, [("gauge", "any Gauge")]),
				Self.instantiable("First", isSeam: true, [("secondBuilder", "Instantiator<Second>"), ("third", "Third")]),
				Self.instantiable("Second", isSeam: true, [("firstBuilder", "Instantiator<First>")]),
			]),
			Self.appModule(instantiating: "First"),
		]
		let read = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		let computed = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, discardsStoredSeamSignatures: true, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		#expect(read.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
		let places = try #require(read.modules["Feature"]?.moduleInfoFile?.seamSignatures).storedPlaces
		let passedUpPlacesWrittenWhole = places.placesBySeam.joined().filter {
			if case let .written(place) = $0 {
				place.innerSeamType != nil
			} else {
				false
			}
		}
		#expect(passedUpPlacesWrittenWhole.count == 1, "\(places.placesBySeam.map { $0.map { $0.isPassedUp } })")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsBackPlacesItWrote_whenTwoSeamsThatBuildOneAnotherPassUpPlacesDeclaredBeforeAndAfterTheCall() async throws {
		// `Outer` and `Ping` build one another. `Outer` passes `Before`'s place up from `Before`, and `After`'s from `Ping`,
		// which has it from `Outer`; `Ping` passes `Before`'s up from `Outer`. So `Ping` is among the seams whose records
		// `Outer`'s place of `Before`'s site could name beside the one it copies, and `Ping`'s record of that site copies
		// `Outer`'s: named, the two would each be read from the other.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Base", swiftFileContent: [
				"public protocol Gauge {}",
				Self.instantiable("Before", isSeam: true, [("gauge", "any Gauge")]),
				Self.instantiable("After", isSeam: true, [("gauge", "any Gauge")]),
				Self.instantiable("Outer", isSeam: true, [("beforeBuilder", "Instantiator<Before>"), ("pingBuilder", "Instantiator<Ping>"), ("afterBuilder", "Instantiator<After>")]),
				Self.instantiable("Ping", isSeam: true, [("outerBuilder", "Instantiator<Outer>")]),
			]),
			Self.appModule(instantiating: "Outer"),
		]
		let read = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		let computed = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, discardsStoredSeamSignatures: true, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		#expect(read.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
		// The file's own records read back, each place from the seam the run passed it up from.
		let written = try #require(read.modules["Feature"]?.moduleInfoFile?.seamSignatures)
		let outerPlaces = try #require(try written.decoded.first { $0.seamType.asSource == "Outer" }?.signature?.holes)
		#expect(outerPlaces.map { "\($0.site.seamType.asSource) from \($0.innerSeamType?.asSource ?? "")" } == ["Before from Before", "After from Ping"])
		#expect(try written.storedPlaces.placesBySeam.joined().contains { $0.isPassedUp })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesRecordOfModuleBeneath_whenAnotherCallPresentsThePlacesSiteByALongerRoute() async throws {
		// `Top` builds `Bottom` itself and through `Outer`, which builds it through `Inner` and holds a place of its own,
		// so that `Top` passes places up from both. `Outer`'s record of `Bottom`'s place has a longer route than `Top`'s
		// place of it, and is a record of a module beneath, which names no place of `Top`'s module: the place takes from
		// it the declarations `Outer` binds, where it would otherwise hold each in full.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Base", swiftFileContent: [
				"public protocol Gauge {}",
				Self.instantiable("Network", isSeam: false, []),
				Self.receivingSeam("Bottom", building: "gauge: any Gauge"),
				Self.receivingSeam("Inner", building: "bottomBuilder: Instantiator<Bottom>"),
				Self.instantiable("Clock", isSeam: false, []),
				Self.receivingSeam("Outer", building: "clock: Clock", "gauge: any Gauge", "innerBuilder: Instantiator<Inner>"),
			]),
			ModuleFixture(name: "Upper", packageName: "Base", swiftFileContent: [
				"import Feature\n" + Self.receivingSeam("Top", building: "bottomBuilder: Instantiator<Bottom>", "outerBuilder: Instantiator<Outer>"),
			], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import Feature
				import Upper

				@Instantiable(fulfillingAdditionalTypes: [Gauge.self])
				public final class LiveGauge: Gauge, Instantiable {
					public init() {}
				}

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
					public init(network: Network, seam: Top) {
						self.network = network
						self.seam = seam
					}
					@Instantiated let network: Network
					@Instantiated let seam: Top
				}
				""",
			], dependencies: ["Feature", "Upper"]),
		]
		let read = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		let computed = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, discardsStoredSeamSignatures: true, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		#expect(read.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
		let places = try #require(read.modules["Upper"]?.moduleInfoFile?.seamSignatures).storedPlaces
		let otherRecordCounts = places.placesBySeam.joined().map {
			if case let .passedUp(place) = $0 {
				place.others.count
			} else {
				-1
			}
		}
		#expect(otherRecordCounts == [1, 0])
	}

	// MARK: Tests – Size

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_growsModuleInfoByTheSameAmountPerLayer_whenChainOfSameSizedModulesDeepens() async throws {
		let output = try await chainOutput(layerCount: 10, viewsReferToModules: true)
		let sizes = try (0..<10).map { layer in
			try #require(output.modules["Layer\(layer)"]?.moduleInfoOutputPath.flatMap { FileManager.default.contents(atPath: $0)?.count })
		}
		// A layer adds its own place and one reference to each place beneath, never the places beneath again: the growth of
		// a layer over the one beneath it is the same near the top as near the bottom, give or take the widths of counts.
		let growthNearBottom = sizes[3] - sizes[2]
		let growthNearTop = sizes[9] - sizes[8]
		#expect(growthNearTop <= growthNearBottom + 32, "\(sizes)")
	}

	// MARK: Tests – Work

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_resolvesEachRecordOnce_whenChainIsDeep() async throws {
		// The top module's places name records all the way down: read by a list of the records still to read, in constant
		// stack, each record once however many places are read through it.
		let layerCount = 120
		let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
		let output = try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
			try await chainOutput(layerCount: layerCount, viewsReferToModules: true, placesOnlyAtBottom: true)
		}
		continuation.finish()
		var workByStep = [GenerationWork.Step: Int]()
		for await work in stream {
			workByStep[work.step, default: 0] += work.elementCount
		}
		#expect(output.modules["App"]?.generatedFiles.isEmpty == false)
		// The run of layer n opens the n modules beneath it and resolves one record in each but the bottom one. Then each
		// layer above the bottom one reads back the place it wrote, from the bytes it wrote: its own places and those of
		// the n modules beneath, and one record in each but the bottom one.
		#expect(workByStep[.openingStoredPlaces] == (0...layerCount).reduce(0, +) + (1..<layerCount).map { $0 + 1 }.reduce(0, +))
		#expect(workByStep[.resolvingStoredPlaces] == (0...layerCount).map { max($0 - 1, 0) }.reduce(0, +) + (1..<layerCount).reduce(0, +))
		#expect(output.modules.values.compactMap(\.generateOutput?.passedUpPlacesWrittenInFull).reduce(0, +) == 0)
	}

	// MARK: Tests – Files that do not match

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func decoded_throws_whenModuleBeneathHoldsOtherPlacesThanThePlaceWasWrittenAgainst() async throws {
		let written = try await chainOutput(layerCount: 2, viewsReferToModules: true)
		let changed = try await chainOutput(layerCount: 2, viewsReferToModules: true, bottomModelCount: 2)
		let upper = try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures)
		let lowerWritten = try #require(written.modules["Layer0"]?.moduleInfoFile?.seamSignatures)
		let lowerChanged = try #require(changed.modules["Layer0"]?.moduleInfoFile?.seamSignatures)
		#expect(try upper.decoded(moduleName: "Layer1", in: ["Layer0": lowerWritten]).first?.signature?.holes.count == 2)
		#expect {
			try upper.decoded(moduleName: "Layer1", in: ["Layer0": lowerChanged])
		} throws: { error in
			"\(error)" == "The module info given holds no places of `Entry0` in module `Layer0` that match the ones a place passed up from it was written against."
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func decoded_throws_whenModuleBeneathIsNotGiven() async throws {
		let written = try await chainOutput(layerCount: 2, viewsReferToModules: true)
		let upper = try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures)
		#expect {
			try upper.decoded(moduleName: "Layer1", in: [:])
		} throws: { error in
			"\(error)" == "The module info given holds no places of `Entry0` in module `Layer0` that match the ones a place passed up from it was written against."
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func encode_printsPlacesAsTheFileHoldsThem_whenPlaceWasPassedUpFromAnotherModulesSeam() async throws {
		// `dump` prints one file. A place whose record another module's file holds cannot be made whole from it, so the
		// places are printed as stored, the seam's own place whole and the passed-up one as the record it names.
		let written = try await chainOutput(layerCount: 2, viewsReferToModules: true)
		let upper = try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures)
		let lower = try #require(written.modules["Layer0"]?.moduleInfoFile?.seamSignatures)
		struct StoredForm: Decodable {
			let signaturesWithoutPlaces: [StoredSeamSignature]
			let storedPlaces: StoredModulePlaces
		}
		let printedUpper = try JSONDecoder().decode(StoredForm.self, from: JSONEncoder().encode(upper))
		let printedLower = try JSONDecoder().decode([StoredSeamSignature].self, from: JSONEncoder().encode(lower))
		#expect(printedUpper.signaturesWithoutPlaces.map { $0.signature?.holes.count } == [0])
		#expect(printedUpper.storedPlaces.lowerSeams.map(\.moduleName) == ["Layer0"])
		#expect(printedUpper.storedPlaces.placesBySeam.map { $0.map(\.isPassedUp).sorted { !$0 && $1 } } == [[false, true]])
		#expect(printedLower.map { $0.signature?.holes.count } == [1])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func encode_throws_whenPlacesAreMalformed() async throws {
		// A file that holds the places of more seams than it has is an error `dump` reports, never a file printed as sound.
		let written = try await chainOutput(layerCount: 2, viewsReferToModules: true)
		let signatures = try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures)
		let places = try signatures.storedPlaces
		let malformed = ModuleSeamSignatures(
			seamTypes: signatures.seamTypes,
			encoding: signatures.encoding(writingPositionsAsAbsent: true),
			placesEncoding: ModuleSeamSignatures.encoding(of: StoredModulePlaces(lowerSeams: places.lowerSeams, placesBySeam: places.placesBySeam + [[]])),
		)
		#expect(throws: StoredPlaceError.self) {
			try JSONEncoder().encode(malformed)
		}
	}

	// MARK: Tests – Places a SafeDITool would not write

	/// A way a module's places can name what the files do not hold.
	enum Malformation: CaseIterable {
		case placesOfMoreSeamsThanTheModuleHas
		case fewerSeamsThanSignatures
		case lowerSeamNotListed
		case recordBeyondTheLowerSeamsPlaces
		case seamTheLowerModuleDoesNotHold
		case keptDeclarationBeyondTheRecords
		case declarationTakenFromRecordNotNamed
		case declarationBoundOnPathOfRecordNotNamed
		case declarationBoundOnPathWithOtherReason
		case recordThatNamesItself
		case recordsDeclarationsKeptTwice
		case oneDeclarationOfRecordKeptTwice
	}

	@Test(arguments: Malformation.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func decoded_throwsRatherThanTraps_whenPlaceNamesWhatTheFilesDoNotHold(malformation: Malformation) async throws {
		let written = try await chainOutput(layerCount: 2, viewsReferToModules: true)
		let upper = try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures)
		let lower = try #require(written.modules["Layer0"]?.moduleInfoFile?.seamSignatures)
		let places = try upper.storedPlaces
		let passedUpIndex = try #require(places.placesBySeam[0].firstIndex { $0.isPassedUp })
		guard case let .passedUp(passedUp) = places.placesBySeam[0][passedUpIndex] else {
			return
		}
		// A declaration to write in a place, whatever it says: one the place written whole holds.
		let placesRead = try #require(try upper.decoded(moduleName: "Layer1", in: ["Layer0": lower]).first?.signature?.holes)
		let placeRead = try #require(placesRead.first)
		let declaration = try #require(placesRead.flatMap(\.uncarriedDeclarations).first)
		func upperHolding(_ place: StoredPassedUpPlace, lowerSeams: [StoredLowerSeam] = places.lowerSeams, seamTypes: [TypeDescription] = upper.seamTypes, moreSeams: [[StoredPlace]] = []) -> ModuleSeamSignatures {
			var placesOfSeam = places.placesBySeam[0]
			placesOfSeam[passedUpIndex] = .passedUp(place)
			var writer = BinaryWriter()
			writer.writeSharingSignatureValues { $0.write(StoredModulePlaces(lowerSeams: lowerSeams, placesBySeam: [placesOfSeam] + moreSeams)) }
			return ModuleSeamSignatures(seamTypes: seamTypes, encoding: upper.encoding(writingPositionsAsAbsent: true), placesEncoding: writer.encoded)
		}
		func place(record: StoredRecordReference = passedUp.record, declarations: [StoredPlaceDeclaration]? = nil) -> StoredPassedUpPlace {
			StoredPassedUpPlace(
				record: record,
				others: passedUp.others,
				presentation: passedUp.presentation,
				addition: StoredPlaceAddition(typesToCall: passedUp.addition.typesToCall, route: passedUp.addition.route, isSendable: passedUp.addition.isSendable, declarations: declarations ?? passedUp.addition.declarations, reenteringCallDeclarations: nil, reenteringPlaceFields: nil),
			)
		}
		let malformed: ModuleSeamSignatures
		var expectedError = "The module info of module `Layer1` holds a place that names a record it does not hold."
		switch malformation {
		case .placesOfMoreSeamsThanTheModuleHas:
			malformed = upperHolding(passedUp, moreSeams: [[]])
		case .fewerSeamsThanSignatures:
			malformed = upperHolding(passedUp, seamTypes: [])
		case .lowerSeamNotListed:
			malformed = upperHolding(place(record: StoredRecordReference(lowerSeam: places.lowerSeams.count, record: 0)))
		case .recordBeyondTheLowerSeamsPlaces:
			malformed = upperHolding(place(record: StoredRecordReference(lowerSeam: passedUp.record.lowerSeam, record: 99)))
		case .seamTheLowerModuleDoesNotHold:
			malformed = upperHolding(passedUp, lowerSeams: places.lowerSeams.map { StoredLowerSeam(moduleName: $0.moduleName, seamType: upper.seamTypes[0], checksum: $0.checksum) })
			expectedError = "The module info given holds no places of `Entry1` in module `Layer0` that match the ones a place passed up from it was written against."
		case .keptDeclarationBeyondTheRecords:
			malformed = upperHolding(place(declarations: [.kept(first: 99, count: 1)]))
		case .declarationTakenFromRecordNotNamed:
			malformed = upperHolding(place(declarations: [.taken(other: passedUp.others.count, declaration: 0)]))
		case .declarationBoundOnPathOfRecordNotNamed:
			let boundOnPath = SeamSignature.Hole.UncarriedDeclaration(
				storing: declaration.property,
				declaringType: declaration.declaringType,
				declarationLocation: nil,
				parameterTakingType: nil,
				builtAfter: nil,
				reason: .boundByPassingUpSeam(seam: placeRead.scopeSeamType, module: placeRead.scopeSeamModule, place: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(placeRead)),
				isBoundFromCallersArgument: false,
				isBuildableAboveSeam: false,
				labelsHeldAboveSeam: [],
				placesInTree: [],
				holdsPlaceFilledElsewhere: false,
			)
			malformed = upperHolding(place(declarations: [.boundOnPath(declaration: boundOnPath, placeOf: passedUp.others.count + 1)]))
		case .declarationBoundOnPathWithOtherReason:
			malformed = upperHolding(place(declarations: [.boundOnPath(declaration: declaration, placeOf: 0)]))
		case .recordThatNamesItself:
			malformed = upperHolding(
				place(record: StoredRecordReference(lowerSeam: 0, record: passedUpIndex)),
				lowerSeams: [StoredLowerSeam(moduleName: "", seamType: upper.seamTypes[0], checksum: 0)],
			)
		case .recordsDeclarationsKeptTwice:
			// Each record of a chain that did this would hold twice the declarations of the one beneath.
			malformed = upperHolding(place(declarations: [.record, .record]))
		case .oneDeclarationOfRecordKeptTwice:
			malformed = upperHolding(place(declarations: [.record, .kept(first: 0, count: 1)]))
		}
		#expect {
			try malformed.decoded(moduleName: "Layer1", in: ["Layer0": lower])
		} throws: { error in
			expectedError == "\(error)"
		}
	}

	// MARK: Tests – A chain of records deeper than a stack holds

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func places_readsAndReleasesPlace_whenItsRecordsChainThousandsDeep() async throws {
		// One seam's places each name the one before as their record, as the places of a chain of seams that deep would,
		// and another seam's place names the last. Reading it follows every record, and letting go of what was read
		// releases every record: neither may nest a call per record, on a thread whose stack is half a megabyte.
		let written = try await chainOutput(layerCount: 2, viewsReferToModules: true)
		let upper = try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures)
		let lower = try #require(written.modules["Layer0"]?.moduleInfoFile?.seamSignatures)
		let places = try upper.storedPlaces
		let passedUp = try #require(places.placesBySeam[0].lazy.compactMap { place -> StoredPassedUpPlace? in
			if case let .passedUp(passedUp) = place {
				passedUp
			} else {
				nil
			}
		}.first)
		let whole = try #require(try lower.storedPlaces.placesBySeam[0].first)
		guard case let .written(wholePlace) = whole else {
			Issue.record("The bottom seam’s place is written whole.")
			return
		}
		let placeRead = try #require(try upper.decoded(moduleName: "Layer1", in: ["Layer0": lower]).first?.signature?.holes.first { $0.innerSeamType != nil })
		let declaration = try #require(placeRead.uncarriedDeclarations.first)
		#expect(!passedUp.addition.typesToCall.isEmpty)
		#expect(!passedUp.addition.route.isEmpty)
		let chainLength = 10000
		func copy(ofRecord record: Int) -> StoredPlace {
			.passedUp(StoredPassedUpPlace(
				record: StoredRecordReference(lowerSeam: 0, record: record),
				others: [],
				presentation: nil,
				addition: StoredPlaceAddition(typesToCall: passedUp.addition.typesToCall, route: passedUp.addition.route, isSendable: passedUp.addition.isSendable, declarations: [.record, .written(declaration)], reenteringCallDeclarations: nil, reenteringPlaceFields: nil),
			))
		}
		let chained = ModuleSeamSignatures(
			seamTypes: [upper.seamTypes[0], lower.seamTypes[0]],
			encoding: [],
			placesEncoding: ModuleSeamSignatures.encoding(of: StoredModulePlaces(
				lowerSeams: [StoredLowerSeam(moduleName: "", seamType: lower.seamTypes[0], checksum: 0)],
				placesBySeam: [[copy(ofRecord: chainLength - 1)], [whole] + (0..<chainLength - 1).map(copy(ofRecord:))],
			)),
		)
		// On a thread with the stack a concurrency thread has on macOS, whatever this platform gives one.
		let read: Result<[SeamSignature.Hole], any Error> = await withCheckedContinuation { continuation in
			let thread = Thread {
				var resolver = PlaceResolver(signaturesByModuleName: ["Chained": chained])
				let read = Result { try resolver.places(ofSeamAt: 0, inModuleNamed: "Chained", sharingSitePathsOf: nil) }
				// Letting go of the resolver releases every record it read.
				resolver = PlaceResolver(signaturesByModuleName: [:])
				continuation.resume(returning: read)
			}
			thread.stackSize = 512 * 1024
			thread.start()
		}
		let placesOfTop = try read.get()
		let top = try #require(placesOfTop.first)
		#expect(placesOfTop.count == 1)
		#expect(top.uncarriedDeclarations.count == chainLength + wholePlace.uncarriedDeclarations.count)
		#expect(top.typesToOwner.count == chainLength * passedUp.addition.typesToCall.count + placeRead.typesToOwner.count - passedUp.addition.typesToCall.count)
		#expect(top.passedUpRoute.count == chainLength * passedUp.addition.route.count)
	}

	// MARK: Tests – A run given a file whose places it cannot read

	/// A way the file of the module beneath a run's module can fail the read of its seam's places.
	enum Damage: CaseIterable {
		case placesCutShort
		case placeNamesLowerSeamNotListed
		case lowerSeamWrittenAgainstOtherPlaces
		case lowerSeamOfModuleNotGiven
	}

	@Test(arguments: Damage.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesSameCodeAsComputingEverySignature_whenPlacesOfModuleBeneathCannotBeRead(damage: Damage) async throws {
		let modules = Self.chainModules(layerCount: 3)
		let written = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		let computed = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, discardsStoredSeamSignatures: true, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		// A file whose checksum holds over places only a SafeDITool that wrote them wrong could make: the file reads, and
		// the places throw when the tree of the module above reaches the seam.
		let rewrite: @Sendable (ModuleInfoFile) throws -> ModuleInfoFile = { file in
			let places = try file.seamSignatures.storedPlaces
			let damagedPlacesEncoding: [UInt8] = switch damage {
			case .placesCutShort:
				file.seamSignatures.placesEncoding(writingPositionsAsAbsent: true).dropLast()
			case .placeNamesLowerSeamNotListed:
				ModuleSeamSignatures.encoding(of: StoredModulePlaces(lowerSeams: [], placesBySeam: places.placesBySeam))
			case .lowerSeamWrittenAgainstOtherPlaces:
				ModuleSeamSignatures.encoding(of: StoredModulePlaces(lowerSeams: places.lowerSeams.map { StoredLowerSeam(moduleName: $0.moduleName, seamType: $0.seamType, checksum: $0.checksum &+ 1) }, placesBySeam: places.placesBySeam))
			case .lowerSeamOfModuleNotGiven:
				ModuleSeamSignatures.encoding(of: StoredModulePlaces(lowerSeams: places.lowerSeams.map { StoredLowerSeam(moduleName: "Absent", seamType: $0.seamType, checksum: $0.checksum) }, placesBySeam: places.placesBySeam))
			}
			return ModuleInfoFile(
				moduleName: file.moduleName,
				ownEntryChecksum: file.ownEntryChecksum,
				packageName: file.packageName,
				dependencyModuleNames: file.dependencyModuleNames,
				imports: file.imports,
				mockImports: file.mockImports,
				instantiables: file.instantiables,
				configurations: file.configurations,
				filesWithUnexpectedNodes: file.filesWithUnexpectedNodes,
				conditionalCompilationDecisions: file.conditionalCompilationDecisions,
				instantiableTypeNamesInAnyClause: file.instantiableTypeNamesInAnyClause,
				plainTypeDeclarations: file.plainTypeDeclarations,
				seamSignatures: ModuleSeamSignatures(seamTypes: file.seamSignatures.seamTypes, encoding: file.seamSignatures.encoding(writingPositionsAsAbsent: true), placesEncoding: damagedPlacesEncoding),
				view: file.view,
			)
		}
		#expect(try #require(written.modules["Layer1"]?.moduleInfoFile?.seamSignatures).storedPlaces.placesBySeam.joined().contains { $0.isPassedUp })

		// The run tells of the block that threw, which is all that shows it computed again what the file stores.
		let (failedBlocks, failedBlocksContinuation) = AsyncStream<StoredBlockDecodeObservation.Block>.makeStream()
		var filesToDelete = [URL]()
		let damaged = try await StoredBlockDecodeObservation.$failureObserver.withValue({ failedBlocksContinuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, moduleInfoRewrites: ["Layer1": rewrite], modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		}
		self.filesToDelete += filesToDelete
		failedBlocksContinuation.finish()
		var blocksThatThrew = [StoredBlockDecodeObservation.Block]()
		for await block in failedBlocks {
			blocksThatThrew.append(block)
		}
		// Once in the run of `Layer2`, whose seam calls the seam of `Layer1`, and once in the run of `App`, whose tree reaches it.
		#expect(blocksThatThrew == [.seamSignatures, .seamSignatures])
		#expect(damaged.modules["Layer2"]?.generatedFiles == computed.modules["Layer2"]?.generatedFiles)
		#expect(damaged.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
		#expect(damaged.modules["App"]?.generatedFiles == written.modules["App"]?.generatedFiles)
		// The module above names no record of the file it could not read: it writes each place it passes up whole.
		#expect(damaged.modules["Layer2"]?.generateOutput?.passedUpPlacesWrittenInFull == 2)
		#expect(try #require(damaged.modules["Layer2"]?.moduleInfoFile?.seamSignatures).storedPlaces.placesBySeam.joined().contains { $0.isPassedUp } == false)
	}

	// MARK: Tests – A place the form does not hold

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesPlaceInFull_whenRecordDoesNotReadBackAsThePlace() async throws {
		let modules = Self.chainModules(layerCount: 3)
		let output = try await StoredPlaceWriteCheck.$alteringReadBackBytes.withValue({ $0 + [0] }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, modulesBeneath: { $0 }, viewsReferToModules: true, expectsPassedUpPlacesWrittenInFull: true, filesToDelete: &filesToDelete)
		}
		let placesWrittenInFull = output.modules.values.compactMap(\.generateOutput?.passedUpPlacesWrittenInFull).reduce(0, +)
		let computed = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, discardsStoredSeamSignatures: true, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
		// Layer1 passes up one place and Layer2 two, and the bytes handed back in place of each read differ from its own.
		#expect(placesWrittenInFull == 3)
		#expect(try #require(output.modules["Layer2"]?.moduleInfoFile?.seamSignatures).storedPlaces.placesBySeam.joined().contains { $0.isPassedUp } == false)
		#expect(output.modules["App"]?.generatedFiles == computed.modules["App"]?.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func executeSafeDIToolMultiModuleTest_recordsIssue_whenModuleWritesPassedUpPlaceInFull() async throws {
		// Every multi-module test and fuzzer graph runs under this check: a place the form does not hold fails the test.
		let modules = Self.chainModules(layerCount: 2)
		var filesToDelete = [URL]()
		try await withKnownIssue {
			_ = try await StoredPlaceWriteCheck.$alteringReadBackBytes.withValue({ $0 + [0] }) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, modulesBeneath: { $0 }, viewsReferToModules: true, filesToDelete: &filesToDelete)
			}
		} matching: { issue in
			issue.description.contains("The run of module `Layer1` wrote 1 passed-up place in full, not as the record it copies")
		}
		self.filesToDelete += filesToDelete
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func chainOutput(
		layerCount: Int,
		viewsReferToModules: Bool,
		passesModulesBeneath: Bool = true,
		discardsStoredSeamSignatures: Bool = false,
		compiles: Bool = false,
		bottomModelCount: Int = 1,
		placesOnlyAtBottom: Bool = false,
	) async throws -> MultiModuleTestOutput {
		try await executeSafeDIToolMultiModuleTest(
			modules: Self.chainModules(layerCount: layerCount, bottomModelCount: bottomModelCount, placesOnlyAtBottom: placesOnlyAtBottom),
			integration: .moduleInfo,
			compileVerification: compiles ? .recordingIssues : .skipped,
			discardsStoredSeamSignatures: discardsStoredSeamSignatures,
			modulesBeneath: passesModulesBeneath ? { $0 } : nil,
			viewsReferToModules: viewsReferToModules,
			filesToDelete: &filesToDelete,
		)
	}

	/// A public type that instantiates each of `properties`, a seam where `isSeam`.
	private static func instantiable(_ name: String, isSeam: Bool, _ properties: [(label: String, type: String)]) -> String {
		"""
		@Instantiable\(isSeam ? "(generateDependencyTree: true)" : "")
		public final class \(name): Instantiable {
			public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "\t\tself.\($0.label) = \($0.label)" }.joined(separator: "\n"))
			}
		\(properties.map { "\t@Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}
		"""
	}

	/// A public seam that receives `network: Network` and instantiates each of `properties`, written `label: Type`.
	private static func receivingSeam(_ name: String, building properties: String...) -> String {
		"""
		@Instantiable(generateDependencyTree: true)
		public final class \(name): Instantiable {
			public init(network: Network, \(properties.joined(separator: ", "))) {
				self.network = network
		\(properties.map { "\t\tself.\($0.prefix { $0 != ":" }) = \($0.prefix { $0 != ":" })" }.joined(separator: "\n"))
			}
			@Received let network: Network
		\(properties.map { "\t@Instantiated let \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	/// The module `App` above `Feature`, which fulfills `Gauge` and whose root instantiates `Feature`'s `seamName`.
	private static func appModule(instantiating seamName: String) -> ModuleFixture {
		ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
			"""
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [Gauge.self])
			public final class LiveGauge: Gauge, Instantiable {
				public init() {}
			}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
				public init(seam: \(seamName)) {
					self.seam = seam
				}
				@Instantiated let seam: \(seamName)
			}
			""",
		], dependencies: ["Feature"])
	}

	/// `Core`, then `layerCount` seams each of which builds the one beneath it and a model that builds `any Gauge`, which
	/// no module beneath `App` fulfills, then `App`, whose root builds the top seam: the place of each model is passed up
	/// through every seam above it. The seams are `layersPerModule` to a module, the lowest in `Layer0`.
	/// - Parameters:
	///   - bottomModelCount: How many properties of the bottom seam build its model.
	///   - placesOnlyAtBottom: Whether only the bottom seam builds a model.
	private static func chainModules(layerCount: Int, layersPerModule: Int = 1, bottomModelCount: Int = 1, placesOnlyAtBottom: Bool = false) -> [ModuleFixture] {
		var modules = [ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: [
			"""
			public protocol Gauge {}

			@Instantiable
			public final class Service: Instantiable {
				public init() {}
			}
			""",
		])]
		let moduleCount = layerCount / layersPerModule
		for module in 0..<moduleCount {
			var content = "import Core\n" + (module == 0 ? "" : "import Layer\(module - 1)\n")
			for layer in (module * layersPerModule)..<((module + 1) * layersPerModule) {
				let modelCount = layer == 0 ? bottomModelCount : placesOnlyAtBottom ? 0 : 1
				let models = (0..<modelCount).map { "model\(layer)_\($0)" }
				let parameters = ["service: Service"] + models.map { "\($0): Model\(layer)" } + (layer == 0 ? [] : ["entry\(layer - 1)Builder: Instantiator<Entry\(layer - 1)>"])
				content += """

				@Instantiable(generateDependencyTree: true)
				public final class Entry\(layer): Instantiable {
					public init(\(parameters.joined(separator: ", "))) {
						self.service = service
				\(models.map { "\t\tself.\($0) = \($0)\n" }.joined())\(layer == 0 ? "" : "\t\tself.entry\(layer - 1)Builder = entry\(layer - 1)Builder\n")\t}
					@Received let service: Service
				\(models.map { "\t@Instantiated let \($0): Model\(layer)\n" }.joined())\(layer == 0 ? "" : "\t@Instantiated let entry\(layer - 1)Builder: Instantiator<Entry\(layer - 1)>\n")}

				"""
				if modelCount > 0 {
					content += """

					@Instantiable
					public final class Model\(layer): Instantiable {
						public init(service: Service, gauge: any Gauge) {
							self.service = service
							self.gauge = gauge
						}
						@Received let service: Service
						@Instantiated let gauge: any Gauge
					}

					"""
				}
			}
			modules.append(ModuleFixture(name: "Layer\(module)", packageName: "Base", swiftFileContent: [content], dependencies: ["Core"] + (module == 0 ? [] : ["Layer\(module - 1)"])))
		}
		modules.append(ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
			"""
			import Core
			import Layer\(moduleCount - 1)

			@Instantiable(fulfillingAdditionalTypes: [Gauge.self])
			public final class LiveGauge: Gauge, Instantiable {
				public init() {}
			}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
				public init(service: Service, entry: Entry\(layerCount - 1)) {
					self.service = service
					self.entry = entry
				}
				@Instantiated let service: Service
				@Instantiated let entry: Entry\(layerCount - 1)
			}
			""",
		], dependencies: ["Core", "Layer\(moduleCount - 1)"]))
		return modules
	}
}
