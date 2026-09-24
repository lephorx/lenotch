on run argv
    tell application "Finder"
        tell disk (item 1 of argv)
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set bounds to {160, 120, 760, 460}
            end tell
            tell icon view options of container window
                set background picture to (POSIX file ((item 2 of argv) & "/Lenotch.app/Contents/Resources/installer-background.png") as alias)
            end tell
            close
            open
            delay 2
        end tell
    end tell
end run
