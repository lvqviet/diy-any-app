# DIY Any App

Personal macOS menu bar app that combines features of paid apps into one native Swift app.

## Features

### Battery (inspired by AlDente)

- **Charge Limiter**: stop charging at a limit (20–100%) while plugged in. Above the limit, charging pauses and the Mac runs on adapter power.
- **Discharge**: drain the battery down to the limit while the adapter stays plugged in, then hold there.
- **Automatic Discharge**: discharge automatically whenever the battery is above the limit while plugged in.
- **Top Up**: charge to 100% once; the limit returns as soon as the adapter is unplugged.

Behavior:

- Charge control only applies while the app is running. Quitting (or a crash) restores normal charging.
- While charging toward the limit or discharging, idle sleep is held off. If the Mac is put to sleep anyway, charging is paused and adapter power restored right before sleep, so the limit is never exceeded and the battery never drains while asleep.

## Architecture

| Part | Path | Role |
| --- | --- | --- |
| App | `App/` | SwiftUI menu bar panel + main window, runs as the user |
| Helper | `Helper/` | Root launchd daemon registered via `SMAppService`; the only part that writes SMC keys |
| BatteryCore | `Packages/BatteryCore/` | SMC client, battery reader, pure charge policy, XPC protocol (unit-tested) |

App and helper talk over XPC (`com.diyanyapp.me.helper`); each side checks the other's code signature (team `U8GCXBC6Q3`).

### SMC keys (Apple Silicon)

| Key | Purpose | Values |
| --- | --- | --- |
| `CHTE` | Charging on/off (macOS 15/26-era firmware) | `00000000` on, `01000000` off |
| `CH0B`/`CH0C` | Charging on/off (older firmware) | `00` on, `02` off |
| `CH0J` | Adapter power on/off | `00` on, `01` off |
| `CHIE` | Adapter power on/off (alternative) | `00` on, `08` off |

Firmware shipped with macOS 27 / 26.7 (and some 15.x security updates) gates these keys behind a private entitlement ([batt#152](https://github.com/charlie0129/batt/issues/152)). The app detects this and marks the affected features as unsupported.

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & install

```sh
scripts/install.sh        # signed Release build, installed to /Applications
```

Development:

```sh
xcodegen generate         # creates DIYAnyApp.xcodeproj (not committed)
open DIYAnyApp.xcodeproj
cd Packages/BatteryCore && swift test
```

First launch: click **Install Helper**, then allow "DIY Any App" in System Settings › General › Login Items & Extensions.

Helper logs:

```sh
log stream --predicate 'subsystem == "com.diyanyapp.me.helper"'
```

Do not run AlDente (or another charge-control app) at the same time.
