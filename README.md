# DIY Any App

Personal macOS menu bar app that combines features of paid apps into one native Swift app.

## Features

### Battery (inspired by AlDente)

- **Charge Limiter**: stop charging at a limit (20–100%) while plugged in. Above the limit, charging pauses and the Mac runs on adapter power.
- **Discharge**: drain the battery down to the limit while the adapter stays plugged in, then hold there.
- **Automatic Discharge**: discharge automatically whenever the battery is above the limit while plugged in.
- **Top Up**: charge to 100% once; the limit returns as soon as the adapter is unplugged.
- **Sailing Mode**: below the limit, charging only resumes once the battery drops more than 5% under it (e.g. limit 80% charges again below 75%), then charges back to the limit. Avoids many tiny charge cycles while plugged in.
- **Power and health**: adapter name and negotiated wattage, power drawn from the adapter, battery charge/discharge power, voltage, cycle count, and battery health both as macOS reports it (Maximum Capacity) and as raw full-charge / design capacity in mAh.

Behavior:

- Charge control only applies while the app is running. Quitting (or a crash) restores normal charging.
- If the control loop fails 3 times in a row (about 15 seconds), normal charging is restored so a stale state such as adapter power cut during a discharge cannot persist. Control resumes automatically once reads succeed again.
- While charging toward the limit or discharging, idle sleep is held off. If the Mac is put to sleep anyway, charging is paused and adapter power restored right before sleep, so the limit is never exceeded and the battery never drains while asleep.

### Ports

- Lists TCP ports in LISTEN state with process name, PID, bound address and the process's working directory (usually the project folder). Read directly from the kernel via libproc.
- **Stop** sends SIGTERM; if the process still holds its port after 3 seconds, **Force Kill** (SIGKILL) is offered.
- Open `http://localhost:<port>`, copy PID or URL, show the project folder in Finder or Terminal.
- Apps and macOS services (AirPlay, Spotify, editor helpers) are hidden by default; a search also matches them.
- Only this user's processes are listed. Ports held by other users or root (e.g. `sudo npm start`) are not readable without root and are deliberately not handled.
- The menu bar panel shows dev servers with a stop button; the main window shows the full list.
- Scans every 2 seconds, only while the panel or the Ports page is visible.

### Dev Utils (inspired by DevUtils, DevToys)

JSON format/minify (keeps key order and number spelling), Base64 and URL encode/decode, JWT decode (signature not verified), Unix timestamp to date and back, MD5/SHA-1/SHA-256/SHA-512, UUID. Output updates while typing.

## Architecture

| Part | Path | Role |
| --- | --- | --- |
| App | `App/` | SwiftUI menu bar panel + main window, runs as the user |
| Helper | `Helper/` | Root launchd daemon registered via `SMAppService`; the only part that writes SMC keys |
| BatteryCore | `Packages/BatteryCore/` | SMC client, battery reader, pure charge policy, XPC protocol (unit-tested) |
| DevCore | `Packages/DevCore/` | Port scanner (libproc) and Dev Utils conversions (unit-tested) |

App and helper talk over XPC (`com.diyanyapp.me.helper`); each side checks the other's code signature (team `U8GCXBC6Q3`).

### SMC keys (Apple Silicon)

| Key | Purpose | Values |
| --- | --- | --- |
| `CHTE` | Charging on/off (macOS 15/26-era firmware) | `00000000` on, `01000000` off |
| `CH0B`/`CH0C` | Charging on/off (older firmware) | `00` on, `02` off |
| `CH0J` | Adapter power on/off | `00` on, `01` off |
| `CHIE` | Adapter power on/off (alternative) | `00` on, `08` off |

Read-only telemetry (no root needed): `AC-W` charger physically attached (stays set while adapter power is cut), `B0AC` battery current in mA, `B0AV` battery voltage in mV, `PDTR` DC-in power in W. These are real time; the AppleSmartBattery driver's equivalents lag by about a minute.

Firmware shipped with macOS 27 / 26.7 (and some 15.x security updates) gates these keys behind a private entitlement ([batt#152](https://github.com/charlie0129/batt/issues/152)). The app detects this and marks the affected features as unsupported.

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & install

```sh
scripts/install.sh        # signed Release build, installed to /Applications
```

### Updating

Commit the change, then run `scripts/install.sh` again. It quits the running app, replaces it in
`/Applications` and relaunches it. Settings (UserDefaults) and the helper registration are kept.
The helper notices its binary changed and restarts itself, so no reinstall or re-approval is needed.

Bump `HelperConstants.protocolVersion` whenever the XPC interface changes; the app then asks to
reinstall the helper (Battery › Helper › Uninstall, then Install). The same applies if the
launchd plist changes.

Bump `MARKETING_VERSION` in `project.yml` for notable releases. The build number is the git
commit count. The signing certificate (free Personal Team) is valid for one year; Xcode renews
it automatically on the next build.

### App icon

The icon is generated from `Design/app-icon-source.png` (square, at least 1024 px):

```sh
swift scripts/make-app-icon.swift Design/app-icon-source.png App/Assets.xcassets/AppIcon.appiconset
```

### Testing on hardware

`scripts/dev-helper.sh` builds the Debug helper and runs its developer commands as root, logging to `build/logs/`:

```sh
scripts/dev-helper.sh status                        # read-only
scripts/dev-helper.sh selftest                      # toggles CHTE/CH0J and checks the battery reacts
scripts/dev-helper.sh run --limit 80 --discharge    # runs the real control loop in the foreground
scripts/dev-helper.sh run --limit 80 --sailing      # same, with Sailing Mode
scripts/dev-helper.sh charging on                   # recovery
scripts/dev-helper.sh adapter on                    # recovery
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
