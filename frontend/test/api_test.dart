import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dataset_agent_web/api.dart';

void main() {
  test('tool requests retain authorization and Persian JSON', () async {
    final api = DatasetApi(
      baseUrl: 'http://localhost:8000/',
      token: 'project-token',
      client: MockClient((request) async {
        expect(request.url.path, '/tools/edit_dataset');
        expect(request.headers['Authorization'], 'Bearer project-token');
        expect(
          jsonDecode(request.body)['arguments']['cells'][0]['value'],
          'تهران',
        );
        return http.Response('{"status":"ok"}', 200);
      }),
    );
    await api.tool('edit_dataset', {
      'cells': [
        {'row_index': 0, 'column': 'city', 'value': 'تهران'},
      ],
    });
    api.close();
  });
  test('polling returns success and surfaces job failure', () async {
    var calls = 0;
    final api = DatasetApi(
      baseUrl: 'http://localhost',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            ++calls == 1
                ? {'status': 'running'}
                : {
                    'status': 'succeeded',
                    'result': {'answer': 'آماده'},
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    expect(
      (await api.waitForJob('job_1', interval: Duration.zero))['answer'],
      'آماده',
    );
    expect(calls, 2);
    api.close();
    final failed = DatasetApi(
      baseUrl: 'http://localhost',
      client: MockClient(
        (_) async => http.Response(
          '{"status":"failed","error":{"message":"invalid edit"}}',
          200,
        ),
      ),
    );
    await expectLater(failed.waitForJob('job_2'), throwsA(isA<ApiException>()));
    failed.close();
  });
  test('downloads do not forward credentials to external origins', () async {
    final api = DatasetApi(baseUrl: 'http://localhost', token: 'secret');
    await expectLater(
      api.download('//evil.example/stolen'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.download('https://evil.example/stolen'),
      throwsA(isA<ApiException>()),
    );
    api.close();
  });
}
