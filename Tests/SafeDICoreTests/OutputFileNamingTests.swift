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
	func outputFileNames_namesEachPathTheSame_whenInputOrderChanges() {
		let inputFilePaths = ["Feature/Root.swift", "Root.swift", "Feature_Root.swift", "Feature_Root_2.swift", "A_B/Root.swift", "A/B/Root.swift"]
		let expectedNamesByPath = Dictionary(uniqueKeysWithValues: zip(inputFilePaths, outputFileNames(forFilesAt: inputFilePaths)))
		for reorderedInputFilePaths in [inputFilePaths.reversed(), inputFilePaths.sorted(), inputFilePaths.sorted().reversed()] {
			#expect(Dictionary(uniqueKeysWithValues: zip(reorderedInputFilePaths, outputFileNames(forFilesAt: reorderedInputFilePaths))) == expectedNamesByPath)
		}
	}

	@Test
	func mockOutputFileNames_suffixesTheLaterPath_whenADirectoryPrefixedNameMatchesAnotherFileName() {
		#expect(mockOutputFileNames(forFilesAt: ["Feature/Service.swift", "Service.swift", "Feature_Service.swift"]) == [
			"Feature_Service+SafeDIMock.swift",
			"Service+SafeDIMock.swift",
			"Feature_Service_2+SafeDIMock.swift",
		])
	}
}
