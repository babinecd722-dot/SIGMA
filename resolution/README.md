# RESOLUTION

Black Russia overlay module — ESP / AIM / GPS teleport — built against official launcher  
`https://dl.blackcdn.me/launcher.apk` (`com.br.top` **16.89.8717**).

Offsets come from reversing `libblackrussia-client.so` (see `docs/REVERSE.md`). Not SA-MP layouts.

## Features

- Floating semi-transparent **R** button (drag / tap → toggle menu)
- ImGui menu: ESP, AIM, Teleport, Misc
- ESP: box, skeleton placeholders, HP/armour bars, name, distance, snapline
- AIM: FOV circle, target lock line, bone select (cam write still RE-open)
- Teleport: auto-discover `CMapModel*` (heap fingerprint `+0x3C0` → `0x2005A88`), read GPS `m_navigationTarget` @ `+0x394`, soft-write entity/vehicle `CVector` @ `+0x38`

## Soft / anti-noise notes

- Heap position writes use plain `memcpy` on already-RW pages — **no** `mprotect` / I-cache flush on game objects
- Code hooks still need RWX only on the hooked page
- Marker coords validated (finite, map bounds, max distance from local)
- Local-pos table object (`0x3197BD0` path) synced when it differs from ped

## Build

```bash
# NDK r27c verified in CI-style local build
cmake -S resolution/native -B resolution/native/build \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release
cmake --build resolution/native/build -j
llvm-strip --strip-unneeded resolution/native/build/libresolution.so \
  -o resolution/out/arm64-v8a/libresolution.so
```

Prebuilt (this branch): `resolution/out/arm64-v8a/libresolution.so`

## Inject into official launcher

```bash
curl -L -o launcher.apk https://dl.blackcdn.me/launcher.apk
python3 resolution/tools/inject_resolution.py \
  --apk launcher.apk \
  --so resolution/out/arm64-v8a/libresolution.so \
  --out resolution-unsigned.apk
# sign, install
```

`JNILib.<clinit>` load order becomes: `update-manager` → **`resolution`** → `blackrussia-client`.

## Teleport flow

1. Open BR map / set GPS pin (`SetGpsNavigationTarget`)
2. Close map UI
3. RESOLUTION → Teleport → **Find CMapModel** (once) → **Go to marker**

Auto-scan throttles to ~2s and prefers anonymous RW heap with active `mode==1`.

## Brand

| | |
|--|--|
| Name | RESOLUTION |
| FAB | letter **R**, glass disc, teal accent `#2EE6A6` |
| Assets | `resolution/assets/fab_r.png` |

<img alt="RESOLUTION FAB" src="assets/fab_r.png" />
