#include "game/player.h"

#include "game/br_offsets.h"
#include "game/game.h"
#include "util/log.h"
#include "util/memory.h"

#include <cmath>
#include <cstdio>
#include <cstring>

namespace res::game::player {
namespace {

PedSnapshot FromEntity(uintptr_t ent, int id, bool is_local) {
  PedSnapshot s;
  s.ptr = ent;
  s.id = id;
  s.is_local = is_local;
  if (!ent) return s;

  Vec3 pos{};
  if (!ReadEntityPos(ent, pos)) return s;
  s.pos = pos;
  s.valid = true;
  std::snprintf(s.name, sizeof(s.name), "%s%d", is_local ? "Local#" : "ID ", id);

  uint8_t in_veh = 0;
  mem::Read(reinterpret_cast<void*>(ent + br::kEntInVeh), in_veh);
  uintptr_t veh = 0;
  mem::Read(reinterpret_cast<void*>(ent + br::kEntVehicle), veh);
  s.in_vehicle = in_veh && veh;

  // Bones: not recovered yet — approximate from entity origin only.
  s.bone_count = static_cast<int>(BoneId::Count);
  for (int i = 0; i < s.bone_count; ++i) s.bones[i] = pos;
  s.bones[static_cast<int>(BoneId::Head)] = pos + Vec3{0.f, 0.f, 1.0f};
  s.bones[static_cast<int>(BoneId::Neck)] = pos + Vec3{0.f, 0.f, 0.85f};
  s.bones[static_cast<int>(BoneId::Spine)] = pos + Vec3{0.f, 0.f, 0.55f};
  return s;
}

uintptr_t LocalPosEntity() {
  // Mirrors helper 0x1310FD4: id via **(base+0x20AB860), object table 0x3197BD0.
  const uintptr_t base = detail::Base();
  if (!base) return 0;
  uintptr_t id_slot = detail::Deref(base + br::kLocalPosIdSlot);
  if (!id_slot) return 0;
  uint16_t id = 0;
  if (!mem::Read(reinterpret_cast<void*>(id_slot), id)) return 0;
  return detail::Deref(base + br::kLocalPosTable + static_cast<uintptr_t>(id) * br::kLocalPosStride);
}

uintptr_t TransformTarget(uintptr_t ent) {
  if (!ent) return 0;
  uint8_t flag = 0;
  uintptr_t veh = 0;
  mem::Read(reinterpret_cast<void*>(ent + br::kEntInVeh), flag);
  mem::Read(reinterpret_cast<void*>(ent + br::kEntVehicle), veh);
  return (flag && veh) ? veh : ent;
}

bool SoftWritePos(uintptr_t ent, const Vec3& pos) {
  uintptr_t dst = TransformTarget(ent);
  if (!dst) return false;
  // Heap objects are already RW — no mprotect.
  return mem::WriteBytes(reinterpret_cast<void*>(dst + br::kEntPos), &pos, sizeof(pos));
}

}  // namespace

uintptr_t Pool() { return detail::PlayerPool(); }

uintptr_t LocalPlayer() {
  uintptr_t pool = Pool();
  if (!pool) return 0;
  return detail::Deref(pool + br::kPoolLocal);
}

uintptr_t PlayerAt(std::uint16_t id) {
  uintptr_t pool = Pool();
  if (!pool || id > br::kMaxPlayerId) return 0;
  return detail::Deref(pool + br::kPoolRemoteBase + static_cast<uintptr_t>(id) * 8u);
}

uintptr_t PedOf(uintptr_t player) {
  if (!player) return 0;
  return detail::Deref(player + br::kPlayerPed);
}

bool ReadEntityPos(uintptr_t ent, Vec3& out) {
  if (!ent) return false;
  uintptr_t src = TransformTarget(ent);
  return mem::ReadBytes(reinterpret_cast<void*>(src + br::kEntPos), &out, sizeof(out));
}

PedSnapshot Local() {
  uintptr_t lp = LocalPlayer();
  if (!lp) return {};
  uint16_t id = 0;
  mem::Read(reinterpret_cast<void*>(lp + br::kPlayerId), id);
  return FromEntity(PedOf(lp), static_cast<int>(id), true);
}

std::vector<PedSnapshot> All() {
  std::vector<PedSnapshot> out;
  uintptr_t pool = Pool();
  if (!pool) return out;

  auto local = Local();
  if (local.valid) out.push_back(local);

  for (uint16_t id = 0; id <= br::kMaxPlayerId; ++id) {
    if (local.valid && id == static_cast<uint16_t>(local.id)) continue;
    uintptr_t pl = PlayerAt(id);
    if (!pl) continue;
    uintptr_t ped = PedOf(pl);
    if (!ped) continue;
    auto snap = FromEntity(ped, id, false);
    if (snap.valid) out.push_back(snap);
  }
  return out;
}

bool SetPosition(const Vec3& pos) {
  if (!std::isfinite(pos.x) || !std::isfinite(pos.y) || !std::isfinite(pos.z)) return false;

  bool ok = false;
  uintptr_t ped = PedOf(LocalPlayer());
  if (ped) ok = SoftWritePos(ped, pos) || ok;

  // Also sync the local-pos helper object when it differs (same rule as 0x1310FD4).
  uintptr_t loc_ent = LocalPosEntity();
  if (loc_ent && loc_ent != ped) ok = SoftWritePos(loc_ent, pos) || ok;

  if (!ok) {
    RES_LOGW("SetPosition failed (no writable ped/vehicle)");
    return false;
  }
  return true;
}

bool GetBone(uintptr_t ped, BoneId bone, Vec3& out) {
  Vec3 pos{};
  if (!ReadEntityPos(ped, pos)) return false;
  switch (bone) {
    case BoneId::Head: out = pos + Vec3{0.f, 0.f, 1.0f}; break;
    case BoneId::Neck: out = pos + Vec3{0.f, 0.f, 0.85f}; break;
    case BoneId::Spine:
    case BoneId::Pelvis: out = pos + Vec3{0.f, 0.f, 0.55f}; break;
    default: out = pos; break;
  }
  return true;
}

}  // namespace res::game::player
