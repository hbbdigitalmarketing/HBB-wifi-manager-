import 'dart:async';
import 'expiry_notifications.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'customer_space.dart';

import 'welcome_page.dart';
const orange = Color(0xFFFF6A00);
const cream = Color(0xFFFFF8F0);
const ink = Color(0xFF29231F);

bool firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase indisponible : $e');
  }
  runApp(const HBBApp());
}
class HBBApp extends StatelessWidget {
  const HBBApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HBB WiFi Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(seedColor: orange),
        appBarTheme: const AppBarTheme(
          backgroundColor: cream,
          foregroundColor: ink,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const WelcomePage(),
    );
  }
}

class WiFiClient {
  String id;
  String name;
  String phone;
  String code;
  int price;
  int durationDays;
  DateTime createdAt;
  bool archived;
  // Anciens forfaits (renouvellements). Absent des anciennes données => liste vide.
  List<Map<String, dynamic>> history;

  WiFiClient({
    required this.id,
    required this.name,
    required this.phone,
    required this.code,
    required this.price,
    required this.durationDays,
    required this.createdAt,
    this.archived = false,
    List<Map<String, dynamic>>? history,
  }) : history = history ?? [];

  DateTime get expiresAt => createdAt.add(Duration(days: durationDays));

  int get remainingSeconds => expiresAt.difference(DateTime.now()).inSeconds;

  bool get active => remainingSeconds > 0;

  String get planLabel => 'Forfait Wi-Fi $durationDays jours';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'code': code,
        'price': price,
        'durationDays': durationDays,
        'createdAt': createdAt.toIso8601String(),
        'archived': archived,
        'history': history,
      };

  factory WiFiClient.fromMap(Map<String, dynamic> m) {
    final h = m['history'];
    return WiFiClient(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      code: '${m['code'] ?? ''}',
      price: (m['price'] as num?)?.toInt() ?? 0,
      durationDays: (m['durationDays'] as num?)?.toInt() ?? 30,
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
      archived: m['archived'] == true,
      history: h is List
          ? h.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [],
    );
  }
}

class WiFiPayment {
  String id;
  String clientId;
  String clientName;
  int amount;
  DateTime date;

  WiFiPayment({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'clientId': clientId,
        'clientName': clientName,
        'amount': amount,
        'date': date.toIso8601String(),
      };

  factory WiFiPayment.fromMap(Map<String, dynamic> m) => WiFiPayment(
        id: '${m['id'] ?? ''}',
        clientId: '${m['clientId'] ?? ''}',
        clientName: '${m['clientName'] ?? ''}',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        date: DateTime.tryParse('${m['date']}') ?? DateTime.now(),
      );
}

class ManagerPage extends StatefulWidget {
  const ManagerPage({super.key});

  @override
  State<ManagerPage> createState() => _ManagerPageState();
}

class _ManagerPageState extends State<ManagerPage> {
  final List<WiFiClient> clients = [];
  final List<WiFiPayment> payments = [];

  int tab = 0;
  String period = '30 jours';
  bool busy = false;
  bool showAccount = false;
  String query = '';
  String message = 'Données enregistrées sur cet appareil';

  Timer? ticker;
  StreamSubscription<User?>? authSub;

  // Ignore le compte anonyme créé par l'Espace client.
  User? get user {
    if (!firebaseReady) return null;
    final u = FirebaseAuth.instance.currentUser;
    return (u == null || u.isAnonymous) ? null : u;
  }

