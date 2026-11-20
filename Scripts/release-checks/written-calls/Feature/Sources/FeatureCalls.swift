// Hand-written calls of the mocks this module generates, which are `internal`.

#if DEBUG
struct StubProfileStore: ProfileStore {}

struct StubUploader: Uploader {}

// “Dependency kinds in the generated mock”: a seam’s `mock()` takes the builder its initializer takes for a hole, in
// place of the flat parameter.
func callUploadCenterMock() {
	let _: UploadCenter = UploadCenter.mock(uploaderBuilder: { StubUploader() })
}

func callProfileScreenMocks() {
	let a = AnyProfileStore(StubProfileStore())
	let b = AnyProfileStore(StubProfileStore())
	// “Dependency kinds in the generated mock”, verbatim but for the names: `profile` gets `a`, and `settings` gets `b`.
	let _: ProfileScreen = ProfileScreen.mock(
		profileStore: a,
		safeDIOverrides: .init(settings: { _ in SettingsPanel(profileStore: b) }),
	)
}
#endif
