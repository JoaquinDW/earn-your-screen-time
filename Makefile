# Earn Your Screen Time — atajos de desarrollo.
# Usa el toolchain de Xcode sin tocar xcode-select (no pide contraseña).

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

PROJECT   := EarnYourScreenTime.xcodeproj
SCHEME    := EarnYourScreenTime
SIMULATOR := platform=iOS Simulator,name=iPhone 17 Pro
DERIVED   := .build/DerivedData

.PHONY: all gen test build device open clean

all: gen test build

## Regenera el .xcodeproj desde project.yml (correr tras agregar archivos o targets)
gen:
	xcodegen generate

## Corre los tests de la lógica de dominio en la Mac (no necesita iPhone ni simulador)
test:
	cd Packages/EarnDomain && swift test

## Compila la app para el simulador (sin firmar: sirve aunque no tengas cuenta Apple)
build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIMULATOR)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO | tail -3

## Compila para iPhone real (solo verifica que compile; instalar se hace desde Xcode)
device:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO | tail -3

## Abre el proyecto en Xcode
open:
	open $(PROJECT)

clean:
	rm -rf $(DERIVED)
	cd Packages/EarnDomain && swift package clean
