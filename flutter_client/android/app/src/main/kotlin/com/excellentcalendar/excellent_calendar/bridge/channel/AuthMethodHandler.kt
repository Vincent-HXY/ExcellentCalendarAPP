package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenRecordCorruptedException
import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenSecureStorageException
import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenSecureStore
import com.excellentcalendar.excellent_calendar.bridge.contract.AuthRefreshTokenContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall

/**
 * Handles auth.refresh_token.store/read/delete/exists on the shared native
 * MethodChannel. This handler owns no login business logic and never logs
 * the sensitive payload (sensitive_payload=true).
 */
internal class AuthMethodHandler(
    private val tokenStore: RefreshTokenSecureStore?,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodAuthRefreshTokenStore,
        NativeMethodChannelHandler.MethodAuthRefreshTokenRead,
        NativeMethodChannelHandler.MethodAuthRefreshTokenDelete,
        NativeMethodChannelHandler.MethodAuthRefreshTokenExists,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) {
            completion.notImplemented()
            return
        }
        when (call.method) {
            NativeMethodChannelHandler.MethodAuthRefreshTokenStore -> store(call, completion)
            NativeMethodChannelHandler.MethodAuthRefreshTokenRead -> read(call, completion)
            NativeMethodChannelHandler.MethodAuthRefreshTokenDelete -> delete(call, completion)
            NativeMethodChannelHandler.MethodAuthRefreshTokenExists -> exists(call, completion)
            else -> completion.notImplemented()
        }
    }

    private fun store(call: MethodCall, completion: SingleCompletion) {
        val record = nativeExecutor.parse(call, completion) {
            AuthRefreshTokenContracts.storeRequest(it)
        } ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            val store = tokenStore ?: return@executeOperation notConfigured()
            try {
                store.store(record)
                NativeResultContract.success(
                    AuthRefreshTokenContracts.operationResponse(),
                    contractVersion = contractProfile.contractVersion,
                )
            } catch (error: RefreshTokenSecureStorageException) {
                storageFailure()
            } catch (error: RefreshTokenRecordCorruptedException) {
                corruptedFailure()
            }
        }
    }

    private fun read(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeOperation(call.method, completion) {
            val store = tokenStore ?: return@executeOperation notConfigured()
            try {
                val record = store.read()
                    ?: return@executeOperation NativeResultContract.failure(
                        code = NativeErrorCodes.SecureTokenNotFound,
                        message = "No Refresh Token record exists in Android secure storage.",
                        contractVersion = contractProfile.contractVersion,
                    )
                NativeResultContract.success(
                    AuthRefreshTokenContracts.secureRecordResponse(record),
                    contractVersion = contractProfile.contractVersion,
                )
            } catch (error: RefreshTokenSecureStorageException) {
                storageFailure()
            } catch (error: RefreshTokenRecordCorruptedException) {
                corruptedFailure()
            }
        }
    }

    private fun delete(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeOperation(call.method, completion) {
            val store = tokenStore ?: return@executeOperation notConfigured()
            try {
                store.delete()
                NativeResultContract.success(
                    AuthRefreshTokenContracts.operationResponse(),
                    contractVersion = contractProfile.contractVersion,
                )
            } catch (error: RefreshTokenSecureStorageException) {
                storageFailure()
            }
        }
    }

    private fun exists(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeOperation(call.method, completion) {
            val store = tokenStore ?: return@executeOperation notConfigured()
            try {
                NativeResultContract.success(
                    AuthRefreshTokenContracts.presenceResponse(store.exists()),
                    contractVersion = contractProfile.contractVersion,
                )
            } catch (error: RefreshTokenSecureStorageException) {
                storageFailure()
            }
        }
    }

    private fun storageFailure() = NativeResultContract.failure(
        code = NativeErrorCodes.SecureTokenStorageFailed,
        message = "Android secure storage could not persist or delete the Refresh Token.",
        retryable = true,
        contractVersion = contractProfile.contractVersion,
    )

    private fun corruptedFailure() = NativeResultContract.failure(
        code = NativeErrorCodes.SecureTokenCorrupted,
        message = "The encrypted Refresh Token record cannot be decoded safely.",
        contractVersion = contractProfile.contractVersion,
    )

    private fun notConfigured() = NativeResultContract.failure(
        code = NativeErrorCodes.FeatureNotImplemented,
        message = "auth.refresh_token.* is not configured in this build.",
        contractVersion = contractProfile.contractVersion,
    )
}
