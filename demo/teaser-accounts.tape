# Run from the repository root; supply an output with vhs -o PATH.
# Actual picker, made-up accounts, and dry-run browser routing only.
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
Set TypingSpeed 180ms
Set Framerate 20

Hide
Type@1ms "source demo/teaser-accounts-session.sh"
Enter
Wait+Screen@15s /TEASER ACCOUNTS READY/
Type@1ms "drivethru"
Enter
Wait+Screen@10s /\d+\/\d+/
# Hide the metadata preview with the actual picker shortcut at this width.
Ctrl+P
Sleep 200ms
Show

Sleep 300ms
Type@180ms "budget"
Sleep 1.1s
Type@220ms " work"
Sleep 1.1s
Ctrl+O
Wait+Screen@10s /OPEN WITH WORK ACCOUNT/
Sleep 1.5s
