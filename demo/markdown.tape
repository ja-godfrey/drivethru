# Run ./demo/render.sh markdown for the captioned GIF.
Source demo/common.tape

Hide
Type@1ms "source demo/session.sh markdown"
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
Sleep 1.1s
Tab
Sleep 600ms
Tab
Sleep 1.2s
Ctrl+Y
Wait+Screen@10s /TWO LINKS, ONE PASTE/
Sleep 3s
