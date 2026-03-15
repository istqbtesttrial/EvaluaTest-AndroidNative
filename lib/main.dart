import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EvaluaTestApp());
}

class EvaluaTestApp extends StatelessWidget {
  const EvaluaTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2563EB);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EvaluaTest Native',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w800),
          headlineSmall: TextStyle(fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: seed, width: 1.5),
          ),
        ),
      ),
      home: const AppBootstrapper(),
    );
  }
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  late Future<BootstrapData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<BootstrapData> _load() async {
    final catalog = await QuestionCatalog.load();
    final prefs = await SharedPreferences.getInstance();
    final history = StatsStore.fromPrefs(prefs);
    return BootstrapData(catalog: catalog, prefs: prefs, history: history);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BootstrapData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SplashLoadingScreen();
        }
        return EvaluaTestHome(data: snapshot.data!);
      },
    );
  }
}

class BootstrapData {
  const BootstrapData({
    required this.catalog,
    required this.prefs,
    required this.history,
  });

  final QuestionCatalog catalog;
  final SharedPreferences prefs;
  final StatsStore history;
}

enum AppStage { login, dashboard, exam, results }

class EvaluaTestHome extends StatefulWidget {
  const EvaluaTestHome({super.key, required this.data});

  final BootstrapData data;

  @override
  State<EvaluaTestHome> createState() => _EvaluaTestHomeState();
}

class _EvaluaTestHomeState extends State<EvaluaTestHome> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pageController = PageController();
  final _pageNotifier = ValueNotifier<int>(0);

  AppStage _stage = AppStage.login;
  String? _loginError;
  bool _rememberMe = true;
  String _displayName = 'Élève';
  ExamSession? _session;
  Duration _remaining = const Duration(minutes: 75);
  Timer? _timer;
  late StatsStore _stats;

  @override
  void initState() {
    super.initState();
    _stats = widget.data.history;
    _rememberMe = widget.data.prefs.getBool('remember_me') ?? true;
    final savedName = widget.data.prefs.getString('display_name');
    if (savedName != null && savedName.isNotEmpty) {
      _displayName = savedName;
      _usernameController.text = savedName;
      if (_rememberMe) {
        _stage = AppStage.dashboard;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _pageController.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() => _loginError = 'Entre ton login et ton mot de passe.');
      return;
    }

    await widget.data.prefs.setBool('remember_me', _rememberMe);
    if (_rememberMe) {
      await widget.data.prefs.setString('display_name', username);
    } else {
      await widget.data.prefs.remove('display_name');
    }

    setState(() {
      _displayName = username;
      _loginError = null;
      _stage = AppStage.dashboard;
    });
  }

  Future<void> _logout() async {
    _timer?.cancel();
    await widget.data.prefs.remove('display_name');
    setState(() {
      _stage = AppStage.login;
      _session = null;
      _remaining = const Duration(minutes: 75);
      _loginError = null;
      _passwordController.clear();
    });
  }

  void _startExam() {
    final questions = widget.data.catalog.buildExamQuestions(40);
    final session = ExamSession(
      startedAt: DateTime.now(),
      questions: questions,
      answers: List<int?>.filled(questions.length, null),
    );

    _pageNotifier.value = 0;
    _pageController.jumpToPage(0);
    _timer?.cancel();

    setState(() {
      _session = session;
      _remaining = const Duration(minutes: 75);
      _stage = AppStage.exam;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 1) {
        timer.cancel();
        _submitExam();
      } else {
        setState(() => _remaining -= const Duration(seconds: 1));
      }
    });
  }

  void _answerQuestion(int index, int choice) {
    final session = _session;
    if (session == null) return;
    setState(() => session.answers[index] = choice);
  }

  void _goToPage(int index) {
    _pageNotifier.value = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _submitExam() async {
    final session = _session;
    if (session == null) return;
    _timer?.cancel();
    session.completedAt = DateTime.now();

    final entry = SessionRecord(
      timestamp: DateTime.now(),
      score: session.score,
      totalQuestions: session.questions.length,
      durationSeconds: session.timeSpent.inSeconds,
    );
    _stats = _stats.add(entry);
    await _stats.save(widget.data.prefs);

    setState(() => _stage = AppStage.results);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case AppStage.login:
        return LoginScreen(
          usernameController: _usernameController,
          passwordController: _passwordController,
          rememberMe: _rememberMe,
          loginError: _loginError,
          onRememberChanged: (value) => setState(() => _rememberMe = value),
          onLogin: _login,
          stats: _stats,
        );
      case AppStage.dashboard:
        return DashboardScreen(
          displayName: _displayName,
          catalog: widget.data.catalog,
          stats: _stats,
          onStartExam: _startExam,
          onLogout: _logout,
        );
      case AppStage.exam:
        return ExamScreen(
          session: _session!,
          remaining: _remaining,
          pageController: _pageController,
          pageNotifier: _pageNotifier,
          onAnswer: _answerQuestion,
          onGoToPage: _goToPage,
          onSubmit: _submitExam,
        );
      case AppStage.results:
        return ResultsScreen(
          session: _session!,
          stats: _stats,
          onRestart: _startExam,
          onBackToDashboard: () => setState(() => _stage = AppStage.dashboard),
        );
    }
  }
}

