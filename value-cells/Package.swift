// swift-tools-version: 6.0
// Step 2b's value cells: each cell's sources with the code a records-on build of step 2b generated for them, checked in.
// No plugin runs. Tools version 6.0 compiles every target in Swift 6 mode.
import Foundation
import PackageDescription

let safeDICheckout = ProcessInfo.processInfo.environment["SAFEDI_CHECKOUT"] ?? "../SafeDI"
// A path dependency's identity is its folder's name.
let safeDIPackage = URL(fileURLWithPath: safeDICheckout).lastPathComponent

let package = Package(
	name: "FillValueCells",
	platforms: [.macOS(.v14), .iOS(.v17)],
	dependencies: [.package(path: safeDICheckout)],
	targets: [
		// fill-builder-captures-parents-binding
		.target(name: "Cell1Feature", dependencies: [.product(name: "SafeDI", package: safeDIPackage)]),
		.target(name: "Cell1App", dependencies: ["Cell1Feature", .product(name: "SafeDI", package: safeDIPackage)]),
		// fill-nested-functions
		.target(name: "Cell2Feature", dependencies: [.product(name: "SafeDI", package: safeDIPackage)]),
		.target(name: "Cell2App", dependencies: ["Cell2Feature", .product(name: "SafeDI", package: safeDIPackage)]),
		// fill-sendable-under-main-actor-root
		.target(name: "Cell3Feature", dependencies: [.product(name: "SafeDI", package: safeDIPackage)]),
		.target(name: "Cell3App", dependencies: ["Cell3Feature", .product(name: "SafeDI", package: safeDIPackage)]),
		// fill-two-builders-capture-one-binding
		.target(name: "Cell4Feature", dependencies: [.product(name: "SafeDI", package: safeDIPackage)]),
		.target(name: "Cell4App", dependencies: ["Cell4Feature", .product(name: "SafeDI", package: safeDIPackage)]),
	],
)
