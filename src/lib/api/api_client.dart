import 'dart:convert';
import 'dart:typed_data';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_nb_net/flutter_net.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_interceptor.dart';
import 'package:oasx/api/config_transfer_models.dart';
import 'package:oasx/config/constants.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/translation/i18n.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/api/github_release_model.dart';

import './home_model.dart';
import './update_info_model.dart';
import 'dio_http_cache/dio_http_cache.dart';

part 'api_client_menu_config.dart';
part 'api_client_config_transfer.dart';
part 'api_client_task_transfer.dart';
part 'api_client_script.dart';
part 'api_client_feedback.dart';
part 'api_client_statistics.dart';
part 'api_client_logs.dart';

class ApiResult<T> {
  ApiResult({this.data, this.error, this.code});

  final T? data;
  final String? error;
  final int? code;

  bool get isSuccess => error == null || error!.isEmpty;

  ApiResult.success(this.data) : error = null, code = null;

  ApiResult.failure(this.error, [this.code]) : data = null;

  factory ApiResult.fromJson(Map<String, dynamic> json) {
    return ApiResult(
      data: json['data'],
      error: json['error'],
      code: json['code'],
    );
  }

  factory ApiResult.fromResponse(dynamic value) {
    if (value is Map<String, dynamic> &&
        (value.containsKey('data') ||
            value.containsKey('error') ||
            value.containsKey('code'))) {
      return ApiResult.fromJson(value);
    }
    return ApiResult.success(value as T?);
  }

  Map<String, dynamic> toJson() {
    return {'data': data, 'error': error, 'code': code};
  }
}

class ApiClient {
  static const String _defaultAddress = 'http://127.0.0.1:22288';
  static final ApiClient _instance = ApiClient._internal();

  factory ApiClient() => _instance;

  late final CacheOptions _cacheOptions;

  ApiClient._internal() {
    final temporaryDirectory =
        GetStorage().read(StorageKey.temporaryDirectory.name) ?? '';
    final cacheStore = kIsWeb
        ? MemCacheStore()
        : FileCacheStore(temporaryDirectory);
    _cacheOptions = CacheOptions(
      store: cacheStore,
      policy: CachePolicy.request,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      cipher: null,
      keyBuilder: CacheOptions.defaultCacheKeyBuilder,
      allowPostMethod: false,
    );
    NetOptions.instance
        .setConnectTimeout(const Duration(seconds: 3))
        .enableLogger(false)
        .addInterceptor(DioCacheInterceptor(options: _cacheOptions))
        .addInterceptor(ApiInterceptor())
        .create();
    setAddress(_defaultAddress);
  }

  String address = _defaultAddress;

  bool get hasConfiguredBackendAddress => address.trim().isNotEmpty;

  void setAddress(String address) {
    final normalized = address.trim();
    this.address = normalized;
    NetOptions.instance.dio.options.baseUrl = normalized.isEmpty
        ? _defaultAddress
        : normalized;
  }

  void resetAddress() {
    setAddress(_defaultAddress);
  }

  void clearAddress() {
    address = '';
    NetOptions.instance.dio.options.baseUrl = _defaultAddress;
  }

  Future<ApiResult<T>> request<T>(
    Future<Result<dynamic>> Function() apiFn, {
    void Function(String msg, int code)? onError,
  }) async {
    try {
      final res = await apiFn();
      return res.when(
        success: (data) => ApiResult.fromResponse(data),
        failure: (msg, code) {
          onError?.call(msg, code);
          return ApiResult.failure(msg, code);
        },
      );
    } catch (e) {
      printError(info: '$e');
      return ApiResult.failure(e.toString());
    }
  }

  Future<bool> testAddress() async {
    final res = await request(() => get('/test'), onError: (msg, code) {});
    return res.isSuccess && res.data == 'success';
  }

  Future<bool> killServer() async {
    final res = await request(
      () => get('/home/kill_server'),
      onError: (msg, code) {},
    );
    return res.isSuccess && res.data == 'success';
  }

  Future<bool> notifyTest(String setting, String title, String content) async {
    final res = await request(
      () => post(
        '/home/notify_test',
        queryParameters: {
          'setting': setting,
          'title': title,
          'content': content,
        },
      ),
    );
    if (res.isSuccess && res.data == true) {
      Get.snackbar(I18n.notifyTestSuccess.tr, '');
      return true;
    }
    Get.snackbar(I18n.notifyTestFailed.tr, res.data.toString());
    return false;
  }

  Future<GithubReleaseModel> getGithubRelease() async {
    final res = await getGithubReleaseResult();
    return res.isSuccess && res.data != null ? res.data! : GithubReleaseModel();
  }

  /// 拉取本仓库最新 release。
  ///
  /// 注意：**这里不能用 `decodeType`**。`ApiInterceptor.onResponse` 会把所有
  /// 响应统一包装成 `{code, error, data}`，而 `flutter_nb_net` 的 `decodeType`
  /// 是在 dio 拦截器跑完之后才拿 `response.data` 去解析的 —— 于是
  /// `GithubReleaseModel.fromJson` 收到的是外层包装 map，取不到 `tag_name`
  /// / `html_url`，`isValid` 恒为 false，检查更新必然失败。
  ///
  /// 正确做法与 [getUpdateInfo] 一致：不传 decodeType，先取出包装层的 `data`，
  /// 再用 `fromJson` 手动解析。
  Future<ApiResult<GithubReleaseModel>> getGithubReleaseResult() async {
    final res = await request<dynamic>(() => get(updateUrlGithub));
    final raw = res.data;
    if (raw is Map<String, dynamic>) {
      return ApiResult<GithubReleaseModel>.success(
        GithubReleaseModel.fromJson(raw),
      );
    }
    final message = (res.error ?? '').trim();
    return ApiResult<GithubReleaseModel>.failure(
      message.isEmpty ? 'unexpected release payload' : message,
      res.code,
    );
  }

  Future<ReadmeGithubModel> getGithubReadme() async {
    // 同 getGithubReleaseResult：不能用 decodeType，否则拿到的是
    // ApiInterceptor 包装后的外层 map，取不到 `content` 字段。
    final res = await request<dynamic>(
      () => get(
        readmeUrlGithub,
        options: buildCacheOptions(
          const Duration(days: 7),
          options: Options(extra: {'cache': true}),
        ),
      ),
    );
    final raw = res.data;
    if (raw is Map<String, dynamic>) {
      return ReadmeGithubModel.fromJson(raw);
    }
    return ReadmeGithubModel();
  }

  Future<UpdateInfoModel> getUpdateInfo() async {
    final res = await request(() => get('/home/update_info'));
    return res.isSuccess
        ? UpdateInfoModel.fromJson(res.data)
        : UpdateInfoModel();
  }

  Future<String?> getExecuteUpdate() async {
    final res = await request(() => get('/home/execute_update'));
    if (res.isSuccess) {
      showDialog('Update', res.data.toString());
      return res.data;
    }
    return res.data;
  }

  Future<bool> putChineseTranslate() async {
    final res = await request(
      () => put('/home/chinese_translate', data: Messages().all_cn_translate),
    );
    return res.isSuccess && res.data == true;
  }

  Future<Map<String, Map<String, String>>> getAdditionalTranslate() async {
    final res = await request(() => get('/home/additional_translate'));
    final result = <String, Map<String, String>>{};
    if (res.isSuccess) {
      result['zh_CN'] = (res.data['zh-CN'] as Map).cast<String, String>();
      result['en_US'] = (res.data['en-US'] as Map).cast<String, String>();
    }
    return result;
  }
}
