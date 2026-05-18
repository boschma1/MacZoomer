.PHONY: generate build test lint clean

PROJECT := MacZoomer.xcodeproj
SCHEME  := MacZoomer

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

test:
	swift test

lint:
	@command -v swiftlint >/dev/null 2>&1 && swiftlint || \
		echo "swiftlint not installed (requires Xcode). Skipping."

clean:
	rm -rf .build build DerivedData $(PROJECT)
