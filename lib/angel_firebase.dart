import 'dart:async';
import 'package:angel_framework/angel_framework.dart';
import 'package:firebase/firebase_io.dart';

/// A simple Angel service that manipulates a Firebase collection.
class FirebaseService extends Service {
  Uri _baseUri;

  /// A [FirebaseClient] instance that will be used to query the remote database.
  final FirebaseClient client;

  /// The URL of the database to manipulate. Ex. `https://[PROJECT_ID].firebaseio.com`
  final String databaseUrl;

  /// If set to `true` (default), then parameters from the query string (params['query'] in service methods) are forwarded to Firebase.
  ///
  /// This setting will be disregarded if a service method is called from the server-side. Thus, the server is always free to query Firebase
  /// however it likes.
  final bool allowQuery;

  /// If set to `true` (default: `false`), then clients will be permitted to delete all items in the collection.
  /// Don't activate this unless you know what you are doing...
  final bool allowRemoveAll;

  FirebaseService(this.client, this.databaseUrl,
      {this.allowQuery: true, this.allowRemoveAll: false}) {
    _baseUri = Uri.parse(databaseUrl);
  }

  Uri _applyParams(Map params, Uri base) {
    bool disallow = allowQuery == false ||
        params == null ||
        !params.containsKey('query') ||
        params['query'] is! Map;
    if (disallow && params?.containsKey('provider') == true) return base;
    var safeQuery = {};

    if (params?.containsKey('query') == true) {
      params['query'].forEach((k, v) {
        if (k is String && !Service.SPECIAL_QUERY_KEYS.contains(k))
          safeQuery[k] = v;
      });
    }

    var query = {}..addAll(base.queryParameters)..addAll(safeQuery);

    if (query.isEmpty) {
      return new Uri(
          scheme: base.scheme,
          userInfo: base.userInfo,
          host: base.host,
          port: base.port,
          path: base.path);
    } else
      return new Uri(
          scheme: base.scheme,
          userInfo: base.userInfo,
          host: base.host,
          port: base.port,
          path: base.path,
          queryParameters: query);
  }

  List _mapToList(Map result) {
    List out = [];
    result.forEach((k, v) {
      if (v is Map && !v.containsKey('id'))
        out.add(v..['id'] = k);
      else
        out.add(v);
    });
    return out;
  }

  @override
  Future index([Map params]) =>
      client.get(_applyParams(params, _baseUri)).then((result) {
        if (result is Map) {
          // If indexing our collection returns a Map, we'll want to transform it into a list.
          //
          // Ex.
          // Original JSON: "{0: {"foo": "bar"}, 1: {"foo": "baz"}}"
          // Returned Dart: [{id: 0, foo: bar}, {id: 1, foo: baz}]
          return _mapToList(result);
        } else if (result is List) {
          // Otherwise, make a list using indices
          return _mapToList(result.asMap());
        } else
          return result;
      });

  @override
  Future read(id, [Map params]) => client
          .get(_applyParams(params, _baseUri.resolve('$id.json')))
          .then((result) {
        // Add `id` to result, if necessary
        if (result is Map && !result.containsKey('id'))
          result[id] = id.toString();
        return result;
      });

  @override
  Future create(data, [Map params]) async {
    Map result = await client.post(_applyParams(params, _baseUri), data);
    var id = result['name'];
    return await read(id, params);
  }

  @override
  Future modify(id, data, [Map params]) async {
    await client.patch(
        _applyParams(params, _baseUri.resolve('$id.json')), data);
    return await read(id, params);
  }

  @override
  Future update(id, data, [Map params]) async {
    await client.put(_applyParams(params, _baseUri.resolve('$id.json')), data);
    return await read(id, params);
  }

  @override
  Future remove(id, [Map params]) async {
    var old = await read(id, params);
    await client.delete(_applyParams(params, _baseUri.resolve('$id.json')));
    return old;
  }
}
