APP := .build/Aloud.app
BIN := .build/debug/Aloud

.PHONY: dev watch gallery build bundle icon test check clean

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
	@cp App/Aloud.icns $(APP)/Contents/Resources/Aloud.icns

# The app icon, from the mark's 1024 export. The .icns is committed so the Xcode
# target has it without a build step; run this again when the export changes.
icon:
	swift Tools/icon.swift $(CURDIR)

# The command-line-tools-only toolchain ships Testing.framework outside the
# default framework search path, and its Foundation cross-import overlay has no
# swiftmodule, so `import Testing` needs these flags to resolve and link.
# (Baking them into Package.swift via unsafeFlags instead makes SwiftPM fall back to
# .xctest-bundle test execution, which silently runs zero tests in this sandbox.)
# Xcode's toolchain finds its own Testing.framework, and pointing it at the CLT's
# copy links against a module from another compiler, so the flags apply only when
# the command-line tools are the active developer directory.
CLT := /Library/Developer/CommandLineTools
TESTING_FRAMEWORK := $(CLT)/Library/Developer/Frameworks
ifeq ($(shell xcode-select -p),$(CLT))
TEST_FLAGS := \
	-Xswiftc -F$(TESTING_FRAMEWORK) \
	-Xlinker -F$(TESTING_FRAMEWORK) \
	-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORK) \
	-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
endif

test:
	swift test $(TEST_FLAGS)

check:
	swift format lint --strict --recursive Sources Tests Tools/KokoroBundle Tools/kokoro-bundle Package.swift
	swift build

clean:
	rm -rf .build
