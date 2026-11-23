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

@testable import SafeDIMigration

/// The role file the tests share: the prototype's edge-case types, a type whose mock builds a received dependency, and
/// a public mock.
extension MigrationRoles {
	static let fixture = MigrationRoles(mockedTypes: [
		MockedType(type: "Banner", module: "App", takesOverrides: true, parameters: [
			Parameter(label: "note", role: .rootDefault, isOptionalType: true),
			Parameter(label: "retries", role: .rootDefault),
			Parameter(label: "userService", role: .uncovered),
		]),
		MockedType(type: "Badge", module: "App", takesOverrides: false, parameters: [
			Parameter(label: "label", role: .rootDefault, isOptionalType: true),
		]),
		MockedType(type: "Outer.Inner", module: "App", takesOverrides: false, parameters: [
			Parameter(label: "count", role: .rootDefault),
		]),
		MockedType(type: "Profile", module: "App", takesOverrides: true, parameters: [
			Parameter(label: "name", role: .forwarded),
			Parameter(label: "user", role: .receivedBuildable, hasFlatParameter: false, overridesField: "user_Draft"),
			Parameter(label: "clock", role: .outsideValue),
			Parameter(label: "handler", role: .uncovered, isClosureType: true),
			Parameter(label: "logger", role: .uncovered, isSendableAutoclosure: true),
			Parameter(label: "default", role: .uncovered),
			Parameter(label: "tint", role: .rootDefault, fieldLabel: "tint_Color"),
		]),
		MockedType(type: "Panel", module: "Feature", isPublic: true, takesOverrides: true, parameters: [
			Parameter(label: "id", role: .forwarded),
			Parameter(label: "session", role: .receivedBuildable, overridesField: "session"),
			Parameter(label: "rowBuilder", role: .publicMockBuilder),
			Parameter(label: "serviceBuilder", role: .holeBuilder),
			Parameter(label: "theme", role: .rootDefault),
			Parameter(label: "title", role: .rootDefault, isOptionalType: true),
		]),
		MockedType(type: "Empty", module: "App", takesOverrides: false, parameters: []),
		MockedType(type: "Shared", module: "App", takesOverrides: false, parameters: []),
		MockedType(type: "Shared", module: "Feature", takesOverrides: false, parameters: []),
	])
}

/// Migrates one file, `Calls.swift`, beside `otherSources`.
func migrate(
	_ text: String,
	otherSources: [SourceFile] = [],
	roles: MigrationRoles = .fixture,
	options: MigrationOptions = .init(),
) -> MigrationResult {
	Migration.migrate(sources: [SourceFile(path: "Calls.swift", text: text)] + otherSources, roles: roles, options: options)
}

/// The text `Calls.swift` has after migrating it.
func migratedText(
	_ text: String,
	otherSources: [SourceFile] = [],
	roles: MigrationRoles = .fixture,
	options: MigrationOptions = .init(),
) -> String {
	let result = migrate(text, otherSources: otherSources, roles: roles, options: options)
	return result.rewrittenFiles.first { $0.path == "Calls.swift" }?.text ?? text
}

/// A finding in `Calls.swift`.
func finding(_ kind: MigrationFinding.Kind, line: Int, column: Int, _ text: String) -> MigrationFinding {
	MigrationFinding(kind: kind, site: SourceSite(path: "Calls.swift", line: line, column: column), text: text)
}
