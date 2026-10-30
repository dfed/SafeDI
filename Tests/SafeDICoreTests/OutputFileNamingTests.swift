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

import SafeDICore
import Testing

struct OutputFileNamingTests {
	@Test
	func outputFileNames_suffixesTheLaterPath_whenADirectoryPrefixedNameMatchesAnotherFileName() {
		#expect(outputFileNames(forFilesAt: ["Feature/Root.swift", "Root.swift", "Feature_Root.swift"]) == [
			"Feature_Root+SafeDI.swift",
			"Root+SafeDI.swift",
			"Feature_Root_2+SafeDI.swift",
		])
	}

	@Test
	func outputFileNames_suffixesTheLaterPath_whenPrefixingEveryParentDirectoryLeavesACollision() {
		// At one directory these are `A_B_Root`, `B_Root`, and `B_Root`; at two, `A_B_Root` twice and `C_B_Root`.
		#expect(outputFileNames(forFilesAt: ["A_B/Root.swift", "A/B/Root.swift", "C/B/Root.swift"]) == [
			"A_B_Root_2+SafeDI.swift",
			"A_B_Root+SafeDI.swift",
			"C_B_Root+SafeDI.swift",
		])
	}

	@Test
	func outputFileNames_skipsASuffixAnotherFileUses_whenResolvingACollision() {
		#expect(outputFileNames(forFilesAt: ["Feature/Root.swift", "Root.swift", "Feature_Root.swift", "Feature_Root_2.swift"]) == [
			"Feature_Root+SafeDI.swift",
			"Root+SafeDI.swift",
			"Feature_Root_3+SafeDI.swift",
			"Feature_Root_2+SafeDI.swift",
		])
	}

	@Test
	func outputFileNames_prefixesParentDirectories_whenFileNamesDifferOnlyInLetterCase() {
		// A volume that ignores letter case, such as macOS's default, would hold `Root+SafeDI.swift` and
		// `root+SafeDI.swift` as one file.
		#expect(outputFileNames(forFilesAt: ["A/Root.swift", "B/root.swift"]) == [
			"A_Root+SafeDI.swift",
			"B_root+SafeDI.swift",
		])
	}

	@Test
	func outputFileNames_suffixesTheLaterPath_whenAPrefixedNameMatchesAnotherFileNameIgnoringLetterCase() {
		#expect(outputFileNames(forFilesAt: ["Feature/root.swift", "Root.swift", "feature_Root.swift"]) == [
			"Feature_root+SafeDI.swift",
			"Root+SafeDI.swift",
			"feature_Root_2+SafeDI.swift",
		])
	}

	@Test
	func outputFileNames_prefixesParentDirectories_whenFileNamesDifferInLetterCaseAndUnicodeNormalization() {
		// `É` precomposed in one name, and `e` followed by a combining acute accent in the other.
		#expect(outputFileNames(forFilesAt: ["A/CAF\u{C9}.swift", "B/cafe\u{301}.swift"]) == [
			"A_CAF\u{C9}+SafeDI.swift",
			"B_cafe\u{301}+SafeDI.swift",
		])
	}

	@Test
	func outputFileNames_namesEachPathTheSame_whenInputOrderChanges() {
		let inputFilePaths = ["Feature/Root.swift", "Root.swift", "Feature_Root.swift", "Feature_Root_2.swift", "A_B/Root.swift", "A/B/Root.swift", "feature/root.swift", "B/ROOT.swift"]
		let expectedNamesByPath = Dictionary(uniqueKeysWithValues: zip(inputFilePaths, outputFileNames(forFilesAt: inputFilePaths)))
		for reorderedInputFilePaths in [inputFilePaths.reversed(), inputFilePaths.sorted(), inputFilePaths.sorted().reversed()] {
			#expect(Dictionary(uniqueKeysWithValues: zip(reorderedInputFilePaths, outputFileNames(forFilesAt: reorderedInputFilePaths))) == expectedNamesByPath)
		}
	}

	@Test
	func mockOutputFileNames_suffixesTheLaterPath_whenADirectoryPrefixedNameMatchesAnotherFileName() {
		let names = mockOutputFileNames(forFilesAt: ["Feature/Service.swift", "Service.swift", "Feature_Service.swift"], additionalMocksToGenerate: [])
		#expect(names.mockFiles == [
			"Feature_Service+SafeDIMock.swift",
			"Service+SafeDIMock.swift",
			"Feature_Service_2+SafeDIMock.swift",
		])
		#expect(names.additionalMocks == [])
	}

	@Test
	func mockOutputFileNames_suffixesAnAdditionalMock_whenItsTypeNameMatchesAFileMockName() {
		let names = mockOutputFileNames(forFilesAt: ["Service.swift"], additionalMocksToGenerate: ["Service", "Other"])
		#expect(names.mockFiles == ["Service+SafeDIMock.swift"])
		#expect(names.additionalMocks == ["Service_2+SafeDIMock.swift", "Other+SafeDIMock.swift"])
	}

	@Test
	func mockOutputFileNames_suffixesAnAdditionalMock_whenItsTypeNameMatchesAFileMockNameIgnoringLetterCase() {
		let names = mockOutputFileNames(forFilesAt: ["service.swift"], additionalMocksToGenerate: ["Service"])
		#expect(names.mockFiles == ["service+SafeDIMock.swift"])
		#expect(names.additionalMocks == ["Service_2+SafeDIMock.swift"])
	}

	@Test
	func mockOutputFileNames_suffixesTheLaterTypeName_whenAdditionalMockTypeNamesDifferOnlyInLetterCase() {
		// `Service` sorts before `service`, so it keeps the name.
		let names = mockOutputFileNames(forFilesAt: [], additionalMocksToGenerate: ["service", "Service"])
		#expect(names.mockFiles == [])
		#expect(names.additionalMocks == ["service_2+SafeDIMock.swift", "Service+SafeDIMock.swift"])
	}

	@Test
	func mockOutputFileNames_skipsASuffixAnotherAdditionalMockUses_whenResolvingACollision() {
		let names = mockOutputFileNames(forFilesAt: ["Service.swift"], additionalMocksToGenerate: ["Service", "Service_2"])
		#expect(names.mockFiles == ["Service+SafeDIMock.swift"])
		#expect(names.additionalMocks == ["Service_3+SafeDIMock.swift", "Service_2+SafeDIMock.swift"])
	}

	@Test
	func mockOutputFileNames_namesEachPathAndTypeTheSame_whenInputOrderChanges() {
		let inputFilePaths = ["Feature/Service.swift", "Service.swift", "Feature_Service.swift"]
		let additionalMocksToGenerate = ["Service_2", "Service", "Feature_Service", "service"]
		let expectedNames = mockOutputFileNames(forFilesAt: inputFilePaths, additionalMocksToGenerate: additionalMocksToGenerate)
		#expect(expectedNames.mockFiles == [
			"Feature_Service+SafeDIMock.swift",
			"Service+SafeDIMock.swift",
			"Feature_Service_2+SafeDIMock.swift",
		])
		// `service` matches `Service.swift`'s mock ignoring letter case, and claims its suffix after `Service`.
		#expect(expectedNames.additionalMocks == [
			"Service_2+SafeDIMock.swift",
			"Service_3+SafeDIMock.swift",
			"Feature_Service_3+SafeDIMock.swift",
			"service_4+SafeDIMock.swift",
		])
		let expectedFileNamesByPath = Dictionary(uniqueKeysWithValues: zip(inputFilePaths, expectedNames.mockFiles))
		let expectedNamesByTypeName = Dictionary(uniqueKeysWithValues: zip(additionalMocksToGenerate, expectedNames.additionalMocks))
		for (reorderedInputFilePaths, reorderedAdditionalMocksToGenerate) in [
			(inputFilePaths.reversed(), additionalMocksToGenerate.reversed()),
			(inputFilePaths.sorted(), additionalMocksToGenerate.sorted()),
			(inputFilePaths.sorted().reversed(), additionalMocksToGenerate.sorted().reversed()),
		] as [([String], [String])] {
			let names = mockOutputFileNames(forFilesAt: reorderedInputFilePaths, additionalMocksToGenerate: reorderedAdditionalMocksToGenerate)
			#expect(Dictionary(uniqueKeysWithValues: zip(reorderedInputFilePaths, names.mockFiles)) == expectedFileNamesByPath)
			#expect(Dictionary(uniqueKeysWithValues: zip(reorderedAdditionalMocksToGenerate, names.additionalMocks)) == expectedNamesByTypeName)
		}
	}
}
