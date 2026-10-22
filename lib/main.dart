
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

const orange = Color(0xFFFF6A00);
const gold = Color(0xFFFFC857);
const cream = Color(0xFFFFF8F0);

const localKey = 'hbb_clients';
const backupLocalKey = 'hbb_clients_backup';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool ready = false;

  try {
    await Firebase.initializeApp()
        .timeout(const Duration(seconds: 12));
    ready = true;
  } catch (e) {
    debugPrint('Firebase non initialise : $e');
  }

  runApp(HBBApp(firebaseReady: ready));
}

class HBBApp extends StatelessWidget {
  final bool firebaseReady;

  const HBBApp({super.key, required this.firebaseReady});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'HBB WiFi Manager',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: cream,
          colorScheme: ColorScheme.fromSeed(seedColor: orange),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
          ),
        ),
        home: HomePage(firebaseReady: firebaseReady),
      );
}

class WifiClient {
  String id, name, phone, code;
  int price;
  DateTime start, end, paymentDate;

  WifiClient({
    required this.id,
    required this.name,
    required this.phone,
    required this.code,
    required this.price,
    required this.start,
    required this.end,
    required this.paymentDate,
  });

  bool get active => DateTime.now().isBefore(end);

  Duration get remaining {
    final d = end.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'code': code,
        'price': price,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'paymentDate': paymentDate.toIso8601String(),
      };

  factory WifiClient.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();

    DateTime date(dynamic v, DateTime fallback) =>
        DateTime.tryParse('$v') ?? fallback;

    final start = date(
      j['start'] ?? j['startDate'] ?? j['dateDebut'],
      now,
    );

    return WifiClient(
      id: '${j['id'] ?? j['code'] ?? ''}',
      name: '${j['name'] ?? j['nom'] ?? 'Client'}',
      phone: '${j['phone'] ?? j['telephone'] ?? ''}',
      code: '${j['code'] ?? ''}',
      price: int.tryParse(
            '${j['price'] ?? j['prix'] ?? 0}',
          ) ??
          0,
      start: start,
      end: date(
        j['end'] ?? j['endDate'] ?? j['dateFin'],
        start,
      ),
      paymentDate: date(
        j['paymentDate'] ?? j['datePaiement'],
        start,
      ),
    );
  }
}

String money(int n) {
  final s = n.toString();
  final b = StringBuffer();

  for (int i = 0; i < s.length; i++) {
    b.write(s[i]);

    if ((s.length - i - 1) % 3 == 0 &&
        i != s.length - 1) {
      b.write(' ');
    }
  }

  return '${b.toString()} FCFA';
}

String remainingText(Duration d) {
  if (d == Duration.zero) return 'Expiré';

  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;

  if (days > 0) return '$days j $hours h';
  if (hours > 0) return '$hours h $minutes min';

  return '$minutes min';
}

String newCode(Set<String> existing) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();

  while (true) {
    final code = List.generate(
      8,
      (_) => chars[r.nextInt(chars.length)],
    ).join();

    if (!existing.contains(code)) return code;
  }
}

class HomePage extends StatefulWidget {
  final bool firebaseReady;

