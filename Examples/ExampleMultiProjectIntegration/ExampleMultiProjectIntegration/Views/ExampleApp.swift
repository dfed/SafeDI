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

import Combine
import SafeDI
import Subproject
import SwiftUI

// @Instantiable macro marks this type as capable of being instantiated by SafeDI. The `isRoot` parameter marks this type as being the root of the dependency tree.
@Instantiable(isRoot: true)
@MainActor
@main
public struct NotesApp: Instantiable, App {
	public var body: some Scene {
		WindowGroup {
			if let userName = userService.userName {
				// Returns a new instance of `NoteView`.
				noteViewBuilder.instantiate(userName)
			} else {
				// Returns a new instance of a `NameEntryView`.
				nameEntryViewBuilder.instantiate()
			}
		}
	}

	// Memberwise initializer to satisfy SafeDI.
	// `public init()` will be generated for this type because this type is a root.
	public init(
		userService: AnyUserService,
		stringStorage: StringStorage,
		nameEntryViewBuilder: Instantiator<NameEntryView>,
		noteViewBuilder: Instantiator<NoteView>
	) {
		self.userService = userService
		self.stringStorage = stringStorage
		self.nameEntryViewBuilder = nameEntryViewBuilder
		self.noteViewBuilder = noteViewBuilder
	}

	/// A private property that is instantiated when the app is instantiated and manages the User state.
	@ObservedObject @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) private var userService: AnyUserService
	/// A private property that is instantiated when the app is instantiated and manages the persistence of strings.
	@Instantiated private let stringStorage: StringStorage
	/// A private property that is instantiated when the app is instantiated and can create a NameEntryView on demand.
	@Instantiated private let nameEntryViewBuilder: Instantiator<NameEntryView>
	/// A private property that is instantiated when the app is instantiated and can create a NoteView on demand.
	@Instantiated private let noteViewBuilder: Instantiator<NoteView>
}
