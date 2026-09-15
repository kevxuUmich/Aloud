APP := .build/Aloud.app
BIN := .build/debug/Aloud

.PHONY: dev watch gallery build bundle icon kokoro-bundle kokoro-release test check clean

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

# The Kokoro model bundle the app downloads on first use: pinned inputs in, one Apple
# Archive and its checksum out, under .build/kokoro-bundle. The first run downloads
# about 180 MB; later runs reuse the verified inputs.
KOKORO_VERSION := 1
KOKORO_OUT := .build/kokoro-bundle

kokoro-bundle:
	swift run -c release kokoro-bundle --version $(KOKORO_VERSION) --out $(KOKORO_OUT)

# Attaches the archive to the kokoro-models release on the Aloud repo, creating the
# release the first time. The release is its own tag so the model does not churn with
# app releases. Needs `gh` logged in with push rights.
#
# --clobber can replace the artefact the app pins by hash, so before uploading this
# checks whether a differently-checksummed archive is already published under this
# version and refuses rather than silently replacing what apps in the wild trust.
kokoro-release: kokoro-bundle
	gh release view kokoro-models >/dev/null 2>&1 || gh release create kokoro-models \
		--title "Kokoro models" \
		--notes "The Kokoro voice models Aloud downloads on first use. Built by make kokoro-bundle from pinned Hugging Face inputs; the .sha256 sidecar is what the app checks."
	published="$$(mktemp)"; \
	if curl -sfL "https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-$(KOKORO_VERSION).aar.sha256" -o "$$published" \
		&& [ "$$(awk '{print $$1}' "$$published")" != "$$(awk '{print $$1}' "$(KOKORO_OUT)/kokoro-$(KOKORO_VERSION).aar.sha256")" ]; then \
		rm -f "$$published"; \
		echo "kokoro-$(KOKORO_VERSION).aar is already published with a different checksum; bump KOKORO_VERSION"; \
		exit 1; \
	fi; \
	rm -f "$$published"
	gh release upload kokoro-models $(KOKORO_OUT)/kokoro-$(KOKORO_VERSION).aar $(KOKORO_OUT)/kokoro-$(KOKORO_VERSION).aar.sha256 --clobber

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
