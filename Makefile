# Xcode が無くても、Command Line Tools の swift だけで作れる
APP := JellyCursor.app
CONFIG ?= release
INSTALL_DIR ?= $(HOME)/Applications
SWIFT_FLAGS ?=

.PHONY: all build app test install run clean

all: app

build:
	swift build -c $(CONFIG) --product JellyCursor $(SWIFT_FLAGS)

# .app にまとめ、その場で署名する（ログイン時に起動するには署名が要る）
app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/JellyCursor" "$(APP)/Contents/MacOS/JellyCursor"
	cp Support/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force -s - "$(APP)"
	@echo "built $(APP)"

test:
	swift test $(SWIFT_FLAGS)

# ログイン時に起動する設定は、アプリの場所を覚えるので、決まった場所に置いてから使う
install: app
	mkdir -p "$(INSTALL_DIR)"
	-pkill -x JellyCursor
	rm -rf "$(INSTALL_DIR)/$(APP)"
	ditto "$(APP)" "$(INSTALL_DIR)/$(APP)"
	@echo "installed $(INSTALL_DIR)/$(APP)"

run: app
	open "$(APP)"

clean:
	rm -rf .build "$(APP)"