  const HomePage({
    super.key,
    required this.firebaseReady,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<WifiClient> clients = [];

  bool loading = true;
  bool syncing = false;

  int tab = 0;

  User? get user => widget.firebaseReady
      ? FirebaseAuth.instance.currentUser
      : null;

  @override
  void initState() {
    super.initState();
    loadLocal();
  }

  bool validJsonList(String? value) {
    if (value == null || value.isEmpty) return false;

    try {
      return jsonDecode(value) is List;
    } catch (_) {
      return false;
    }
  }

  // Charge les données principales ou la copie de secours.
  Future<void> loadLocal() async {
    try {
      final p = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 12));

      await p.reload().timeout(const Duration(seconds: 12));

      final primary = p.getString(localKey);
      final backup = p.getString(backupLocalKey);

      String? raw = primary;

      if (!validJsonList(raw) && validJsonList(backup)) {
        raw = backup;
        debugPrint('Récupération depuis la copie de secours.');
      }

      if (validJsonList(raw)) {
        final decoded = jsonDecode(raw!) as List;
        final loaded = <WifiClient>[];

        for (final item in decoded) {
          try {
            loaded.add(
              WifiClient.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            );
          } catch (e) {
            debugPrint('Client illisible ignore : $e');
          }
        }

        clients
          ..clear()
          ..addAll(loaded);

        // Répare la sauvegarde principale à partir du secours.
        if (raw == backup && backup != null) {
          await p.setString(localKey, backup);
        }
      }
    } catch (e, st) {
      debugPrint('Erreur chargement local : $e\n$st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lecture locale impossible. Vérifie le stockage du téléphone.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // Enregistre deux copies locales et vérifie leur contenu.
  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 12));

      final encoded = jsonEncode(
        clients.map((c) => c.toJson()).toList(),
      );

      // Écrit d'abord la copie de secours.
      final backupSaved = await p
          .setString(backupLocalKey, encoded)
          .timeout(const Duration(seconds: 12));

      if (!backupSaved ||
          p.getString(backupLocalKey) != encoded) {
        throw Exception('Copie de secours non confirmée.');
      }

      // Écrit ensuite la sauvegarde principale.
      final saved = await p
          .setString(localKey, encoded)
          .timeout(const Duration(seconds: 12));

      if (!saved || p.getString(localKey) != encoded) {
        throw Exception('Sauvegarde principale non confirmée.');
      }

      debugPrint('Sauvegarde locale vérifiée.');
    } catch (e, st) {
      debugPrint('ERREUR SAUVEGARDE LOCALE : $e\n$st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 7),
            content: Text(
              'ERREUR : sauvegarde non confirmée. '
              'Ne ferme pas l’application ; réessaie.',
            ),
          ),
        );
      }

      rethrow;
    }

    // Le cloud ne remplace jamais la sauvegarde locale.
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('data')
            .doc('clients')
            .set({
          'clients': clients.map((c) => c.toJson()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final batch = FirebaseFirestore.instance.batch();

        for (final c in clients) {
          if (c.code.isEmpty) continue;

          final ref = FirebaseFirestore.instance
              .collection('clientLookup')
              .doc(c.code);

          batch.set(ref, {
            'name': c.name,
            'start': c.start.toIso8601String(),
            'end': c.end.toIso8601String(),
            'ownerUid': user!.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
      } catch (e) {
        debugPrint('Synchronisation cloud impossible : $e');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sauvegarde locale faite, mais le cloud a échoué.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> googleLogin() async {
    if (!widget.firebaseReady || syncing) return;

    setState(() => syncing = true);

    try {
      final account = await GoogleSignIn().signIn();

      if (account == null) return;

      final auth = await account.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      await syncCloud();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connexion Google réussie.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connexion impossible : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> syncCloud() async {
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('data')
        .doc('clients');

    final snap = await ref.get();

    if (snap.exists) {
      final list = snap.data()?['clients'];

      if (list is List) {
        final merged = <String, WifiClient>{};

        for (final item in list) {
          try {
            final c = WifiClient.fromJson(
              Map<String, dynamic>.from(item as Map),
            );

            merged[c.id.isNotEmpty ? c.id : c.code] = c;
          } catch (_) {}
        }

        for (final c in clients) {
          merged[c.id.isNotEmpty ? c.id : c.code] = c;
        }

        clients
          ..clear()
          ..addAll(merged.values);
      }
    }

    await save();

    if (mounted) setState(() {});
  }

  Future<void> logout() async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();

      if (mounted) setState(() {});
    } catch (e) {
      message('Déconnexion impossible : $e');
    }
  }

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> addClient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final price = TextEditingController();
    final days = TextEditingController(text: '30');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau client'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Nom du client',
                ),
              ),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                ),
              ),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix payé (FCFA)',
                ),
              ),
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durée (jours)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final n = name.text.trim();
    final amount = int.tryParse(price.text.trim());
    final duration = int.tryParse(days.text.trim());
    final phoneValue = phone.text.trim();

    if (n.isEmpty ||
        amount == null ||
        amount < 0 ||
        duration == null ||
        duration <= 0) {
      message('Vérifie le nom, le prix et la durée.');
      return;
    }

    final now = DateTime.now();

    final client = WifiClient(
      id: now.microsecondsSinceEpoch.toString(),
      name: n,
      phone: phoneValue,
      code: newCode(clients.map((c) => c.code).toSet()),
      price: amount,
      start: now,
      end: now.add(Duration(days: duration)),
      paymentDate: now,
    );

    clients.add(client);

    try {
      await save();

      if (mounted) {
        setState(() {});
        message('Client créé et sauvegarde vérifiée. Code : ${client.code}');
      }
    } catch (e) {
      // Retire le client de la liste si la sauvegarde locale échoue.
      clients.removeWhere((c) => c.id == client.id);

      if (mounted) {
        setState(() {});
        message(
          'Échec de sauvegarde locale. '
          'Le client n’a pas été enregistré. Erreur : $e',
        );
      }
    }
  }

  int revenue(DateTime from, DateTime to) => clients
      .where((c) =>
          !c.paymentDate.isBefore(from) &&
          c.paymentDate.isBefore(to))
      .fold(0, (sum, c) => sum + c.price);

  int get total => clients.fold(0, (s, c) => s + c.price);

  Widget stat(String title, int value) => Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Text(
                money(value),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: orange,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );

  Widget dashboard() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'Tableau de bord',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        stat(
          'Hier',
          revenue(
            today.subtract(const Duration(days: 1)),
            today,
          ),
        ),
        stat(
          '7 derniers jours',
          revenue(
            today.subtract(const Duration(days: 6)),
            today.add(const Duration(days: 1)),
          ),
        ),
        stat(
          '30 derniers jours',
          revenue(
            today.subtract(const Duration(days: 29)),
            today.add(const Duration(days: 1)),
          ),
        ),
        stat('Total encaissé', total),
        stat('Clients enregistrés', clients.length),
        stat('Abonnements actifs', clients.where((c) => c.active).length),
      ],
    );
  }

  Widget clientList() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mes clients',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: addClient,
                icon: const Icon(Icons.person_add_alt_1, color: orange),
              ),
            ],
          ),
          for (final c in clients)
            Card(
              color: Colors.white,
              child: ListTile(
                title: Text(
                  c.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Code : ${c.code}\n'
                  'Début : ${c.start.toLocal()}\n'
                  'Fin : ${c.end.toLocal()}\n'
                  'Temps restant : ${remainingText(c.remaining)}\n'
                  'Paiement : ${money(c.price)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Supprimer ce client ?'),
                        content: const Text(
                          'Cette action supprimera le client localement.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Supprimer'),
                          ),
                        ],
                      ),
                    );

                    if (yes != true) return;

                    clients.remove(c);

                    try {
                      await save();
                      if (mounted) setState(() {});
                    } catch (_) {
                      clients.add(c);
                      if (mounted) setState(() {});
                    }
                  },
                ),
              ),
            ),
        ],
      );

  Widget clientSpace() {
    final code = TextEditingController();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Espace client',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Entre ton code personnel pour consulter ton abonnement.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Code client',
              hintText: 'Ex. A8BC2XYZ',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final entered = code.text.trim().toUpperCase();

              if (entered.isEmpty) return;

              WifiClient? local;

              for (final c in clients) {
                if (c.code.toUpperCase() == entered) {
                  local = c;
                  break;
                }
              }

              Map<String, dynamic>? cloud;

              if (local == null && widget.firebaseReady) {
                try {
                  final snap = await FirebaseFirestore.instance
                      .collection('clientLookup')
                      .doc(entered)
                      .get();

                  if (snap.exists) cloud = snap.data();
                } catch (_) {
                  message(
                    'Consultation cloud indisponible. Vérifie les règles Firestore.',
                  );
                  return;
                }
              }

              if (!mounted) return;

              if (local == null && cloud == null) {
                message('Code inconnu ou accès cloud indisponible.');
                return;
              }

              final start = local?.start ??
                  DateTime.parse(cloud!['start'].toString());

              final end = local?.end ??
                  DateTime.parse(cloud!['end'].toString());

              final name = local?.name ?? cloud!['name'].toString();

              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Bonjour $name'),
                  content: Text(
                    'Début : $start\n\n'
                    'Fin : $end\n\n'
                    'Temps restant : ${remainingText(
                      end.difference(DateTime.now()).isNegative
                          ? Duration.zero
                          : end.difference(DateTime.now()),
                    )}\n\n'
                    'Statut : ${DateTime.now().isBefore(end) ? 'ACTIF' : 'EXPIRÉ'}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Consulter mon abonnement'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HBB WiFi Manager',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (user == null)
            IconButton(
              tooltip: 'Connexion Google',
              onPressed: syncing ? null : googleLogin,
              icon: syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login, color: orange),
            )
          else
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'sync') syncCloud();
                if (v == 'logout') logout();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'sync',
                  child: Text('Synchroniser maintenant'),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Déconnexion Google'),
                ),
              ],
              icon: const Icon(Icons.account_circle, color: orange),
            ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: [
          dashboard(),
          clientList(),
          clientSpace(),
        ],
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton(
              backgroundColor: orange,
              foregroundColor: Colors.white,
              onPressed: addClient,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: 'Espace client',
          ),
        ],
      ),
    );
  }
}
