#include <jni.h>

// smoke 测试的 JNI 导出函数：只返回固定字符串，用来确认 C++ 已被成功调用。
extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_flutter_1native_1smoke_MainActivity_nativePing(
    JNIEnv* env,
    jobject /* this */) {
  return env->NewStringUTF("pong from C++ via Kotlin JNI");
}
