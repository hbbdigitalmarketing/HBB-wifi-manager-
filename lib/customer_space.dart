import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final RegExp _codeRe = RegExp(r'^HBB-[A-Z0-9]{6,8}$');

String normalizeCode(String raw) => raw.trim().toUpperCase();

class CodeCollisionException implements Exception {
  final String code;
  CodeCollisionException(this.code);
  @override
  String toString() => 'Le code $code appartient déjà à un autre gestionnaire.';
}

class PublicPlan {
  final String label;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int? price;
  final bool archived;
  PublicPlan({
    required this.label,
    required this.createdAt,
    required this.expiresAt,
    this.price,
    this.archived = false,
  });

  factory PublicPlan.fromMap(Map<String, dynamic> m) => PublicPlan(
        label: (m['label'] ?? 'Forfait Wi-Fi').toString(),
        createdAt: (m['createdAt'] as Timestamp).toDate(),
        expiresAt: (m['expiresAt'] as Timestamp).toDate(),
        price: (m['price'] as num?)?.toInt(),
        archived: m['archived'] == true,
      );
}

class PublicPlanService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final Random _rng = Random.secure();

  static String generateCode() =>
      'HBB-${List.generate(8, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join()}';

  static Future<void> _ensureAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  }

  static Future<PublicPlan?> lookup(String raw) async {
    final code = normalizeCode(raw);
    if (!_codeRe.hasMatch(code)) {
      throw const FormatException('Code mal formé');
    }
    await _ensureAuth();
    final snap = await _db
        .collection('plans')
        .doc(code)
        .get(const GetOptions(source: Source.server));
    if (!snap.exists || snap.data() == null) return null;
    return PublicPlan.fromMap(snap.data()!);
  }

  static Future<void> publish({
    required String code,
    required String label,
    required DateTime createdAt,
    required DateTime expiresAt,
    int? price,
    bool archived = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Connexion gestionnaire requise.');
    }
    final c = normalizeCode(code);
    final ref = _db.collection('plans').doc(c);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists && existing.data()?['ownerUid'] != user.uid) {
        throw CodeCollisionException(c);
      }
      tx.set(ref, {
        'ownerUid': user.uid,
        'label': label,
        'createdAt': Timestamp.fromDate(createdAt.toUtc()),
        'expiresAt': Timestamp.fromDate(expiresAt.toUtc()),
        if (price != null) 'price': price,
        'archived': archived,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<String> createUniqueCodeAndPublish({
    required String label,
    required DateTime createdAt,
    required DateTime expiresAt,
    int? price,
  }) async {
    for (var i = 0; i < 10; i++) {
      final code = generateCode();
      try {
        await publish(
            code: code,
            label: label,
            createdAt: createdAt,
            expiresAt: expiresAt,
            price: price);
        return code;
      } on CodeCollisionException {
        continue;
      }
    }
    throw StateError('Impossible de générer un code unique, réessayez.');
  }

  /// Publie les clients existants avec LEUR code actuel (aucune donnée modifiée).
  /// Retourne les codes en collision.
  static Future<List<String>> publishExisting(
      List<Map<String, dynamic>> clients) async {
    final collisions = <String>[];
    for (final c in clients) {
      try {
        await publish(
          code: c['code'] as String,
          label: (c['label'] ?? 'Forfait Wi-Fi') as String,
          createdAt: c['createdAt'] as DateTime,
          expiresAt: c['expiresAt'] as DateTime,
          price: c['price'] as int?,
          archived: c['archived'] == true,
        );
      } on CodeCollisionException catch (e) {
        collisions.add(e.code);
      }
    }
    return collisions;
  }
}

String remainingLabel(DateTime expiresAt, DateTime now) {
  final d = expiresAt.difference(now);
  if (d.inSeconds <= 0) return 'Expiré';
  final days = d.inDays;
  final h = d.inHours % 24;
  final m = d.inMinutes % 60;
  if (days > 0) return '$days j $h h restantes';
  if (d.inHours > 0) return '${d.inHours} h $m min restantes';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min restantes';
}

String formatDateTime(DateTime dt) {
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}';
}

class CustomerSpaceScreen extends StatefulWidget {
  const CustomerSpaceScreen({super.key});
  @override
  State<CustomerSpaceScreen> createState() => _CustomerSpaceScreenState();
}

class _CustomerSpaceScreenState extends State<CustomerSpaceScreen> {
  final _controller = TextEditingController();
  PublicPlan? _plan;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _consult() async {
    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
    });
    try {
      final plan = await PublicPlanService.lookup(_controller.text);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        if (plan == null) _error = 'Code introuvable. Vérifiez-le et réessayez.';
      });
    } on FormatException {
      setState(() => _error = 'Code invalide. Format attendu : HBB-XXXXXX.');
    } on FirebaseException catch (e) {
      setState(() => _error = (e.code == 'unavailable' || e.code == 'network-request-failed')
          ? 'Pas de connexion Internet. Réessayez plus tard.'
          : 'Consultation impossible (${e.code}).');
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final now = DateTime.now();
    final expired = plan != null && !plan.expiresAt.isAfter(now);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Espace client',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Saisissez votre code personnel pour consulter votre forfait.'),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Votre code (ex. HBB-AB12CD)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _consult(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _consult,
          child: _loading
              ? const SizedBox(
                  height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Consulter mon forfait'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (plan != null) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.label,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(expired ? 'Statut : Expiré' : 'Statut : Actif',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: expired ? Colors.red : Colors.green.shade700)),
                  const SizedBox(height: 8),
                  Text('Début : ${formatDateTime(plan.createdAt)}'),
                  Text('Expiration : ${formatDateTime(plan.expiresAt)}'),
                  const SizedBox(height: 8),
                  Text(remainingLabel(plan.expiresAt, now),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  if (plan.price != null) ...[
                    const SizedBox(height: 8),
                    Text('Prix : ${plan.price} FCFA'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _loading ? null : _consult, child: const Text('Actualiser')),
        ],
      ],
    );
  }
}
