android_arm64:
	dart ./setup.dart android --arch arm64
macos_arm64:
	dart ./setup.dart macos --arch arm64
android_app:
	dart ./setup.dart android
android_arm64_core:
	dart ./setup.dart android --arch arm64 --out core
macos_arm64_core:
	dart ./setup.dart macos --arch arm64  --out core


macLocal:
	rm -rf dist
	rm -rf build
	dart ./setup.dart macos --arch arm64 --env stable

macLocal_amd64:
	rm -rf dist
	rm -rf build
	dart ./setup.dart macos --arch amd64 --env stable


notarizeLocal:
	DMG_FILE=$$(ls dist/FlClashX-*.dmg) && \
	echo "Found DMG: $$DMG_FILE" && \
	xcrun notarytool submit "$$DMG_FILE" --keychain-profile "flclash-notarization" --wait && \
	xcrun stapler staple "$$DMG_FILE" && \
	xcrun stapler validate "$$DMG_FILE"

cleanLocal:
	rm -rf dist
	rm -rf build