import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EvaluaTestApp());
}

class EvaluaTestApp extends StatelessWidget {
  const EvaluaTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFF2563EB);

    return MaterialApp(
      title: 'EvaluaTest Native',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: baseColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: const Color(0xFF0F172A),
          displayColor: const Color(0xFF0F172A),
        ),
      ),
      home: const NativeHomePage(),
    );
  }
}

class NativeHomePage extends StatefulWidget {
  const NativeHomePage({super.key});

  @override
  State<NativeHomePage> createState() => _NativeHomePageState();
}

class _NativeHomePageState extends State<NativeHomePage> {
  late Future<QuestionCatalog> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = QuestionCatalog.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: FutureBuilder<QuestionCatalog>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          final catalog = snapshot.data;
          final questionCount = catalog?.totalQuestions ?? 0;
          final chapterCount = catalog?.chapters.length ?? 0;

          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text('EvaluaTest Native'),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Android natif premium • Flutter',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'On repart proprement.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Base native Android élégante, stable et pensée mobile dès le départ.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                expandedHeight: 280,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          MetricCard(
                            label: 'Questions importées',
                            value: '$questionCount',
                            icon: Icons.quiz_outlined,
                          ),
                          MetricCard(
                            label: 'Chapitres',
                            value: '$chapterCount',
                            icon: Icons.layers_outlined,
                          ),
                          const MetricCard(
                            label: 'Stack',
                            value: 'Flutter',
                            icon: Icons.phone_android_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const SectionTitle(
                        title: 'Cap produit',
                        subtitle:
                            'La nouvelle base qu’on va transformer en vraie app premium.',
                      ),
                      const SizedBox(height: 16),
                      const FeatureTile(
                        icon: Icons.lock_outline,
                        title: 'Auth native propre',
                        subtitle:
                            'Écran login sobre, fiable, sans comportement WebView parasite.',
                      ),
                      const FeatureTile(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Dashboard premium',
                        subtitle:
                            'Accueil lisible, progression rassurante, CTA clairs.',
                      ),
                      const FeatureTile(
                        icon: Icons.fact_check_outlined,
                        title: 'Mode examen mobile-first',
                        subtitle:
                            'Questions nettes, options confortables, navigation ultra simple.',
                      ),
                      const FeatureTile(
                        icon: Icons.insights_outlined,
                        title: 'Résultats & correction',
                        subtitle:
                            'Analyse propre, review utile, sensation haut de gamme.',
                      ),
                      const SizedBox(height: 24),
                      const SectionTitle(
                        title: 'Chapitres détectés',
                        subtitle:
                            'Les données existantes sont déjà branchées comme source de migration.',
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (snapshot.hasError)
                        ErrorCard(message: snapshot.error.toString())
                      else
                        ...?catalog?.chapters.map(
                          (chapter) => ChapterCard(chapter: chapter),
                        ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            backgroundColor: Colors.white,
                            builder: (context) => const NextStepSheet(),
                          );
                        },
                        icon: const Icon(Icons.rocket_launch_outlined),
                        label: const Text('Voir la prochaine étape'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class QuestionCatalog {
  QuestionCatalog({required this.chapters});

  final List<ChapterInfo> chapters;

  int get totalQuestions =>
      chapters.fold(0, (sum, chapter) => sum + chapter.questionCount);

  static Future<QuestionCatalog> load() async {
    const files = [
      'assets/questions/chapt1.json',
      'assets/questions/chapt2.json',
      'assets/questions/chapt3.json',
      'assets/questions/chapt4.json',
      'assets/questions/chapt5.json',
      'assets/questions/chapt6.json',
    ];

    final chapters = <ChapterInfo>[];

    for (final file in files) {
      final raw = await rootBundle.loadString(file);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final questions = (decoded['questions'] as List<dynamic>? ?? const []);
      chapters.add(
        ChapterInfo(
          id: decoded['chapterId'] as int? ?? 0,
          title: (decoded['title'] as String?) ?? 'Chapitre',
          questionCount: questions.length,
          sampleQuestion: questions.isEmpty
              ? 'Aucune question détectée.'
              : (questions.first as Map<String, dynamic>)['enonce']
                        as String? ??
                    'Question indisponible.',
        ),
      );
    }

    return QuestionCatalog(chapters: chapters);
  }
}

class ChapterInfo {
  ChapterInfo({
    required this.id,
    required this.title,
    required this.questionCount,
    required this.sampleQuestion,
  });

  final int id;
  final String title;
  final int questionCount;
  final String sampleQuestion;
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB)),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFF475569))),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF475569), height: 1.4),
        ),
      ],
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    height: 1.35,
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

class ChapterCard extends StatelessWidget {
  const ChapterCard({super.key, required this.chapter});

  final ChapterInfo chapter;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Chapitre ${chapter.id}',
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${chapter.questionCount} questions',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            chapter.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            chapter.sampleQuestion,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF475569), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Erreur de chargement des données : $message',
        style: const TextStyle(color: Color(0xFF991B1B)),
      ),
    );
  }
}

class NextStepSheet extends StatelessWidget {
  const NextStepSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Prochaine étape exacte',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text(
              '1. Poser le design system final (couleurs, spacing, composants).',
            ),
            SizedBox(height: 8),
            Text(
              '2. Implémenter le vrai flux auth natif + persistance locale stable.',
            ),
            SizedBox(height: 8),
            Text(
              '3. Construire le moteur d\'examen natif avec progression, timer et review.',
            ),
            SizedBox(height: 8),
            Text(
              '4. Générer une première APK Flutter propre pour test UX sur téléphone réel.',
            ),
          ],
        ),
      ),
    );
  }
}
