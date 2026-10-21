import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const orange = Color(0xFFFF6A00);
const gold = Color(0xFFFFD45A);
const cream = Color(0xFFFFF8F0);
const ink = Color(0xFF30271F);

void main() => runApp(const HBBApp());

class HBBApp extends StatelessWidget {
  const HBBApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HBB WiFi Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: orange,
          brightness: Brightness.light,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class Client {
  String name;
  String phone;
  DateTime start;
  int durationHours;

  Client({
    required this.name,
    required this.phone,
    required this.start,
    required this.durationHours,
  });

  DateTime get expiry => start.add(Duration(hours: durationHours));

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'start': start.toIso8601String(),
        'durationHours': durationHours,
      };

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        name: j['name'] as String,
        phone: j['phone'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
        durationHours: j['durationHours'] as int,
      );
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: orange.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Client> clients = [];
  final searchController = TextEditingController();

  String search = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadClients();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadClients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('hbb_clients');

      if (saved != null) {
        final data = jsonDecode(saved) as List;
        clients.addAll(
          data.map(
            (e) => Client.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
      }
    } catch (_) {}

    if (mounted) setState(() => loading = false);
  }

  Future<void> saveClients() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'hbb_clients',
      jsonEncode(clients.map((c) => c.toJson()).toList()),
    );
  }

  String formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  String remaining(Client c) {
    final diff = c.expiry.difference(DateTime.now());

    if (diff.inSeconds <= 0) return 'Abonnement expiré';
    if (diff.inDays > 0) {
      return '${diff.inDays} j ${diff.inHours % 24} h restantes';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours} h ${diff.inMinutes % 60} min restantes';
    }
    return '${diff.inMinutes} min restantes';
  }

  Future<void> editClient({Client? client}) async {
    final name = TextEditingController(text: client?.name ?? '');
    final phone = TextEditingController(text: client?.phone ?? '');

    String unit = client != null && client.durationHours % 24 != 0
        ? 'Heures'
        : 'Jours';

    int duration = client == null
        ? 7
        : unit == 'Jours'
            ? client.durationHours ~/ 24
            : client.durationHours;

    final durationController =
        TextEditingController(text: duration.toString());
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          backgroundColor: const Color(0xFFFFFCF8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          title: Text(
            client == null ? 'Nouveau client' : 'Modifier le client',
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nom du client',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty
                            ? 'Nom obligatoire'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone (facultatif)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: unit,
                    decoration: const InputDecoration(labelText: 'Unité'),
                    items: const [
                      DropdownMenuItem(
                        value: 'Heures',
                        child: Text('Heures'),
                      ),
                      DropdownMenuItem(
                        value: 'Jours',
                        child: Text('Jours'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null || v == unit) return;
                      final n = int.tryParse(durationController.text) ?? 1;

                      refresh(() {
                        duration = v == 'Jours'
                            ? (n / 24).ceil().clamp(1, 3650)
                            : (n * 24).clamp(1, 87600);
                        unit = v;
                        durationController.text = duration.toString();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Durée en $unit',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1) return 'Durée invalide';
                      if (n > (unit == 'Jours' ? 3650 : 87600)) {
                        return 'Durée trop élevée';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;

                final n = int.parse(durationController.text);
                Navigator.pop(dialogContext, {
                  'name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'hours': unit == 'Jours' ? n * 24 : n,
                });
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    phone.dispose();
    durationController.dispose();

    if (result == null || !mounted) return;

    setState(() {
      if (client == null) {
        clients.insert(
          0,
          Client(
            name: result['name'] as String,
            phone: result['phone'] as String,
            start: DateTime.now(),
            durationHours: result['hours'] as int,
          ),
        );
      } else {
        client
          ..name = result['name'] as String
          ..phone = result['phone'] as String
          ..durationHours = result['hours'] as int;
      }
    });

    await saveClients();
  }

  Future<void> renew(Client c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renouveler l’abonnement ?'),
        content: Text(
          'Le nouvel abonnement de ${c.name} commencera maintenant.',
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
    );

    if (ok != true || !mounted) return;

    setState(() => c.start = DateTime.now());
    await saveClients();
  }

  Future<void> delete(Client c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce client ?'),
        content: Text('Supprimer ${c.name} de cette application ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => clients.remove(c));
    await saveClients();
  }

  Widget stat(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget clientCard(Client c, int index) {
    final expired = !c.expiry.isAfter(DateTime.now());
    final statusColor = expired ? Colors.red.shade700 : Colors.green.shade700;

    return TweenAnimationBuilder<double>(
      key: ValueKey('${c.name}_${c.start}_$index'),
      tween: Tween(begin: 0.94, end: 1),
      duration: Duration(milliseconds: 280 + (index % 4) * 50),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(scale: value, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE5C9), gold],
                      ),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: orange,
                        fontSize: 21,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        Text(
                          c.phone.isEmpty ? 'Téléphone non renseigné' : c.phone,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      expired ? 'Expiré' : 'Actif',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _detail(Icons.login_rounded, 'Début', formatDate(c.start)),
              const SizedBox(height: 10),
              _detail(
                Icons.event_available_rounded,
                'Expiration',
                formatDate(c.expiry),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.hourglass_bottom_rounded, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remaining(c),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 25),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => editClient(client: c),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                  ),
                  TextButton.icon(
                    onPressed: () => renew(c),
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    label: const Text('Renouveler'),
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    onPressed: () => delete(c),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = clients.where((c) {
      final query = search.toLowerCase().trim();
      return c.name.toLowerCase().contains(query) ||
          c.phone.toLowerCase().contains(query);
    }).toList();

    final active =
        clients.where((c) => c.expiry.isAfter(DateTime.now())).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [orange, gold],
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: orange.withValues(alpha: 0.20),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.wifi_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HBB WiFi Manager',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'HBB DIGITAL',
                    style: TextStyle(
                      fontSize: 10,
                      color: orange,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => editClient(),
            icon: const Icon(Icons.person_add_alt_1, color: orange),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: orange,
        foregroundColor: Colors.white,
        onPressed: () => editClient(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter un client'),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: orange),
            )
          : Stack(
              children: [
                Positioned(
                  top: 60,
                  right: -90,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  top: 320,
                  left: -110,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: orange.withValues(alpha: 0.055),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 15),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(21),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                orange,
                                Color(0xFFFF923D),
                                gold,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: orange.withValues(alpha: 0.22),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.wifi_rounded,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'GESTION DES ABONNEMENTS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  stat(
                                    '${clients.length}',
                                    'Clients',
                                    Icons.people_alt_outlined,
                                  ),
                                  const SizedBox(width: 12),
                                  stat(
                                    '$active',
                                    'Abonnements actifs',
                                    Icons.verified_outlined,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          onChanged: (v) => setState(() => search = v),
                          decoration: InputDecoration(
                            hintText: 'Rechercher un client...',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: orange,
                            ),
                            suffixIcon: search.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      setState(() => search = '');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(25),
                                  child: GlassPanel(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.wifi_rounded,
                                          color: orange,
                                          size: 48,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          clients.isEmpty
                                              ? 'Bienvenue dans HBB WiFi Manager'
                                              : 'Aucun client trouvé',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 17,
                                            color: ink,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Ajoutez un client pour commencer.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  100,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) =>
                                    clientCard(filtered[index], index),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
