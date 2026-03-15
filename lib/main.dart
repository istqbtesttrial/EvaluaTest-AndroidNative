import 'dart:async';
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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
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
  late Future<QuestionCatalog> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = QuestionCatalog.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuestionCatalog>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashLoadingScreen();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erreur de chargement des questions : ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return EvaluaTestHome(catalog: snapshot.data!);
      },
    );
  }
}

class EvaluaTestHome extends StatefulWidget {
  const EvaluaTestHome({super.key, required this.catalog});

  final QuestionCatalog catalog;

  @override
  State<EvaluaTestHome> createState() => _EvaluaTestHomeState();
}

class _EvaluaTestHomeState extends State<EvaluaTestHome> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pageController = PageController();
  final _scrollController = ScrollController();

  AppStage _stage = AppStage.login;
  String? _loginError;
  bool _rememberMe = true;
  String _displayName = 'Élève';

  ExamSession? _session;
  Duration _remaining = const Duration(minutes: 75);
  Timer? _timer;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _login() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _loginError = 'Entre ton login et ton mot de passe.';
      });
      return;
    }

    setState(() {
      _displayName = username;
      _loginError = null;
      _stage = AppStage.dashboard;
    });
  }

  void _logout() {
    _timer?.cancel();
    setState(() {
      _stage = AppStage.login;
      _session = null;
      _remaining = const Duration(minutes: 75);
      _loginError = null;
      _passwordController.clear();
    });
  }

  void _startExam() {
    final questions = widget.catalog.allQuestions.take(40).toList();
    final session = ExamSession(
      startedAt: DateTime.now(),
      questions: questions,
      answers: List<int?>.filled(questions.length, null),
    );

    _timer?.cancel();
    _pageController.jumpToPage(0);

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
        return;
      }
      setState(() {
        _remaining -= const Duration(seconds: 1);
      });
    });
  }

  void _answerQuestion(int questionIndex, int choiceIndex) {
    final session = _session;
    if (session == null) return;

    setState(() {
      session.answers[questionIndex] = choiceIndex;
    });
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _submitExam() {
    final session = _session;
    if (session == null) return;

    _timer?.cancel();
    session.completedAt = DateTime.now();
    setState(() {
      _stage = AppStage.results;
    });
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
        );
      case AppStage.dashboard:
        return DashboardScreen(
          displayName: _displayName,
          catalog: widget.catalog,
          rememberMe: _rememberMe,
          onStartExam: _startExam,
          onLogout: _logout,
        );
      case AppStage.exam:
        return ExamScreen(
          session: _session!,
          remaining: _remaining,
          pageController: _pageController,
          scrollController: _scrollController,
          onAnswer: _answerQuestion,
          onGoToPage: _goToPage,
          onSubmit: _submitExam,
        );
      case AppStage.results:
        return ResultsScreen(
          session: _session!,
          onBackToDashboard: () => setState(() => _stage = AppStage.dashboard),
          onRestart: _startExam,
        );
    }
  }
}

