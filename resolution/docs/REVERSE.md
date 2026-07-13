# RESOLUTION — reverse notes (facts only)

Target APK: `https://dl.blackcdn.me/launcher.apk`  
Package `com.br.top` · version `16.89.8717` (`versionCode` 1476)  
`libblackrussia-client.so` arm64 · SHA256 `a8a1856a4574cd08cefad13b43560006deba7b0eb65e3111559c6950d8e487a7`

All RVAs below are file/VA offsets into that `.so` (ET_DYN, load bias 0 in file).

---

## Load path

`JNILib.<clinit>`:

1. `loadLibrary("update-manager")`
2. `loadLibrary("blackrussia-client")`

---

## Network player hub (from `JNILib_getPlayerId`)

| Item | Evidence |
|------|----------|
| Global slot | `0x33CE110` — `adrp/ldr` in `Java_…_getPlayerId` @ `0x187A498` |
| Init | ctor @ `0x1891B1C` stored into that slot (alloc path in JNI init @ `0x187A518`) |
| Local player | `*(T**)pool` — helper `0x1891E30`: `ldr x0,[x0]; ret` |
| Player id | `*(uint16_t*)player` — `0x1872290`: `ldrh w0,[x0]; ret` |
| Ped pointer | `*(void**)(player + 0x38)` — `0x1872298`: `ldr x0,[x0,#0x38]; ret` |
| Remote by id | `0x1891E38`: if `id <= 0x5DF` → `*(pool + 8 + id*8)` |

This is **BRClient** `network/PlayerPool.cpp` / `LocalPlayer.cpp` / `RemotePlayer.cpp` — not SA-MP.

---

## Entity / ped world position (from local-pos helper)

Function `@ 0x1310FD4` (called from map distance code):

1. `id = **(uint16_t**)(base + 0x20AB860)`
2. `obj = *(void**)(0x3197BD0 + id * 0xF8)`
3. If `obj+0x4D8 != 0` && `*(u8*)(obj+0x4E0)` → use vehicle object at `+0x4D8`
4. Position: `CVector` at **`obj + 0x38`**
   - `ldp s0,s1,[x8,#0x38]`
   - `ldr s2,[x8,#0x40]`

Same `+0x38` XY read after ped getter in `@ 0x14A527C`.

Ped flags seen in multiple sites: `+0x4E0` (byte), `+0x4D8` (ptr, vehicle).

---

## Map GPS / navigation (teleport marker)

### `Gui::MapObjectLocation` (`MapObject*.cpp` accessors)

| Offset | Field | Accessor |
|--------|-------|----------|
| `+0x00` | `m_id` (`uint32`) | `GetId` assert string `m_id` |
| `+0x04` | has-id flag (`u8`) | `0x15C6CA4` / `0x15C6CAC` |
| `+0x08` | `m_position` `CVector` | `GetPosition` @ `0x15C6D08`: `ldp s0,s1,[x0,#8]; ldr s2,[x0,#0x10]` |
| `+0x14` | has-position flag (`u8`) | `HasPosition` @ `0x15C6D00`: `ldrb w0,[x0,#0x14]` |

### `Gui::CMapModel`

| Offset | Field | Evidence |
|--------|-------|----------|
| `+0x37C` | secondary `MapObjectLocation` | ctor init; getter `0x15BE72C` |
| `+0x394` | `m_navigationTarget` | ctor; `HasPosition` assert `m_navigationTarget.HasPosition()`; uses in `@ 0x15C0D48` |
| `+0x3B8` | nav mode byte | `0x15BE700`: `ldrb w0,[x0,#0x3B8]`; `0x15BE708` returns `&(+0x394)` only if `== 1` |
| `+0x198` | list begin/end of related objects (stride `0x18`) | `ldp x23,x24,[x19,#0x198]` |

API names recovered from mangled strings:

- `CMapModel::SetGpsNavigationTarget(CVector const&, bool)`
- `CMapModel::SetNavigationTarget(MapObjectLocation const&, bool)`
- `CMapModel::ClearNavigation(bool)`
- `ReportNavigationTargetChanged`

### `Gui::CMapViewModel`

| Offset | Field | Evidence |
|--------|-------|----------|
| `+0x60` | `m_mapModel` (`CMapModel*`) | `@ 0x15D3610`: `ldr x0,[x19,#0x60]; bl 0x15BE708` then `HasPosition`/`GetPosition` on result |

---

## CMapModel runtime fingerprint

Ctor `@ 0x15BAF40` stores empty-list sentinel into `CMapModel+0x3C0`:

- sentinel RVA `0x2005A88` (`adrp 0x2005000` + `#0xa88`)
- Empty nav fallback from `0x15BE708` when mode ≠ 1: RVA `0x33B6068`

RESOLUTION discovers `CMapModel*` by scanning RW anonymous heap for `*(map+0x3C0) == client_base+0x2005A88`, preferring `mode==1` + `HasPosition` on `+0x394`.

---

## Still open (do not invent)

- Stable global / GuiManager → `CMapViewModel*` path (singleton not pinned; heap fingerprint used instead)
- Full bone matrix via `SkinGetBonePositionsToTable` / `m_transform` (assert only so far)
- Camera view/proj matrix for W2S (Noesis/librw path, not recovered)
- Exact writer body of `SetGpsNavigationTarget` (read path recovered; teleport reads pin then soft-writes entity `+0x38`)

---

## Product implication

ESP/aim/teleport code must use the structures above. No SA-MP `PlayerPool` / `localPlayer+0x8` layouts.
