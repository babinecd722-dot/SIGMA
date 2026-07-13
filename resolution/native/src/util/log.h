#pragma once

#include <android/log.h>

#define RES_LOG_TAG "RESOLUTION"
#define RES_LOGI(...) __android_log_print(ANDROID_LOG_INFO, RES_LOG_TAG, __VA_ARGS__)
#define RES_LOGW(...) __android_log_print(ANDROID_LOG_WARN, RES_LOG_TAG, __VA_ARGS__)
#define RES_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, RES_LOG_TAG, __VA_ARGS__)
