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
@testable import SafeDITool

/// When `generate` reuses the module `scan` cached, verified through the two commands.
///
/// The input CSV lists absolute paths while scan records paths relative to the project root,
/// so a fresh parse in `generate` names the root differently from the manifest and fails with
/// `rootNotInManifest`. Success therefore shows `generate` reused scan's cache, and that error shows
/// it parsed afresh.
struct SafeDIToolScanCacheFreshnessTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesCache_whenNoInputChanged() async throws {
		let project = try await scannedProject()

		try await project.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenInputContentAndModificationTimeChange() async throws {
		let project = try await scannedProject()
		try Self.rootContent.appending("\n// Edited.\n").write(to: project.rootFile, atomically: true, encoding: .utf8)
		try FileModificationTime(seconds: 4_000_000_000, nanoseconds: 0).apply(toItemAtPath: project.rootFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenModificationTimeMovesBackward() async throws {
		// A checkout or copy that restores an older file reports an earlier time than the scan saw.
		let project = try await scannedProject()
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.rootFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenModificationTimeChangesWithinTheSameSecond() async throws {
		let project = try await scannedProject()
		let scannedTime = try FileModificationTime(ofItemAtPath: project.rootFile.path)
		try FileModificationTime(
			seconds: scannedTime.seconds,
			nanoseconds: scannedTime.nanoseconds == 0 ? 1 : scannedTime.nanoseconds - 1,
		).apply(toItemAtPath: project.rootFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesCache_whenContentChangesButModificationTimeIsRestored() async throws {
		// The check reads modification times only, which is what lets other tests hide an edit from it.
		let project = try await scannedProject()
		let scannedTime = try FileModificationTime(ofItemAtPath: project.rootFile.path)
		try Self.rootContent.appending("\n// Edited.\n").write(to: project.rootFile, atomically: true, encoding: .utf8)
		try scannedTime.apply(toItemAtPath: project.rootFile.path)

		try await project.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesCache_whenSymbolicLinkAndTargetAreUnchanged() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)

		try await project.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenSymbolicLinkTargetChanges() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.targetFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenSymbolicLinkIsRetargetedToFileWithTheSameModificationTime() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)
		let otherTarget = project.directory.appendingPathComponent("OtherTarget.swift")
		try Self.rootContent.write(to: otherTarget, atomically: true, encoding: .utf8)
		try FileModificationTime(ofItemAtPath: project.targetFile.path).apply(toItemAtPath: otherTarget.path)
		let linkTime = try FileModificationTime(ofItemAtPath: project.rootFile.path)
		try FileManager.default.removeItem(at: project.rootFile)
		try FileManager.default.createSymbolicLink(at: project.rootFile, withDestinationURL: otherTarget)
		// Only the link itself changed, and a link's own time is what reveals that.
		#expect(try FileModificationTime(ofItemAtPath: project.rootFile.path) != linkTime)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenSymbolicLinkTargetIsDeleted() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)
		try FileManager.default.removeItem(at: project.targetFile)

		// The fresh parse cannot read the dangling link.
		await assertThrowsError(containing: "Root.swift") {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsJSONFromAnEarlierRelease() async throws {
		// Earlier releases wrote the cache as JSON, under another name.
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			try JSONEncoder().encode(CachedScannedModuleInfo(scanCacheData: cache))
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsEmpty() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { _ in Data() }

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsCutShort() async throws {
		// A write interrupted before it finished, for a build system that does not write atomically.
		let project = try await scannedProject()
		try project.rewriteCache { cache in cache.dropLast() }

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsCorrupted() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.endIndex - 1] ^= 0x01
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheDoesNotBeginWithMagic() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.startIndex] = UInt8(ascii: "X")
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheHasAnotherFormatVersion() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.startIndex + 4] &+= 1
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheHasAnotherSchemaFingerprint() async throws {
		// A SafeDITool whose cached types are laid out differently, such as another development build.
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.startIndex + 6] ^= 0x01
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesTypeDeclarationOfFileWithoutSafeDIMarker_whenExtensionHoldingInstantiableExtendsItsType() async throws {
		let project = try await scannedProject(alongside: Self.namespaceFiles)

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Space")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.package])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Space.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileWithoutSafeDIMarkerDeclaringExtendedTypeChanges() async throws {
		let project = try await scannedProject(alongside: Self.namespaceFiles)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.directory.appendingPathComponent("Space.swift").path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesProtocolDeclarationOfFileWithoutSafeDIMarker_whenDeclarationsInitializerMentionsIt() async throws {
		let project = try await scannedProject(alongside: Self.mentionedProtocolFiles)

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Theme")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.public])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Theme.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileWithoutSafeDIMarkerDeclaringMentionedProtocolChanges() async throws {
		let project = try await scannedProject(alongside: Self.mentionedProtocolFiles)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.directory.appendingPathComponent("Theme.swift").path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileWalkedAgainUnderGeneratesConditionsMentionsTypeScansDeclarationsDidNot() async throws {
		// Under scan's conditions no declaration mentions `Theme`, so scan read no declaration of it; under `STAGING`
		// `Badge`'s does, which only a fresh parse reads.
		let project = try await scannedProject(alongside: [
			"Theme.swift": "public protocol Theme {}",
			"Badge.swift": """
			@Instantiable
			public struct Badge: Instantiable {
			    #if STAGING
			    public init(theme: (any Theme)?) {
			        self.theme = theme
			    }

			    @Received(onlyIfAvailable: true) let theme: (any Theme)?
			    #else
			    public init() {}
			    #endif
			}
			""",
		])

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate(activeCompilationConditions: ["STAGING"])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSelectedClauseFromRewalk_whenScanLackedFlagAndGenerateHasIt() async throws {
		// IF18: scan selected the `#else` clause; `generate`, given `FLAG`, walks the file again and reads the `package`
		// declaration, as a scan with `FLAG` would have.
		let files = try await generatedFilesFromRewalk(of: ["Badge.swift": Self.tokenInEachClauseOfFlag + Self.badgeSeam], scannedWith: [], generatedWith: ["FLAG"])
		#expect(files.cached == files.reference)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.activeAssertion("FLAG") + Self.packageTierBadge)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSelectedClauseFromRewalk_whenScanHadFlagAndGenerateLacksIt() async throws {
		// IF18: scan selected the `#if` clause; `generate`, without `FLAG`, reads the `public` declaration.
		let files = try await generatedFilesFromRewalk(of: ["Badge.swift": Self.tokenInEachClauseOfFlag + Self.badgeSeam], scannedWith: ["FLAG"], generatedWith: [])
		#expect(files.cached == files.reference)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.inactiveAssertion("FLAG") + Self.publicTierBadge)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSelectedClauseFromRewalk_whenMarkerFreeFileDeclaresTypeInsideFlagBlock() async throws {
		// IF18: `Token.swift` holds no SafeDI marker, but the conditions its block consults make it a file `generate` parses
		// again rather than skips.
		let files = try await generatedFilesFromRewalk(of: ["Badge.swift": Self.badgeSeam, "Token.swift": Self.tokenInEachClauseOfFlag], scannedWith: [], generatedWith: ["FLAG"])
		#expect(files.cached == files.reference)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.activeAssertion("FLAG") + Self.packageTierBadge)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSelectedClauseFromRewalk_whenFlagBlockIsNestedInPlatformBlock() async throws {
		// IF18: the platform block declares `Token` in no clause directly, but the `FLAG` block nested in it does, so the
		// outer block's walk consults `FLAG` too.
		let token = "#if canImport(Foundation)\n#if FLAG\npackage struct Token {}\n#else\npublic struct Token {}\n#endif\n#endif\n\n"
		let files = try await generatedFilesFromRewalk(of: ["Badge.swift": token + Self.badgeSeam], scannedWith: [], generatedWith: ["FLAG"])
		#expect(files.cached == files.reference)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.activeAssertion("FLAG") + Self.packageTierBadge)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSelectedClauseFromRewalk_whenPlatformBlockIsNestedInFlagBlock() async throws {
		// IF18: the platform block in the clause `FLAG` selects is read whole.
		let token = "#if FLAG\n#if canImport(Foundation)\npackage struct Token {}\n#endif\n#else\npublic struct Token {}\n#endif\n\n"
		let files = try await generatedFilesFromRewalk(of: ["Badge.swift": token + Self.badgeSeam], scannedWith: [], generatedWith: ["FLAG"])
		#expect(files.cached == files.reference)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.activeAssertion("FLAG") + Self.packageTierBadge)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsSelectedClauseFromRewalk_whenFlagBlockHoldsImportAndTypeDeclaration() async throws {
		// IF18: a block that holds an import is read again for its imports alone only when it declares no plain type.
		let token = "#if FLAG\nimport Foundation\npackage struct Token {}\n#else\npublic struct Token {}\n#endif\n\n"
		let files = try await generatedFilesFromRewalk(of: ["Badge.swift": token + Self.badgeSeam], scannedWith: [], generatedWith: ["FLAG"])
		#expect(files.cached == files.reference)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + "#if canImport(Foundation)\nimport Foundation\n#endif\n\n" + Self.activeAssertion("FLAG") + Self.packageTierBadge)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenRewalkedFileStopsMentioningTypeScanKept() async throws {
		// IF18: under `FLAG`, `Holder` mentions `Token`, so scan kept `Token.swift`'s declarations and asserted the `OTHER`
		// decision that skips them; without `FLAG`, nothing mentions `Token`, so a fresh parse reads no declaration of it
		// and asserts nothing about `OTHER`, though `Token.swift` itself consults no condition that changed.
		let files = try await generatedFilesFromCacheAndAfresh(
			of: [
				"Badge.swift": Self.badgeBuildingCache,
				"Holder.swift": Self.holderMentioningTokenUnderFlag,
				"Token.swift": "#if OTHER\npackage struct Token {}\n#else\npublic struct Token {}\n#endif",
			],
			scannedWith: ["FLAG"],
			generatedWith: [],
		)
		#expect(files.cached == files.fresh)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.inactiveAssertion("FLAG") + Self.badgeBuildingCacheTiers)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenRewalkedFileStopsMentioningInstantiableTypeNameGuardedNestedTypeShares() async throws {
		// IF18: `Token` is a top-level `@Instantiable` type, whose own declaration proves it, and `Outer.Token`, which the
		// module keeps since `Outer` encloses an `@Instantiable` type, is declared under `#if OTHER`. Under `FLAG`, `Holder`
		// mentions `Token`, so scan asserted the `OTHER` decision that skips `Outer.Token`; without `FLAG`, nothing
		// mentions `Token`, so a fresh parse asserts nothing about `OTHER`, and `generate` parses afresh too, though
		// `Outer.swift` consults no condition that changed.
		let files = try await generatedFilesFromCacheAndAfresh(
			of: [
				"Badge.swift": Self.badgeBuildingCache,
				"Holder.swift": Self.holderMentioningTokenUnderFlag,
				"Outer.swift": "public enum Outer {\n    @Instantiable\n    public struct Inner: Instantiable {\n        public init() {}\n    }\n\n    #if OTHER\n    struct Token {}\n    #endif\n}",
				"Token.swift": "@Instantiable\npublic struct Token: Instantiable {\n    public init() {}\n}",
			],
			scannedWith: ["FLAG"],
			generatedWith: [],
		)
		#expect(files.cached == files.fresh)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.inactiveAssertion("FLAG") + Self.badgeBuildingCacheTiers)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenRewalkedFileStartsMentioningTypeScanDidNotKeep() async throws {
		// IF18: the reverse: under `FLAG`, `Holder` mentions `Token`, which scan, without it, did not keep, so `generate`
		// parses afresh and asserts the `OTHER` decision that skips `Token`'s declaration.
		let files = try await generatedFilesFromCacheAndAfresh(
			of: [
				"Badge.swift": Self.badgeBuildingCache,
				"Holder.swift": Self.holderMentioningTokenUnderFlag,
				"Token.swift": "#if OTHER\npackage struct Token {}\n#else\npublic struct Token {}\n#endif",
			],
			scannedWith: [],
			generatedWith: ["FLAG"],
		)
		#expect(files.cached == files.fresh)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.activeAssertion("FLAG") + Self.inactiveAssertion("OTHER") + Self.badgeBuildingCacheTiers)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsModuleFilesByModuleNames_whenOnlyAdditionalDirectoryFileMentionsTypeOfRewalkedFile() async throws {
		// IF18: only `Extra`'s `Reader`, which `Feature` reads through `additionalDirectoriesToInclude`, mentions `Token`. A
		// fresh parse keeps the declarations of a module file by the names the module's own declarations mention, so it
		// drops `Gadget.swift`'s `Token` and asserts nothing about `FLAG`; `generate`, walking `Gadget.swift` again for
		// `STAGING`, keeps what a fresh parse keeps.
		let files = try await generatedFilesFromCacheAndAfresh(
			of: [
				"Badge.swift": Self.badgeBuildingCache,
				"Gadget.swift": """
				#if FLAG
				package struct Token {}
				#endif

				#if STAGING
				@Instantiable
				public struct Gadget: Instantiable {
				    public init() {}
				}
				#endif
				""",
				"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"])\n",
			],
			additionalDirectoryFiles: [
				"Reader.swift": "public struct Token {}\n\n@Instantiable\npublic struct Reader: Instantiable {\n    public init(token: Token) {\n        self.token = token\n    }\n\n    @Forwarded let token: Token\n}",
			],
			scannedWith: ["FLAG"],
			generatedWith: ["FLAG", "STAGING"],
		)
		#expect(files.cached == files.fresh)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.activeAssertion("STAGING") + Self.badgeBuildingCacheTiers)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsNothingAboutAdditionalDirectorysInternalType_whenItWalksTheFileAgain() async throws {
		// IF18: `Reader.swift`, which `Feature` reads through `additionalDirectoriesToInclude`, declares `Token` `internal`
		// under `FLAG` and mentions it, so its scan consults `FLAG`, and `generate`, which reports `FLAG`, walks it again.
		// The file is another module's, whose `internal` declaration no mention in `Feature` names, so neither that walk nor
		// a fresh parse asserts `FLAG`.
		let files = try await generatedFilesFromCacheAndAfresh(
			of: [
				"Badge.swift": Self.badgeBuildingCache,
				"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"])\n",
			],
			additionalDirectoryFiles: [
				"Reader.swift": "#if FLAG\nstruct Token {}\n#endif\n\n@Instantiable\npublic struct Reader: Instantiable {\n    public init(token: Token?) {\n        self.token = token\n    }\n\n    @Received(onlyIfAvailable: true) let token: Token?\n}",
			],
			scannedWith: [],
			generatedWith: ["FLAG"],
		)
		#expect(files.cached == files.fresh)
		#expect(files.cached["Badge+SafeDI.swift"] == generatedFileHeader + Self.badgeBuildingCacheTiers)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesNoRecordOfSkippedClause_whenFlagIsNotReported() async throws {
		// IF18: without `FLAG`, scan records the `#else` clause's declaration alone.
		let project = try await scannedProject(alongside: ["Badge.swift": Self.tokenInEachClauseOfFlag + Self.badgeSeam])

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		let badgeScan = try #require(cache.conditionSensitiveFileScans.first { $0.fileScan.path == "Badge.swift" })
		#expect(badgeScan.fileScan.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Token")])
		#expect(badgeScan.fileScan.plainTypeDeclarations.map(\.access.level) == [.public])
		#expect(badgeScan.fileScan.plainTypeDeclarations.map(\.access.declarationStartLocation?.line) == [4])
		#expect(badgeScan.fileScan.consultedCompilationConditions == ["FLAG"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesPlainDeclarationDecisionsWithNames_whenBlockDeclaresTypeADeclarationMentions() async throws {
		// IF18: `Badge` mentions `Token`, so the decision that selects the clause declaring it is cached among the file's
		// decisions, which every generated file asserts.
		let project = try await scannedProject(alongside: ["Badge.swift": Self.tokenInEachClauseOfFlag + Self.badgeSeam])

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		let badgeScan = try #require(cache.conditionSensitiveFileScans.first { $0.fileScan.path == "Badge.swift" })
		#expect(badgeScan.fileScan.conditionalCompilationDecisions == [ConditionalCompilationDecision(condition: "FLAG", isActive: false)])
		#expect(badgeScan.fileScan.plainTypeDeclarationDecisions.isEmpty)
		#expect(cache.keptPlainTypeNames == KeptPlainTypeNames(outermostTypeNames: ["Badge", "Cache", "Root", "Token"], mentionedTypeNames: ["Cache", "Token"], extendedTypeNames: []))
		#expect(cache.additionalKeptPlainTypeNames == cache.keptPlainTypeNames)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_dropsPlainDeclarationDecisionsAndConsultsNothing_whenNothingMentionsTheType() async throws {
		// IF18: no declaration mentions `Unrelated`, so the module keeps no declaration of it, whichever clause is selected:
		// the decision that skips it is not asserted, and the file consults no condition, so `generate` never walks it
		// again for `FLAG`.
		let project = try await scannedProject(alongside: ["Badge.swift": "#if FLAG\nstruct Unrelated {}\n#endif\n\n" + Self.badgeSeam, "Token.swift": "public struct Token {}"])

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.conditionSensitiveFileScans.isEmpty)
		#expect(cache.moduleInfo.conditionalCompilationDecisions.isEmpty)
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Token")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesTypealias_whenFileWithoutSafeDIMarkerDeclaresTypeADeclarationMentions() async throws {
		// C8: the text search finds `typealias Handler`, so the file is parsed and its typealias recorded.
		let project = try await scannedProject(alongside: [
			"Handler.swift": "public typealias Handler = () -> Void",
			"Badge.swift": """
			@Instantiable
			public struct Badge: Instantiable {
			    public init(handler: @escaping Handler) {
			        self.handler = handler
			    }

			    @Received let handler: Handler
			}
			""",
		])

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Handler")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.public])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Handler.swift"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Token`, declared `package` when `FLAG` is active and `public` otherwise, followed by a blank line.
	private static let tokenInEachClauseOfFlag = "#if FLAG\npackage struct Token {}\n#else\npublic struct Token {}\n#endif\n\n"

	/// The seam `Badge`, which receives `token` only if available and builds `Cache`.
	private static let badgeSeam = """
	@Instantiable(generateDependencyTree: true)
	public struct Badge: Instantiable {
	    init(token: Token?, cache: Cache) {
	        self.token = token
	        self.cache = cache
	    }

	    @Received(onlyIfAvailable: true) let token: Token?
	    @Instantiated let cache: Cache
	}

	@Instantiable
	struct Cache: Instantiable {
	    init() {}
	}
	"""

	/// The seam `Badge`, which builds `Cache` and mentions no other type, and `Cache`.
	private static let badgeBuildingCache = """
	@Instantiable(generateDependencyTree: true)
	public struct Badge: Instantiable {
	    init(cache: Cache) {
	        self.cache = cache
	    }

	    @Instantiated let cache: Cache
	}

	@Instantiable
	struct Cache: Instantiable {
	    init() {}
	}
	"""

	/// `badgeBuildingCache`'s generated initializers, after its file's header and assertions.
	private static let badgeBuildingCacheTiers = """
	extension Badge {
	    public init() {
	        let cache = Cache()
	        self.init(cache: cache)
	    }
	}

	extension Badge {
	    public enum __safeDI_Badge_CBF29CE484222325 {}
	}
	"""

	/// `Holder`, whose initializer mentions `Token` only when `FLAG` is active.
	private static let holderMentioningTokenUnderFlag = """
	@Instantiable
	public struct Holder: Instantiable {
	    #if FLAG
	    public init(token: Token?) {
	        self.token = token
	    }

	    @Received(onlyIfAvailable: true) let token: Token?
	    #else
	    public init() {}
	    #endif
	}
	"""

	/// `Badge`'s generated initializers, after its file's header and assertions, when `Token` is `package`.
	private static let packageTierBadge = """
	extension Badge {
	    public init() {
	        self.init(token: nil)
	    }

	    package init(token: Token? = nil) {
	        let cache = Cache()
	        self.init(token: token, cache: cache)
	    }
	}

	extension Badge {
	    public enum __safeDI_Badge_16885A1AAD60582A {}
	}
	"""

	/// `Badge`'s generated initializers, after its file's header and assertions, when `Token` is `public`.
	private static let publicTierBadge = """
	extension Badge {
	    public init(token: Token? = nil) {
	        let cache = Cache()
	        self.init(token: token, cache: cache)
	    }
	}

	extension Badge {
	    public enum __safeDI_Badge_029593DA1BB2FBD5 {}
	}
	"""

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as active.
	private static func activeAssertion(_ condition: String) -> String {
		"""
		#if !(\(condition))
		#error("SafeDI scanned this module assuming `#if \(condition)` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as inactive.
	private static func inactiveAssertion(_ condition: String) -> String {
		"""
		#if \(condition)
		#error("SafeDI scanned this module assuming `#if \(condition)` was inactive, but it is active in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

	/// A protocol in a file of its own, which mentions no SafeDI marker, and a declaration whose initializer mentions it.
	private static let mentionedProtocolFiles = [
		"Theme.swift": "public protocol Theme {}",
		"Badge.swift": """
		@Instantiable
		public struct Badge: Instantiable {
		    public init(theme: any Theme) {
		        self.theme = theme
		    }

		    @Received let theme: any Theme
		}
		""",
	]

	/// A namespace enum in a file of its own, which mentions no SafeDI marker, and an extension of it that declares an
	/// `@Instantiable` type.
	private static let namespaceFiles = [
		"Space.swift": "package enum Space {}",
		"Shelf.swift": """
		extension Space {
		    @Instantiable
		    public final class Shelf: Instantiable {
		        public init() {}
		    }
		}
		""",
	]

	private static let rootContent = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init() {}
	}
	"""

	private struct ScannedProject {
		let directory: URL
		/// The input the CSV lists.
		let rootFile: URL
		/// The file `rootFile` links to, or `rootFile` itself.
		let targetFile: URL
		let swiftFileCSV: URL
		let manifestFile: URL

		/// Replaces the cache scan wrote with what `rewrite` makes of it.
		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		func rewriteCache(_ rewrite: (Data) throws -> Data) throws {
			let cacheURL = scannedModuleInfoURL(forManifestPath: manifestFile.path)
			try rewrite(Data(contentsOf: cacheURL)).write(to: cacheURL)
		}

		/// The error a fresh parse in `generate` throws, naming the root as the CSV does.
		var rootNotInManifestMessage: String {
			"Found @Instantiable(isRoot: true) in '\(rootFile.path)', but this file is not listed in the manifest’s dependencyTreeGeneration. SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateDependencyTree: true` or `generateMock: true`, or a #SafeDIConfiguration in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it. A hand-written manifest must list the file, or the type must not be a root."
		}

		func generate(activeCompilationConditions: [String] = []) async throws {
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			] + (activeCompilationConditions.isEmpty ? [] : ["--active-compilation-conditions"] + activeCompilationConditions)).run()
		}
	}

	/// A project whose root is in `Root.swift`, and which holds the content of `otherFiles` at each file name.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedProject(throughSymbolicLink: Bool = false, alongside otherFiles: [String: String] = [:]) async throws -> ScannedProject {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let rootFile = directory.appendingPathComponent("Root.swift")
		let targetFile = throughSymbolicLink ? directory.appendingPathComponent("Target.swift") : rootFile
		try Self.rootContent.write(to: targetFile, atomically: true, encoding: .utf8)
		if throughSymbolicLink {
			try FileManager.default.createSymbolicLink(at: rootFile, withDestinationURL: targetFile)
		}
		let otherFileURLs = try otherFiles.keys.sorted().map { fileName in
			let fileURL = directory.appendingPathComponent(fileName)
			try otherFiles[fileName]?.write(to: fileURL, atomically: true, encoding: .utf8)
			return fileURL
		}
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try ([rootFile] + otherFileURLs).map(\.path).joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [directory, swiftFileCSV, outputDirectory, manifestFile, scannedModuleInfoURL(forManifestPath: manifestFile.path)]

		try await Scan.parse([
			"--input-sources-file", swiftFileCSV.path,
			"--project-root", directory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		]).run()
		return ScannedProject(
			directory: directory,
			rootFile: rootFile,
			targetFile: targetFile,
			swiftFileCSV: swiftFileCSV,
			manifestFile: manifestFile,
		)
	}

	/// What `generate` writes under `generatedWith` for module `Feature`, holding `files`, which the SwiftPM plugin scans
	/// under `scannedWith` and whose build settings then report `generatedWith`, from scan's cache, which walks again each
	/// file whose block consults a condition the two sets give different values; and what it writes for a scan under
	/// `generatedWith`, which walks nothing again.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generatedFilesFromRewalk(of files: [String: String], scannedWith scanConditions: [String], generatedWith generateConditions: [String]) async throws -> (cached: [String: String], reference: [String: String]) {
		let buildSettingArguments = [
			"--build-setting-active-compilation-conditions=[\(generateConditions.joined(separator: " "))]",
			"--build-setting-other-swift-flags=[]",
		]
		let cached = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: files, activeCompilationConditions: scanConditions, buildSettingArguments: buildSettingArguments, verificationCompilationConditions: generateConditions)],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: files, activeCompilationConditions: generateConditions, buildSettingArguments: buildSettingArguments)],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		return (cached.modules["Feature"]?.generatedFiles ?? [:], reference.modules["Feature"]?.generatedFiles ?? [:])
	}

	/// What `generate` writes under `generatedWith` for a project holding `Root.swift` and `files`, from a cache `scan` wrote
	/// under `scannedWith`, and what it writes for the same manifest once that cache is gone, which it parses afresh. Each
	/// file's `$ADDITIONAL_DIRECTORY` names a directory outside the target holding `additionalDirectoryFiles`, which the
	/// input CSV does not list. As the plugin's, the CSV's paths are relative to the project root, which is the working
	/// directory, so a fresh parse names each file as the manifest does.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generatedFilesFromCacheAndAfresh(
		of files: [String: String],
		additionalDirectoryFiles: [String: String] = [:],
		scannedWith scanConditions: [String],
		generatedWith generateConditions: [String],
	) async throws -> (cached: [String: String], fresh: [String: String]) {
		let projectRoot = FileManager.default.currentDirectoryPath
		let fixtureDirectory = ".build/SafeDIToolTestFixtures/\(UUID().uuidString)"
		let fixtureURL = URL(fileURLWithPath: projectRoot).appendingPathComponent(fixtureDirectory)
		filesToDelete.append(fixtureURL)
		let outputDirectory = fixtureURL.appendingPathComponent("Output")
		for directory in ["Target", "Extra", "Output"] {
			try FileManager.default.createDirectory(at: fixtureURL.appendingPathComponent(directory), withIntermediateDirectories: true)
		}
		for (fileName, content) in additionalDirectoryFiles {
			try content.write(to: fixtureURL.appendingPathComponent("Extra").appendingPathComponent(fileName), atomically: true, encoding: .utf8)
		}
		var inputFilePaths = ["\(fixtureDirectory)/Target/Root.swift"]
		try Self.rootContent.write(to: fixtureURL.appendingPathComponent("Target/Root.swift"), atomically: true, encoding: .utf8)
		for fileName in files.keys.sorted() {
			try files[fileName]?
				.replacingOccurrences(of: "$ADDITIONAL_DIRECTORY", with: "\(fixtureDirectory)/Extra")
				.write(to: fixtureURL.appendingPathComponent("Target").appendingPathComponent(fileName), atomically: true, encoding: .utf8)
			inputFilePaths.append("\(fixtureDirectory)/Target/\(fileName)")
		}
		let swiftFileCSV = fixtureURL.appendingPathComponent("Inputs.csv")
		try inputFilePaths.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		// The scan cache lies beside the manifest, inside the fixture directory.
		let manifestFile = fixtureURL.appendingPathComponent("Manifest.json")

		try await Scan.parse([
			"--input-sources-file", swiftFileCSV.path,
			"--project-root", projectRoot,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		] + (scanConditions.isEmpty ? [] : ["--active-compilation-conditions"] + scanConditions)).run()
		func generatedFiles() async throws -> [String: String] {
			// The build settings, which replace the conditions the manifest records, as Swift Build expands them.
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
				"--build-setting-active-compilation-conditions=[\(generateConditions.joined(separator: " "))]",
				"--build-setting-other-swift-flags=[]",
			]).run()
			let manifest = try JSONDecoder().decode(SafeDIToolManifest.self, from: Data(contentsOf: manifestFile))
			var generatedFiles = [String: String]()
			for outputFilePath in (manifest.dependencyTreeGeneration + manifest.mockGeneration).map(\.outputFilePath) {
				generatedFiles[(outputFilePath as NSString).lastPathComponent] = try String(contentsOfFile: outputFilePath, encoding: .utf8)
			}
			return generatedFiles
		}
		let cached = try await generatedFiles()
		try FileManager.default.removeItem(at: scannedModuleInfoURL(forManifestPath: manifestFile.path))
		let fresh = try await generatedFiles()
		return (cached, fresh)
	}
}
