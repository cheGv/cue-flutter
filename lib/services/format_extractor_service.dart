// lib/services/format_extractor_service.dart
//
// Phase C — Cue Format Adaptation, Component One.
// Uploads sample reports to Supabase storage, then calls the proxy's
// /format-extract and /format-confirm endpoints. Per CLAUDE.md §13 the client
// sends only file references (signed URLs) + context — never a prompt. The
// http.Client, tokenProvider, and SupabaseClient are injectable so the service
// is unit-testable without live network / storage.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/format_template.dart';

class FormatExtractorService {
  FormatExtractorService({
    SupabaseClient? supabase,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
    Future<String> Function(String storagePath)? signedUrlProvider,
    String baseUrl = _defaultBase,
  })  : _injectedSupabase = supabase,
        _client = client ?? http.Client(),
        _tokenProvider = tokenProvider ?? _defaultToken,
        _signedUrlProvider = signedUrlProvider,
        _base = baseUrl;

  static const _defaultBase = 'https://cue-ai-proxy.onrender.com';
  static const _bucket = 'format_template_sources';
  // Extraction reads multiple documents through an LLM — allow a long ceiling.
  static const _extractTimeout = Duration(seconds: 90);
  static const _confirmTimeout = Duration(seconds: 15);
  static const _signedUrlTtl = 3600; // seconds

  // Resolved lazily — only storage ops (upload, default signer) touch it, so
  // tests that inject http + tokenProvider + signedUrlProvider never trigger
  // Supabase.instance (which would assert-fail before app init).
  final SupabaseClient? _injectedSupabase;
  SupabaseClient get _supabase => _injectedSupabase ?? Supabase.instance.client;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;
  final Future<String> Function(String storagePath)? _signedUrlProvider;
  final String _base;

  static Future<String?> _defaultToken() async =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Future<String> _defaultSignedUrl(String storagePath) =>
      _supabase.storage.from(_bucket).createSignedUrl(storagePath, _signedUrlTtl);

  /// Upload a source document to {uid}/{templateId}/{filename}. Returns the
  /// SourceDocument descriptor (storage path + type) to persist on the row.
  Future<SourceDocument> uploadSourceDocument({
    required Uint8List bytes,
    required String filename,
    required String fileType, // 'pdf' | 'docx'
    required String templateId,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw FormatExtractorException('You are not signed in.');
    final path = '$uid/$templateId/$filename';
    final contentType = fileType == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return SourceDocument(
      filename: filename,
      storagePath: path,
      fileType: fileType,
      uploadedAt: DateTime.now(),
    );
  }

  /// Sign each source doc, POST to /format-extract, return the parsed template
  /// + warnings.
  Future<FormatExtractionResult> requestExtraction({
    required String templateId,
    required List<SourceDocument> sourceDocuments,
  }) async {
    final signer = _signedUrlProvider ?? _defaultSignedUrl;
    final files = <Map<String, dynamic>>[];
    for (final d in sourceDocuments) {
      final signed = await signer(d.storagePath);
      files.add({
        'filename': d.filename,
        'file_type': d.fileType,
        'storage_path': d.storagePath,
        'signed_url': signed,
      });
    }

    final token = await _tokenProvider();
    if (token == null) throw FormatExtractorException('You are not signed in.');

    final resp = await _client
        .post(
          Uri.parse('$_base/format-extract'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'template_id': templateId, 'files': files}),
        )
        .timeout(_extractTimeout);

    if (resp.statusCode != 200) {
      throw FormatExtractorException(_errorMessage(resp));
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return FormatExtractionResult(
      template: ExtractedTemplate.fromJson(
        body['extracted_template'] is Map
            ? Map<String, dynamic>.from(body['extracted_template'] as Map)
            : const {},
      ),
      warnings: (body['extraction_warnings'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  /// Lock the (possibly edited) template via /format-confirm. Returns the
  /// server-stamped confirmed_at on success.
  Future<DateTime?> confirmTemplate({
    required String templateId,
    required ExtractedTemplate confirmedTemplate,
  }) async {
    final token = await _tokenProvider();
    if (token == null) throw FormatExtractorException('You are not signed in.');

    final resp = await _client
        .post(
          Uri.parse('$_base/format-confirm'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'template_id': templateId,
            'confirmed_template': confirmedTemplate.toJson(),
          }),
        )
        .timeout(_confirmTimeout);

    if (resp.statusCode != 200) {
      throw FormatExtractorException(_errorMessage(resp));
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final ts = body['confirmed_at'] as String?;
    return ts == null ? null : DateTime.tryParse(ts);
  }

  String _errorMessage(http.Response resp) {
    try {
      final b = jsonDecode(resp.body) as Map<String, dynamic>;
      return (b['error'] as String?) ?? 'Request did not complete (${resp.statusCode}).';
    } catch (_) {
      return 'Request did not complete (${resp.statusCode}).';
    }
  }
}

class FormatExtractionResult {
  final ExtractedTemplate template;
  final List<String> warnings;
  const FormatExtractionResult({required this.template, required this.warnings});
}

class FormatExtractorException implements Exception {
  final String message;
  FormatExtractorException(this.message);
  @override
  String toString() => message;
}
