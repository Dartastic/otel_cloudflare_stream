// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_cloudflare_stream/otel_cloudflare_stream.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_cloudflare_stream-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('VOD ready records stored + delivered minutes split', () async {
    await tracedCloudflareStream<String>(
      operation: 'stream.upload.tus',
      accountId: 'acct-1',
      invoke: () async => const CloudflareStreamCallResult(
        value: 'ok',
        result: CloudflareStreamResult(
          videoUid: 'vid-1',
          minutesStored: 120,
          minutesDelivered: 9600,
          status: 'ready',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(
      spans.findSpanByName('cloudflare_stream stream.upload.tus')!,
    );
    expect(a['cloudflare.account.id'], 'acct-1');
    expect(a['cloudflare_stream.minutes_stored'], 120);
    expect(a['cloudflare_stream.minutes_delivered'], 9600);
    expect(a['cloudflare_stream.status'], 'ready');
  });

  test('Live input with simulcast records targets', () async {
    await tracedCloudflareStream<String>(
      operation: 'stream.live_inputs.create',
      invoke: () async => const CloudflareStreamCallResult(
        value: 'ok',
        result: CloudflareStreamResult(
          liveInputUid: 'live-1',
          simulcastTargets: 3,
        ),
      ),
    );
    expect(
      attrsOf(spans.findSpanByName(
        'cloudflare_stream stream.live_inputs.create',
      )!)['cloudflare_stream.simulcast_targets'],
      3,
    );
  });

  test('error status sets span error', () async {
    await tracedCloudflareStream<String>(
      operation: 'stream.upload.tus',
      invoke: () async => const CloudflareStreamCallResult(
        value: 'ok',
        result: CloudflareStreamResult(status: 'error'),
      ),
    );
    expect(
      spans.findSpanByName('cloudflare_stream stream.upload.tus')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutCloudflareStreamInstrumentationAsync(() async {
      await tracedCloudflareStream<String>(
        operation: 'stream.list',
        invoke: () async => const CloudflareStreamCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('cloudflare_stream '), isEmpty);
  });
}
