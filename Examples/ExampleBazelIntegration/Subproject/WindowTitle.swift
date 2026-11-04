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

import Models
import SafeDI

/// A seam: `Subproject` generates the initializers that build this type's tree, `TitleFormatter` included, which is
/// `internal`, and the trees of other modules call them. Its `public` initializer cannot take a `NoteTheme`, which
/// `Models` declares `package`, so it passes `nil` for `theme`; its `package` one takes it.
@Instantiable(generateDependencyTree: true)
public final class WindowTitle: Instantiable {
	init(theme: NoteTheme?, titleFormatter: TitleFormatter) {
		self.theme = theme
		self.titleFormatter = titleFormatter
	}

	public var text: String {
		titleFormatter.title(withSuffix: theme?.titleSuffix)
	}

	@Received(onlyIfAvailable: true) private let theme: NoteTheme?
	@Instantiated private let titleFormatter: TitleFormatter
}
