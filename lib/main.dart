import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'main.dart' show ManagerPage, orange, cream, ink;

// ════════════════════════════════════════════════════════════════
//  OUTILS PARTAGÉS : transition, fond liquide, verre liquide
// ════════════════════════════════════════════════════════════════

Route<T> _fadeScaleRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 700),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Carte « Liquid Glass » : flou, reflet dégradé, bord lumineux.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blur;
  final double opacity;

  const _Glass({
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(14),
    this.blur = 18,
    this.opacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: orange.withValues(alpha: 0.20),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: opacity + 0.30),
                  Colors.white.withValues(alpha: opacity),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.75),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Icône avec dégradé orange.
Widget _gradientIcon(IconData icon, double size) {
  return ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (r) => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF9B45), Color(0xFFE85500)],
    ).createShader(r),
    child: Icon(icon, size: size, color: Colors.white),
  );
}

/// Fond fluide : dégradé + blobs qui se déforment + vagues liquides.
class _LiquidBackground extends StatelessWidget {
  final Animation<double> t;
  const _LiquidBackground({required this.t});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cream, Color(0xFFFFE6D2), Color(0xFFFFD2AE)],
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: _BlobsPainter(t),
            size: Size.infinite,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 220,
          child: RepaintBoundary(
            child: CustomPaint(painter: _WavePainter(t)),
          ),
        ),
      ],
    );
  }
}

class _Blob {
  final double x, y, radius, phase;
  final Color color;
  const _Blob(this.x, this.y, this.radius, this.phase, this.color);
}

class _BlobsPainter extends CustomPainter {
  final Animation<double> t;
  _BlobsPainter(this.t) : super(repaint: t);