class SplashLoadingScreen extends StatelessWidget {
  const SplashLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 18),
              Text(
                'Préparation de l’expérience native…',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.rememberMe,
    required this.loginError,
    required this.onRememberChanged,
    required this.onLogin,
    required this.stats,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final String? loginError;
  final ValueChanged<bool> onRememberChanged;
  final Future<void> Function() onLogin;
  final StatsStore stats;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF172554), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 12),
              const Text(
                'EvaluaTest',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version Flutter native. Plus premium, plus stable, plus crédible sur téléphone réel.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PremiumPill(label: 'Connexion premium'),
                    const SizedBox(height: 14),
                    const Text(
                      'Connexion',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Base simple pour l’instant, mais solide et agréable à utiliser.',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Login',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      onSubmitted: (_) => onLogin(),
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Switch(value: rememberMe, onChanged: onRememberChanged),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Rester connecté')),
                      ],
                    ),
                    if (loginError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          loginError!,
                          style: const TextStyle(color: Color(0xFF991B1B)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onLogin,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Entrer dans l’espace élève'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatChip(label: 'Sessions', value: '${stats.attempts}'),
                  StatChip(
                    label: 'Meilleur score',
                    value: stats.bestScoreLabel,
                  ),
                  StatChip(label: 'Temps moyen', value: stats.averageTimeLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.displayName,
    required this.catalog,
    required this.stats,
    required this.onStartExam,
    required this.onLogout,
  });

  final String displayName;
  final QuestionCatalog catalog;
  final StatsStore stats;
  final VoidCallback onStartExam;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Salut $displayName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tu as maintenant une base Android native avec historique local et stats persistées.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: onLogout,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                          ),
                          icon: const Icon(Icons.logout, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        HeroMetric(
                          label: 'Dernier score',
                          value: stats.lastScoreLabel,
                          icon: Icons.flag_outlined,
                        ),
                        HeroMetric(
                          label: 'Meilleur score',
                          value: stats.bestScoreLabel,
                          icon: Icons.emoji_events_outlined,
                        ),
                        HeroMetric(
                          label: 'Tentatives',
                          value: '${stats.attempts}',
                          icon: Icons.history_outlined,
                        ),
                        HeroMetric(
                          label: 'Temps moyen',
                          value: stats.averageTimeLabel,
                          icon: Icons.timer_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList.list(
              children: [
                GradientActionCard(onStartExam: onStartExam),
                const SizedBox(height: 20),
                SectionTitle(
                  title: 'Historique récent',
                  subtitle: stats.records.isEmpty
                      ? 'Aucune session enregistrée pour le moment.'
                      : 'Tes dernières sessions sont sauvegardées localement.',
                ),
                const SizedBox(height: 12),
                if (stats.records.isEmpty)
                  const EmptyHistoryCard()
                else
                  ...stats.records
                      .take(5)
                      .map((record) => HistoryCard(record: record)),
                const SizedBox(height: 20),
                SectionTitle(
                  title: 'Base de contenu',
                  subtitle:
                      '${catalog.totalQuestions} questions réparties sur ${catalog.chapters.length} chapitres.',
                ),
                const SizedBox(height: 12),
                ...catalog.chapters.map(
                  (chapter) => ChapterPreviewCard(chapter: chapter),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExamScreen extends StatelessWidget {
  const ExamScreen({
    super.key,
    required this.session,
    required this.remaining,
    required this.pageController,
    required this.pageNotifier,
    required this.onAnswer,
    required this.onGoToPage,
    required this.onSubmit,
  });

  final ExamSession session;
  final Duration remaining;
  final PageController pageController;
  final ValueNotifier<int> pageNotifier;
  final void Function(int, int) onAnswer;
  final void Function(int) onGoToPage;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mode examen',
                              style: TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${session.answeredCount}/${session.questions.length} répondues',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TimerChip(value: formatDuration(remaining)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: session.answeredCount / session.questions.length,
                      minHeight: 10,
                      backgroundColor: const Color(0xFFE2E8F0),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 42,
                    child: ValueListenableBuilder<int>(
                      valueListenable: pageNotifier,
                      builder: (context, currentPage, _) {
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final answered = session.answers[index] != null;
                            final active = currentPage == index;
                            return InkWell(
                              onTap: () => onGoToPage(index),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFF2563EB)
                                      : answered
                                      ? const Color(0xFFDBEAFE)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: active
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemCount: session.questions.length,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                onPageChanged: (value) => pageNotifier.value = value,
                itemCount: session.questions.length,
                itemBuilder: (context, index) {
                  final question = session.questions[index];
                  final selected = session.answers[index];
                  final last = index == session.questions.length - 1;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    children: [
                      Row(
                        children: [
                          PremiumPill(label: 'Question ${index + 1}'),
                          const Spacer(),
                          Text(
                            question.chapterTitle,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              question.enonce,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 22),
                            ...List.generate(question.choices.length, (
                              choiceIndex,
                            ) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ChoiceTile(
                                  label: optionLetter(choiceIndex),
                                  text: question.choices[choiceIndex],
                                  selected: selected == choiceIndex,
                                  onTap: () => onAnswer(index, choiceIndex),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          if (index > 0)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => onGoToPage(index - 1),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                                child: const Text('Précédent'),
                              ),
                            ),
                          if (index > 0) const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: last
                                  ? onSubmit
                                  : () => onGoToPage(index + 1),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                              ),
                              child: Text(
                                last ? 'Valider l’examen' : 'Suivant',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (last) ...[
                        const SizedBox(height: 16),
                        SubmitSummaryCard(session: session),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({
    super.key,
    required this.session,
    required this.stats,
    required this.onRestart,
    required this.onBackToDashboard,
  });

  final ExamSession session;
  final StatsStore stats;
  final VoidCallback onRestart;
  final VoidCallback onBackToDashboard;

  @override
  Widget build(BuildContext context) {
    final score = session.score;
    final total = session.questions.length;
    final percent = ((score / total) * 100).round();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                ),
                borderRadius: BorderRadius.all(Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PremiumPill(label: 'Résultats'),
                  const SizedBox(height: 16),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$score / $total bonnes réponses',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                HeroMetric(
                  label: 'Meilleur score',
                  value: stats.bestScoreLabel,
                  icon: Icons.workspace_premium_outlined,
                ),
                HeroMetric(
                  label: 'Dernier score',
                  value: stats.lastScoreLabel,
                  icon: Icons.history_toggle_off,
                ),
                HeroMetric(
                  label: 'Temps utilisé',
                  value: formatDuration(session.timeSpent),
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionTitle(
              title: 'Correction rapide',
              subtitle: 'Lecture propre et immédiate question par question.',
            ),
            const SizedBox(height: 12),
            ...List.generate(total, (index) {
              final q = session.questions[index];
              final answer = session.answers[index];
              final ok = answer == q.correctIndex;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: softCard,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PremiumPill(label: 'Q${index + 1}'),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            q.chapterTitle,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          ok ? Icons.check_circle : Icons.cancel,
                          color: ok
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      q.enonce,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ta réponse : ${answer == null ? 'Non répondue' : q.choices[answer]}',
                      style: const TextStyle(color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bonne réponse : ${q.choices[q.correctIndex]}',
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onRestart,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Relancer un examen'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onBackToDashboard,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: const Text('Retour au dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class GradientActionCard extends StatelessWidget {
  const GradientActionCard({super.key, required this.onStartExam});
  final VoidCallback onStartExam;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Examen blanc Foundation Level',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '40 questions • 75 minutes • navigation fluide • historique local sauvegardé',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onStartExam,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Commencer l’examen'),
          ),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F172A),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PremiumPill extends StatelessWidget {
  const PremiumPill({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class HeroMetric extends StatelessWidget {
  const HeroMetric({
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
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB)),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFF475569))),
        ],
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
          ),
        ],
      ),
    );
  }
}

class EmptyHistoryCard extends StatelessWidget {
  const EmptyHistoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard,
      child: const Text(
        'Dès que tu termines un premier examen, le dashboard affichera dernier score, meilleur score, temps moyen et historique récent.',
      ),
    );
  }
}

class HistoryCard extends StatelessWidget {
  const HistoryCard({super.key, required this.record});
  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final percent = ((record.score / record.totalQuestions) * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: softCard,
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '$percent%',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.score}/${record.totalQuestions} bonnes réponses',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.friendlyDate} • ${formatDuration(Duration(seconds: record.durationSeconds))}',
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
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

class ChapterPreviewCard extends StatelessWidget {
  const ChapterPreviewCard({super.key, required this.chapter});
  final ChapterInfo chapter;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: softCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PremiumPill(label: 'Chapitre ${chapter.id}'),
              const Spacer(),
              Text(
                '${chapter.questionCount} questions',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            chapter.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            chapter.sampleQuestion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF475569), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
            ],
          ),
        ),
      ),
    );
  }
}

class TimerChip extends StatelessWidget {
  const TimerChip({super.key, required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Color(0xFF92400E)),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class SubmitSummaryCard extends StatelessWidget {
  const SubmitSummaryCard({super.key, required this.session});
  final ExamSession session;

  @override
  Widget build(BuildContext context) {
    final unanswered = session.questions.length - session.answeredCount;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Résumé avant validation',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Répondues : ${session.answeredCount} • Non répondues : $unanswered',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.88)),
          ),
        ],
      ),
    );
  }
}

