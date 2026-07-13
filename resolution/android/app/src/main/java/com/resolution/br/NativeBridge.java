package com.resolution.br;

public final class NativeBridge {
    static {
        System.loadLibrary("resolution");
    }

    private NativeBridge() {}

    public static native void init();

    public static native void onTouch(int action, float x, float y, int pointerId);

    public static native void bindMapModel(long mapModelPtr);
}
