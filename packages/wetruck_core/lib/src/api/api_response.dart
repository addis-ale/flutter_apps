/// Typed envelope for API responses. Mirrors `ApiResponse<T>` from
/// `shipper/src/lib/api-client.ts`. Callers branch on [isSuccess] / [error]
/// or destructure via pattern matching.
class ApiResponse<T> {
  const ApiResponse._({
    required this.status,
    this.data,
    this.error,
    this.errorData,
  });

  /// HTTP status. `0` means the request never reached the server
  /// (offline, DNS, timeout).
  final int status;

  final T? data;

  /// Human-readable error message, ready to show in UI.
  final String? error;

  /// Raw decoded error body — useful for field-level form errors etc.
  final Object? errorData;

  bool get isSuccess => error == null && status >= 200 && status < 300;

  factory ApiResponse.success(T data, int status) =>
      ApiResponse._(data: data, status: status);

  factory ApiResponse.failure({
    required String error,
    required int status,
    Object? errorData,
  }) =>
      ApiResponse._(error: error, status: status, errorData: errorData);

  factory ApiResponse.networkError() => const ApiResponse._(
        status: 0,
        error:
            "We couldn't reach the server. Please check your internet connection and try again.",
      );
}
