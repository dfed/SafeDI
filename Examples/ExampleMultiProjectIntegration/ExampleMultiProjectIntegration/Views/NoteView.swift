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

import SafeDI
import Subproject
import SwiftUI

@MainActor
@Instantiable
public struct NoteView: Instantiable, View {
	public init(userName: String, userService: any UserService, stringStorage: StringStorage) {
		self.userName = userName
		self.userService = userService
		self.stringStorage = stringStorage
		_note = State(initialValue: stringStorage.string(forKey: userName) ?? "")
	}

	public var body: some View {
		VStack {
			Text("\(userName)’s note")
			TextEditor(text: $note)
				.onChange(of: note) { _, newValue in
					stringStorage.setString(newValue, forKey: userName)
				}
			Button(action: {
				userService.userName = nil
			}, label: {
				Text("Log out")
			})
		}
		.padding()
	}

	@Forwarded private let userName: String
	@Received private let userService: any UserService
	@Received private let stringStorage: StringStorage

	@State private var note: String = ""
}

#Preview {
	NoteView(
		userName: "dfed",
		userService: DefaultUserService(stringStorage: UserDefaults.standard),
		stringStorage: UserDefaults.standard
	)
}
