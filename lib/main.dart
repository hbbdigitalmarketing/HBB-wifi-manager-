
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

const clientsKey = 'hbb_clients';
const backupKey = 'hbb_clients_backup';
const paymentsKey = 'hbb_payments';
const archivesKey = 'hbb_archives';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool firebaseReady = false;

  try {
    await Firebase.initializeApp()
        .timeout(const Duration(seconds: 12));
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase indisponible : $e');
  }

  runApp(HBBApp(firebaseReady: firebaseReady));
}

class HBBApp extends StatelessWidget {
  final bool firebaseReady;

  const HBBApp({super.key, required this.firebaseReady});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HBB WI-FI MANAGER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(seedColor: orange),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.88),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      home: HomePage(firebaseReady: firebaseReady),
    );
  }
}

String formatMoney(int amount) {
  final s = amount.toString();
  final out = StringBuffer();

  for (var i = 0; i < s.length; i++) {
    out.write(s[i]);
    if ((s.length - i - 1) % 3 == 0 && i != s.length - 1) {
      out.write(' ');
    }
  }

  return '${out.toString()} FCFA';
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} '
      '${two(d.hour)}:${two(d.minute)}';
}

String remaining(Duration d) {
  if (d.isNegative || d == Duration.zero) return 'Expiré';
  if (d.inDays > 0) {
    return '${d.inDays} j ${d.inHours % 24} h';
  }
  if (d.inHours > 0) {
    return '${d.inHours} h ${d.inMinutes % 60} min';
  }
  return '${d.inMinutes} min';
}

String generateCode(Set<String> existing) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();

  while (true) {
    final code = List.generate(
      8,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    if (!existing.contains(code)) return code;
  }
}

class Client {
  String id;
  String name;
  String phone;
  String code;
  int price;
  DateTime createdAt;
  DateTime start;
  DateTime end;
  bool archived;

  Client({
    required this.id,
    required this.name,
    required this.phone,
    required this.code,
    required this.price,
    required this.createdAt,
    required this.start,
    required this.end,
    this.archived = false,
  });

  bool get active => DateTime.now().isBefore(end);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'code': code,
    'price': price,
    'createdAt': createdAt.toIso8601String(),
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'archived': archived,
  };

  factory Client.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();

    DateTime readDate(dynamic v, DateTime fallback) =>
        DateTime.tryParse('$v') ?? fallback;

    final start = readDate(j['start'] ?? j['startDate'], now);

    return Client(
      id: '${j['id'] ?? j['code'] ?? now.microsecondsSinceEpoch}',
      name: '${j['name'] ?? j['nom'] ?? 'Client'}',
      phone: '${j['phone'] ?? j['telephone'] ?? ''}',
      code: '${j['code'] ?? ''}',
      price: int.tryParse('${j['price'] ?? j['prix'] ?? 0}') ?? 0,
      createdAt: readDate(j['createdAt'], start),
      start: start,
      end: readDate(j['end'] ?? j['endDate'], start),
      archived: j['archived'] == true,
    );
  }
}

class Payment {
  final String id;
  final String clientId;
  final String clientName;
  final int amount;
  final DateTime date;
  final String method;

  Payment({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.amount,
    required this.date,
    required this.method,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientId': clientId,
    'clientName': clientName,
    'amount': amount,
    'date': date.toIso8601String(),
    'method': method,
  };

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: '${j['id']}',
    clientId: '${j['clientId'] ?? ''}',
    clientName: '${j['clientName'] ?? ''}',
    amount: int.tryParse('${j['amount'] ?? 0}') ?? 0,
    date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
    method: '${j['method'] ?? 'Autre'}',
  );
}

class HomePage extends StatefulWidget {
  final bool firebaseReady;

