import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'auth_refresh_token_adapter.dart';

/// Configuration for the cloud backend API.
class AuthConfig {
  AuthConfig({
    this.baseUrl = 'http://localhost:8080',
    this.accessTokenTtlSeconds = 900,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 15),
  });

  /// Base URL of the cloud backend (no trailing slash).
  final String baseUrl;

  /// Access Token TTL from the backend contract (default: 900s = 15 min).
  final int accessTokenTtlSeconds;

  /// HTTP connect timeout.
  final Duration connectTimeout;

  /// HTTP receive timeout.
  final Duration receiveTimeout;

  /// Resolve an API path relative to the base URL.
  Uri uri(String path) => Uri.parse('$baseUrl/api/v1$path');
}

/// Backend error returned in the ApiResult envelope.
class BackendError {
  const BackendError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.fieldErrors = const [],
    this.retryAfterSeconds,
  });

  factory BackendError.fromJson(Map<String, dynamic> json) {
    return BackendError(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'Unknown error',
      retryable: json['retryable'] as bool? ?? false,
      fieldErrors: (json['field_errors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      retryAfterSeconds: json['retry_after_seconds'] as int?,
    );
  }

  /// Parse a [ProblemDetail][RFC 9457] response body.
  ///
  /// The backend exception handlers return ProblemDetail, e.g.:
  /// ```json
  /// {"title": "INVALID_CREDENTIALS", "detail": "Invalid email or password",
  ///  "status": 401, "timestamp": "2026-08-02T...", "type": "about:blank"}
  /// ```
  factory BackendError.fromProblemDetail(Map<String, dynamic> json) {
    final title = json['title'] as String? ?? 'UNKNOWN';
    final detail = json['detail'] as String? ?? 'Unknown error';
    final status = json['status'] as int? ?? 500;

    return BackendError(
      code: title,
      message: detail,
      retryable: status >= 500,
      fieldErrors: const [],
      retryAfterSeconds: null,
    );
  }

  final String code;
  final String message;
  final bool retryable;
  final List<String> fieldErrors;
  final int? retryAfterSeconds;

  bool get isAuthInvalid => code == 'AUTH_INVALID_CREDENTIALS';
  bool get isEmailUnverified => code == 'AUTH_EMAIL_UNVERIFIED';
  bool get isSessionExpired => code == 'AUTH_SESSION_EXPIRED';
  bool get isAccountDisabled => code == 'AUTH_ACCOUNT_DISABLED';
  bool get isRefreshTokenInvalid => code == 'AUTH_REFRESH_TOKEN_INVALID';
  bool get isRateLimited => code == 'API_RATE_LIMITED';
  bool get isUnauthenticated => code == 'API_UNAUTHENTICATED';
}

/// Wrapper for an API response from the backend.
class ApiResponse<T> {
  const ApiResponse({
    required this.ok,
    this.data,
    this.error,
    this.requestId,
    this.statusCode,
  });

  factory ApiResponse.fromHttpResponse(
    int statusCode,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>)? parseData,
    T Function(List<dynamic>)? parseList,
  ) {
    final ok = body['ok'] as bool? ?? (statusCode >= 200 && statusCode < 300);
    BackendError? error;
    T? data;

    if (!ok && body['error'] != null) {
      error = BackendError.fromJson(body['error'] as Map<String, dynamic>);
    } else if (!ok && body['title'] != null) {
      // Backend returns ProblemDetail (RFC 9457) on errors:
      // {title, detail, status, timestamp, type}
      error = BackendError.fromProblemDetail(body);
    }
    if (ok) {
      if (body['data'] != null && body['data'] is Map<String, dynamic>) {
        data = parseData?.call(body['data'] as Map<String, dynamic>);
      } else if (body['data'] != null && body['data'] is List<dynamic>) {
        // For list responses, ignore parseData since we don't have a list parser
      } else if (parseData != null) {
        // No 'data' wrapper — pass the full body (flat backend response)
        data = parseData(body);
      }
    }

    return ApiResponse<T>(
      ok: ok,
      data: data,
      error: error,
      requestId: body['request_id'] as String?,
      statusCode: statusCode,
    );
  }

  final bool ok;
  final T? data;
  final BackendError? error;
  final String? requestId;
  final int? statusCode;
}

