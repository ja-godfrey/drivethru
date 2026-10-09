# Run ./demo/render.sh copy for the captioned GIF.
Source demo/common.tape

Hide
Type@1ms "source demo/session.sh copy"
Enter
Wait+Screen@15s /DEMO READY/
Type@1ms "clear"
Enter
Sleep 200ms
Show

Type "drivethru"
Enter
Wait+Screen@10s /\d+\/\d+/
Sleep 700ms
Type@100ms "board deck"
Sleep 1.5s
Enter
Wait+Screen@10s /READY TO PASTE/
Sleep 3s
