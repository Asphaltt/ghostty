.DEFAULT_GOAL := build

ZIG_VERSION := $(shell sed -nE 's/^[[:space:]]*\.minimum_zig_version = "([^"]+)".*/\1/p' build.zig.zon)
ZIG ?= $(firstword $(wildcard $(HOME)/.local/bin/zig-aarch64-macos-$(ZIG_VERSION)/zig) zig)
CONFIGURATION ?= Debug
OPTIMIZE ?= ReleaseFast
GHOSTTY_EXPERIMENTAL_FLOATING_TABS ?= 1

init: build

build: core
	macos/build.nu --configuration "$(CONFIGURATION)"

core:
	"$(ZIG)" build -Demit-macos-app=false -Dxcframework-target=native -Doptimize="$(OPTIMIZE)"

run:
	@test -x "macos/build/$(CONFIGURATION)/Ghostty.app/Contents/MacOS/ghostty" || { \
		echo "Ghostty is not built. Run: make build CONFIGURATION=$(CONFIGURATION)" >&2; exit 1; \
	}
	GHOSTTY_EXPERIMENTAL_FLOATING_TABS="$(GHOSTTY_EXPERIMENTAL_FLOATING_TABS)" \
		"macos/build/$(CONFIGURATION)/Ghostty.app/Contents/MacOS/ghostty"

test: core
	macos/build.nu --configuration "$(CONFIGURATION)" --action test

help:
	@printf '%s\n' \
		'make              Build the native GhosttyKit framework and macOS app' \
		'make run          Launch the existing build with floating tabs enabled' \
		'make test         Build the framework and run macOS unit tests' \
		'make clean        Remove generated build artifacts' \
		'make run GHOSTTY_EXPERIMENTAL_FLOATING_TABS=0  Disable floating tabs' \
		'make ZIG=/path/to/zig CONFIGURATION=ReleaseLocal  Override build tools/settings' \
		'Required Zig series: $(ZIG_VERSION); selected executable: $(ZIG)'

.PHONY: init build core run test help

# glad updates the GLAD loader. To use this, place the generated glad.zip
# in this directory next to the Makefile, remove vendor/glad and run this target.
#
# Generator: https://gen.glad.sh/
glad: vendor/glad
.PHONY: glad

vendor/glad: vendor/glad/include/glad/gl.h vendor/glad/include/glad/glad.h

vendor/glad/include/glad/gl.h: glad.zip
	rm -rf vendor/glad
	mkdir -p vendor/glad
	unzip glad.zip -dvendor/glad
	find vendor/glad -type f -exec touch '{}' +

vendor/glad/include/glad/glad.h: vendor/glad/include/glad/gl.h
	@echo "#include <glad/gl.h>" > $@

clean:
	rm -rf \
		zig-out .zig-cache \
		macos/build \
		macos/GhosttyKit.xcframework
.PHONY: clean
