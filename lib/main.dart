
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

const orange = Color(0xFFFF6A00);
const cream = Color(0xFFFFF8F0);
const ink = Color(0xFF29231F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
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
      home: const ManagerPage(),
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

  WiFiClient({
    required this.id,
    required this.name,
    required this.phone,
    required this.code,
    required this.price,
    required this.durationDays,
    required this.createdAt,
    this.archived = false,
  });

  DateTime get expiresAt =>
      createdAt.add(Duration(days: durationDays));

  int get remainingSeconds =>
      expiresAt.difference(DateTime.now()).inSeconds;

  bool get active => remainingSeconds > 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'code': code,
        'price': price,
        'durationDays': durationDays,
        'createdAt': createdAt.toIso8601String(),
        'archived': archived,
      };

  factory WiFiClient.fromMap(Map<String, dynamic> m) {
    return WiFiClient(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      code: '${m['code'] ?? ''}',
      price: (m['price'] as num?)?.toInt() ?? 0,
      durationDays:
          (m['durationDays'] as num?)?.toInt() ?? 30,
      createdAt: DateTime.tryParse('${m['createdAt']}') ??
          DateTime.now(),
      archived: m['archived'] == true,
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

  factory WiFiPayment.fromMap(Map<String, dynamic> m) =>
      WiFiPayment(
        id: '${m['id'] ?? ''}',
        clientId: '${m['clientId'] ?? ''}',
        clientName: '${m['clientName'] ?? ''}',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        date: DateTime.tryParse('${m['date']}') ??
            DateTime.now(),
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
  String message = 'Données enregistrées sur cet appareil';

  User? get user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    loadLocal();
    FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> loadLocal() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString('hbb_clients');
    final pay = p.getString('hbb_payments');

    if (c != null) {
      clients
        ..clear()
        ..addAll((jsonDecode(c) as List).map(
          (e) => WiFiClient.fromMap(
            Map<String, dynamic>.from(e),
          ),
        ));
    }
    if (pay != null) {
      payments
        ..clear()
        ..addAll((jsonDecode(pay) as List).map(
          (e) => WiFiPayment.fromMap(
            Map<String, dynamic>.from(e),
          ),
        ));
    }
    if (mounted) setState(() {});
  }

  Future<void> saveLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'hbb_clients',
      jsonEncode(clients.map((e) => e.toMap()).toList()),
    );
    await p.setString(
      'hbb_payments',
      jsonEncode(payments.map((e) => e.toMap()).toList()),
    );
  }

  String get money =>
      '${payments.where((p) => inPeriod(p.date)).fold<int>(0, (s, p) => s + p.amount)} FCFA';

  bool inPeriod(DateTime date) {
    final now = DateTime.now();
    switch (period) {
      case 'Hier':
        final yesterday = DateTime(now.year, now.month, now.day - 1);
        return date.year == yesterday.year &&
            date.month == yesterday.month &&
            date.day == yesterday.day;
      case '7 jours':
        return date.isAfter(now.subtract(const Duration(days: 7)));
      case '30 jours':
        return date.isAfter(now.subtract(const Duration(days: 30)));
      default:
        return true;
    }
  }

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}';

  String newCode() {
    final n = DateTime.now().microsecondsSinceEpoch % 1000000;
    return 'HBB-${n.toString().padLeft(6, '0')}';
  }

  Future<void> addClient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final price = TextEditingController(text: '1000');
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
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix en FCFA',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durée en jours',
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

    if (ok != true || name.text.trim().isEmpty) return;

    final amount = int.tryParse(price.text) ?? 0;
    final duration = int.tryParse(days.text) ?? 30;
    final id = newId();

    final client = WiFiClient(
      id: id,
      name: name.text.trim(),
      phone: phone.text.trim(),
      code: newCode(),
      price: amount,
      durationDays: duration < 1 ? 1 : duration,
      createdAt: DateTime.now(),
    );

    setState(() {
      clients.insert(0, client);
      if (amount > 0) {
        payments.insert(
          0,
          WiFiPayment(
            id: newId(),
            clientId: id,
            clientName: client.name,
            amount: amount,
            date: DateTime.now(),
          ),
        );
      }
    });

    await saveLocal();
    await syncCloud(showMessage: false);
  }

  Future<void> addPayment(WiFiClient client) async {
    final controller =
        TextEditingController(text: '${client.price}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Paiement • ${client.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Montant en FCFA',
          ),
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
  }

  Future<void> signInGoogle() async {
    if (busy) return;
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
      message = 'Connexion impossible : vérifie Firebase et Google';
    }

    if (mounted) setState(() => busy = false);
    if (user != null) await syncCloud();
  }

  Future<void> signOutGoogle() async {
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    if (mounted) {
      setState(() {
        message = 'Déconnecté : données locales conservées';
      });
    }
  }

  Future<void> syncCloud({bool showMessage = true}) async {
    final current = user;
    if (current == null || busy) return;

    setState(() {
      busy = true;
      message = 'Synchronisation en cours…';
    });

    try {
      final root = FirebaseFirestore.instance
          .collection('users')
          .doc(current.uid);

      final clientCol = root.collection('clients');
      final paymentCol = root.collection('payments');

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

      final batch = FirebaseFirestore.instance.batch();

      for (final c in clients) {
        batch.set(clientCol.doc(c.id), c.toMap());
      }
      for (final p in payments) {
        batch.set(paymentCol.doc(p.id), p.toMap());
      }

      await batch.commit();
      await saveLocal();

      message = 'Synchronisation Google réussie';
    } catch (e) {
      message = 'Erreur cloud. Les données locales restent conservées.';
    }

    if (mounted) {
      setState(() => busy = false);
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  String remaining(WiFiClient c) {
    if (!c.active) return 'Expiré';
    final d = c.remainingSeconds ~/ 86400;
    final h = (c.remainingSeconds % 86400) ~/ 3600;
    final m = (c.remainingSeconds % 3600) ~/ 60;
    if (d > 0) return '$d j $h h restantes';
    if (h > 0) return '$h h $m min restantes';
    return '$m min restantes';
  }

  @override
  Widget build(BuildContext context) {
    final visible = clients.where((c) => !c.archived).toList();

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
            tooltip: 'Synchroniser',
            onPressed: busy ? null : () => syncCloud(),
            icon: const Icon(Icons.cloud_sync_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: tab == 3
            ? customerSpace()
            : tab == 2
                ? archivesPage()
                : tab == 1
                    ? paymentsPage()
                    : tab == 0
                        ? dashboard(visible)
                        : clientsPage(visible),
      ),
      floatingActionButton: (tab == 0 || tab == 1)
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
        onDestinationSelected: (v) => setState(() => tab = v),
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
                          onSelected: (_) =>
                              setState(() => period = p),
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
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Tous les clients'),
        Text(
          '${visible.length} client(s)',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          emptyState('Ajoute ton premier client')
        else
          ...visible.map(clientCard),
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
          ...payments.where((p) => inPeriod(p.date)).map((p) =>
              Container(
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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${p.date.day}/${p.date.month}/${p.date.year}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${p.amount} F',
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

  Widget customerSpace() {
    final c = clients.where((c) => !c.archived).toList();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Espace client'),
        const Text(
          'Recherche le code client pour consulter sa durée restante.',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              const Icon(Icons.wifi_rounded, size: 42, color: orange),
              const SizedBox(height: 8),
              const Text(
                'HBB WiFi',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text('Les informations de connexion'),
              const SizedBox(height: 16),
              ...c.map((client) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFE6D5),
                      child: Icon(Icons.person, color: orange),
                    ),
                    title: Text(client.name),
                    subtitle: Text(
                      'Code : ${client.code}\n${remaining(client)}',
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      client.active
                          ? Icons.check_circle
                          : Icons.timer_off,
                      color: client.active ? Colors.green : Colors.red,
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 20),
        sectionTitle('Sauvegarde Google'),
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
                          : () => syncCloud(),
                  icon: Icon(
                    user == null ? Icons.login : Icons.cloud_sync,
                  ),
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
      ],
    );
  }

  Widget clientCard(WiFiClient c) {
    return Container(
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
                  if (v == 'archive') toggleArchive(c);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'pay',
                    child: Text('Ajouter un paiement'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      c.archived ? 'Restaurer' : 'Archiver',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
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
