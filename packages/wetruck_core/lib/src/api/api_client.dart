import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../auth/token_storage.dart';
import 'api_config.dart';
import 'api_response.dart';

typedef LocaleResolver = String Function();

class BinaryResponse {
  const BinaryResponse({
    required this.bytes,
    required this.headers,
    required this.status,
  });
  final Uint8List bytes;
  final Map<String, List<String>> headers;
  final int status;

  /// Header lookup that's case-insensitive — Dio lowercases incoming
  /// header names but servers vary, so we play it safe.
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }
}

/// Direct port of `shipper/src/lib/api-client.ts`.
///
///   - Adds `Authorization: Bearer <token>` from [TokenStorage] when present.
///   - Adds `Accept-Language` from [localeResolver] (defaults to `en`).
///   - On `401` (except `/auth/login` and `/auth/refresh`), calls `POST
///     /auth/refresh` once. If that succeeds, retries the original request.
///     If it fails, calls [onAuthFailure] and surfaces the error.
///   - Uses [CookieJar] so the httpOnly refresh cookie is sent back on
///     `/auth/refresh` (the Next/Capacitor build relied on `credentials:
///     "include"` for this).
///   - Network errors collapse to [ApiResponse.networkError].
class ApiClient {
  ApiClient({
    required ApiConfig config,
    required TokenStorage tokenStorage,
    required FutureOr<void> Function() onAuthFailure,
    LocaleResolver? localeResolver,
    Dio? dio,
    CookieJar? cookieJar,
  })  : _tokenStorage = tokenStorage,
        _onAuthFailure = onAuthFailure,
        _localeResolver = localeResolver ?? (() => 'en'),
        _cookieJar = cookieJar ?? CookieJar(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.baseUrl,
                contentType: 'application/json',
                responseType: ResponseType.json,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                // Don't throw on non-2xx — we map them into ApiResponse.
                validateStatus: (_) => true,
              ),
            ) {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  final TokenStorage _tokenStorage;
  final FutureOr<void> Function() _onAuthFailure;
  final LocaleResolver _localeResolver;
  final Dio _dio;
  final CookieJar _cookieJar;

  /// Drop every cookie the jar has accumulated. Call on logout so the
  /// refresh cookie can't be replayed by the next signed-in user.
  Future<void> clearCookies() => _cookieJar.deleteAll();

  /// Binary GET. Used by the captcha service, which needs to extract a
  /// custom response header (`X-Captcha-Id`) alongside the image bytes.
  /// Returns null on any failure — captcha's UI handles re-prompting.
  Future<BinaryResponse?> getBytes(
    String endpoint, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final normalizedPath = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    final mergedHeaders = <String, String>{
      'Accept-Language': _localeResolver(),
      ...?headers,
    };
    try {
      final response = await _dio.get<List<int>>(
        normalizedPath,
        options: Options(
          headers: mergedHeaders,
          responseType: ResponseType.bytes,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return BinaryResponse(
        bytes: Uint8List.fromList(bytes),
        headers: response.headers.map,
        status: status,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads raw bytes from an absolute URL — e.g. a presigned S3 link
  /// returned by the document endpoints. No `Authorization` header is
  /// attached: presigned URLs carry their own credentials in the query
  /// string, and adding ours can break the signature on some buckets.
  /// Returns null on any failure so callers can show a friendly fallback.
  Future<Uint8List?> fetchUrlBytes(String url, {Duration? timeout}) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // Absolute URL → Dio ignores baseUrl. Strip our JSON content-type.
          headers: const <String, dynamic>{},
          contentType: null,
          sendTimeout: timeout,
          receiveTimeout: timeout ?? const Duration(seconds: 60),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _request<T>(
        endpoint: endpoint,
        method: 'GET',
        query: query,
        headers: headers,
      );

  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _request<T>(
        endpoint: endpoint,
        method: 'POST',
        body: body,
        query: query,
        headers: headers,
      );

  /// Multipart POST for file uploads. Builds a Dio `FormData` from the
  /// `fields` map and the (single) file. Dio sets `Content-Type:
  /// multipart/form-data; boundary=...` automatically when it sees a
  /// `FormData` body, overriding our JSON default in [BaseOptions]. The
  /// backend validates uploads by filename extension (see
  /// `validate_extension_from_filename`), so we don't bother attaching a
  /// MIME type — Dio infers a reasonable one from the filename.
  Future<ApiResponse<T>> postMultipart<T>(
    String endpoint, {
    required Map<String, String> fields,
    required Uint8List fileBytes,
    required String fileName,
    String fileFieldName = 'file',
  }) =>
      _multipart<T>(
        endpoint: endpoint,
        method: 'POST',
        fields: fields,
        fileBytes: fileBytes,
        fileName: fileName,
        fileFieldName: fileFieldName,
      );

  /// Multipart PATCH — used to replace an uploaded file in place (e.g. swap
  /// the file of an existing ship document while keeping its row/type).
  Future<ApiResponse<T>> patchMultipart<T>(
    String endpoint, {
    required Map<String, String> fields,
    required Uint8List fileBytes,
    required String fileName,
    String fileFieldName = 'file',
  }) =>
      _multipart<T>(
        endpoint: endpoint,
        method: 'PATCH',
        fields: fields,
        fileBytes: fileBytes,
        fileName: fileName,
        fileFieldName: fileFieldName,
      );

  Future<ApiResponse<T>> _multipart<T>({
    required String endpoint,
    required String method,
    required Map<String, String> fields,
    required Uint8List fileBytes,
    required String fileName,
    String fileFieldName = 'file',
  }) async {
    final form = FormData.fromMap({
      ...fields,
      fileFieldName: MultipartFile.fromBytes(fileBytes, filename: fileName),
    });
    return _request<T>(
      endpoint: endpoint,
      method: method,
      body: form,
    );
  }

  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _request<T>(
        endpoint: endpoint,
        method: 'PUT',
        body: body,
        query: query,
        headers: headers,
      );

  Future<ApiResponse<T>> patch<T>(
    String endpoint, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _request<T>(
        endpoint: endpoint,
        method: 'PATCH',
        body: body,
        query: query,
        headers: headers,
      );

  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _request<T>(
        endpoint: endpoint,
        method: 'DELETE',
        body: body,
        query: query,
        headers: headers,
      );

  Future<ApiResponse<T>> _request<T>({
    required String endpoint,
    required String method,
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    final normalizedPath = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    final mergedHeaders = <String, String>{
      'Accept-Language': _localeResolver(),
      ...?headers,
    };

    final token = await _tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      mergedHeaders['Authorization'] = 'Bearer $token';
    }

    try {
      final response = await _dio.request<dynamic>(
        normalizedPath,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: mergedHeaders,
        ),
      );

      // Expired access token — try once, then either retry or sign out.
      if (response.statusCode == 401 && !isRetry) {
        final isAuthEndpoint =
            normalizedPath == '/auth/login' ||
                normalizedPath == '/auth/refresh';

        if (!isAuthEndpoint) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            return _request<T>(
              endpoint: endpoint,
              method: method,
              body: body,
              query: query,
              headers: headers,
              isRetry: true,
            );
          }
          await _onAuthFailure();
        }
      }

      final status = response.statusCode ?? 0;
      final payload = response.data;

      if (status < 200 || status >= 300) {
        return ApiResponse<T>.failure(
          status: status,
          error: _extractErrorMessage(payload),
          errorData: payload,
        );
      }

      return ApiResponse<T>.success(payload as T, status);
    } on DioException catch (_) {
      return ApiResponse<T>.networkError();
    } catch (_) {
      return ApiResponse<T>.networkError();
    }
  }

  Future<bool> _tryRefresh() async {
    try {
      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        options: Options(validateStatus: (_) => true),
      );
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        return false;
      }
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final access = data['access_token'];
        final refresh = data['refresh_token'];
        if (access is String && access.isNotEmpty) {
          await _tokenStorage.writeAccessToken(access);
        }
        if (refresh is String && refresh.isNotEmpty) {
          await _tokenStorage.writeRefreshToken(refresh);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mirrors the message extraction in `api-client.ts:120-140` so the UI
  /// strings stay identical to what users already see in the Next.js app.
  String _extractErrorMessage(Object? payload) {
    if (payload is Map<String, dynamic>) {
      final detail = payload['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List) {
        final parts = detail
            .whereType<Map<String, dynamic>>()
            .map((d) => (d['msg'] ?? d['message'])?.toString())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
      final message = payload['message'];
      if (message is String && message.isNotEmpty) return message;
      final error = payload['error'];
      if (error is String && error.isNotEmpty) return error;
    }
    return 'Request failed';
  }
}
