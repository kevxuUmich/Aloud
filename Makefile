APP := .build/Aloud.app
BIN := .build/debug/Aloud

.PHONY: dev watch gallery build bundle test check clean

dev: build bundle
	@pkill -x Aloud || true
	@open $(APP)

gallery: build bundle
	@pkill -x Aloud || true
	@open $(APP) --args --gallery

watch:
	watchexec -e swift,plist -r --debounce 300ms -- make dev

build:
	swift build --product Aloud

bundle:
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/Aloud
	@cp App/Info.plist $(APP)/Contents/Info.plist

# The command-line-tools-only toolchain here ships Testing.framework outside the
# default framework search path, and its Foundation cross-import overlay has no
# swiftmodule, so `import Testing` needs these flags to resolve and link.
# (Baking them into Package.swift via unsafeFlags instead makes SwiftPM fall back to
# .xctest-bundle test execution, which silently runs zero tests in this sandbox.)
TESTING_FRAMEWORK := /Library/Developer/CommandLineTools/Library/Developer/Frameworks

test:
	swift test \
		-Xswiftc -F$(TESTING_FRAMEWORK) \
		-Xlinker -F$(TESTING_FRAMEWORK) \
		-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORK) \
		-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays

check:
	swift format lint --strict --recursive Sources Tests Package.swift
	swift build

clean:
	rm -rf .build
