#include <jni.h>

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_flutter_1native_1smoke_MainActivity_nativePing(
    JNIEnv* env,
    jobject /* this */) {
  return env->NewStringUTF("pong from C++ via Kotlin JNI");
}
