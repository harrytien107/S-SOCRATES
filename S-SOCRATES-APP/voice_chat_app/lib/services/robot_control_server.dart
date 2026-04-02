import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef RobotMicActionHandler = Future<void> Function(String action);
typedef RobotCommandHandler =
    Future<void> Function(String text, String emotion);
typedef RobotStateSnapshot = Map<String, dynamic> Function();

class RobotControlServer {
  RobotControlServer({
    required this.onMicAction,
    required this.onCommand,
    required this.getSnapshot,
    this.port = 9000,
  });

  final RobotMicActionHandler onMicAction;
  final RobotCommandHandler onCommand;
  final RobotStateSnapshot getSnapshot;
  final int port;

  HttpServer? _server;

  Future<void> start() async {
    if (_server != null) return;

    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    debugPrint('RobotControlServer listening on 0.0.0.0:$port');
    unawaited(_server!.forEach(_handleRequest));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
      debugPrint('RobotControlServer stopped');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _writeJson(request.response, HttpStatus.ok, {
          'status': 'ok',
          'server': 'robot-control',
          ...getSnapshot(),
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/status') {
        await _writeJson(request.response, HttpStatus.ok, getSnapshot());
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/mic') {
        final payload = await _readJson(request);
        final action = (payload['action'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (!{'start', 'stop', 'cancel'}.contains(action)) {
          await _writeJson(request.response, HttpStatus.badRequest, {
            'error': 'Invalid mic action. Use start, stop, or cancel.',
          });
          return;
        }

        unawaited(onMicAction(action));
        await _writeJson(request.response, HttpStatus.ok, {
          'status': 'accepted',
          'action': action,
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/command') {
        final payload = await _readJson(request);
        final text = (payload['text'] ?? '').toString();
        final emotion = (payload['emotion'] ?? 'neutral')
            .toString()
            .trim()
            .toLowerCase();
        if (emotion.isEmpty) {
          await _writeJson(request.response, HttpStatus.badRequest, {
            'error': 'emotion is required',
          });
          return;
        }

        unawaited(onCommand(text, emotion));
        await _writeJson(request.response, HttpStatus.ok, {
          'status': 'accepted',
          'emotion': emotion,
        });
        return;
      }

      await _writeJson(request.response, HttpStatus.notFound, {
        'error': 'Not found',
        'path': request.uri.path,
      });
    } catch (e, st) {
      debugPrint('RobotControlServer error: $e\n$st');
      await _writeJson(request.response, HttpStatus.internalServerError, {
        'error': e.toString(),
      });
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = statusCode;
    response.write(jsonEncode(body));
    await response.close();
  }
}
