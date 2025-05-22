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
import SwiftUI

@MainActor
@Instantiable
public struct NameEntryView: Instantiable, View {
	public init(userService: any UserService) {
		self.userService = userService
	}

	public var body: some View {
		VStack {
			TextField(
				text: $name,
				prompt: Text("Enter your name"),
				label: {}
			)
			Button(action: {
				userService.userName = name
			}, label: {
				Text("Log in")
			})
		}
		.padding()
	}

	@State private var name: String = ""

	@Received private let userService: any UserService
}

#Preview {
	NameEntryView(userService: DefaultUserService(stringStorage: UserDefaults.standard))
}
