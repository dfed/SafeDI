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

/// Records that the root was launched.
///
/// `logger` receives the root's `eventLogger` under another name. The generated code assigns one to
/// the other under a `#sourceLocation` directive naming this file, so the compiler would report a
/// type mismatch at the `@Received` below. The compiler warns when that directive spells this file's
/// path differently than the build handed it the file, and this package treats warnings as errors.
@Instantiable @MainActor
public final class LaunchRecorder: Instantiable {
	public init(logger: EventLogger) {
		self.logger = logger
		logger.record("Launched")
	}

	@Received(fulfilledByDependencyNamed: "eventLogger", ofType: EventLogger.self) let logger: EventLogger
}