/// Exception thrown by the HTTP client layer.
class AuthHttpException implements Exception {
  const AuthHttpException(this.message, {this.statusCode, this.error});

  final String message;
  final int? statusCode;
  final BackendError? error;
}

/// Unified HTTP client for backend API calls.
///
/// Automatically adds the Bearer token and handles 401-triggered refresh.
class AuthHttpClient {
  AuthHttpClient({
    required this.config,
    required this.refreshTokenAdapter,
  });

  final AuthConfig config;
  final AuthRefreshTokenAdapter refreshTokenAdapter;

  String? _accessToken;
  VoidCallback? onRefreshFailed;

  /// Set the current access token in memory.
  void setAccessToken(String token) {
    _accessToken = token;
  }

  /// Clear the current access token from memory.
  void clearAccessToken() {
    _accessToken = null;
  }

  final HttpClient _client = HttpClient();

  // Refresh lock: only one refresh at a time.
  bool _isRefreshing = false;
  bool _refreshResult = false;
  final List<_PendingRequest> _pendingQueue = [];

  /// Send a GET request.
  Future<ApiResponse<T>> get<T>(
    String path, {
    T Function(Map<String, dynamic>)? parseData,
    Map<String, String>? queryParams,
  }) async {
    return _executeWithRefresh(() async {
      final uri = queryParams != null
          ? config.uri(path).replace(queryParameters: queryParams)
          : config.uri(path);
      return _send<T>('GET', uri, parseData: parseData);
    });
  }