  static const _blobs = [
    _Blob(0.12, 0.14, 120, 0.0, orange),
    _Blob(0.90, 0.26, 95, 1.3, Color(0xFFFFB27A)),
    _Blob(0.18, 0.62, 85, 2.1, Color(0xFFFF8A3D)),
    _Blob(0.88, 0.76, 130, 3.2, orange),
    _Blob(0.50, 0.95, 100, 4.4, Color(0xFFFFB27A)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final tt = 2 * math.pi * t.value;
    for (final b in _blobs) {
      final cx = b.x * size.width + math.sin(tt + b.phase) * 16;
      final cy = b.y * size.height + math.cos(tt + b.phase * 0.7) * 18;
      final path = Path();
      const steps = 64;
      for (var i = 0; i <= steps; i++) {
        final a = 2 * math.pi * i / steps;
        final r = b.radius *
            (1 +
                0.10 * math.sin(3 * a + tt + b.phase) +
                0.06 * math.sin(2 * a - tt + b.phase * 2));
        final p = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              b.color.withValues(alpha: 0.50),
              b.color.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: b.radius * 1.25),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlobsPainter old) => false;
}

class _WavePainter extends CustomPainter {
  final Animation<double> t;
  _WavePainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    for (var i = 0; i < 3; i++) {
      final path = Path()..moveTo(0, h);
      final dir = i.isEven ? 1.0 : -1.0;
      for (double x = 0; x <= w + 4; x += 4) {
        final y = h * (0.50 + 0.14 * i) +
            math.sin(2 * math.pi * (x / w) * (1 + i * 0.0 + (i + 1)) +
                    2 * math.pi * t.value * dir +
                    i) *
                (10 + i * 3);
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = orange.withValues(alpha: 0.10 + 0.06 * i),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => false;
}

// ════════════════════════════════════════════════════════════════
//  PAGE 1 : ÉCRAN DE BIENVENUE (animation d'intro)
// ════════════════════════════════════════════════════════════════

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _loop;

  late final Animation<double> _logoIn;
  late final Animation<double> _arcs;
  late final Animation<double> _hello;
  late final Animation<double> _title;
  late final Animation<double> _sub;
  late final Animation<double> _button;

  bool _leaving = false;

  Animation<double> _step(double a, double b, [Curve c = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..forward();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _logoIn = _step(0.0, 0.30, Curves.easeOutBack);
    _arcs = _step(0.18, 0.62);
    _hello = _step(0.42, 0.62);
    _title = _step(0.55, 0.82, Curves.easeOutBack);
    _sub = _step(0.74, 0.92);
    _button = _step(0.86, 1.0);
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _enter() {
    if (_leaving) return;
    _leaving = true;
    // Va vers la présentation de l'application (5 écrans)
    Navigator.of(context)
        .pushReplacement(_fadeScaleRoute(const OnboardingPage()));
  }

  Widget _slideFade(Animation<double> a, Widget child, {double dy = 0.4}) {
    return FadeTransition(
      opacity: a.drive(Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: const Interval(0, 1)))),
      child: SlideTransition(
        position: a.drive(Tween<Offset>(begin: Offset(0, dy), end: Offset.zero)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fond liquide fluide
          _LiquidBackground(t: _loop),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo Wi-Fi animé
                SizedBox(
                  width: 260,
                  height: 260,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _loop]),
                    builder: (context, _) => Transform.scale(
                      scale: 0.6 + 0.4 * _logoIn.value,
                      child: CustomPaint(
                        painter: _WifiPainter(
                          appear: _logoIn.value.clamp(0.0, 1.0),
                          reveal: _arcs.value,
                          pulse: _loop.value,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // « Bienvenue dans »
                _slideFade(
                  _hello,
                  Text(
                    'Bienvenue dans',
                    style: TextStyle(
                      fontSize: 20,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Titre en dégradé
                ScaleTransition(
                  scale: _title.drive(Tween(begin: 0.8, end: 1.0)),
                  child: FadeTransition(
                    opacity: _title.drive(Tween(begin: 0.0, end: 1.0)
                        .chain(CurveTween(curve: const Interval(0, 0.6)))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            colors: [
                              Color(0xFFE85500),
                              orange,
                              Color(0xFFFF9B45),
                            ],
                          ).createShader(r),
                          child: const Text(
                            'HBB WiFi Manager',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Sous-titre
                _slideFade(
                  _sub,
                  Column(
                    children: [
                      Text(
                        'HBB DIGITAL',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 5,
                          fontWeight: FontWeight.w800,
                          color: ink.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gérez vos forfaits Wi-Fi simplement',
                        style: TextStyle(
                          fontSize: 15,
                          color: ink.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                  dy: 0.3,
                ),

                const Spacer(flex: 2),

                // Bouton « Commencer »
                _slideFade(
                  _button,
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shadowColor: orange.withValues(alpha: 0.5),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 38, vertical: 17),
                    ),
                    onPressed: _enter,
                    label: const Text(
                      'Commencer',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    icon: AnimatedBuilder(
                      animation: _loop,
                      builder: (context, child) => Transform.translate(
                        offset:
                            Offset(4 * math.sin(2 * math.pi * _loop.value), 0),
                        child: child,
                      ),
                      child: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                  dy: 0.6,
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiPainter extends CustomPainter {
  final double appear; // apparition du badge (0..1)
  final double reveal; // apparition des arcs (0..1)
  final double pulse; // boucle d'animation (0..1)

  _WifiPainter({
    required this.appear,
    required this.reveal,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, size.height / 2);

    // Ondes qui se propagent autour du badge
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var i = 0; i < 3; i++) {
      final t = (pulse + i / 3) % 1.0;
      ring.color = orange.withValues(alpha: (1 - t) * 0.35 * reveal);
      canvas.drawCircle(center, w * 0.30 + t * w * 0.20, ring);
    }

    // Badge blanc avec ombre douce
    canvas.drawCircle(
      center.translate(0, 8),
      w * 0.30,
      Paint()
        ..color = orange.withValues(alpha: 0.28 * appear)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      center,
      w * 0.30,
      Paint()..color = Colors.white.withValues(alpha: appear),
    );

    // Arcs Wi-Fi qui apparaissent un par un, puis respirent
    final origin = center.translate(0, w * 0.115);
    final radii = [w * 0.10, w * 0.19, w * 0.28];
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9;

    for (var i = 0; i < 3; i++) {
      final local = ((reveal * 3.2) - i).clamp(0.0, 1.0);
      final breathe =
          0.6 + 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * pulse - i * 0.9));
      arcPaint.color = orange.withValues(alpha: local * breathe);
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radii[i]),
        -3 * math.pi / 4,
        math.pi / 2,
        false,
        arcPaint,
      );
    }

    // Point central
    canvas.drawCircle(
      origin,
      7 * ((reveal * 3.2).clamp(0.0, 1.0)),
      Paint()..color = orange,
    );
  }

  @override
  bool shouldRepaint(covariant _WifiPainter old) => true;
}

// ════════════════════════════════════════════════════════════════
//  PAGE 2 : PRÉSENTATION DE L'APPLICATION (5 images animées)
// ════════════════════════════════════════════════════════════════

class _Chip {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);
}

class _SlideData {
  final String title;
  final String desc;
  final List<_Chip> chips;
  final Widget Function(Animation<double> t) art;
  const _SlideData({
    required this.title,
    required this.desc,
    required this.chips,
    required this.art,
  });
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop;
  final PageController _pc = PageController();
  int _index = 0;
  bool _leaving = false;

  late final List<_SlideData> _slides = [
    _SlideData(
      title: 'Créez vos forfaits Wi-Fi',
      desc:
          'Définissez en quelques secondes la durée et le prix de chaque forfait : 1 heure, 1 jour, 1 semaine…',
      chips: const [
        _Chip(Icons.timer_rounded, 'Durées libres'),
        _Chip(Icons.sell_rounded, 'Vos prix'),
        _Chip(Icons.speed_rounded, 'Rapide'),
      ],
      art: (t) => _PlansArt(t: t),
    ),
    _SlideData(
      title: 'Générez des tickets',
      desc:
          'Chaque client reçoit un code unique. Vendez, imprimez ou envoyez le ticket en un seul geste.',
      chips: const [
        _Chip(Icons.confirmation_number_rounded, 'Codes uniques'),
        _Chip(Icons.qr_code_2_rounded, 'QR Code'),
        _Chip(Icons.share_rounded, 'Partage facile'),
      ],
      art: (t) => _TicketArt(t: t),
    ),
    _SlideData(
      title: 'Suivez vos clients',
      desc:
          'Voyez en direct qui est connecté, depuis quel appareil et jusqu’à quand dure son forfait.',
      chips: const [
        _Chip(Icons.wifi_tethering_rounded, 'Temps réel'),
        _Chip(Icons.devices_rounded, 'Tous appareils'),
        _Chip(Icons.hourglass_bottom_rounded, 'Durée restante'),
      ],
      art: (t) => _ClientsArt(t: t),
    ),
    _SlideData(
      title: 'Contrôlez vos revenus',
      desc:
          'Des statistiques claires chaque jour, chaque semaine : sachez exactement combien rapporte votre Wi-Fi.',
      chips: const [
        _Chip(Icons.bar_chart_rounded, 'Statistiques'),
        _Chip(Icons.payments_rounded, 'Ventes du jour'),
        _Chip(Icons.trending_up_rounded, 'Évolution'),
      ],
      art: (t) => _StatsArt(t: t),
    ),
    _SlideData(
      title: 'Simple, sûr et toujours là',
      desc:
          'Vos données sont protégées et votre activité reste accessible partout, depuis votre téléphone.',
      chips: const [
        _Chip(Icons.lock_rounded, 'Sécurisé'),
        _Chip(Icons.cloud_done_rounded, 'Sauvegarde'),
        _Chip(Icons.bolt_rounded, 'Instantané'),
      ],
      art: (t) => _SecurityArt(t: t),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    _pc.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  void _finish() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(_fadeScaleRoute(const ManagerPage()));
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pc.nextPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_index > 0) {
      _pc.previousPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    }
  }

  double get _page {
    if (_pc.hasClients && _pc.position.haveDimensions) {
      return _pc.page ?? _index.toDouble();
    }
    return _index.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _LiquidBackground(t: _loop),
          SafeArea(
            child: Column(
              children: [
                // Barre du haut
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 12, 0),
                  child: Row(
                    children: [
                      Text(
                        'HBB WiFi Manager',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: ink.withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isLast ? 0 : 1,
                        child: TextButton(
                          onPressed: _isLast ? null : _finish,
                          child: Text(
                            'Passer',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: orange.withValues(alpha: 0.95),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Les 5 écrans
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final s = _slides[i];
                      return AnimatedBuilder(
                        animation: _pc,
                        builder: (context, _) {
                          final d = (_page - i).clamp(-1.0, 1.0);
                          final ad = d.abs();
                          return _SlideView(
                            data: s,
                            number: i + 1,
                            total: _slides.length,
                            loop: _loop,
                            artOffset: Offset(-d * 70, 0),
                            textOffset: Offset(-d * 30, 0),
                            artScale: 1 - 0.18 * ad,
                            opacity: (1 - ad * 1.2).clamp(0.0, 1.0),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Indicateur liquide
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 34 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: i == _index
                              ? orange
                              : orange.withValues(alpha: 0.25),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // Boutons Retour / Suivant
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
                  child: Row(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        child: _index == 0
                            ? const SizedBox(width: 0, height: 58)
                            : Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: GestureDetector(
                                  onTap: _back,
                                  child: const _Glass(
                                    radius: 29,
                                    padding: EdgeInsets.all(17),
                                    child: Icon(
                                      Icons.arrow_back_rounded,
                                      color: orange,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: _LiquidButton(
                          label: _isLast ? 'Commencer' : 'Suivant',
                          icon: _isLast
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          loop: _loop,
                          onTap: _next,
                        ),
                      ),
                    ],
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

class _SlideView extends StatelessWidget {
  final _SlideData data;
  final int number, total;
  final Animation<double> loop;
  final Offset artOffset, textOffset;
  final double artScale, opacity;

  const _SlideView({
    required this.data,
    required this.number,
    required this.total,
    required this.loop,
    required this.artOffset,
    required this.textOffset,
    required this.artScale,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          // Image animée
          Expanded(
            flex: 5,
            child: Transform.translate(
              offset: artOffset,
              child: Transform.scale(
                scale: artScale,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 300,
                      height: 300,
                      child: data.art(loop),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Texte
          Expanded(
            flex: 4,
            child: Transform.translate(
              offset: textOffset,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '0$number / 0$total',
                        style: const TextStyle(
                          color: orange,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      data.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data.desc,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: ink.withValues(alpha: 0.68),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in data.chips)
                          _Glass(
                            radius: 20,
                            blur: 12,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(c.icon, size: 16, color: orange),
                                const SizedBox(width: 6),
                                Text(
                                  c.label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: ink.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton orange « liquide » avec reflet brillant qui glisse.
class _LiquidButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Animation<double> loop;
  final VoidCallback onTap;

  const _LiquidButton({
    required this.label,
    required this.icon,
    required this.loop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF9B45), orange, Color(0xFFE85500)],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: orange.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Reflet qui glisse
              AnimatedBuilder(
                animation: loop,
                builder: (context, _) {
                  final x = -1.5 + 3.0 * ((loop.value * 2) % 1.0);
                  return Align(
                    alignment: Alignment(x, 0),
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Reflet du haut (effet verre)
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.30),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Row(
                  key: ValueKey(label),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(icon, color: Colors.white, size: 22),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  IMAGE 1 : Forfaits Wi-Fi
// ════════════════════════════════════════════════════════════════

class _RingsPainter extends CustomPainter {
  final double v;
  _RingsPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      final t = (v * 1.0 + i / 3) % 1.0;
      p.color = orange.withValues(alpha: (1 - t) * 0.35);
      canvas.drawCircle(c, 60 + t * 90, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.v != v;
}

class _PlanCard extends StatelessWidget {
  final String title, price;
  final IconData icon;
  const _PlanCard(this.title, this.price, this.icon);

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: orange.withValues(alpha: 0.16),
            ),
            child: Icon(icon, size: 18, color: orange),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlansArt extends StatelessWidget {
  final Animation<double> t;
  const _PlansArt({required this.t});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        double bob(double p) => math.sin(2 * math.pi * (v + p)) * 8;
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: CustomPaint(painter: _RingsPainter(v))),
            Transform.translate(
              offset: Offset(0, bob(0)),
              child: _Glass(
                radius: 70,
                padding: const EdgeInsets.all(34),
                opacity: 0.30,
                child: _gradientIcon(Icons.wifi_rounded, 72),
              ),
            ),
            Positioned(
              left: 0,
              top: 28 + bob(0.3),
              child: const _PlanCard('1 heure', '500 F', Icons.schedule_rounded),
            ),
            Positioned(
              right: 0,
              top: 72 + bob(0.6),
              child: const _PlanCard('1 jour', '1 000 F', Icons.today_rounded),
            ),
            Positioned(
              left: 18,
              bottom: 22 + bob(0.9),
              child: const _PlanCard(
                  '1 semaine', '5 000 F', Icons.date_range_rounded),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  IMAGE 2 : Tickets
// ════════════════════════════════════════════════════════════════

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const n = 9;
    final cell = size.width / n;
    final rnd = math.Random(7);
    final p = Paint()..color = ink;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final corner = (x < 3 && y < 3) || (x > 5 && y < 3) || (x < 3 && y > 5);
        if (corner || rnd.nextDouble() > 0.5) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x * cell + 0.6, y * cell + 0.6, cell - 1.2, cell - 1.2),
              const Radius.circular(1.5),
            ),
            p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => false;
}

class _TicketArt extends StatelessWidget {
  final Animation<double> t;
  const _TicketArt({required this.t});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        final bob = math.sin(2 * math.pi * v) * 7;
        final sweep = (v * 2) % 1.0;
        final pulse = 1 + 0.08 * math.sin(2 * math.pi * v * 2);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Ticket arrière
            Transform.translate(
              offset: Offset(10, 22 - bob),
              child: Transform.rotate(
                angle: -0.14 + 0.02 * math.sin(2 * math.pi * v),
                child: const _Glass(
                  radius: 26,
                  opacity: 0.12,
                  padding: EdgeInsets.zero,
                  child: SizedBox(width: 240, height: 150),
                ),
              ),
            ),

            // Ticket avant
            Transform.translate(
              offset: Offset(0, bob),
              child: Transform.rotate(
                angle: 0.04,
                child: _Glass(
                  radius: 28,
                  opacity: 0.32,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 255,
                    height: 175,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _gradientIcon(Icons.wifi_rounded, 24),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'HBB WiFi',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: ink,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: orange.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        '24 h',
                                        style: TextStyle(
                                          color: orange,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: List.generate(
                                    22,
                                    (i) => Expanded(
                                      child: Container(
                                        height: 1.5,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 1.5),
                                        color: ink.withValues(
                                            alpha: i.isEven ? 0.25 : 0.0),
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'CODE D’ACCÈS',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              letterSpacing: 2,
                                              fontWeight: FontWeight.w800,
                                              color: ink.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'HBB-4827',
                                              style: TextStyle(
                                                fontSize: 25,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 3,
                                                color: orange,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 58,
                                      height: 58,
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: CustomPaint(painter: _QrPainter()),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Reflet brillant qui traverse
                          Positioned(
                            left: -90 + 440 * sweep,
                            top: -20,
                            bottom: -20,
                            width: 70,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.0),
                                    Colors.white.withValues(alpha: 0.55),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Badge « Vendu »
            Positioned(
              right: 4,
              top: 14 - bob,
              child: Transform.scale(
                scale: pulse,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 5),
                      Text(
                        'Vendu',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  IMAGE 3 : Clients connectés
// ════════════════════════════════════════════════════════════════

class _LinksPainter extends CustomPainter {
  final double v;
  final int count;
  final double radius;
  _LinksPainter(this.v, this.count, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..strokeWidth = 1.6
      ..color = orange.withValues(alpha: 0.28);
    final dot = Paint()..color = orange;
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * (v + i / count);
      final p = c + Offset(radius * math.cos(a), radius * math.sin(a));
      canvas.drawLine(c, p, line);
      // Petit point de données qui voyage vers l'appareil
      final k = (v * 3 + i / count) % 1.0;
      canvas.drawCircle(Offset.lerp(c, p, k)!, 3.5, dot);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = orange.withValues(alpha: 0.15);
    canvas.drawCircle(c, radius, ring);
  }

  @override
  bool shouldRepaint(covariant _LinksPainter old) => old.v != v;
}

class _ClientsArt extends StatelessWidget {
  final Animation<double> t;
  const _ClientsArt({required this.t});

  static const _icons = [
    Icons.smartphone_rounded,
    Icons.laptop_mac_rounded,
    Icons.tablet_mac_rounded,
    Icons.tv_rounded,
    Icons.headphones_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    const r = 112.0;
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * v * 3);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _LinksPainter(v, _icons.length, r)),
            ),
            // Routeur au centre
            Align(
              child: Transform.scale(
                scale: 1 + 0.05 * pulse,
                child: _Glass(
                  radius: 50,
                  opacity: 0.32,
                  padding: const EdgeInsets.all(22),
                  child: _gradientIcon(Icons.router_rounded, 48),
                ),
              ),
            ),
            // Appareils en orbite
            for (var i = 0; i < _icons.length; i++)
              Positioned(
                left: 150 + r * math.cos(2 * math.pi * (v + i / _icons.length)) - 26,
                top: 150 + r * math.sin(2 * math.pi * (v + i / _icons.length)) - 26,
                child: _Glass(
                  radius: 26,
                  blur: 12,
                  padding: const EdgeInsets.all(13),
                  child: Icon(_icons[i], size: 26, color: orange),
                ),
              ),
            // Badge en ligne
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: _Glass(
                  radius: 20,
                  blur: 12,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF22C55E)
                              .withValues(alpha: 0.5 + 0.5 * pulse),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '5 appareils connectés',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  IMAGE 4 : Statistiques & revenus
// ════════════════════════════════════════════════════════════════

class _StatsArt extends StatelessWidget {
  final Animation<double> t;
  const _StatsArt({required this.t});

  static const _vals = [0.40, 0.62, 0.50, 0.78, 0.66, 0.95, 0.82];
  static const _days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        final bob = math.sin(2 * math.pi * v) * 7;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, bob * 0.5),
              child: _Glass(
                radius: 30,
                opacity: 0.30,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: SizedBox(
                  width: 244,
                  height: 196,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Revenus de la semaine',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: ink.withValues(alpha: 0.55),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '125 000 F',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '+24 %',
                              style: TextStyle(
                                color: Color(0xFF16A34A),
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1400),
                        curve: Curves.easeOutCubic,
                        builder: (context, grow, _) {
                          return SizedBox(
                            height: 100,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (var i = 0; i < _vals.length; i++)
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: (_vals[i] *
                                                (1 +
                                                    0.05 *
                                                        math.sin(2 *
                                                            math.pi *
                                                            (v + i / 7))) *
                                                74 *
                                                grow)
                                            .clamp(4.0, 80.0),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              orange,
                                              const Color(0xFFFFB27A)
                                                  .withValues(alpha: 0.9),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        _days[i],
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: ink.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bulle flottante
            Positioned(
              right: 0,
              top: 8 - bob,
              child: const _Glass(
                radius: 18,
                blur: 12,
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_alt_rounded, size: 16, color: orange),
                    SizedBox(width: 5),
                    Text(
                      '+12 clients',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 6 + bob,
              child: const _Glass(
                radius: 18,
                blur: 12,
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up_rounded, size: 16, color: orange),
                    SizedBox(width: 5),
                    Text(
                      'Record battu',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  IMAGE 5 : Sécurité & disponibilité
// ════════════════════════════════════════════════════════════════

class _ShieldRingPainter extends CustomPainter {
  final double v;
  _ShieldRingPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    for (var i = 0; i < 6; i++) {
      final start = 2 * math.pi * (v + i / 6);
      p.color = orange.withValues(alpha: 0.18 + 0.30 * (i % 2));
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 108),
        start,
        math.pi / 6,
        false,
        p,
      );
    }
    final q = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = orange.withValues(alpha: 0.18);
    canvas.drawCircle(c, 82, q);
  }

  @override
  bool shouldRepaint(covariant _ShieldRingPainter old) => old.v != v;
}

class _SecurityArt extends StatelessWidget {
  final Animation<double> t;
  const _SecurityArt({required this.t});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        double bob(double p) => math.sin(2 * math.pi * (v + p)) * 8;
        final pulse = 1 + 0.05 * math.sin(2 * math.pi * v * 2);
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: CustomPaint(painter: _ShieldRingPainter(v))),
            Transform.scale(
              scale: pulse,
              child: _Glass(
                radius: 70,
                opacity: 0.32,
                padding: const EdgeInsets.all(32),
                child: _gradientIcon(Icons.verified_user_rounded, 76),
              ),
            ),
            Positioned(
              top: 16 + bob(0.0),
              left: 36,
              child: const _Glass(
                radius: 22,
                blur: 12,
                padding: EdgeInsets.all(11),
                child: Icon(Icons.cloud_done_rounded, color: orange, size: 24),
              ),
            ),
            Positioned(
              top: 40 + bob(0.4),
              right: 28,
              child: const _Glass(
                radius: 22,
                blur: 12,
                padding: EdgeInsets.all(11),
                child: Icon(Icons.bolt_rounded, color: orange, size: 24),
              ),
            ),
            Positioned(
              bottom: 20 + bob(0.7),
              right: 52,
              child: const _Glass(
                radius: 22,
                blur: 12,
                padding: EdgeInsets.all(11),
                child: Icon(Icons.lock_rounded, color: orange, size: 24),
              ),
            ),
            Positioned(
              bottom: 36 + bob(0.2),
              left: 26,
              child: const _Glass(
                radius: 22,
                blur: 12,
                padding: EdgeInsets.all(11),
                child: Icon(Icons.phone_iphone_rounded, color: orange, size: 24),
              ),
            ),
          ],
        );
      },
    );
  }
}
