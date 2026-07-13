#pragma once

#include "game/structures.h"

#include <vector>

namespace res::game {

bool Init();
void Shutdown();
bool Ready();

uintptr_t ClientBase();
std::size_t ClientSize();

CameraSnapshot Camera();
MarkerSnapshot Marker();
PedSnapshot LocalPed();
std::vector<PedSnapshot> Players();

bool WorldToScreen(const Vec3& world, Vec2& out);
bool SetLocalPosition(const Vec3& pos);
bool GetBone(uintptr_t ped, BoneId bone, Vec3& out);

void SetScreenSize(int w, int h);
void SetViewProjection(const float* view16, const float* proj16);

// Optional until GuiManager → CMapViewModel path is fully pinned.
void BindMapModel(uintptr_t map_model);

// Deprecated name kept so older call sites compile; no-op on BR.
void BindNetGame(uintptr_t);

}  // namespace res::game

namespace res::game::detail {
uintptr_t Base();
std::size_t Size();
uintptr_t MapModel();
uintptr_t PlayerPool();
void GetScreen(int& w, int& h);
bool ViewProj(Mat34& view, Mat34& proj);
uintptr_t Deref(uintptr_t addr);
bool ReadMat(uintptr_t addr, Mat34& out);
}  // namespace res::game::detail
EOF