  @override
  void initState() {
    super.initState();
    loadLocal();
    if (firebaseReady) {
      authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted) setState(() {});
      });
    }
    ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    authSub?.cancel();
    super.dispose();
  }

  // ---------- STOCKAGE LOCAL ----------

  Future<void> loadLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final c = p.getString('hbb_clients');
      final pay = p.getString('hbb_payments');

      // Copie de sécurité unique avant toute évolution du modèle.
      if (c != null && p.getString('hbb_clients_backup_v1') == null) {
        await p.setString('hbb_clients_backup_v1', c);
        if (pay != null) await p.setString('hbb_payments_backup_v1', pay);
      }

      final loadedClients = c == null
          ? <WiFiClient>[]
          : (jsonDecode(c) as List)
              .map((e) => WiFiClient.fromMap(Map<String, dynamic>.from(e)))
              .toList();
      final loadedPayments = pay == null
          ? <WiFiPayment>[]
          : (jsonDecode(pay) as List)
              .map((e) => WiFiPayment.fromMap(Map<String, dynamic>.from(e)))
              .toList();

      clients
        ..clear()
        ..addAll(loadedClients);
      payments
             scheduleExpiryAlerts();
        ..clear()
        ..addAll(loadedPayments);
    } catch (e) {
      message = 'Lecture locale impossible : aucune donnée n\'a été modifiée.';
    }
    if (mounted) setState(() {});
  }

  Future<bool> saveLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'hbb_clients',
        jsonEncode(clients.map((e) => e.toMap()).toList()),
      );
      await p.setString(
        'hbb_payments',
        jsonEncode(payments.map((e) => e.toMap()).toList()),
      );
            scheduleExpiryAlerts();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => message = 'Enregistrement local impossible.');
      }
      return false;
    }
  }

  // ---------- OUTILS ----------

  String friendlyError(Object e) {
    if (e is CodeCollisionException) return 'code déjà utilisé';
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unavailable':
        case 'network-request-failed':
          return 'pas de connexion Internet';
        case 'permission-denied':
          return 'accès refusé par les règles Firestore';
        case 'unauthenticated':
          return 'session expirée, reconnecte-toi';
        default:
          return 'erreur ${e.code}';
      }
    }
    if (e is PlatformException) {
      final t = '${e.code} ${e.message}';
      if (t.contains('ApiException: 10')) {
        return 'empreinte SHA-1 non reconnue par Firebase (erreur 10)';
      }
      if (t.contains('ApiException: 7') || t.contains('network_error')) {
        return 'pas de connexion Internet';
      }
      return 'erreur Google (${e.code})';
    }
    if (e is StateError) return e.message;
    return 'erreur inattendue';
  }

  String get money =>
      '${payments.where((p) => inPeriod(p.date)).fold<int>(0, (s, p) => s + p.amount)} FCFA';

  // Hier = jour calendaire précédent (heure locale) ;
  // 7 / 30 jours = fenêtre glissante jusqu'à maintenant ; Total = tout.
  bool inPeriod(DateTime date) {
    final now = DateTime.now();
    switch (period) {
      case 'Hier':
        final y = DateTime(now.year, now.month, now.day - 1);
        return date.year == y.year && date.month == y.month && date.day == y.day;
      case '7 jours':
        return date.isAfter(now.subtract(const Duration(days: 7)));
      case '30 jours':
        return date.isAfter(now.subtract(const Duration(days: 30)));
      default:
        return true;
    }
  }

  String newId() => '${DateTime.now().microsecondsSinceEpoch}';

  String newLocalCode() {
    final used = clients.map((c) => c.code.toUpperCase()).toSet();
    for (var i = 0; i < 50; i++) {
      final code = PublicPlanService.generateCode();
      if (!used.contains(code)) return code;
    }
    return PublicPlanService.generateCode();
  }

  String remaining(WiFiClient c) =>
      remainingLabel(c.expiresAt, DateTime.now());

  // ---------- ACTIONS CLIENTS ----------

  Future<void> addClient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final price = TextEditingController(text: '1000');
    final days = TextEditingController(text: '30');
    var paid = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nouveau client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom du client'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prix en FCFA'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée en jours'),
                ),
                CheckboxListTile(
                  value: paid,
                  onChanged: (v) => setD(() => paid = v ?? true),
                  title: const Text('Paiement encaissé maintenant'),
                  contentPadding: EdgeInsets.zero,
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
      ),
    );

    if (ok != true || name.text.trim().isEmpty) return;

    final amount = int.tryParse(price.text) ?? 0;
    final parsedDays = int.tryParse(days.text) ?? 30;
    final duration = parsedDays < 1 ? 1 : parsedDays;
    final now = DateTime.now();
    final id = newId();

    // Connecté : le code est réservé dans le cloud (unicité garantie, même
    // si deux téléphones créent un client en même temps).
    var code = newLocalCode();
    var published = false;
    if (user != null) {
      try {
        code = await PublicPlanService.createUniqueCodeAndPublish(
          label: 'Forfait Wi-Fi $duration jours',
          createdAt: now,
          expiresAt: now.add(Duration(days: duration)),
          price: amount,
        );
        published = true;
      } catch (e) {
        message =
            'Code créé hors ligne, fiche publique à synchroniser (${friendlyError(e)})';
      }
    }

    final client = WiFiClient(
      id: id,
      name: name.text.trim(),
      phone: phone.text.trim(),
      code: code,
      price: amount,
      durationDays: duration,
      createdAt: now,
    );

    setState(() {
      clients.insert(0, client);
      if (paid && amount > 0) {
        payments.insert(
          0,
          WiFiPayment(
            id: newId(),
            clientId: id,
            clientName: client.name,
            amount: amount,
            date: now,
          ),
        );
      }
    });

    await saveLocal();
    await syncCloud(showMessage: false);
    if (!published) await publishPlans([client]);
  }

  Future<void> renewClient(WiFiClient c) async {
    final price = TextEditingController(text: '${c.price}');
    final days = TextEditingController(text: '${c.durationDays}');
    var paid = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Renouveler • ${c.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.active
                      ? 'Forfait encore actif (${remaining(c)}). Le nouveau forfait démarre MAINTENANT et remplace le temps restant.'
                      : 'Forfait expiré. Le nouveau forfait démarre maintenant.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prix en FCFA'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée en jours'),
                ),
                CheckboxListTile(
                  value: paid,
                  onChanged: (v) => setD(() => paid = v ?? true),
                  title: const Text('Paiement encaissé'),
                  contentPadding: EdgeInsets.zero,
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
              child: const Text('Renouveler'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final amount = int.tryParse(price.text) ?? c.price;
    final parsedDays = int.tryParse(days.text) ?? c.durationDays;
    final duration = parsedDays < 1 ? 1 : parsedDays;
    final now = DateTime.now();

    setState(() {
      c.history.add({
        'start': c.createdAt.toIso8601String(),
        'durationDays': c.durationDays,
        'price': c.price,
      });
      c.createdAt = now;
      c.durationDays = duration;
      c.price = amount;
      if (paid && amount > 0) {
        payments.insert(
          0,
          WiFiPayment(
            id: newId(),
            clientId: c.id,
            clientName: c.name,
            amount: amount,
            date: now,
          ),
        );
      }
    });

    await saveLocal();
    await syncCloud(showMessage: false);
    await publishPlans([c]);
  }

  Future<void> editClient(WiFiClient c) async {
    final name = TextEditingController(text: c.name);
    final phone = TextEditingController(text: c.phone);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nom du client'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (ok != true || name.text.trim().isEmpty) return;
    setState(() {
      c.name = name.text.trim();
      c.phone = phone.text.trim();
    });
    await saveLocal();
    await syncCloud(showMessage: false);
  }

  Future<void> addPayment(WiFiClient client) async {
    final controller = TextEditingController(text: '${client.price}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Paiement • ${client.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Montant en FCFA'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final amount = int.tryParse(controller.text) ?? 0;
    if (amount <= 0) return;

    setState(() {
      payments.insert(
        0,
        WiFiPayment(
          id: newId(),
          clientId: client.id,
          clientName: client.name,
          amount: amount,
          date: DateTime.now(),
        ),
      );
    });
    await saveLocal();
    await syncCloud(showMessage: false);
  }

  Future<void> toggleArchive(WiFiClient client) async {
    setState(() => client.archived = !client.archived);
    await saveLocal();
    await syncCloud(showMessage: false);
    await publishPlans([client]);
  }

  void openClient(WiFiClient c) {
    final pays = payments.where((p) => p.clientId == c.id).toList();
    Widget info(String l, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(l, style: const TextStyle(color: Colors.black54)),
              ),
              Expanded(
                child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(c.name,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              info('Téléphone', c.phone.isEmpty ? '—' : c.phone),
              info('Code client', c.code),
              info('Statut', c.active ? 'Actif' : 'Expiré'),
              info('Début', formatDateTime(c.createdAt)),
              info('Expiration', formatDateTime(c.expiresAt)),
              info('Temps restant', remaining(c)),
              info('Prix', '${c.price} FCFA'),
              info('Durée', '${c.durationDays} jours'),
              if (c.archived) info('Archivage', 'Client archivé'),
              const SizedBox(height: 10),
              const Text('Paiements',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              if (pays.isEmpty) const Text('Aucun paiement enregistré'),
              ...pays.map((p) => Text(
                  '${formatDateTime(p.date)} • ${p.amount} FCFA')),
              if (c.history.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Anciens forfaits',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                ...c.history.map((h) {
                  final d = DateTime.tryParse('${h['start']}');
                  return Text(
                      '${d == null ? '—' : formatDateTime(d)} • ${h['durationDays']} j • ${h['price']} FCFA');
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void openPayments() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Paiements')),
        body: paymentsPage(),
      ),
    ));
  }

  // ---------- GOOGLE & CLOUD ----------

  Future<void> signInGoogle() async {
    if (busy) return;
    if (!firebaseReady) {
      setState(() => message = 'Firebase indisponible sur cet appareil.');
      return;
    }
    setState(() {
      busy = true;
      message = 'Connexion Google…';
    });

    try {
      final google = await GoogleSignIn().signIn();
      if (google == null) {
        message = 'Connexion annulée';
      } else {
        final auth = await google.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: auth.accessToken,
          idToken: auth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
        message = 'Google connecté';
      }
    } catch (e) {
      message = 'Connexion impossible : ${friendlyError(e)}';
    }

    if (mounted) setState(() => busy = false);
    if (user != null) await syncCloud(publishAll: true);
  }

  Future<void> signOutGoogle() async {
    try {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('Déconnexion : $e');
    }
    if (mounted) {
      setState(() => message = 'Déconnecté : données locales conservées');
    }
  }

  // Empêche de mélanger les données de deux gestionnaires sur un même téléphone.
  Future<bool> ensureOwner(User u) async {
    final p = await SharedPreferences.getInstance();
    final owner = p.getString('hbb_owner_uid');
    if (owner == null || owner == u.uid) {
      await p.setString('hbb_owner_uid', u.uid);
      return true;
    }
    if (clients.isEmpty && payments.isEmpty) {
      await p.setString('hbb_owner_uid', u.uid);
      return true;
    }
    if (!mounted) return false;
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Données d\'un autre compte'),
        content: const Text(
          'Les données de cet appareil appartiennent à un autre compte. '
          'Les remplacer par celles du compte connecté ? Une sauvegarde locale est conservée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, me déconnecter'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
    if (replace == true) {
      await p.setString(
        'hbb_backup_$owner',
        jsonEncode({
          'clients': clients.map((e) => e.toMap()).toList(),
          'payments': payments.map((e) => e.toMap()).toList(),
        }),
      );
      setState(() {
        clients.clear();
        payments.clear();
      });
      await p.setString('hbb_owner_uid', u.uid);
      await saveLocal();
      return true;
    }
    await signOutGoogle();
    return false;
  }

  Future<void> syncCloud({
    bool showMessage = true,
    bool publishAll = false,
  }) async {
    final current = user;
    if (current == null) {
      if (showMessage && mounted) {
        setState(() => message = 'Connecte Google pour synchroniser');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    if (busy) return;
    if (!await ensureOwner(current)) return;

    setState(() {
      busy = true;
      message = 'Synchronisation en cours…';
    });

    var ok = false;
    try {
      final root =
          FirebaseFirestore.instance.collection('users').doc(current.uid);
      final clientCol = root.collection('clients');
      final paymentCol = root.collection('payments');

      // 1) Fusion : on AJOUTE ce qui manque en local, on ne supprime rien.
      final cloudClients = await clientCol.get();
      final localClientIds = clients.map((c) => c.id).toSet();
      for (final doc in cloudClients.docs) {
        final data = doc.data();
        final id = '${data['id'] ?? doc.id}';
        if (!localClientIds.contains(id)) {
          clients.add(WiFiClient.fromMap({...data, 'id': id}));
        }
      }

      final cloudPayments = await paymentCol.get();
      final localPaymentIds = payments.map((p) => p.id).toSet();
      for (final doc in cloudPayments.docs) {
        final data = doc.data();
        final id = '${data['id'] ?? doc.id}';
        if (!localPaymentIds.contains(id)) {
          payments.add(WiFiPayment.fromMap({...data, 'id': id}));
        }
      }

      // 2) Envoi par lots de 400 (limite Firestore : 500 par lot).
      final ops = <void Function(WriteBatch)>[];
      for (final c in clients) {
        ops.add((b) => b.set(clientCol.doc(c.id), c.toMap()));
      }
      for (final p in payments) {
        ops.add((b) => b.set(paymentCol.doc(p.id), p.toMap()));
      }
      for (var i = 0; i < ops.length; i += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (final op in ops.skip(i).take(400)) {
          op(batch);
        }
        await batch.commit();
      }

      await saveLocal();
      ok = true;
      message =
          'Synchronisation réussie : ${clients.length} client(s), ${payments.length} paiement(s)';
    } catch (e) {
      message =
          'Échec de la synchronisation : ${friendlyError(e)}. Données locales conservées.';
    }

    if (mounted) setState(() => busy = false);

    if (ok) {
      final p = await SharedPreferences.getInstance();
      final flagKey = 'hbb_plans_published_${current.uid}';
      if (publishAll || p.getBool(flagKey) != true) {
        final done = await publishPlans(List.of(clients));
        if (done) await p.setBool(flagKey, true);
      }
    }

    if (mounted && showMessage) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // Publie la fiche publique (espace client). Ne contient ni nom ni téléphone.
  Future<bool> publishPlans(List<WiFiClient> list) async {
    if (user == null || list.isEmpty) return false;
    final failed = <String>[];
    var changedCode = false;
    String? lastError;

    for (final c in list) {
      try {
        await PublicPlanService.publish(
          code: c.code,
          label: c.planLabel,
          createdAt: c.createdAt,
          expiresAt: c.expiresAt,
          price: c.price,
          archived: c.archived,
        );
      } on CodeCollisionException {
        // Code déjà pris par un autre gestionnaire : nouveau code unique.
        try {
          c.code = await PublicPlanService.createUniqueCodeAndPublish(
            label: c.planLabel,
            createdAt: c.createdAt,
            expiresAt: c.expiresAt,
            price: c.price,
          );
          changedCode = true;
        } catch (e) {
          failed.add(c.name);
          lastError = friendlyError(e);
        }
      } catch (e) {
        failed.add(c.name);
        lastError = friendlyError(e);
      }
    }

    if (changedCode) {
      await saveLocal();
      final cur = user;
      if (cur != null) {
        try {
          final col = FirebaseFirestore.instance
              .collection('users')
              .doc(cur.uid)
              .collection('clients');
          for (final c in list) {
            await col.doc(c.id).set(c.toMap());
          }
        } catch (e) {
          lastError = friendlyError(e);
        }
      }
    }

    if (mounted) {
      setState(() {
        if (failed.isNotEmpty) {
          message =
              'Fiche client non publiée pour : ${failed.join(', ')} ($lastError)';
        } else if (changedCode) {
          message =
              'Un code était déjà utilisé : un nouveau code a été attribué. Vérifie la fiche du client.';
        }
      });
    }
    return failed.isEmpty;
  }

  // ---------- INTERFACE ----------

  @override
  Widget build(BuildContext context) {
    final visible = clients.where((c) => !c.archived).toList();

    final Widget body = showAccount
        ? accountPage()
        : tab == 3
            ? const CustomerSpaceScreen()
            : tab == 2
                ? archivesPage()
                : tab == 1
                    ? clientsPage(visible)
                    : dashboard(visible);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HBB WiFi Manager',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              'HBB DIGITAL',
              style: TextStyle(fontSize: 11, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Compte et sauvegarde',
            onPressed: () => setState(() => showAccount = !showAccount),
            icon: Icon(
              user == null
                  ? Icons.account_circle_outlined
                  : Icons.account_circle_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Synchroniser',
            onPressed: busy ? null : () => syncCloud(publishAll: true),
            icon: const Icon(Icons.cloud_sync_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey('$tab-$showAccount'),
          child: body,
        ),
      ),
      floatingActionButton: ((tab == 0 || tab == 1) && !showAccount)
          ? FloatingActionButton.extended(
              onPressed: addClient,
              backgroundColor: orange,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nouveau client'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() {
          tab = v;
          showAccount = false;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_rounded),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_rounded),
            label: 'Archives',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_pin_circle_rounded),
            label: 'Espace client',
          ),
        ],
      ),
    );
  }

  Widget dashboard(List<WiFiClient> visible) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [orange, Color(0xFFFF9B45)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'REVENUS ENCAISSÉS',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                money,
                style: const TextStyle(
                  fontSize: 27,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: ['Hier', '7 jours', '30 jours', 'Total']
                    .map((p) => ChoiceChip(
                          label: Text(p),
                          selected: period == p,
                          onSelected: (_) => setState(() => period = p),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: metric(
                'Clients actifs',
                '${visible.where((c) => c.active).length}',
                Icons.wifi_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: metric(
                'Total clients',
                '${clients.length}',
                Icons.people_alt_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: openPayments,
          icon: const Icon(Icons.payments_rounded),
          label: const Text('Historique des paiements'),
        ),
        const SizedBox(height: 22),
        sectionTitle('Clients récents'),
        if (visible.isEmpty)
          emptyState('Aucun client pour le moment')
        else
          ...visible.take(5).map(clientCard),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget clientsPage(List<WiFiClient> visible) {
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? visible
        : visible
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.phone.toLowerCase().contains(q) ||
                c.code.toLowerCase().contains(q))
            .toList();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Tous les clients'),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            hintText: 'Rechercher (nom, téléphone, code)',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${list.length} client(s)',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          emptyState(visible.isEmpty
              ? 'Ajoute ton premier client'
              : 'Aucun résultat')
        else
          ...list.map(clientCard),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget archivesPage() {
    final archived = clients.where((c) => c.archived).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Archives'),
        if (archived.isEmpty)
          emptyState('Aucun client archivé')
        else
          ...archived.map(clientCard),
      ],
    );
  }

  Widget paymentsPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Historique des paiements'),
        Text('Revenus sélectionnés : $money'),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          emptyState('Aucun paiement enregistré')
        else
          ...payments.where((p) => inPeriod(p.date)).map((p) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFFFE6D5),
                      child: Icon(Icons.payments_rounded, color: orange),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.clientName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${p.date.day}/${p.date.month}/${p.date.year}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${p.amount} FCFA',
                      style: const TextStyle(
                        color: orange,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget accountPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Compte et sauvegarde Google'),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, color: orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      user?.email ?? 'Google non connecté',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(message),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : user == null
                          ? signInGoogle
                          : () => syncCloud(publishAll: true),
                  icon: Icon(user == null ? Icons.login : Icons.cloud_sync),
                  label: Text(
                    busy
                        ? 'Patiente…'
                        : user == null
                            ? 'Connecter Google'
                            : 'Synchroniser maintenant',
                  ),
                ),
              ),
              if (user != null)
                TextButton(
                  onPressed: signOutGoogle,
                  child: const Text('Déconnecter Google'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => showAccount = false),
          child: const Text('Retour'),
        ),
      ],
    );
  }

  Widget clientCard(WiFiClient c) {
    return GestureDetector(
      onTap: () => openClient(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFFE6D5),
                  child: Text(
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: orange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        c.phone.isEmpty ? 'Pas de téléphone' : c.phone,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Icon(
                  c.active ? Icons.wifi : Icons.wifi_off,
                  color: c.active ? Colors.green : Colors.red,
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.key_rounded, color: orange, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.code,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${c.price} FCFA',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(remaining(c))),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'pay') addPayment(c);
                    if (v == 'renew') renewClient(c);
                    if (v == 'edit') editClient(c);
                    if (v == 'archive') toggleArchive(c);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'pay',
                      child: Text('Ajouter un paiement'),
                    ),
                    const PopupMenuItem(
                      value: 'renew',
                      child: Text('Renouveler le forfait'),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Modifier'),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(c.archived ? 'Restaurer' : 'Archiver'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget metric(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: orange),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(title, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  Widget sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: ink,
          ),
        ),
      );

  Widget emptyState(String text) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(Icons.inbox_rounded, size: 38, color: orange),
            const SizedBox(height: 10),
            Text(text),
          ],
        ),
      );
}
