// swift-tools-version:5.1

import PackageDescription

let package = Package(
   name: "UniversalCharsetDetection",
   products: [
      .library(
         name: "UniversalCharsetDetection",
         targets: [
            "UniversalCharsetDetection",
         ]
      ),
      .library(
         name: "Cuchardet",
         targets: ["Cuchardet"]
      ),
   ],
   targets: [
      .target(
         name: "UniversalCharsetDetection",
         dependencies: [
            "Cuchardet",
         ]
      ),
      .target(
         name: "Cuchardet"
      ),
      .testTarget(
         name: "UniversalCharsetDetectionTests",
         dependencies: [
            "UniversalCharsetDetection",
         ]
      ),
   ],
   swiftLanguageVersions: [.v4_2, .v5]
)
