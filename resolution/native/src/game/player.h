#pragma once

#include "game/structures.h"

#include <vector>

namespace res::game::player {

PedSnapshot Local();
std::vector<PedSnapshot> All();
bool SetPosition(const Vec3& pos);
bool GetBone(uintptr_t ped, BoneId bone, Vec3& out);

uintptr_t Pool();
uintptr_t LocalPlayer();
uintptr_t PlayerAt(std::uint16_t id);
uintptr_t PedOf(uintptr_t player);
bool ReadEntityPos(uintptr_t ent, Vec3& out);

}  // namespace res::game::player
EOF