class QuestionCatalog {
  QuestionCatalog({required this.chapters});
  final List<ChapterInfo> chapters;

  int get totalQuestions => chapters.fold(0, (sum, c) => sum + c.questionCount);
  List<QuestionItem> get allQuestions => [
    for (final chapter in chapters) ...chapter.questions,
  ];

  List<QuestionItem> buildExamQuestions(int count) {
    final all = [...allQuestions];
    all.shuffle(Random(42));
    return all.take(min(count, all.length)).toList();
  }

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
      final chapterId = decoded['chapterId'] as int? ?? 0;
      final title = decoded['title'] as String? ?? 'Chapitre';
      final questions =
          ((decoded['questions'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>())
              .map(
                (item) => QuestionItem(
                  id: item['questionId'] as String? ?? '',
                  chapterId: chapterId,
                  chapterTitle: title,
                  enonce: item['enonce'] as String? ?? '',
                  choices: (item['choices'] as List<dynamic>? ?? const [])
                      .cast<String>(),
                  correctIndex: item['correctIndex'] as int? ?? 0,
                ),
              )
              .toList();
      chapters.add(
        ChapterInfo(
          id: chapterId,
          title: title,
          questions: questions,
          sampleQuestion: questions.isEmpty ? '' : questions.first.enonce,
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
    required this.questions,
    required this.sampleQuestion,
  });
  final int id;
  final String title;
  final List<QuestionItem> questions;
  final String sampleQuestion;
  int get questionCount => questions.length;
}

class QuestionItem {
  QuestionItem({
    required this.id,
    required this.chapterId,
    required this.chapterTitle,
    required this.enonce,
    required this.choices,
    required this.correctIndex,
  });
  final String id;
  final int chapterId;
  final String chapterTitle;
  final String enonce;
  final List<String> choices;
  final int correctIndex;
}

class ExamSession {
  ExamSession({
    required this.startedAt,
    required this.questions,
    required this.answers,
  });
  final DateTime startedAt;
  DateTime? completedAt;
  final List<QuestionItem> questions;
  final List<int?> answers;

  int get answeredCount => answers.whereType<int>().length;
  int get score {
    var total = 0;
    for (var i = 0; i < questions.length; i++) {
      if (answers[i] == questions[i].correctIndex) total++;
    }
    return total;
  }

  Duration get timeSpent =>
      (completedAt ?? DateTime.now()).difference(startedAt);
}

class StatsStore {
  StatsStore(this.records);
  final List<SessionRecord> records;

  factory StatsStore.empty() => StatsStore(const []);

  factory StatsStore.fromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString('session_history');
    if (raw == null || raw.isEmpty) return StatsStore.empty();
    final decoded = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return StatsStore(decoded.map(SessionRecord.fromJson).toList());
  }

  StatsStore add(SessionRecord record) => StatsStore([record, ...records]);

  Future<void> save(SharedPreferences prefs) async {
    final encoded = jsonEncode(
      records.take(20).map((e) => e.toJson()).toList(),
    );
    await prefs.setString('session_history', encoded);
  }

  int get attempts => records.length;
  SessionRecord? get lastRecord => records.isEmpty ? null : records.first;
  int get bestScore =>
      records.isEmpty ? 0 : records.map((e) => e.score).reduce(max);
  int get totalQuestionsBaseline =>
      records.isEmpty ? 40 : records.first.totalQuestions;
  String get lastScoreLabel => lastRecord == null
      ? '-'
      : '${lastRecord!.score}/${lastRecord!.totalQuestions}';
  String get bestScoreLabel =>
      records.isEmpty ? '-' : '$bestScore/$totalQuestionsBaseline';
  String get averageTimeLabel {
    if (records.isEmpty) return '-';
    final avg =
        records.fold<int>(0, (sum, e) => sum + e.durationSeconds) ~/
        records.length;
    return formatDuration(Duration(seconds: avg));
  }
}

class SessionRecord {
  SessionRecord({
    required this.timestamp,
    required this.score,
    required this.totalQuestions,
    required this.durationSeconds,
  });
  final DateTime timestamp;
  final int score;
  final int totalQuestions;
  final int durationSeconds;

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
    timestamp: DateTime.parse(json['timestamp'] as String),
    score: json['score'] as int,
    totalQuestions: json['totalQuestions'] as int,
    durationSeconds: json['durationSeconds'] as int,
  );

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'score': score,
    'totalQuestions': totalQuestions,
    'durationSeconds': durationSeconds,
  };

  String get friendlyDate {
    final d = timestamp;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

String optionLetter(int index) => String.fromCharCode(65 + index);

String formatDuration(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

final BoxDecoration softCard = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(24),
  boxShadow: const [
    BoxShadow(color: Color(0x120F172A), blurRadius: 28, offset: Offset(0, 14)),
  ],
);
