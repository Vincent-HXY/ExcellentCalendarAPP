package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract

/**
 * 表示 native bridge 当前不可用的异常。
 *
 * 这类错误通常不是业务输入问题，而是动态库没有加载成功、JNI 函数名不匹配、
 * 或 Android 系统拒绝加载 so 文件。上层会把它转换成统一的 NativeResult 失败响应。
 */
class NativeBridgeUnavailableException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Kotlin 的 `fun interface` 是“只有一个抽象函数的接口”，也叫 SAM 接口。
 *
 * 它的好处是可以直接用 lambda 创建实例：
 * `NativeLibraryLoader { System.loadLibrary("xxx") }`。
 * 这里抽象出来是为了测试时替换加载逻辑，不必真的加载 native 库。
 */
fun interface NativeLibraryLoader {
    fun load()
}

/**
 * 通过 JNI 调用 C++ 事件内核的 Kotlin 实现。
 *
 * 构造参数说明：
 * - `storageDirectory`：C++ JSON 仓库使用的本地目录；为 null 时跳过初始化。
 * - `libraryLoader`：负责加载 `.so` 动态库，默认调用 `System.loadLibrary`。
 *
 * Kotlin 初学点：
 * - `private val` 是构造函数参数同时声明为私有只读属性。
 * - `: NativeEventBridge` 表示这个类实现了接口，必须提供接口里的函数。
 */
class JniNativeEventBridge(
    private val storageDirectory: String? = null,
    private val libraryLoader: NativeLibraryLoader = NativeLibraryLoader {
        System.loadLibrary(NativeLibraryName)
    },
) : NativeEventBridge {
    /**
     * `@Volatile` 保证多线程下读取到的是最新值。
     *
     * Android 的 MethodChannel 调用可能被派发到后台线程。这里配合 `synchronized(this)`
     * 实现“双重检查”：库只加载一次，失败结果也只记录一次。
     */
    @Volatile
    private var loadAttempted = false

    /** 保存加载失败的异常；为 null 表示加载成功或尚未尝试。 */
    @Volatile
    private var loadFailure: Throwable? = null

    /** storage 初始化也只做一次，避免每次业务调用都重复创建目录/初始化仓库。 */
    @Volatile
    private var storageInitAttempted = false

    /** 如果初始化失败，保存 C++ 返回的 NativeResult JSON，后续调用直接返回同一个失败。 */
    @Volatile
    private var storageInitFailureJson: String? = null

    /** 调用 C++ 创建事件：先确保库和存储可用，再进入 nativeCreateEvent。 */
    override fun createEvent(requestJson: String): String {
        ensureLibraryLoaded()
        ensureStorageInitialized()?.let { return it }
        return try {
            nativeCreateEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeCreateEvent is unavailable.", error)
        }
    }

    /** 调用 C++ 搜索事件。`?.let { return it }` 表示：如果初始化失败 JSON 非空，直接返回。 */
    override fun searchEvents(requestJson: String): String {
        ensureLibraryLoaded()
        ensureStorageInitialized()?.let { return it }
        return try {
            nativeSearchEvents(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeSearchEvents is unavailable.", error)
        }
    }

    /** 调用 C++ 完成事件。当前 native API 可能尚未实现，但仍通过同一条 JNI 通道返回。 */
    override fun completeEvent(requestJson: String): String {
        ensureLibraryLoaded()
        return try {
            nativeCompleteEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeCompleteEvent is unavailable.", error)
        }
    }

    /** 调用 C++ 重新打开事件。 */
    override fun reopenEvent(requestJson: String): String {
        ensureLibraryLoaded()
        return try {
            nativeReopenEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeReopenEvent is unavailable.", error)
        }
    }

    /**
     * `external` 表示函数体不在 Kotlin 中，而是在 JNI/C++ 中实现。
     *
     * C++ 侧函数名必须按 JNI 规则匹配这个包名、类名、方法名，否则运行时会抛出
     * `UnsatisfiedLinkError`。
     */
    external fun nativeCreateEvent(requestJson: String): String

    external fun nativeInitializeStorage(storageDirectory: String): String

    external fun nativeSearchEvents(requestJson: String): String

    external fun nativeCompleteEvent(requestJson: String): String

    external fun nativeReopenEvent(requestJson: String): String

    /** 加载 native 动态库。成功或失败都会被缓存，避免重复加载。 */
    private fun ensureLibraryLoaded() {
        if (!loadAttempted) {
            synchronized(this) {
                if (!loadAttempted) {
                    loadFailure = try {
                        libraryLoader.load()
                        null
                    } catch (error: UnsatisfiedLinkError) {
                        error
                    } catch (error: SecurityException) {
                        error
                    }
                    loadAttempted = true
                }
            }
        }
        val failure = loadFailure
        if (failure != null) {
            throw NativeBridgeUnavailableException("Native event library is unavailable.", failure)
        }
    }

    /**
     * 初始化 C++ 存储层。
     *
     * 返回值是 `String?`：
     * - null：初始化成功，可以继续业务调用。
     * - 非 null：初始化失败，字符串本身就是符合 NativeResult 合约的错误 JSON。
     */
    private fun ensureStorageInitialized(): String? {
        val directory = storageDirectory ?: return null
        if (!storageInitAttempted) {
            synchronized(this) {
                if (!storageInitAttempted) {
                    storageInitFailureJson = initializeStorage(directory)
                    storageInitAttempted = true
                }
            }
        }
        return storageInitFailureJson
    }

    /** 调用 nativeInitializeStorage，并把畸形响应转换成统一的合约错误。 */
    private fun initializeStorage(directory: String): String? {
        val initJson = try {
            nativeInitializeStorage(directory)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeInitializeStorage is unavailable.", error)
        }
        return try {
            val parsed = NativeResultContract.fromJson(initJson) { }
            if (parsed.ok) null else initJson
        } catch (error: NativeContractViolation) {
            NativeContractJsonCodec.encodeObject(
                NativeResultContract.failure(
                    code = NativeErrorCodes.ContractValidationFailed,
                    message = error.message ?: "Native storage initialization returned malformed NativeResult.",
                    details = linkedMapOf("field" to error.field),
                ).toMap(),
            )
        }
    }

    companion object {
        /** `companion object` 类似 Java 的 static 成员容器；这里放动态库名常量。 */
        const val NativeLibraryName = "excellent_calendar_native"
    }
}
