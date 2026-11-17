import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dataset_agent_web/api.dart';
import 'package:dataset_agent_web/main.dart';
import 'package:dataset_agent_web/theme.dart';

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

  testWidgets(
    '60-30-10 palette, profiling flow, transform pipeline, and chat evidence work cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Json? transformArgs;
      Json? chatRequest;
      final dataset = {
        'id': 'dataset_sales',
        'name': 'فروش_تست.csv',
        'kind': 'table',
        'rows': 2,
        'columns': [
          {'name': 'city', 'dtype': 'string'},
          {'name': 'amount', 'dtype': 'Int64'},
        ],
      };

      final api = DatasetApi(
        baseUrl: 'http://localhost',
        client: MockClient((request) async {
          dynamic data;
          if (request.url.path == '/capabilities') {
            data = {
              'provider': 'offline',
              'providers': {'offline': true, 'openai': true},
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
                  {'city': 'تهران', 'amount': 120},
                  {'city': 'اصفهان', 'amount': 80},
                ],
              },
            };
          } else if (request.url.path == '/tools/profile_dataset') {
            data = {
              'data': {
                'row_count': 2,
                'column_count': 2,
                'duplicate_rows': 0,
                'columns': {
                  'city': {
                    'dtype': 'string',
                    'missing': 0,
                    'unique': 2,
                    'non_null': 2,
                    'top_values': [
                      {'value': 'تهران', 'count': 1},
                    ],
                  },
                  'amount': {
                    'dtype': 'Int64',
                    'missing': 0,
                    'unique': 2,
                    'non_null': 2,
                    'mean': 100.0,
                    'min': 80,
                    'max': 120,
                    'iqr_outliers': 0,
                  },
                },
              },
            };
          } else if (request.url.path == '/tools/transform_dataset') {
            transformArgs = jsonDecode(request.body)['arguments'] as Json;
            data = {
              'data': {
                'dataset': {
                  ...dataset,
                  'id': 'dataset_transformed',
                  'parent_id': dataset['id'],
                },
              },
            };
          } else if (request.url.path == '/chat') {
            chatRequest = jsonDecode(request.body) as Json;
            data = {'id': 'job_chat_1', 'status': 'queued'};
          } else if (request.url.path == '/jobs/job_chat_1') {
            data = {
              'id': 'job_chat_1',
              'status': 'succeeded',
              'result': {
                'conversation_id': 'conv_1',
                'dataset_ids': ['dataset_transformed'],
                'answer': 'مجموع فروش برابر ۲۰۰ است.',
                'citations': [
                  {'result_id': 'result_1234567890abcd'},
                ],
                'limitations': ['حالت محلی بدون مدل فعال است.'],
                'artifacts': [],
              },
            };
          } else if (request.url.path == '/results/result_1234567890abcd') {
            data = {
              'data': {'total': 200},
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

      // Verify exact 60-30-10 color tokens on theme.
      final theme = Theme.of(tester.element(find.text('داده‌یار')));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF3EEE3));
      expect(theme.colorScheme.primary, const Color(0xFF111111));
      expect(theme.colorScheme.secondary, const Color(0xFFD9541E));
      expect(AppColors.paper, const Color(0xFFF3EEE3));
      expect(AppColors.onyx, const Color(0xFF111111));
      expect(AppColors.vermilion, const Color(0xFFD9541E));

      // Select dataset -> open Profile tab -> run profiling.
      await tester.tap(find.text('فروش_تست.csv'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تحلیل و آمار'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tab 1');

      await tester.tap(find.text('اجرای پروفایل آماری کامل'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'profile');
      expect(find.text('جزئیات هر ستون'), findsOneWidget);
      expect(find.text('میانگین: 100'), findsOneWidget);

      // Jump from profile column card directly into Transform Studio.
      await tester.tap(find.text('فیلتر').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'jump to filter');

      // Switch to strip, enqueue step, and execute transform pipeline.
      await tester.tap(find.text('پاک‌سازی فاصله‌ها'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'switch to strip');
      await tester.tap(find.text('افزودن به صف مراحل'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'enqueue step');
      expect(find.text('صف مراحل آمادهٔ اجرا (1 مرحله)'), findsOneWidget);

      await tester.tap(find.text('اجرای 1 مرحله و ذخیرهٔ نسخهٔ جدید'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'execute transform');
      expect(transformArgs?['steps'], [
        {
          'operation': 'strip',
          'columns': ['city'],
        },
      ]);

      // Open AI Chat tab, tap starter prompt, send, and inspect evidence.
      await tester.tap(find.text('گفت‌وگو با عامل'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('مقادیر خالی و تکراری‌های این جدول را بررسی کن.'),
      );
      await tester.pumpAndSettle();

      // Dismiss the floating save SnackBar before tapping the bottom composer CTA.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ارسال پیام'));
      await tester.pumpAndSettle();

      expect(chatRequest?['dataset_ids'], ['dataset_transformed']);
      expect(find.text('مجموع فروش برابر ۲۰۰ است.'), findsOneWidget);

      await tester.tap(find.text('مشاهدهٔ شاهد result_1234567'));
      await tester.pumpAndSettle();
      expect(find.text('شواهد محاسبه‌شده'), findsOneWidget);
      await tester.tap(find.text('بستن'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mobile 375px layout renders without overflow and opens drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dataset = {
      'id': 'dataset_mobile',
      'name': 'گزارش_فروش_سالانه.csv',
      'kind': 'table',
      'rows': 1,
      'columns': [
        {'name': 'city', 'dtype': 'string'},
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
                {'city': 'تبریز'},
              ],
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

    // Open mobile drawer and pick dataset.
    await tester.tap(find.byTooltip('فهرست مجموعه‌داده‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('گزارش_فروش_سالانه.csv'));
    await tester.pumpAndSettle();

    expect(find.text('تبریز'), findsOneWidget);

    // Verify remaining tabs on 375px mobile have zero overflows.
    await tester.tap(find.text('تحلیل و آمار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تبدیل داده'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('گفت‌وگو با عامل'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Document dataset adapts workflow tabs and runs BM25 search at 768px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final doc = {
      'id': 'dataset_doc',
      'name': 'گزارش_قرارداد.pdf',
      'kind': 'document',
      'chunk_count': 2,
      'characters': 140,
      'warnings': ['OCR is not enabled.'],
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
            'datasets': [doc],
          };
        } else if (request.url.path == '/tools/inspect_dataset') {
          data = {
            'data': {
              'chunks': [
                {
                  'chunk_id': 'c1',
                  'location': 'page:1',
                  'text': 'متن نمونهٔ صفحهٔ اول دربارهٔ بودجه.',
                },
              ],
            },
          };
        } else if (request.url.path == '/tools/search_documents') {
          data = {
            'data': {
              'hits': [
                {
                  'chunk_id': 'c1',
                  'location': 'page:1',
                  'score': 2.45,
                  'text': 'متن نمونهٔ صفحهٔ اول دربارهٔ بودجه.',
                },
              ],
              'matching_chunks': 1,
              'total_chunks': 2,
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

    await tester.tap(find.byTooltip('فهرست مجموعه‌داده‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('گزارش_قرارداد.pdf'));
    await tester.pumpAndSettle();

    expect(find.text('متن و قطعه‌ها'), findsOneWidget);
    expect(find.text('تبدیل داده'), findsNothing);
    expect(find.text('متن نمونهٔ صفحهٔ اول دربارهٔ بودجه.'), findsOneWidget);

    await tester.tap(find.text('جست‌وجو در سند'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'بودجه');
    await tester.tap(find.text('جست‌وجو'));
    await tester.pumpAndSettle();

    expect(find.text('امتیاز: 2.45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
