import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One queued HTTP response for FakeBackendAdapter.
class FakeBackendResponse {
  const FakeBackendResponse({this.status = 200, required this.body});

  final int status;
  final Object body;

  ResponseBody toResponseBody() {
    final bytes = body is String
        ? utf8.encode(body as String)
        : utf8.encode(jsonEncode(body));
    return ResponseBody.fromString(
      utf8.decode(bytes),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// A captured request through the fake adapter.
class CapturedBackendRequest {
  const CapturedBackendRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Object? body;

  String? get headerAuthorization => headers['Authorization'] as String?;
  String? get headerIdempotencyKey => headers['Idempotency-Key'] as String?;
}

/// In-memory dio HttpClientAdapter: no sockets, no real backend.
class FakeBackendAdapter implements HttpClientAdapter {
  FakeBackendAdapter({List<FakeBackendResponse>? queue, this.handler})
    : queue = List<FakeBackendResponse>.of(queue ?? const []);

  /// Responses consumed in order. Tests may keep appending to it.
  final List<FakeBackendResponse> queue;

  /// Optional per-request responder: return FakeBackendResponse or throw an
  /// Exception (e.g. FakeConnectionError) to simulate transport failures.
  Object Function(RequestOptions request)? handler;

  final List<CapturedBackendRequest> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data;
    final captured = CapturedBackendRequest(
      method: options.method,
      path: options.path,
      headers: Map<String, dynamic>.from(options.headers),
      body: body,
    );
    requests.add(captured);
    final dynamic response = handler != null
        ? handler!(options)
        : queue.isEmpty
        ? const FakeBackendResponse(status: 500, body: '{"broken": true}')
        : queue.removeAt(0);
    if (response is FakeBackendResponse) {
      return response.toResponseBody();
    }
    if (response is Exception) {
      throw response;
    }
    throw StateError(
      'FakeBackendAdapter handler must return FakeBackendResponse or Exception.',
    );
  }
}

/// Convenience: throws a connection error from the adapter.
class FakeConnectionError implements Exception {
  const FakeConnectionError();
}
