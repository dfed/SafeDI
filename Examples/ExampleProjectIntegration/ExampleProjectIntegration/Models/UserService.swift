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

public protocol UserService: ObservableObject {
    var userName: String? { get set }
    var observableObjectPublisher: ObservableObjectPublisher { get }
}

@Instantiable(fulfillingAdditionalTypes: [UserService.self])
public final class DefaultUserService: Instantiable, UserService {
    public init(stringStorage: StringStorage) {
        self.stringStorage = stringStorage
    }

    public var userName: String? {
        get {
            stringStorage.string(forKey: #function)
        }
        set {
            objectWillChange.send()
            stringStorage.setString(newValue, forKey: #function)
        }
    }

    public var observableObjectPublisher: ObservableObjectPublisher {
        objectWillChange
    }

    @Received
    @Published
    private var stringStorage: StringStorage
}
