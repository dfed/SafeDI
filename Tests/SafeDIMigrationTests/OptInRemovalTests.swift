import SafeDIMigration
import Testing

struct OptInRemovalTests {
	@Test
	func removeOptIn_leavesEmptyConfiguration_whenOptInIsOnlyArgument() {
		#expect(removed("#SafeDIConfiguration(apiVersion: .v3Unstable)") == "#SafeDIConfiguration()")
	}

	@Test
	func removeOptIn_keepsOtherArguments_whenOptInIsLast() {
		#expect(removed("#SafeDIConfiguration(additionalImportedModules: [], apiVersion: .v3Unstable)") == "#SafeDIConfiguration(additionalImportedModules: [])")
	}

	@Test
	func removeOptIn_keepsOtherArguments_whenOptInIsFirst() {
		#expect(removed("#SafeDIConfiguration(apiVersion: .v3Unstable, additionalImportedModules: [])") == "#SafeDIConfiguration(additionalImportedModules: [])")
	}

	@Test
	func removeOptIn_keepsLayout_whenArgumentsAreOnLinesOfTheirOwn() {
		#expect(removed("""
		#SafeDIConfiguration(
			additionalImportedModules: [],
			apiVersion: .v3Unstable
		)
		""") == """
		#SafeDIConfiguration(
			additionalImportedModules: []
		)
		""")
	}

	@Test
	func removeOptIn_removesOptIn_whenConfigurationIsDeclaredInsideType() {
		#expect(removed("""
		enum Configuration {
			#SafeDIConfiguration(apiVersion: .v3Unstable)
		}
		""") == """
		enum Configuration {
			#SafeDIConfiguration()
		}
		""")
	}

	@Test
	func removeOptIn_countsEachRemoval_whenSeveralFilesOptIn() {
		let result = Migration.removeOptIn(sources: [
			SourceFile(path: "B.swift", text: "#SafeDIConfiguration(apiVersion: .v3Unstable)"),
			SourceFile(path: "A.swift", text: "#SafeDIConfiguration(apiVersion: .v3Unstable)"),
		])
		#expect(result.rewrittenFiles == [
			SourceFile(path: "A.swift", text: "#SafeDIConfiguration()"),
			SourceFile(path: "B.swift", text: "#SafeDIConfiguration()"),
		])
		#expect(result.editCounts == [.optInSettingRemoved: 2])
		#expect(result.findings == [])
	}

	@Test
	func removeOptIn_changesNothing_whenNoConfigurationOptsIn() {
		let result = Migration.removeOptIn(sources: [
			SourceFile(path: "A.swift", text: "#SafeDIConfiguration(additionalImportedModules: [])\n#warning(\"check\")"),
		])
		#expect(result.rewrittenFiles == [])
		#expect(result.editCounts == [:])
	}

	private func removed(_ text: String) -> String? {
		Migration.removeOptIn(sources: [SourceFile(path: "A.swift", text: text)]).rewrittenFiles.first?.text
	}
}
