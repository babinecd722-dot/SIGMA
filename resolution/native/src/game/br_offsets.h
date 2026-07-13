#pragma once

#include <cstddef>
#include <cstdint>

// Offsets recovered from libblackrussia-client.so (com.br.top 16.89.8717).
// Values are RVAs / field offsets from RESOLUTION reverse — not SA-MP.

namespace res::br {

inline constexpr const char* kClientSo = "libblackrussia-client.so";
inline constexpr const char* kVersion = "16.89.8717";

// --- globals (RVA into client) ---
inline constexpr std::uintptr_t kPlayerPoolSlot = 0x33CE110;  // T** → PlayerPool*
inline constexpr std::uintptr_t kLocalPosIdSlot = 0x20AB860;  // uint16_t** used by pos helper
inline constexpr std::uintptr_t kLocalPosTable = 0x3197BD0;   // entries stride 0xF8, qword @ +0
inline constexpr std::uint32_t kLocalPosStride = 0xF8;
inline constexpr std::uint16_t kMaxPlayerId = 0x5DF;

// --- PlayerPool ---
inline constexpr std::uint32_t kPoolLocal = 0x00;       // Player*
inline constexpr std::uint32_t kPoolRemoteBase = 0x08;  // Player*[id] via pool+8+id*8

// --- Player (Local/Remote network object) ---
inline constexpr std::uint32_t kPlayerId = 0x00;   // uint16
inline constexpr std::uint32_t kPlayerPed = 0x38;  // CPed*

// --- Ped / vehicle entity world transform ---
inline constexpr std::uint32_t kEntPos = 0x38;       // CVector {x,y,z}
inline constexpr std::uint32_t kEntVehicle = 0x4D8;  // vehicle* when occupied
inline constexpr std::uint32_t kEntInVeh = 0x4E0;    // u8 flag

// --- Gui::MapObjectLocation ---
inline constexpr std::uint32_t kLocId = 0x00;
inline constexpr std::uint32_t kLocHasId = 0x04;
inline constexpr std::uint32_t kLocPos = 0x08;  // CVector
inline constexpr std::uint32_t kLocHasPos = 0x14;

// --- Gui::CMapModel ---
inline constexpr std::uint32_t kMapNavAlt = 0x37C;     // MapObjectLocation
inline constexpr std::uint32_t kMapNavTarget = 0x394;  // m_navigationTarget
inline constexpr std::uint32_t kMapNavMode = 0x3B8;    // ==1 → GPS target active path
// Ctor @ 0x15BAF40 stores empty-list sentinel into +0x3C0 (stable fingerprint).
inline constexpr std::uint32_t kMapListSentinel = 0x3C0;
inline constexpr std::uintptr_t kMapListSentinelRva = 0x2005A88;
// Fallback empty location returned by 0x15BE708 when mode != 1.
inline constexpr std::uintptr_t kEmptyNavLocRva = 0x33B6068;

// --- Gui::CMapViewModel ---
inline constexpr std::uint32_t kViewMapModel = 0x60;  // CMapModel* m_mapModel

// --- code RVAs (callables) ---
inline constexpr std::uintptr_t kFnGetPlayerId = 0x1872290;
inline constexpr std::uintptr_t kFnGetPlayerPed = 0x1872298;
inline constexpr std::uintptr_t kFnPoolLocal = 0x1891E30;
inline constexpr std::uintptr_t kFnPoolAt = 0x1891E38;
inline constexpr std::uintptr_t kFnLocalPos = 0x1310FD4;
inline constexpr std::uintptr_t kFnLocHasPos = 0x15C6D00;
inline constexpr std::uintptr_t kFnLocGetPos = 0x15C6D08;
inline constexpr std::uintptr_t kFnLocHasId = 0x15C6CA4;
inline constexpr std::uintptr_t kFnLocGetId = 0x15C6CAC;
inline constexpr std::uintptr_t kFnMapNavPtr = 0x15BE708;  // CMapModel* → MapObjectLocation*

}  // namespace res::br

