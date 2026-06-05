-- Arranges the DMG window for a drag-to-install layout: the app on the left, the
-- /Applications symlink on the right, in icon view. Invoked from the `dmg` mise task
-- against a mounted read-write image. Best-effort — if Finder scripting is
-- unavailable (e.g. a headless machine), the task ignores failures and still ships a
-- valid, if unstyled, DMG.
--
-- Usage: osascript scripts/dmg-layout.applescript <volume-name> <app-file-name>
on run argv
	set volName to item 1 of argv
	set appName to item 2 of argv
	tell application "Finder"
		tell disk volName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {200, 120, 800, 520}
			set theViewOptions to the icon view options of container window
			set arrangement of theViewOptions to not arranged
			set icon size of theViewOptions to 128
			set position of item appName of container window to {160, 205}
			set position of item "Applications" of container window to {440, 205}
			update without registering applications
			delay 1
			close
		end tell
	end tell
end run
