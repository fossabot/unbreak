.DEFAULT_GOAL := build
.PHONY: build release test fmt fmt-check lint clean run

build:
	swift build

release:
	swift build -c release

test:
	swift test

# Format in place (requires swift-format: `brew install swift-format`).
fmt:
	swift-format format --in-place --recursive Sources Tests Package.swift

# CI-friendly: fail if anything is unformatted.
fmt-check:
	swift-format lint --recursive --strict Sources Tests Package.swift

# Optional static analysis (requires swiftlint: `brew install swiftlint`).
lint:
	swiftlint lint --quiet

clean:
	swift package clean
	rm -rf .build

# Run the CLI against stdin, e.g.: pbpaste | make run
run:
	swift run ccfix -