  /// Send a POST request.
  Future<ApiResponse<T>> post<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    return _executeWithRefresh(() async {
      return _send<T>('POST', config.uri(path), body: body, parseData: parseData);
    });
  }

  /// Send a PATCH request.
  Future<ApiResponse<T>> patch<T>(
    String path, {
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    return _executeWithRefresh(() async {
      return _send<T>('PATCH', config.uri(path), body: body, parseData: parseData);
    });
  }

  /// Send a DELETE request.
  Future<ApiResponse<T>> delete<T>(
    String path, {
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    return _executeWithRefresh(() async {
      return _send<T>('DELETE', config.uri(path), parseData: parseData);
    });
  }

  /// Send a multipart POST request (for avatar upload).
  Future<ApiResponse<T>> postMultipart<T>(
    String path, {
    required String field,
    required List<int> fileBytes,
    required String filename,
    String? contentType,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    return _executeWithRefresh(() async {
      final request = await _client.postUrl(config.uri(path));
      final boundary = 'boundary-${DateTime.now().millisecondsSinceEpoch}';
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      final accessToken = _accessToken;
      if (accessToken != null) {
        request.headers.set('Authorization', 'Bearer $accessToken');
      }

      final body = _buildMultipartBody(field, fileBytes, filename, boundary, contentType);
      request.add(body);
      final response = await request.close();
      return _parseHttpResponse<T>(response, parseData: parseData);
    });
  }

  Future<ApiResponse<T>> _send<T>(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.headers.set('Content-Type', 'application/json');
    final accessToken = _accessToken;
    if (accessToken != null) {
      request.headers.set('Authorization', 'Bearer $accessToken');
    }

    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }

    final response = await request.close();
    return _parseHttpResponse<T>(response, parseData: parseData);
  }

  Future<ApiResponse<T>> _parseHttpResponse<T>(
    HttpClientResponse response, {
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    final bodyStr = await response.transform(utf8.decoder).join();
    try {
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      return ApiResponse<T>.fromHttpResponse(
        response.statusCode,
        body,
        parseData,
        null,
      );
    } catch (_) {
      return ApiResponse<T>(
        ok: false,
        error: BackendError(
          code: 'API_INTERNAL_ERROR',
          message: 'Failed to parse response',
        ),
      );
    }
  }

  /// Execute a request, triggering a token refresh on 401.
  ///
  /// The backend returns [ProblemDetail][RFC 9457] on errors, so we check
  /// both the [BackendError] helpers and the raw status code.
  Future<ApiResponse<T>> _executeWithRefresh<T>(
    Future<ApiResponse<T>> Function() requestFn,
  ) async {
    var response = await requestFn();

    // Check if we need to refresh: 401 Unauthorized triggers token refresh.
    // The backend returns ProblemDetail format (no {ok, error} wrapper), so
    // we check the status code directly rather than relying on BackendError helpers.
    final needsRefresh = response.statusCode == 401;

    if (needsRefresh) {
      final refreshed = await _refreshToken();
      if (refreshed) {
        response = await requestFn();
      } else {
        _accessToken = null;
        if (onRefreshFailed != null) onRefreshFailed!();
      }
    }

    return response;
  }

  /// Token refresh with mutual exclusion.
  Future<bool> _refreshToken() async {
    if (_isRefreshing) {
      // Another request is already refreshing; wait for the result.
      final completer = Completer<bool>();
      _pendingQueue.add(_PendingRequest(completer));
      return completer.future;
    }

    _isRefreshing = true;
    _refreshResult = false;

    try {
      // Read the Refresh Token from Android secure storage
      final readResult = await refreshTokenAdapter.read();
      if (!readResult.result.ok || readResult.result.data == null) {
        _refreshResult = false;
        return false;
      }

      final record = readResult.result.data!;

      // Call the backend refresh endpoint
      // NOTE: endpoint and field names must match the backend AuthResponse format
      // (flat response, camelCase field names, no {ok, data} wrapper)
      final refreshRequest = await _client.postUrl(config.uri('/auth/refresh'));
      refreshRequest.headers.set('Content-Type', 'application/json');
      refreshRequest.add(utf8.encode(jsonEncode({
        'refreshToken': record.refreshToken,
      })));

      final refreshResponse = await refreshRequest.close();
      final bodyStr = await refreshResponse.transform(utf8.decoder).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      // Backend returns a flat AuthResponse, e.g.:
      // {userId, accessToken, refreshToken, expiresIn, email, ...}
      // No {ok, data} wrapper — success is determined by HTTP status code.
      if (refreshResponse.statusCode >= 200 && refreshResponse.statusCode < 300) {
        final newAccessToken = body['accessToken'] as String?;
        final newRefreshToken = body['refreshToken'] as String?;
        final newSessionId = body['userId'] as String?;
        final newExpiresIn = body['expiresIn'] as int? ?? 900;

        if (newAccessToken == null || newRefreshToken == null || newSessionId == null) {
          await refreshTokenAdapter.delete();
          _refreshResult = false;
          return false;
        }

        final expiresAt = DateTime.now()
            .toUtc()
            .add(Duration(seconds: newExpiresIn))
            .toIso8601String();

        // Store new Access Token in memory
        _accessToken = newAccessToken;

        // Store new Refresh Token in Android secure storage
        await refreshTokenAdapter.store(
          refreshToken: newRefreshToken,
          sessionId: newSessionId,
          expiresAt: expiresAt,
        );

        _refreshResult = true;
      } else {
        // Refresh failed — delete the stored Refresh Token
        await refreshTokenAdapter.delete();
        _refreshResult = false;
      }
    } catch (_) {
      // Network error or similar — don't delete the token, just report failure
      _refreshResult = false;
    } finally {
      _isRefreshing = false;

      // Unblock queued requests
      final queue = List<_PendingRequest>.from(_pendingQueue);
      _pendingQueue.clear();
      for (final pending in queue) {
        pending.completer.complete(_refreshResult);
      }
    }

    return _refreshResult;
  }

  List<int> _buildMultipartBody(
    String field,
    List<int> fileBytes,
    String filename,
    String boundary,
    String? contentType,
  ) {
    final header = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="$field"; filename="$filename"\r\n'
      'Content-Type: ${contentType ?? "application/octet-stream"}\r\n\r\n',
    );
    final footer = utf8.encode('\r\n--$boundary--\r\n');
    return [...header, ...fileBytes, ...footer];
  }
}

class _PendingRequest {
  _PendingRequest(this.completer);
  final Completer<bool> completer;
}