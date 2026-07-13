# RESOLUTION

Black Russia overlay module — ESP / AIM / GPS teleport — built against official launcher  
`https://dl.blackcdn.me/launcher.apk` (`com.br.top` **16.89.8717**).

Offsets come from reversing `libblackrussia-client.so` (see `docs/REVERSE.md`). Not SA-MP layouts.

## Features

- Floating semi-transparent **R** button (drag / tap → toggle menu)
- ImGui menu: ESP, AIM, Teleport, Misc
- ESP: box, skeleton placeholders, HP/armour bars, name, distance, snapline
- AIM: FOV circle, target lock line, bone select (cam write still RE-open)
- Teleport: read `CMapModel.m_navigationTarget` (`MapObjectLocation` @ `+0x394`) → write entity `CVector` @ `+0x38`

## Build

```bash
# NDK r26+ 
cmake -S resolution/native -B resolution/native/build \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26
cmake --build resolution/native/build -j
```

Output: `libresolution.so`

## Inject into official launcher

```bash
curl -L -o launcher.apk https://dl.blackcdn.me/launcher.apk
python3 resolution/tools/inject_resolution.py \
  --apk launcher.apk \
  --so resolution/native/build/libresolution.so \
  --out resolution-unsigned.apk
# sign, install
```

`JNILib.<clinit>` load order becomes: `update-manager` → **`resolution`** → `blackrussia-client`.

## Teleport flow

1. Open BR map / set GPS pin (`SetGpsNavigationTarget`)
2. Close map UI
3. RESOLUTION → Teleport → **Go to marker**

Requires `CMapModel*` bound (auto-bind path still open; use `NativeBridge.bindMapModel` or continue RE for GuiManager).

## Brand

| | |
|--|--|
| Name | RESOLUTION |
| FAB | letter **R**, glass disc, teal accent `#2EE6A6` |
| Assets | `resolution/assets/fab_r.png` |

<img alt="RESOLUTION FAB" src="assets/fab_r.png" />
EOF