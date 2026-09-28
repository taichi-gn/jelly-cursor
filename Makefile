# Xcode が無くても、Command Line Tools の swift だけで作れる
APP := JellyCursor.app
ICONSET := .build/AppIcon.iconset
CONFIG ?= release
INSTALL_DIR ?= $(HOME)/Applications
SWIFT_FLAGS ?=

.PHONY: all build app test install run clean

all: app

build:
	swift build -c $(CONFIG) --product JellyCursor $(SWIFT_FLAGS)

# .app にまとめ、その場で署名する（ログイン時に起動するには署名が要る）。
# アイコンはアプリ自身に描かせて書き出し、iconutil で .icns にする
app: build
	rm -rf "$(APP)" "$(ICONSET)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c $(CONFIG) --show-bin-path $(SWIFT_FLAGS))/JellyCursor" "$(APP)/Contents/MacOS/JellyCursor"
	"$(APP)/Contents/MacOS/JellyCursor" --write-iconset "$(ICONSET)"
	iconutil -c icns "$(ICONSET)" -o "$(APP)/Contents/Resources/AppIcon.icns"
	cp Support/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force -s - "$(APP)"
	@echo "built $(APP)"

test:
	swift test $(SWIFT_FLAGS)

# ログイン時に起動する設定は、アプリの場所を覚えるので、決まった場所に置いてから使う。入れたら起動し直す
install: app
	mkdir -p "$(INSTALL_DIR)"
	-pkill -x JellyCursor
	rm -rf "$(INSTALL_DIR)/$(APP)"
	ditto "$(APP)" "$(INSTALL_DIR)/$(APP)"
	@echo "installed $(INSTALL_DIR)/$(APP)"
	open "$(INSTALL_DIR)/$(APP)"

# 動いている JellyCursor があると open はそちらを前に出すだけなので、終わらせてから開く
run: app
	-pkill -x JellyCursor
	open "$(APP)"

clean:
	rm -rf .build "$(APP)"
