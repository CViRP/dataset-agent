import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dataset_agent_web/api.dart';
import 'package:dataset_agent_web/main.dart';

void main() {
  testWidgets(
    'Persian workspace loads datasets and sends positional cell edits',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Json? edit;
      final dataset = {
        'id': 'dataset_original',
        'name': 'فروش.csv',
        'kind': 'table',
        'rows': 1,
        'columns': [
          {'name': 'city', 'dtype': 'str'},
        ],
      };
      final api = DatasetApi(
        baseUrl: 'http://localhost',
        client: MockClient((request) async {
          dynamic data;
          if (request.url.path == '/capabilities') {
            data = {
              'provider': 'offline',
              'providers': {'offline': true},
              'limits': {'upload_mb': 25},
            };
          } else if (request.url.path == '/datasets') {
            data = {
              'datasets': [dataset],
            };
          } else if (request.url.path == '/tools/query_table') {
            data = {
              'data': {
                'rows': [
                  {'city': 'شیراز'},
                ],
              },
            };
          } else if (request.url.path == '/tools/edit_dataset') {
            edit = jsonDecode(request.body)['arguments'] as Json;
            data = {
              'data': {
                'dataset': {
                  ...dataset,
                  'id': 'dataset_child',
                  'parent_id': dataset['id'],
                },
              },
            };
          } else {
            return http.Response('{}', 404);
          }
          return http.Response(
            utf8.decode(utf8.encode(jsonEncode(data))),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(DatasetApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('داده‌یار'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('داده‌یار'))),
        TextDirection.rtl,
      );
      await tester.tap(find.text('فروش.csv'));
      await tester.pumpAndSettle();
      expect(find.text('شیراز'), findsOneWidget);
      await tester.tap(find.text('شیراز'));
      // The operation progress indicator animates while its edit dialog is open.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField).last, '"تهران"');
      await tester.tap(find.text('ذخیرهٔ نسخهٔ جدید'));
      await tester.pumpAndSettle();
      expect(edit?['dataset_id'], 'dataset_original');
      expect(edit?['cells'], [
        {'row_index': 0, 'column': 'city', 'value': 'تهران'},
      ]);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
