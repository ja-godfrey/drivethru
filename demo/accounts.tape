# Run ./demo/render.sh accounts for the captioned GIF.
Source demo/common.tape

Hide
Type@1ms "source demo/session.sh accounts"
Enter
Wait+Screen@15s /DEMO READY/
Type@1ms "clear"
Enter
Sleep 200ms
Show

Type "drivethru"
Enter
Wait+Screen@10s /\d+\/\d+/
Sleep 500ms
Type@100ms "budget"
Sleep 1.3s
Type@150ms " work"
Sleep 1.5s
Ctrl+O
Wait+Screen@15s /MATCHING CHROME PROFILE/
Sleep 3s
