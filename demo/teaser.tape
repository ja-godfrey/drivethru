# Run from the repository root; supply an output with vhs -o PATH.
# Uses the actual picker and synthetic fixture; no personal Drive or clipboard.
Require fzf
Require openssl
Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 18
Set Width 640
Set Height 400
Set Padding 16
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set CursorBlink false
Set TypingSpeed 80ms
Set Framerate 20

Hide
Type@1ms "source demo/teaser-session.sh"
Enter
Wait+Screen@15s /TEASER READY/
Type@1ms "clear"
Enter
Sleep 200ms
Show

Sleep 200ms
Type "drivethru"
Enter
Wait+Screen@10s /\d+\/\d+/
# Use the picker's real shortcut: its metadata preview wraps at this width.
Ctrl+P
Sleep 300ms
Type@90ms "board deck"
Sleep 800ms
Enter
Wait+Screen@10s /READY TO PASTE/
Sleep 1.5s