enum AppStage { login, dashboard, exam, results }

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
              SizedBox(height: 20),
              Text(
                'Préparation de l’expérience native…',
                style: TextStyle(color: Colors.white, fontSize: 16),
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
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final String? loginError;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 36),
              const Text(
                'EvaluaTest',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version Android native. Plus propre, plus premium, plus fiable.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x330F172A),
                      blurRadius: 30,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PremiumPill(label: 'Espace élèves'),
                    const SizedBox(height: 14),
                    const Text(
                      'Connexion',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Un écran simple, rassurant et pensé mobile dès le départ.',
                      style: TextStyle(color: Color(0xFF475569), height: 1.45),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: usernameController,
                      textInputAction: TextInputAction.next,
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
                        Checkbox(
                          value: rememberMe,
                          onChanged: (value) =>
                              onRememberChanged(value ?? false),
                        ),
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
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Entrer dans l’espace élève'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
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

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.displayName,
    required this.catalog,
    required this.rememberMe,
    required this.onStartExam,
    required this.onLogout,
  });

  final String displayName;
  final QuestionCatalog catalog;
  final bool rememberMe;
  final VoidCallback onStartExam;
  final VoidCallback onLogout;

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
                                'Bonsoir $displayName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Prêt pour une session ISTQB propre, lisible et sans friction.',
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
                        DashboardMetric(
                          label: 'Questions',
                          value: '${catalog.totalQuestions}',
                          icon: Icons.quiz_outlined,
                        ),
                        DashboardMetric(
                          label: 'Chapitres',
                          value: '${catalog.chapters.length}',
                          icon: Icons.layers_outlined,
                        ),
                        DashboardMetric(
                          label: 'Mode',
                          value: rememberMe ? 'Mémoire ON' : 'Session',
                          icon: Icons.phone_android_outlined,
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
                const SectionTitle(
                  title: 'Session d’examen',
                  subtitle:
                      'Une expérience directe : démarrage simple, progression claire, correction propre.',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: _cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Examen blanc Foundation Level',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '40 questions • 75 minutes • navigation fluide • rendu mobile-first',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onStartExam,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Commencer l’examen'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Chapitres disponibles',
                  subtitle:
                      'La base de questions existante est déjà branchée dans la nouvelle app native.',
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
    required this.scrollController,
    required this.onAnswer,
    required this.onGoToPage,
    required this.onSubmit,
  });

  final ExamSession session;
  final Duration remaining;
  final PageController pageController;
  final ScrollController scrollController;
  final void Function(int questionIndex, int choiceIndex) onAnswer;
  final void Function(int index) onGoToPage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final progress = session.answeredCount / session.questions.length;

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
                      value: progress,
                      minHeight: 10,
                      backgroundColor: const Color(0xFFE2E8F0),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: session.questions.length,
                itemBuilder: (context, index) {
                  final question = session.questions[index];
                  final selected = session.answers[index];
                  final isLast = index == session.questions.length - 1;

                  return SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: _cardDecoration(),
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
                                final isSelected = selected == choiceIndex;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ChoiceTile(
                                    label: optionLetter(choiceIndex),
                                    text: question.choices[choiceIndex],
                                    selected: isSelected,
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
                                onPressed: isLast
                                    ? onSubmit
                                    : () => onGoToPage(index + 1),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                                child: Text(
                                  isLast ? 'Valider l’examen' : 'Suivant',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (isLast) SubmitSummaryCard(session: session),
                      ],
                    ),
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
    required this.onBackToDashboard,
    required this.onRestart,
  });

  final ExamSession session;
  final VoidCallback onBackToDashboard;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final score = session.score;
    final percent = ((score / session.questions.length) * 100).round();

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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
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
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$score / ${session.questions.length} bonnes réponses',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                DashboardMetric(
                  label: 'Bonnes',
                  value: '$score',
                  icon: Icons.check_circle_outline,
                ),
                DashboardMetric(
                  label: 'Répondues',
                  value: '${session.answeredCount}',
                  icon: Icons.edit_note_outlined,
                ),
                DashboardMetric(
                  label: 'Temps utilisé',
                  value: formatDuration(session.timeSpent),
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionTitle(
              title: 'Correction rapide',
              subtitle:
                  'Lecture claire question par question pour un vrai ressenti premium.',
            ),
            const SizedBox(height: 12),
            ...List.generate(session.questions.length, (index) {
              final question = session.questions[index];
              final answer = session.answers[index];
              final isCorrect = answer == question.correctIndex;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PremiumPill(label: 'Q${index + 1}'),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            question.chapterTitle,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          isCorrect ? Icons.check_circle : Icons.cancel,
                          color: isCorrect
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      question.enonce,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ta réponse : ${answer == null ? 'Non répondue' : question.choices[answer]}',
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bonne réponse : ${question.choices[question.correctIndex]}',
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Relancer un examen'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
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

class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
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
      decoration: _cardDecoration(),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
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
            'Répondues : ${session.answeredCount} • Non répondues : ${session.questions.length - session.answeredCount}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class QuestionCatalog {
  QuestionCatalog({required this.chapters});

  final List<ChapterInfo> chapters;

  int get totalQuestions =>
      chapters.fold(0, (sum, chapter) => sum + chapter.questions.length);

  List<QuestionItem> get allQuestions => [
    for (final chapter in chapters) ...chapter.questions,
  ];

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
      if (answers[i] == questions[i].correctIndex) {
        total++;
      }
    }
    return total;
  }

  Duration get timeSpent =>
      (completedAt ?? DateTime.now()).difference(startedAt);
}

String optionLetter(int index) => String.fromCharCode(65 + index);

String formatDuration(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(24),
  boxShadow: const [
    BoxShadow(color: Color(0x120F172A), blurRadius: 28, offset: Offset(0, 14)),
  ],
);
