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

test:
	swift test

check:
	swift format lint --strict --recursive Sources Tests Package.swift
	swift build

clean:
	rm -rf .build