  const HomePage({super.key, required this.firebaseReady});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver {
  final List<Client> clients = [];
  final List<Payment> payments = [];

  bool loading = true;
  bool busy = false;
  String search = '';
  int tab = 0;

  User? get user => widget.firebaseReady
      ? FirebaseAuth.instance.currentUser
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadData();
    }
  }

  void notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  List<dynamic>? decodeList(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final primary = prefs.getString(clientsKey);
      final backup = prefs.getString(backupKey);

      final primaryList = decodeList(primary);
      final backupList = decodeList(backup);

      // Récupère le secours si la principale est absente,
      // illisible ou vide alors que le secours contient des clients.
      final useBackup = backupList != null &&
          backupList.isNotEmpty &&
          (primaryList == null || primaryList.isEmpty);

      final source = useBackup ? backupList : primaryList;

      clients.clear();
      for (final item in source ?? []) {
        try {
          clients.add(Client.fromJson(
            Map<String, dynamic>.from(item as Map),
          ));
        } catch (_) {}
      }

      payments.clear();
      for (final item in decodeList(prefs.getString(paymentsKey)) ?? []) {
        try {
          payments.add(Payment.fromJson(
            Map<String, dynamic>.from(item as Map),
          ));
        } catch (_) {}
      }

      if (useBackup) {
        final encoded = jsonEncode(
          clients.map((c) => c.toJson()).toList(),
        );
        await prefs.setString(clientsKey, encoded);
      }
    } catch (e) {
      debugPrint('Erreur de lecture : $e');
      notify('Lecture impossible. Les données ne doivent pas être supprimées.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();

    final encodedClients = jsonEncode(
      clients.map((c) => c.toJson()).toList(),
    );
    final encodedPayments = jsonEncode(
      payments.map((p) => p.toJson()).toList(),
    );

    // Vérifie la copie de secours avant la copie principale.
    final backupOk = await prefs.setString(backupKey, encodedClients);
    if (!backupOk || prefs.getString(backupKey) != encodedClients) {
      throw Exception('Copie de secours non confirmée');
    }

    final mainOk = await prefs.setString(clientsKey, encodedClients);
    if (!mainOk || prefs.getString(clientsKey) != encodedClients) {
      throw Exception('Sauvegarde principale non confirmée');
    }

    final paymentsOk = await prefs.setString(paymentsKey, encodedPayments);
    if (!paymentsOk ||
        prefs.getString(paymentsKey) != encodedPayments) {
      throw Exception('Sauvegarde des paiements non confirmée');
    }
  }

  Future<void> loginGoogle() async {
    if (!widget.firebaseReady || busy) {
      notify('Firebase est indisponible pour le moment.');
      return;
    }

    setState(() => busy = true);

    try {
      final account = await GoogleSignIn().signIn();
      if (account == null) return;

      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      notify('Connexion Google réussie. Vérifie la synchronisation avant de changer de téléphone.');
      if (mounted) setState(() {});
    } catch (e) {
      notify('Connexion impossible : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    if (user == null) return;

    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text(
          'Les données locales resteront sur ce téléphone. '
          'Veux-tu continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );

    if (keep != true) return;

    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      if (mounted) setState(() {});
    } catch (e) {
      notify('Déconnexion impossible : $e');
    }
  }

  Future<void> addClient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final price = TextEditingController(text: '0');
    final duration = TextEditingController(text: '30');
    String unit = 'Jours';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, updateDialog) => AlertDialog(
          title: const Text('Nouveau client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Montant payé (FCFA)',
                  ),
                ),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: unit,
                  decoration: const InputDecoration(labelText: 'Unité'),
                  items: const [
                    DropdownMenuItem(value: 'Heures', child: Text('Heures')),
                    DropdownMenuItem(value: 'Jours', child: Text('Jours')),
                  ],
                  onChanged: (v) {
                    if (v != null) updateDialog(() => unit = v);
                  },
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

    if (confirmed != true || !mounted) return;

    final n = name.text.trim();
    final p = phone.text.trim();
    final amount = int.tryParse(price.text.trim());
    final count = int.tryParse(duration.text.trim());

    if (n.isEmpty || amount == null || amount < 0 ||
        count == null || count <= 0) {
      notify('Vérifie le nom, le montant et la durée.');
      return;
    }

    final now = DateTime.now();
    final end = unit == 'Heures'
        ? now.add(Duration(hours: count))
        : now.add(Duration(days: count));

    final client = Client(
      id: now.microsecondsSinceEpoch.toString(),
      name: n,
      phone: p,
      code: generateCode(clients.map((c) => c.code).toSet()),
      price: 0,
      createdAt: now,
      start: now,
      end: end,
    );

    clients.insert(0, client);

    try {
      // Le prix d'un client n'est pas automatiquement un revenu.
      if (amount > 0) {
        payments.add(Payment(
          id: 'PAY-${now.microsecondsSinceEpoch}',
          clientId: client.id,
          clientName: client.name,
          amount: amount,
          date: now,
          method: 'À préciser',
        ));
      }

      await saveData();
      if (mounted) setState(() {});
      notify('Client créé. Code : ${client.code}');
    } catch (e) {
      notify('Sauvegarde non confirmée. Vérifie les données avant de réessayer : $e');
    }
  }

  Future<void> recordPayment(Client client) async {
    final amount = TextEditingController();
    String method = 'Mobile Money';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, updateDialog) => AlertDialog(
          title: Text('Paiement — ${client.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Montant réellement reçu (FCFA)',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: method,
                items: const [
                  DropdownMenuItem(
                    value: 'Mobile Money',
                    child: Text('Mobile Money'),
                  ),
                  DropdownMenuItem(value: 'Espèces', child: Text('Espèces')),
                  DropdownMenuItem(
                    value: 'Virement bancaire',
                    child: Text('Virement bancaire'),
                  ),
                  DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                ],
                onChanged: (v) {
                  if (v != null) updateDialog(() => method = v);
                },
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
      ),
    );

    if (confirmed != true) return;
    final value = int.tryParse(amount.text.trim());

    if (value == null || value <= 0) {
      notify('Le paiement doit être supérieur à zéro.');
      return;
    }

    final now = DateTime.now();
    payments.add(Payment(
      id: 'PAY-${now.microsecondsSinceEpoch}',
      clientId: client.id,
      clientName: client.name,
      amount: value,
      date: now,
      method: method,
    ));

    try {
      await saveData();
      if (mounted) setState(() {});
      notify('Paiement enregistré : ${formatMoney(value)}');
    } catch (e) {
      notify('Erreur de sauvegarde : $e');
    }
  }

  Future<void> archiveClient(Client client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archiver le client ?'),
        content: const Text(
          'Le client sera conservé dans les archives et pourra être restauré.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    client.archived = true;
    try {
      await saveData();
      if (mounted) setState(() {});
      notify('Client archivé.');
    } catch (e) {
      notify('Erreur de sauvegarde : $e');
    }
  }

  Future<void> restoreClient(Client client) async {
    client.archived = false;
    try {
      await saveData();
      if (mounted) setState(() {});
      notify('Client restauré.');
    } catch (e) {
      notify('Erreur de sauvegarde : $e');
    }
  }

  int revenue(DateTime from, DateTime to) => payments
      .where((p) =>
          !p.date.isBefore(from) && p.date.isBefore(to))
      .fold(0, (sum, p) => sum + p.amount);

  int get totalRevenue =>
      payments.fold(0, (sum, p) => sum + p.amount);

  Widget glassCard(Widget child) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget metric(String label, int value) => glassCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 8),
        Text(
          formatMoney(value),
          style: const TextStyle(
            color: orange,
            fontWeight: FontWeight.bold,
            fontSize: 21,
          ),
        ),
      ],
    ),
  );

  Widget dashboard() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'Bonjour 👋',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const Text('Gérez vos clients simplement'),
        const SizedBox(height: 12),
        metric(
          'Hier',
          revenue(
            today.subtract(const Duration(days: 1)),
            today,
          ),
        ),
        metric(
          '7 derniers jours',
          revenue(
            today.subtract(const Duration(days: 6)),
            today.add(const Duration(days: 1)),
          ),
        ),
        metric(
          '30 derniers jours',
          revenue(
            today.subtract(const Duration(days: 29)),
            today.add(const Duration(days: 1)),
          ),
        ),
        metric('Total encaissé', totalRevenue),
        Row(
          children: [
            Expanded(
              child: glassCard(Column(
                children: [
                  const Text('Clients actifs'),
                  Text(
                    '${clients.where((c) => !c.archived && c.active).length}',
                    style: const TextStyle(
                      fontSize: 25,
                      color: orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: glassCard(Column(
                children: [
                  const Text('Expirés'),
                  Text(
                    '${clients.where((c) => !c.archived && !c.active).length}',
                    style: const TextStyle(
                      fontSize: 25,
                      color: orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: addClient,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Ajouter un client'),
        ),
      ],
    );
  }

  Widget clientList({bool archived = false, bool expired = false}) {
    final list = clients.where((c) {
      if (c.archived != archived) return false;
      if (!archived && c.active == expired) return false;

      final q = search.trim().toLowerCase();
      return q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q) ||
          c.code.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              hintText: 'Rechercher un client...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Aucun client trouvé'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final c = list[i];
                    return glassCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  c.archived
                                      ? 'Archivé'
                                      : c.active
                                          ? 'Actif'
                                          : 'Expiré',
                                ),
                                backgroundColor: c.active && !c.archived
                                    ? const Color(0xFFE0F7E9)
                                    : const Color(0xFFFFE4D6),
                              ),
                            ],
                          ),
                          Text('Code : ${c.code}'),
                          Text('Téléphone : ${c.phone}'),
                          Text('Début : ${formatDate(c.start)}'),
                          Text('Fin : ${formatDate(c.end)}'),
                          Text('Temps restant : ${remaining(c.end.difference(DateTime.now()))}'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: [
                              if (archived)
                                TextButton.icon(
                                  onPressed: () => restoreClient(c),
                                  icon: const Icon(Icons.restore),
                                  label: const Text('Restaurer'),
                                )
                              else ...[
                                TextButton.icon(
                                  onPressed: () => recordPayment(c),
                                  icon: const Icon(Icons.payments_outlined),
                                  label: const Text('Paiement'),
                                ),
                                TextButton.icon(
                                  onPressed: () => archiveClient(c),
                                  icon: const Icon(Icons.archive_outlined),
                                  label: const Text('Archiver'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget paymentsView() {
    final sorted = payments.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        metric('Total encaissé', totalRevenue),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucun paiement enregistré.'),
          ),
        for (final p in sorted)
          glassCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.clientName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(formatMoney(p.amount)),
                Text(formatDate(p.date)),
                Text('Moyen : ${p.method}'),
                Text('Référence : ${p.id}'),
              ],
            ),
          ),
      ],
    );
  }

  Widget settingsView() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      glassCard(const ListTile(
        leading: Icon(Icons.wifi, color: orange),
        title: Text('HBB WI-FI MANAGER'),
        subtitle: Text('Gérez vos clients simplement'),
      )),
      glassCard(ListTile(
        leading: const Icon(Icons.cloud_outlined, color: orange),
        title: const Text('Compte Google'),
        subtitle: Text(
          user == null ? 'Mode local' : user!.email ?? 'Connecté',
        ),
        trailing: user == null
            ? const Icon(Icons.login)
            : const Icon(Icons.verified_user_outlined),
        onTap: user == null ? loginGoogle : logout,
      )),
      glassCard(ListTile(
        leading: const Icon(Icons.save_outlined, color: orange),
        title: const Text('Vérifier la sauvegarde locale'),
        onTap: () async {
          try {
            await saveData();
            notify('Sauvegarde locale vérifiée.');
          } catch (e) {
            notify('Erreur : $e');
          }
        },
      )),
      glassCard(ListTile(
        leading: const Icon(Icons.info_outline, color: orange),
        title: const Text('Informations'),
        subtitle: const Text(
          'Version de base — les fonctions Cloud et la sécurité '
          'doivent être configurées et testées séparément.',
        ),
      )),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = [
      dashboard(),
      clientList(),
      paymentsView(),
      clientList(archived: true),
      settingsView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HBB WI-FI MANAGER',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (user == null)
            IconButton(
              tooltip: 'Connexion Google',
              onPressed: busy ? null : loginGoogle,
              icon: const Icon(Icons.login, color: orange),
            )
          else
            IconButton(
              tooltip: 'Déconnexion',
              onPressed: logout,
              icon: const Icon(Icons.account_circle, color: orange),
            ),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              backgroundColor: orange,
              foregroundColor: Colors.white,
              onPressed: addClient,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() {
            tab = i;
            search = '';
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tableau de bord',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Paiements',
          ),
          NavigationDestination(
            icon: Icon(Icons.archive_outlined),
            selectedIcon: Icon(Icons.archive),
            label: 'Archives',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}
