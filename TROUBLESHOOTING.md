# Problems encourtered while creating an app using this Pod

1. Don't forget use_frameworks! in the Podfile

2. Compilation error:

```
rsync: mkstemp "/Users/francoisdevemy/Library/Developer/Xcode/DerivedData/DemoSharedCredentials-eimnpvwzqrnliybmgmhpaqpubkjs/Build/Products/Debug-iphoneos/DemoSharedCredentials.app/Frameworks/Alamofire.framework/.Alamofire.piojbA" failed: Operation not permitted (1)
rsync: mkstemp "/Users/francoisdevemy/Library/Developer/Xcode/DerivedData/DemoSharedCredentials-eimnpvwzqrnliybmgmhpaqpubkjs/Build/Products/Debug-iphoneos/DemoSharedCredentials.app/Frameworks/Alamofire.framework/.Info.plist.VoW8C8" failed: Operation not permitted (1)

sent 3185471 bytes  received 70 bytes  6371082.00 bytes/sec
total size is 3184836  speedup is 1.00
rsync error: some files could not be transferred (code 23) at /AppleInternal/Library/BuildRoots/11aa8fb2-5f4b-11ee-bc7f-926038f30c31/Library/Caches/com.apple.xbs/Sources/rsync/rsync/main.c(996) [sender=2.6.9]
Command PhaseScriptExecution failed with a nonzero exit code
```

To solve this,
> The same question，in Xcode15，I did this，solved it。Targets -> Build Setting -> Build Options -> User Script Sandboxing，set Yes To No。You can search "ENABLE_USER_SCRIPT_SANDBOXING"

https://github.com/CocoaPods/CocoaPods/pull/11828#issuecomment-1884590077

Other proposed solutions that did not work for me :<br>
Add or remove `-f` to `readlink -f "${source}"` in [Pods-Sandbox-frameworks.sh](Sandbox%2FPods%2FTarget%20Support%20Files%2FPods-Sandbox%2FPods-Sandbox-frameworks.sh)
<br>Transform in `realpath "${source}"` or `greadlink -f "${source}"` <br>
https://github.com/CocoaPods/CocoaPods/issues/11808#issuecomment-1564803402 <br>
https://github.com/CocoaPods/CocoaPods/issues/11808#issuecomment-1580178630
