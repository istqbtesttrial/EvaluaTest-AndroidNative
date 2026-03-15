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
    const seed = Color(0xFF3B82F6);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EvaluaTest Native',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          headlineSmall: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: seed, width: 1.4),
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
        if (!snapshot.hasData) return const SplashLoadingScreen();
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
      if (_rememberMe) _stage = AppStage.dashboard;
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
      duration: const Duration(milliseconds: 240),
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
          onRememberChanged: (v) => setState(() => _rememberMe = v),
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.home_work_outlined, size: 44, color: Color(0xFF3B82F6)),
            SizedBox(height: 16),
            CircularProgressIndicator(color: Color(0xFF3B82F6)),
            SizedBox(height: 16),
            Text('Préparation de l’expérience…'),
          ],
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            const Text(
              'EvaluaTest',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Une expérience d’examen plus calme, plus nette, plus premium.',
              style: TextStyle(color: Color(0xFF6A6A6A), height: 1.45),
            ),
            const SizedBox(height: 24),
            SearchPill(
              icon: Icons.school_outlined,
              title: 'Foundation Level',
              subtitle: '40 questions • 75 minutes • mobile native',
              actionLabel: 'Entrer',
            ),
            const SizedBox(height: 18),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connexion',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Simple, propre, rassurante — sans surcharge visuelle.',
                    style: TextStyle(color: Color(0xFF6A6A6A)),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Login',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    onSubmitted: (_) => onLogin(),
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberMe,
                        onChanged: (v) => onRememberChanged(v ?? false),
                      ),
                      const Text('Rester connecté'),
                    ],
                  ),
                  if (loginError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        loginError!,
                        style: const TextStyle(color: Color(0xFF1D4ED8)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onLogin,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('Entrer dans l’espace élève'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TinyMetric(
                    title: 'Sessions',
                    value: '${stats.attempts}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TinyMetric(
                    title: 'Meilleur score',
                    value: stats.bestScoreLabel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TinyMetric(
                    title: 'Temps moyen',
                    value: stats.averageTimeLabel,
                  ),
                ),
              ],
            ),
          ],
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(Icons.school_outlined, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Salut $displayName',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Prêt pour une session propre et fluide ?',
                      style: TextStyle(color: Color(0xFF6A6A6A)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SearchPill(
            icon: Icons.play_circle_outline,
            title: 'Examen blanc Foundation Level',
            subtitle: 'Lancer une session complète maintenant',
            actionLabel: 'Go',
            onTap: onStartExam,
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: 'Tableau de bord',
            subtitle: 'Des infos simples, utiles, sans bruit.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 146,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children:
                  [
                        DashboardCard(
                          title: 'Dernier score',
                          value: stats.lastScoreLabel,
                          icon: Icons.history,
                        ),
                        DashboardCard(
                          title: 'Meilleur score',
                          value: stats.bestScoreLabel,
                          icon: Icons.workspace_premium_outlined,
                        ),
                        DashboardCard(
                          title: 'Tentatives',
                          value: '${stats.attempts}',
                          icon: Icons.repeat_rounded,
                        ),
                        DashboardCard(
                          title: 'Temps moyen',
                          value: stats.averageTimeLabel,
                          icon: Icons.timer_outlined,
                        ),
                      ]
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: e,
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: 'Historique récent',
            subtitle: 'Les dernières sessions sauvegardées localement.',
          ),
          const SizedBox(height: 12),
          if (stats.records.isEmpty)
            const SoftCard(
              child: Text(
                'Aucune session encore. Lance un premier examen pour remplir cet espace.',
              ),
            )
          else
            ...stats.records.take(5).map((r) => HistoryCard(record: r)),
          const SizedBox(height: 18),
          SectionTitle(
            title: 'Base de questions',
            subtitle:
                '${catalog.totalQuestions} questions disponibles sur ${catalog.chapters.length} chapitres.',
          ),
          const SizedBox(height: 12),
          ...catalog.chapters.map((c) => ChapterPreviewCard(chapter: c)),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: 72,
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: const [
            BottomNavChip(
              icon: Icons.home_rounded,
              label: 'Accueil',
              active: true,
            ),
            BottomNavChip(icon: Icons.quiz_outlined, label: 'Examens'),
            BottomNavChip(icon: Icons.insights_outlined, label: 'Stats'),
          ],
        ),
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
                              'Session en cours',
                              style: TextStyle(color: Color(0xFF6A6A6A)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${session.answeredCount}/${session.questions.length} répondues',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TimerChip(value: formatDuration(remaining)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: session.answeredCount / session.questions.length,
                      minHeight: 9,
                      backgroundColor: const Color(0xFFEBEBEB),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ValueListenableBuilder<int>(
                      valueListenable: pageNotifier,
                      builder: (context, current, _) {
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: session.questions.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final active = current == index;
                            final answered = session.answers[index] != null;
                            return GestureDetector(
                              onTap: () => onGoToPage(index),
                              child: Container(
                                width: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFF3B82F6)
                                      : answered
                                      ? const Color(0xFFEFF6FF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: active
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFFEBEBEB),
                                  ),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            );
                          },
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
                onPageChanged: (v) => pageNotifier.value = v,
                itemCount: session.questions.length,
                itemBuilder: (context, index) {
                  final q = session.questions[index];
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
                            q.chapterTitle,
                            style: const TextStyle(
                              color: Color(0xFF6A6A6A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.enonce,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.42,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ...List.generate(q.choices.length, (choiceIndex) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ChoiceTile(
                                  label: optionLetter(choiceIndex),
                                  text: q.choices[choiceIndex],
                                  selected: selected == choiceIndex,
                                  onTap: () => onAnswer(index, choiceIndex),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                                backgroundColor: const Color(0xFF3B82F6),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                last ? 'Valider l’examen' : 'Suivant',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (last) ...[
                        const SizedBox(height: 14),
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
    final percent = ((session.score / session.questions.length) * 100).round();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PremiumPill(label: 'Résultats'),
                const SizedBox(height: 14),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${session.score}/${session.questions.length} bonnes réponses',
                  style: const TextStyle(color: Color(0xFF6A6A6A)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TinyMetric(
                  title: 'Meilleur score',
                  value: stats.bestScoreLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TinyMetric(
                  title: 'Dernier score',
                  value: stats.lastScoreLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TinyMetric(
                  title: 'Temps',
                  value: formatDuration(session.timeSpent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: 'Correction',
            subtitle: 'Lecture claire, compacte, utile.',
          ),
          const SizedBox(height: 12),
          ...List.generate(session.questions.length, (index) {
            final q = session.questions[index];
            final answer = session.answers[index];
            final ok = answer == q.correctIndex;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFEBEBEB)),
              ),
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
                            color: Color(0xFF6A6A6A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        ok ? Icons.check_circle : Icons.cancel,
                        color: ok
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF2563EB),
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
                  const SizedBox(height: 8),
                  Text(
                    'Ta réponse : ${answer == null ? 'Non répondue' : q.choices[answer]}',
                    style: const TextStyle(color: Color(0xFF6A6A6A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bonne réponse : ${q.choices[q.correctIndex]}',
                    style: const TextStyle(
                      color: Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onRestart,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('Relancer un examen'),
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
    );
  }
}

class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF3B82F6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6A6A6A),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF3B82F6),
              shape: BoxShape.circle,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class TinyMetric extends StatelessWidget {
  const TinyMetric({super.key, required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6A6A6A)),
          ),
        ],
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF3B82F6)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Color(0xFF6A6A6A))),
        ],
      ),
    );
  }
}

class BottomNavChip extends StatelessWidget {
  const BottomNavChip({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF3B82F6) : const Color(0xFF6A6A6A);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
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
          color: Color(0xFF3B82F6),
          fontWeight: FontWeight.w700,
        ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$percent%',
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.w800,
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
                  style: const TextStyle(color: Color(0xFF6A6A6A)),
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
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF6A6A6A), height: 1.4),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
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
                  color: Color(0xFF6A6A6A),
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
            style: const TextStyle(color: Color(0xFF6A6A6A), height: 1.4),
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
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFFEBEBEB),
              width: selected ? 1.5 : 1,
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
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFF7F7F7),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : Colors.black87,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Color(0xFF3B82F6), size: 18),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111111),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Résumé avant validation',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            'Répondues : ${session.answeredCount} • Non répondues : $unanswered',
            style: const TextStyle(color: Color(0xFF6A6A6A)),
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
