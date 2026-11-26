import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'models.dart';

/// All local files live below one application-support directory.
class AppPaths {
  AppPaths(this.root);

  final Directory root;

  File get identityFile => File(p.join(root.path, 'identity.json'));
  File get settingsFile => File(p.join(root.path, 'settings.json'));
  File get peersFile => File(p.join(root.path, 'peers.json'));
  Directory get historyDir => Directory(p.join(root.path, 'history'));
  File get historyFile => File(p.join(historyDir.path, 'history.json'));
  Directory get imageDir => Directory(p.join(historyDir.path, 'images'));

  Future<void> ensure() async {
    await root.create(recursive: true);
    await historyDir.create(recursive: true);
    await imageDir.create(recursive: true);
  }
}

Future<Map<String, Object?>?> readJsonFile(File file) async {
  try {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {
    // A corrupt cache should never prevent the application from starting.
  }
  return null;
}

Future<void> writeJsonFile(File file, Map<String, Object?> value) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
  if (await file.exists()) {
    await file.delete();
  }
  await temporary.rename(file.path);
}

class IdentityStore {
  IdentityStore(this.paths);

  final AppPaths paths;

  Future<LocalIdentity> loadOrCreate(String platform) async {
    final json = await readJsonFile(paths.identityFile);
    final existing = json == null ? null : LocalIdentity.fromJson(json);
    if (existing != null) return existing;
    final identity = LocalIdentity(
      id: _hex(randomBytes(16)),
      name: defaultDeviceName(platform),
      platform: platform,
    );
    await save(identity);
    return identity;
  }

  Future<void> save(LocalIdentity identity) async {
    await writeJsonFile(paths.identityFile, identity.toJson());
  }

  static String _hex(List<int> bytes) =>
      bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

class SettingsStore {
  SettingsStore(this.paths);

  final AppPaths paths;

  Future<AppSettings> load(String platform) async {
    final json = await readJsonFile(paths.settingsFile);
    if (json == null) return AppSettings.defaults(platform: platform);
    return AppSettings.fromJson(json, platform: platform);
  }

  Future<void> save(AppSettings settings) async {
    await writeJsonFile(paths.settingsFile, settings.toJson());
  }
}

class PeerStore {
  PeerStore(this.paths);

  final AppPaths paths;

  Future<Map<String, PairedPeer>> load() async {
    final json = await readJsonFile(paths.peersFile);
    if (json == null) return <String, PairedPeer>{};
    final raw = json['peers'];
    if (raw is! List) return <String, PairedPeer>{};
    final result = <String, PairedPeer>{};
    for (final value in raw) {
      if (value is Map) {
        final peer = PairedPeer.fromJson(value.cast<String, Object?>());
        if (peer != null) result[peer.id] = peer;
      }
    }
    return result;
  }

  Future<void> save(Map<String, PairedPeer> peers) async {
    await writeJsonFile(paths.peersFile, <String, Object?>{
      'version': 1,
      'peers': peers.values.map((peer) => peer.toJson()).toList(),
    });
  }
}

/// Bounded, on-disk clipboard history. Images are stored as PNG files so the
/// metadata file stays small.
class HistoryStore {
  HistoryStore(this.paths, {this.maxItems = 40, this.maxImageBytes = 120 * 1024 * 1024});

  final AppPaths paths;
  final int maxItems;
  final int maxImageBytes;

  final List<ClipItem> _items = <ClipItem>[];
  bool _loaded = false;

  List<ClipItem> get items => List<ClipItem>.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await paths.ensure();
    final json = await readJsonFile(paths.historyFile);
    final raw = json?['items'];
    if (raw is! List) return;
    final loaded = <ClipItem>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final map = value.cast<String, Object?>();
      final item = await _itemFromJson(map);
      if (item != null) loaded.add(item);
    }
    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _items
      ..clear()
      ..addAll(loaded.take(maxItems));
    await _enforceLimits();
  }

  Future<ClipItem?> _itemFromJson(Map<String, Object?> map) async {
    final kind = ClipKind.fromWire(map['kind'] as String?);
    final id = map['id'] as String?;
    final originId = map['originId'] as String?;
    final originName = map['originName'] as String?;
    final createdAt = DateTime.tryParse(map['createdAt'] as String? ?? '');
    if (id == null || originId == null || originName == null || createdAt == null) {
      return null;
    }
    if (kind == ClipKind.text) {
      final text = map['text'] as String?;
      if (text == null) return null;
      return ClipItem(
        id: id,
        kind: ClipKind.text,
        text: text,
        createdAt: createdAt,
        originId: originId,
        originName: originName,
        incoming: map['incoming'] as bool? ?? false,
      );
    }
    final imageName = map['imageFile'] as String?;
    if (imageName == null) return null;
    final file = File(p.join(paths.imageDir.path, imageName));
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return ClipItem(
        id: id,
        kind: ClipKind.image,
        bytes: bytes,
        createdAt: createdAt,
        originId: originId,
        originName: originName,
        incoming: map['incoming'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> add(ClipItem item) async {
    await load();
    if (_items.isNotEmpty && _items.first.id == item.id) return false;
    _items.insert(0, item);
    if (item.kind == ClipKind.image) {
      try {
        final file = File(p.join(paths.imageDir.path, '${item.id}.png'));
        await file.writeAsBytes(item.bytes!, flush: true);
      } catch (_) {
        // Keep the in-memory entry even if the image cannot be persisted.
      }
    }
    await _enforceLimits();
    await _save();
    return true;
  }

  Future<void> remove(String id) async {
    await load();
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    if (item.kind == ClipKind.image) {
      try {
        await File(p.join(paths.imageDir.path, '${item.id}.png')).delete();
      } catch (_) {}
    }
    await _save();
  }

  Future<void> clear() async {
    await load();
    _items.clear();
    try {
      if (await paths.imageDir.exists()) {
        await paths.imageDir.delete(recursive: true);
      }
      await paths.imageDir.create(recursive: true);
    } catch (_) {}
    await _save();
  }

  Future<void> _enforceLimits() async {
    while (_items.length > maxItems) {
      final removed = _items.removeLast();
      if (removed.kind == ClipKind.image) {
        try {
          await File(p.join(paths.imageDir.path, '${removed.id}.png')).delete();
        } catch (_) {}
      }
    }
    var imageTotal = 0;
    final keep = <ClipItem>[];
    for (final item in _items) {
      if (item.kind == ClipKind.image) {
        final size = item.bytes?.length ?? 0;
        if (imageTotal + size > maxImageBytes && keep.isNotEmpty) {
          try {
            await File(p.join(paths.imageDir.path, '${item.id}.png')).delete();
          } catch (_) {}
          continue;
        }
        imageTotal += size;
      }
      keep.add(item);
    }
    _items
      ..clear()
      ..addAll(keep);
  }

  Future<void> _save() async {
    await writeJsonFile(paths.historyFile, <String, Object?>{
      'version': 1,
      'items': _items.map((item) {
        return <String, Object?>{
          'id': item.id,
          'kind': item.kind.wireName,
          if (item.kind == ClipKind.text) 'text': item.text,
          if (item.kind == ClipKind.image) 'imageFile': '${item.id}.png',
          'createdAt': item.createdAt.toIso8601String(),
          'originId': item.originId,
          'originName': item.originName,
          'incoming': item.incoming,
        };
      }).toList(),
    });
  }
}

/// Convenience for tests and callers that need a PNG-looking header check.
bool looksLikePng(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}
