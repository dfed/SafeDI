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
import Foundation
import SafeDI

public protocol UserService: ObservableObject {
	var user: User? { get set }
	var observableObjectPublisher: ObservableObjectPublisher { get }
}

/// A type-erased wrapper around a `UserService` that is itself a `UserService` and `ObservableObject`.
public final class AnyUserService: UserService, ObservableObject {
	public init(_ userService: some UserService) {
		self.userService = userService
		objectWillChange = userService
			.objectWillChange
			.map { _ in () }
			.eraseToAnyPublisher()
	}

	public var user: User? {
		get {
			userService.user
		}
		set {
			userService.user = newValue
		}
	}

	public var observableObjectPublisher: ObservableObjectPublisher {
		userService.observableObjectPublisher
	}

	public let objectWillChange: AnyPublisher<Void, Never>

	private let userService: any UserService
}

@Instantiable(fulfillingAdditionalTypes: [UserService.self], generateMock: true)
public final class DefaultUserService: Instantiable, UserService {
	public init(stringStorage: StringStorage) {
		self.stringStorage = stringStorage
	}

	public var user: User? {
		get {
			guard let data = stringStorage.string(forKey: Self.userKey)?.data(using: .utf8) else {
				return nil
			}
			return try? JSONDecoder().decode(User.self, from: data)
		}
		set {
			objectWillChange.send()
			let encoded = newValue.flatMap { try? JSONEncoder().encode($0) }
			stringStorage.setString(encoded.flatMap { String(data: $0, encoding: .utf8) }, forKey: Self.userKey)
		}
	}

	public var observableObjectPublisher: ObservableObjectPublisher {
		objectWillChange
	}

	@Received
	@Published private var stringStorage: StringStorage

	private static let userKey = "user"
}
