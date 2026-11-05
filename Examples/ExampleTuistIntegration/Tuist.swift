import ProjectDescription

let tuist = Tuist(
	project: .tuist(
		compatibleXcodeVersions: .upToNextMajor("26.0"),
		// The plugin lives in this same repo. In a real adopting
		// project you'd use the commit of the SafeDI version in
		// `Tuist/Package.swift` (not its `tag:`, which Tuist cannot
		// load the plugin from; see the manual's Tuist section):
		//
		//   .git(url: "https://github.com/dfed/SafeDI",
		//        sha: "<commit>",
		//        directory: "TuistPlugins/SafeDITuist")
		//
		// Tuist resolves `.local(path:)` against `manifestDir/Tuist`
		// (one component deeper than the manifest itself), so the
		// path needs one more leading `..` than feels natural.
		plugins: [
			.local(path: "../../../TuistPlugins/SafeDITuist"),
		],
	),
)
