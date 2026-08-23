package com.excellentcalendar.excellent_calendar.bridge.ring

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntime
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.RingRevisionRequest

class RingMethodOrchestrator(
    private val activity: Activity,
    private val runtime: RingRuntime,
) {
    private var pendingPicker: PendingPicker? = null

    fun getState(): NativeResultContract = runtime.state()

    fun pickRingtone(request: RingRevisionRequest, callback: (NativeResultContract) -> Unit) {
        if (pendingPicker != null) {
            callback(failure(NativeErrorCodes.RingtonePickerFailed, "A ringtone picker is already active.", true))
            return
        }
        if (settingsRevision() != request.expectedSettingsRevision) {
            callback(failure(NativeErrorCodes.RingSettingsConflict, "Ring settings changed before ringtone selection.", true))
            return
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
        pendingPicker = PendingPicker(request.expectedSettingsRevision, callback)
        try {
            activity.startActivityForResult(intent, PickerRequestCode)
        } catch (_: RuntimeException) {
            pendingPicker = null
            callback(failure(NativeErrorCodes.RingtonePickerFailed, "Android ringtone picker could not be opened.", true))
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PickerRequestCode) return false
        val pending = pendingPicker ?: return true
        pendingPicker = null
        if (resultCode != Activity.RESULT_OK) {
            pending.callback(selection("cancelled", runtime.state()))
            return true
        }
        val uri = if (android.os.Build.VERSION.SDK_INT >= 33) {
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        } ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        if (uri == null) {
            pending.callback(failure(NativeErrorCodes.RingtonePickerFailed, "The selected ringtone is unavailable.", true))
            return true
        }
        val name = runCatching { RingtoneManager.getRingtone(activity, uri)?.getTitle(activity) }.getOrNull()
            ?: "Selected alarm"
        val updated = runtime.updateRingtone(pending.expectedRevision, uri.toString(), name, available = true)
        pending.callback(selection("selected", updated))
        return true
    }

    fun close() {
        pendingPicker?.callback?.invoke(
            failure(NativeErrorCodes.RingtonePickerFailed, "Ringtone selection was interrupted.", true),
        )
        pendingPicker = null
    }

    private fun settingsRevision(): Long {
        @Suppress("UNCHECKED_CAST")
        val state = runtime.state().data as? Map<String, Any?> ?: return -1
        @Suppress("UNCHECKED_CAST")
        val settings = state["settings"] as? Map<String, Any?> ?: return -1
        return (settings["revision"] as Number).toLong()
    }

    private fun selection(status: String, stateResult: NativeResultContract): NativeResultContract {
        if (!stateResult.ok) return stateResult
        return NativeResultContract.success(
            linkedMapOf("selection_status" to status, "state" to stateResult.data),
            contractVersion = 2,
        )
    }

    private fun failure(code: String, message: String, retryable: Boolean): NativeResultContract =
        NativeResultContract.failure(code, message, retryable = retryable, contractVersion = 2)

    private data class PendingPicker(
        val expectedRevision: Long,
        val callback: (NativeResultContract) -> Unit,
    )

    companion object {
        const val PickerRequestCode = 7304
    }
}
