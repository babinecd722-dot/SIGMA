#pragma once

namespace res::render {
bool Init();
void Shutdown();
void BeginFrame(int width, int height);
void EndFrame();
bool Ready();
}
