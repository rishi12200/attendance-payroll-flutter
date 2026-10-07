import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/app_exception.dart';
import '../domain/branch.dart';

abstract interface class BranchRepository {
  Future<List<Branch>> listBranches({String status = 'active'});
  Future<Branch> getBranch(String id);
  Future<Branch> createBranch(Map<String, Object?> fields);
  Future<Branch> updateBranch(String id, Map<String, Object?> fields);
  Future<Branch> deactivate(String id);
  Future<Branch> reactivate(String id);
}

class ApiBranchRepository implements BranchRepository {
  const ApiBranchRepository(this._api);

  final ApiTransport _api;

  @override
  Future<List<Branch>> listBranches({String status = 'active'}) =>
      _withApiErrors(() async {
        final result = await _api.getJson(
          '/branches',
          queryParameters: {'status': status},
        );
        if (result is! List) _invalidResponse();
        return result
            .map((item) => Branch.fromJson(_asJsonMap(item)))
            .toList(growable: false);
      });

  @override
  Future<Branch> getBranch(String id) => _withApiErrors(
    () async => Branch.fromJson(
      _asJsonMap(await _api.getJson('/branches/${Uri.encodeComponent(id)}')),
    ),
  );

  @override
  Future<Branch> createBranch(Map<String, Object?> fields) =>
      _withApiErrors(
        () async => Branch.fromJson(
          _asJsonMap(await _api.postJson('/branches', data: fields)),
        ),
      );

  @override
  Future<Branch> updateBranch(String id, Map<String, Object?> fields) =>
      _withApiErrors(
        () async => Branch.fromJson(
          _asJsonMap(
            await _api.patchJson(
              '/branches/${Uri.encodeComponent(id)}',
              data: fields,
            ),
          ),
        ),
      );

  @override
  Future<Branch> deactivate(String id) => _withApiErrors(
    () async => Branch.fromJson(
      _asJsonMap(
        await _api.postJson(
          '/branches/${Uri.encodeComponent(id)}/deactivate',
        ),
      ),
    ),
  );

  @override
  Future<Branch> reactivate(String id) => _withApiErrors(
    () async => Branch.fromJson(
      _asJsonMap(
        await _api.postJson(
          '/branches/${Uri.encodeComponent(id)}/reactivate',
        ),
      ),
    ),
  );
}

Map<String, dynamic> _asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  _invalidResponse();
}

Never _invalidResponse() => throw const AppException(
  code: 'INVALID_RESPONSE',
  message: 'The server returned an invalid branch response.',
  details: {},
);

Future<T> _withApiErrors<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw AppException.fromDioException(error);
  }
}
