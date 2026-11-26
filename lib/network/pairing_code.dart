import '../core/crypto.dart';

class PairingCodeEntry {
  PairingCodeEntry({
    required this.code,
    required this.createdAt,
    required this.expiresAt,
  });

  final String code;
  final DateTime createdAt;
  final DateTime expiresAt;

  String get normalized => normalizePairingCode(code);
  String get formatted => formatPairingCode(code);

  Duration get remaining {
    final value = expiresAt.difference(DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  bool get isExpired => !DateTime.now().isBefore(expiresAt);
}

/// Holds the single one-time pairing code currently offered by this device.
class PairingCodeStore {
  PairingCodeStore({this.validity = const Duration(minutes: 5)});

  final Duration validity;
  PairingCodeEntry? _active;

  PairingCodeEntry? get active {
    final entry = _active;
    if (entry == null) return null;
    if (entry.isExpired) {
      _active = null;
      return null;
    }
    return entry;
  }

  PairingCodeEntry generate() {
    final now = DateTime.now();
    final entry = PairingCodeEntry(
      code: generatePairingCode(),
      createdAt: now,
      expiresAt: now.add(validity),
    );
    _active = entry;
    return entry;
  }

  void consume() => _active = null;

  void clear() => _active = null;
}

String pairingCodeForDisplay(String code) => formatPairingCode(code);
