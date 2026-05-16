// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_cloudflare_stream_suppression.dart';

const _tracerName = 'dartastic_otel_libs_cloudflare_stream';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class CloudflareStreamResult {
  const CloudflareStreamResult({
    this.videoUid,
    this.liveInputUid,
    this.minutesStored,
    this.minutesDelivered,
    this.status,
    this.simulcastTargets,
    this.statusCode,
  });

  final String? videoUid;
  final String? liveInputUid;

  /// Cloudflare Stream bills storage and delivery as distinct
  /// minute pools — never collapse them.
  final int? minutesStored;
  final int? minutesDelivered;

  /// `pendingupload`, `queued`, `inprogress`, `ready`, `error`.
  final String? status;

  /// Number of Stream Connect simulcast targets (RTMP/SRT push-outs).
  final int? simulcastTargets;
  final int? statusCode;
}

class CloudflareStreamCallResult<T> {
  const CloudflareStreamCallResult({required this.value, this.result});
  final T value;
  final CloudflareStreamResult? result;
}

/// Wraps a Cloudflare Stream API call in a CLIENT span. [operation] is
/// the route key like `stream.upload.tus`, `stream.copy`,
/// `stream.live_inputs.create`, `stream.subtitles.generate`,
/// `stream.webhook.create`.
Future<T> tracedCloudflareStream<T>({
  required String operation,
  required Future<CloudflareStreamCallResult<T>> Function() invoke,
  String? accountId,
}) async {
  if (cloudflareStreamInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'cloudflare_stream',
    'rpc.method': operation,
  };
  if (accountId != null) m['cloudflare.account.id'] = accountId;

  final span = _tracer().startSpan(
    'cloudflare_stream $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.videoUid != null) {
        extras.add(OTel.attributeString(
          'cloudflare_stream.video.uid',
          r.result!.videoUid!,
        ));
      }
      if (r.result!.liveInputUid != null) {
        extras.add(OTel.attributeString(
          'cloudflare_stream.live_input.uid',
          r.result!.liveInputUid!,
        ));
      }
      if (r.result!.minutesStored != null) {
        extras.add(OTel.attributeInt(
          'cloudflare_stream.minutes_stored',
          r.result!.minutesStored!,
        ));
      }
      if (r.result!.minutesDelivered != null) {
        extras.add(OTel.attributeInt(
          'cloudflare_stream.minutes_delivered',
          r.result!.minutesDelivered!,
        ));
      }
      if (r.result!.status != null) {
        extras.add(OTel.attributeString(
          'cloudflare_stream.status',
          r.result!.status!,
        ));
        if (r.result!.status == 'error') {
          span.setStatus(
            SpanStatusCode.Error,
            'Cloudflare Stream status=error',
          );
        }
      }
      if (r.result!.simulcastTargets != null) {
        extras.add(OTel.attributeInt(
          'cloudflare_stream.simulcast_targets',
          r.result!.simulcastTargets!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Cloudflare Stream HTTP ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
