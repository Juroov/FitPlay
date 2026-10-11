import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('fittrack_dark_mode') ?? true;

  final appState = AppState(initialDarkMode: isDarkMode);

  runApp(
    ChangeNotifierProvider.value(value: appState, child: const FitTrackApp()),
  );
}

// ==========================================
// DATA MODELS (Domain Layer)
// ==========================================

class Exercise {
  final String id;
  String name;
  int sets;
  int reps;
  double? weight;
  List<double>? setWeights;
  String? notes;
  bool isCompleted;

  Exercise({
    required this.id,
    required this.name,
    this.sets = 3,
    this.reps = 10,
    this.weight,
    this.setWeights,
    this.notes,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'sets': sets,
    'reps': reps,
    'weight': weight,
    'setWeights': setWeights,
    'notes': notes,
    'isCompleted': isCompleted,
  };

  factory Exercise.fromMap(Map<String, dynamic> map) => Exercise(
    id: map['id'] ?? UniqueKey().toString(),
    name: map['name'] ?? 'Exercise',
    sets: map['sets'] is int ? map['sets'] : 3,
    reps: map['reps'] is int ? map['reps'] : 10,
    weight: (map['weight'] != null) ? (map['weight'] as num).toDouble() : null,
    setWeights: (map['setWeights'] as List<dynamic>?)
        ?.map((e) => (e as num).toDouble())
        .toList(),
    notes: map['notes'],
    isCompleted: map['isCompleted'] ?? false,
  );

  Exercise copyWith({
    String? id,
    String? name,
    int? sets,
    int? reps,
    double? weight,
    List<double>? setWeights,
    String? notes,
    bool? isCompleted,
  }) => Exercise(
    id: id ?? this.id,
    name: name ?? this.name,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    weight: weight ?? this.weight,
    setWeights:
        setWeights ??
        (this.setWeights != null ? List<double>.from(this.setWeights!) : null),
    notes: notes ?? this.notes,
    isCompleted: isCompleted ?? this.isCompleted,
  );

  List<double> getEffectiveSetWeights() {
    if (setWeights != null && setWeights!.isNotEmpty) {
      if (setWeights!.length == sets) return setWeights!;
      if (setWeights!.length < sets) {
        final last = setWeights!.last;
        return [
          ...setWeights!,
          ...List.filled(sets - setWeights!.length, last),
        ];
      }
      return setWeights!.sublist(0, sets);
    }
    return List.filled(sets, weight ?? 0.0);
  }

  String formatWeightsSummary(String units) {
    final effective = getEffectiveSetWeights();
    if (effective.every((w) => w <= 0.0)) {
      if (weight != null && weight! > 0) {
        final wStr = weight!.truncateToDouble() == weight!
            ? weight!.toInt().toString()
            : weight!.toString();
        return '$wStr $units';
      }
      return '';
    }
    final first = effective.first;
    if (effective.every((w) => w == first)) {
      final wStr = first.truncateToDouble() == first
          ? first.toInt().toString()
          : first.toString();
      return '$wStr $units';
    }
    return '${effective.map((w) => w.truncateToDouble() == w ? w.toInt().toString() : w.toString()).join(' · ')} $units';
  }
}

class Workout {
  final String id;
  String name;
  String category; // push, pull, legs, upper, lower, custom
  List<Exercise> exercises;
  bool archived;

  Workout({
    required this.id,
    required this.name,
    required this.category,
    required this.exercises,
    this.archived = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'exercises': exercises.map((e) => e.toMap()).toList(),
    'archived': archived,
  };

  factory Workout.fromMap(Map<String, dynamic> map) => Workout(
    id: map['id'] ?? UniqueKey().toString(),
    name: map['name'] ?? 'Workout',
    category: map['category'] ?? 'custom',
    exercises:
        (map['exercises'] as List<dynamic>?)
            ?.map((e) => Exercise.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [],
    archived: map['archived'] ?? false,
  );

  Workout copyWith({
    String? id,
    String? name,
    String? category,
    List<Exercise>? exercises,
    bool? archived,
  }) => Workout(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    exercises: exercises ?? this.exercises.map((e) => e.copyWith()).toList(),
    archived: archived ?? this.archived,
  );
}

class WorkoutLog {
  final String id; // format: yyyy-MM-dd_workoutId
  final String workoutId;
  final String workoutName;
  final String category;
  final String date; // yyyy-MM-dd
  final DateTime completedAt;
  final int durationSeconds;
  final List<Exercise> exercises;

  WorkoutLog({
    required this.id,
    required this.workoutId,
    required this.workoutName,
    required this.category,
    required this.date,
    required this.completedAt,
    required this.durationSeconds,
    required this.exercises,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'workoutId': workoutId,
    'workoutName': workoutName,
    'category': category,
    'date': date,
    'completedAt': completedAt.toIso8601String(),
    'durationSeconds': durationSeconds,
    'exercises': exercises.map((e) => e.toMap()).toList(),
  };

  factory WorkoutLog.fromMap(Map<String, dynamic> map) => WorkoutLog(
    id: map['id'] ?? '',
    workoutId: map['workoutId'] ?? '',
    workoutName: map['workoutName'] ?? '',
    category: map['category'] ?? 'custom',
    date: map['date'] ?? '',
    completedAt: map['completedAt'] != null
        ? DateTime.parse(map['completedAt'])
        : DateTime.now(),
    durationSeconds: map['durationSeconds'] ?? 0,
    exercises:
        (map['exercises'] as List<dynamic>?)
            ?.map((e) => Exercise.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

// ==========================================
// APPLICATION STATE & CONTROLLER
// ==========================================

class AppState extends ChangeNotifier {
  AppState({bool initialDarkMode = true}) : _isDarkMode = initialDarkMode;

  static const _googleWebClientId =
      '1039199888579-f9kdl8u8ssej12l9cttec5po9umjmqrs.apps.googleusercontent.com';
  Future<void>? _googleSignInInitialization;

  bool _isDarkMode;
  bool get isDarkMode => _isDarkMode;

  // Auth state — driven by FirebaseAuth
  bool _isAuthenticated = false;
  String _userEmail = '';
  String _displayName = '';
  String _units = 'kg'; // 'kg' or 'lb'

  bool get isAuthenticated => _isAuthenticated;
  String get userEmail => _userEmail;
  String get displayName => _displayName;
  String get units => _units;

  // Workouts and schedule
  List<Workout> _workouts = [];
  Map<String, List<String>> _weeklySchedule = {
    '1': ['push-1'], // Mon
    '2': ['pull-1'], // Tue
    '3': [], // Wed (Rest)
    '4': ['legs-1'], // Thu
    '5': ['upper-1'], // Fri
    '6': [], // Sat (Rest)
    '7': [], // Sun (Rest)
  };

  // Completed logs
  List<WorkoutLog> _logs = [];

  List<Workout> get workouts => _workouts.where((w) => !w.archived).toList();
  Map<String, List<String>> get weeklySchedule => _weeklySchedule;
  List<WorkoutLog> get logs => List.unmodifiable(_logs);

  // Active workout session state
  Workout? _activeWorkoutSession;
  int _sessionSeconds = 0;
  Timer? _sessionTimer;

  Workout? get activeWorkoutSession => _activeWorkoutSession;
  int get sessionSeconds => _sessionSeconds;
  bool get isSessionRunning => _activeWorkoutSession != null;

  // Storage key constants (kept for dark-mode preference only)
  static const _kDarkModeKey = 'fittrack_dark_mode';
  static const _kUnitsKey = 'fittrack_units';

  // ── Firestore helpers ──────────────────────────────────────────────────────

  bool get isFirebaseAvailable => Firebase.apps.isNotEmpty;

  String? get _uid =>
      isFirebaseAvailable ? FirebaseAuth.instance.currentUser?.uid : null;

  CollectionReference<Map<String, dynamic>>? get _workoutsCol =>
      (isFirebaseAvailable && _uid != null)
      ? FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('workouts')
      : null;

  CollectionReference<Map<String, dynamic>>? get _logsCol =>
      (isFirebaseAvailable && _uid != null)
      ? FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('logs')
      : null;

  DocumentReference<Map<String, dynamic>>? get _scheduleDoc =>
      (isFirebaseAvailable && _uid != null)
      ? FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('meta')
            .doc('schedule')
      : null;

  // ── Load user data from Firestore after sign-in ────────────────────────────

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _units = prefs.getString(_kUnitsKey) ?? 'kg';

    if (!isFirebaseAvailable || _uid == null) {
      if (_workouts.isEmpty) {
        await _initDefaultTemplates();
      }
      notifyListeners();
      return;
    }

    // Load profile metadata
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        if (data['displayName'] is String &&
            (data['displayName'] as String).isNotEmpty) {
          _displayName = data['displayName'] as String;
        }
        if (data['units'] is String) {
          _units = data['units'] as String;
        }
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    }

    // Load workouts
    try {
      final snap = await _workoutsCol?.get();
      if (snap == null || snap.docs.isEmpty) {
        await _initDefaultTemplates();
      } else {
        _workouts = snap.docs.map((d) => Workout.fromMap(d.data())).toList();
      }
    } catch (_) {
      if (_workouts.isEmpty) {
        await _initDefaultTemplates();
      }
    }

    // Load schedule
    try {
      final schedSnap = await _scheduleDoc?.get();
      if (schedSnap != null && schedSnap.exists && schedSnap.data() != null) {
        final raw = schedSnap.data()!;
        _weeklySchedule = raw.map(
          (k, v) => MapEntry(
            k,
            (v as List<dynamic>).map((e) => e.toString()).toList(),
          ),
        );
      }
    } catch (_) {}

    // Load logs
    try {
      final logsSnap = await _logsCol
          ?.orderBy('completedAt', descending: true)
          .get();
      if (logsSnap != null) {
        _logs = logsSnap.docs.map((d) => WorkoutLog.fromMap(d.data())).toList();
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> _saveWorkouts() async {
    if (!isFirebaseAvailable || _uid == null || _workoutsCol == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      // Overwrite all workout docs
      for (final w in _workouts) {
        batch.set(_workoutsCol!.doc(w.id), w.toMap());
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Firestore save workouts error: $e');
    }
  }

  Future<void> _saveSchedule() async {
    if (!isFirebaseAvailable || _uid == null || _scheduleDoc == null) return;
    try {
      await _scheduleDoc!.set(_weeklySchedule);
    } catch (e) {
      debugPrint('Firestore save schedule error: $e');
    }
  }

  Future<void> saveLog(WorkoutLog log) async {
    if (!isFirebaseAvailable || _uid == null || _logsCol == null) return;
    try {
      await _logsCol!.doc(log.id).set(log.toMap());
    } catch (e) {
      debugPrint('Error saving log to Firestore: $e');
    }
  }

  Future<void> _deleteLog(String logId) async {
    if (!isFirebaseAvailable || _uid == null || _logsCol == null) return;
    try {
      await _logsCol!.doc(logId).delete();
    } catch (e) {
      debugPrint('Error deleting log from Firestore: $e');
    }
  }

  Future<void> _initDefaultTemplates() async {
    _workouts = [
      Workout(
        id: 'push-1',
        name: 'Push Day (Chest, Delts, Triceps)',
        category: 'push',
        exercises: [
          Exercise(
            id: 'p1',
            name: 'Barbell Bench Press',
            sets: 4,
            reps: 8,
            weight: 70,
            notes: 'Warm up thoroughly',
          ),
          Exercise(
            id: 'p2',
            name: 'Incline Dumbbell Press',
            sets: 3,
            reps: 10,
            weight: 24,
            notes: 'Focus on upper chest contraction',
          ),
          Exercise(
            id: 'p3',
            name: 'Overhead Shoulder Press',
            sets: 3,
            reps: 10,
            weight: 45,
          ),
          Exercise(
            id: 'p4',
            name: 'Cable Lateral Raises',
            sets: 4,
            reps: 15,
            weight: 10,
          ),
          Exercise(
            id: 'p5',
            name: 'Tricep Rope Pushdowns',
            sets: 3,
            reps: 12,
            weight: 25,
          ),
        ],
      ),
      Workout(
        id: 'pull-1',
        name: 'Pull Day (Back & Biceps)',
        category: 'pull',
        exercises: [
          Exercise(
            id: 'pl1',
            name: 'Barbell Deadlift',
            sets: 3,
            reps: 5,
            weight: 110,
            notes: 'Keep spine neutral',
          ),
          Exercise(
            id: 'pl2',
            name: 'Lat Pulldowns',
            sets: 4,
            reps: 10,
            weight: 60,
          ),
          Exercise(
            id: 'pl3',
            name: 'Seated Cable Rows',
            sets: 3,
            reps: 10,
            weight: 55,
          ),
          Exercise(
            id: 'pl4',
            name: 'Face Pulls',
            sets: 3,
            reps: 15,
            weight: 20,
          ),
          Exercise(
            id: 'pl5',
            name: 'Dumbbell Hammer Curls',
            sets: 3,
            reps: 12,
            weight: 16,
          ),
        ],
      ),
      Workout(
        id: 'legs-1',
        name: 'Leg Day (Quads & Hamstrings)',
        category: 'legs',
        exercises: [
          Exercise(
            id: 'lg1',
            name: 'Barbell Back Squat',
            sets: 4,
            reps: 8,
            weight: 85,
          ),
          Exercise(
            id: 'lg2',
            name: 'Romanian Deadlift',
            sets: 3,
            reps: 10,
            weight: 70,
          ),
          Exercise(
            id: 'lg3',
            name: 'Leg Press',
            sets: 3,
            reps: 12,
            weight: 150,
          ),
          Exercise(
            id: 'lg4',
            name: 'Lying Leg Curls',
            sets: 3,
            reps: 12,
            weight: 45,
          ),
          Exercise(
            id: 'lg5',
            name: 'Standing Calf Raises',
            sets: 4,
            reps: 15,
            weight: 50,
          ),
        ],
      ),
      Workout(
        id: 'upper-1',
        name: 'Upper Body Pump',
        category: 'upper',
        exercises: [
          Exercise(
            id: 'u1',
            name: 'Incline Barbell Press',
            sets: 3,
            reps: 8,
            weight: 65,
          ),
          Exercise(
            id: 'u2',
            name: 'Chest-Supported Row',
            sets: 3,
            reps: 10,
            weight: 26,
          ),
          Exercise(
            id: 'u3',
            name: 'Dumbbell Shoulder Press',
            sets: 3,
            reps: 10,
            weight: 20,
          ),
          Exercise(
            id: 'u4',
            name: 'EZ-Bar Bicep Curls',
            sets: 3,
            reps: 12,
            weight: 28,
          ),
          Exercise(
            id: 'u5',
            name: 'Skull Crushers',
            sets: 3,
            reps: 12,
            weight: 25,
          ),
        ],
      ),
      Workout(
        id: 'lower-1',
        name: 'Lower Body Strength',
        category: 'lower',
        exercises: [
          Exercise(
            id: 'lw1',
            name: 'Front Squats',
            sets: 3,
            reps: 8,
            weight: 60,
          ),
          Exercise(
            id: 'lw2',
            name: 'Bulgarian Split Squats',
            sets: 3,
            reps: 10,
            weight: 16,
          ),
          Exercise(
            id: 'lw3',
            name: 'Leg Extensions',
            sets: 3,
            reps: 15,
            weight: 50,
          ),
        ],
      ),
    ];
    await _saveWorkouts();
    await _saveSchedule();
  }

  // ── Auth actions (FirebaseAuth) ────────────────────────────────────────────

  Future<void> login(String email, String password) async {
    if (isFirebaseAvailable) {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;
      _isAuthenticated = true;
      _userEmail = user.email ?? email;
      _displayName = user.displayName ?? email.split('@').first;
      await loadUserData();
    } else {
      _isAuthenticated = true;
      _userEmail = email;
      _displayName = email.split('@').first;
      if (_workouts.isEmpty) {
        await _initDefaultTemplates();
      }
    }
    notifyListeners();
  }

  Future<void> register(String name, String email, String password) async {
    if (isFirebaseAvailable) {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;
      await user.updateDisplayName(name);
      _isAuthenticated = true;
      _displayName = name;
      _userEmail = user.email ?? email;
      // Persist user document in Firestore
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'displayName': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'units': _units,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore profile creation error: $e');
      }
      // Seed default templates into Firestore for new user
      await _initDefaultTemplates();
      await loadUserData();
    } else {
      _isAuthenticated = true;
      _displayName = name;
      _userEmail = email;
      if (_workouts.isEmpty) {
        await _initDefaultTemplates();
      }
    }
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    if (!isFirebaseAvailable) {
      throw FirebaseAuthException(
        code: 'firebase-unavailable',
        message: 'Firebase is unavailable on this platform.',
      );
    }

    final UserCredential credential;
    if (kIsWeb) {
      credential = await FirebaseAuth.instance.signInWithPopup(
        GoogleAuthProvider(),
      );
    } else {
      _googleSignInInitialization ??= GoogleSignIn.instance.initialize(
        serverClientId: _googleWebClientId,
      );
      await _googleSignInInitialization;
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final firebaseCredential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      credential = await FirebaseAuth.instance.signInWithCredential(
        firebaseCredential,
      );
    }

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'missing-user',
        message: 'Google sign-in did not return a user account.',
      );
    }

    _isAuthenticated = true;
    _userEmail = user.email ?? '';
    _displayName =
        user.displayName ?? user.email?.split('@').first ?? 'Athlete';

    try {
      final profile = <String, dynamic>{
        'displayName': _displayName,
        'email': _userEmail,
        'units': _units,
        'lastSignInAt': FieldValue.serverTimestamp(),
      };
      if (credential.additionalUserInfo?.isNewUser ?? false) {
        profile['createdAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(profile, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Google profile sync error: $error');
    }

    await loadUserData();
    notifyListeners();
  }

  Future<void> logout() async {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _activeWorkoutSession = null;
    _sessionSeconds = 0;
    if (isFirebaseAvailable) {
      if (!kIsWeb) {
        try {
          _googleSignInInitialization ??= GoogleSignIn.instance.initialize(
            serverClientId: _googleWebClientId,
          );
          await _googleSignInInitialization;
          await GoogleSignIn.instance.signOut();
        } catch (error) {
          debugPrint('Google sign-out notice: $error');
        }
      }
      await FirebaseAuth.instance.signOut();
    }
    _isAuthenticated = false;
    _workouts = [];
    _logs = [];
    _weeklySchedule = {
      '1': [],
      '2': [],
      '3': [],
      '4': [],
      '5': [],
      '6': [],
      '7': [],
    };
    _userEmail = '';
    _displayName = '';
    notifyListeners();
  }

  /// Called by FitTrackApp when FirebaseAuth reports an existing session
  Future<void> restoreSession(User user) async {
    _isAuthenticated = true;
    _userEmail = user.email ?? '';
    _displayName =
        user.displayName ?? user.email?.split('@').first ?? 'Athlete';
    await loadUserData();
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String units,
  }) async {
    _displayName = name;
    _units = units;
    if (isFirebaseAvailable) {
      // Update Firebase display name
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      if (_uid != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(_uid).set({
            'displayName': name,
            'units': units,
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Firestore profile update error: $e');
        }
      }
    }
    // Persist units preference locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUnitsKey, _units);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkModeKey, _isDarkMode);
  }

  Future<void> loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_kDarkModeKey) ?? true;
    notifyListeners();
  }

  // Workout CRUD
  void addWorkout(Workout workout) {
    _workouts.add(workout);
    _saveWorkouts();
    notifyListeners();
  }

  void updateWorkout(Workout updated) {
    final index = _workouts.indexWhere((w) => w.id == updated.id);
    if (index != -1) {
      _workouts[index] = updated;
      _saveWorkouts();
      notifyListeners();
    }
  }

  void archiveWorkout(String workoutId) {
    final index = _workouts.indexWhere((w) => w.id == workoutId);
    if (index != -1) {
      _workouts[index].archived = true;
      // Also remove from weekly schedule
      for (final key in _weeklySchedule.keys) {
        _weeklySchedule[key]?.remove(workoutId);
      }
      _saveWorkouts();
      _saveSchedule();
      notifyListeners();
    }
  }

  void setDayWorkouts(int isoWeekday, List<String> workoutIds) {
    _weeklySchedule[isoWeekday.toString()] = workoutIds;
    _saveSchedule();
    notifyListeners();
  }

  // Active workout session methods
  void startWorkoutSession(Workout workout) {
    // Clone workout so session edits don't mutate original
    _activeWorkoutSession = workout.copyWith(
      exercises: workout.exercises
          .map((e) => e.copyWith(isCompleted: false))
          .toList(),
    );
    _sessionSeconds = 0;
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sessionSeconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  void toggleExerciseInSession(int index) {
    if (_activeWorkoutSession != null &&
        index >= 0 &&
        index < _activeWorkoutSession!.exercises.length) {
      final current = _activeWorkoutSession!.exercises[index].isCompleted;
      _activeWorkoutSession!.exercises[index].isCompleted = !current;
      notifyListeners();
    }
  }

  void cancelActiveSession() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _activeWorkoutSession = null;
    _sessionSeconds = 0;
    notifyListeners();
  }

  Future<void> completeActiveSession() async {
    if (_activeWorkoutSession == null) return;
    _sessionTimer?.cancel();

    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    final logId =
        '${dateKey}_${_activeWorkoutSession!.id}_${now.millisecondsSinceEpoch}';

    final newLog = WorkoutLog(
      id: logId,
      workoutId: _activeWorkoutSession!.id,
      workoutName: _activeWorkoutSession!.name,
      category: _activeWorkoutSession!.category,
      date: dateKey,
      completedAt: now,
      durationSeconds: _sessionSeconds,
      exercises: _activeWorkoutSession!.exercises
          .map((e) => e.copyWith())
          .toList(),
    );

    // Remove existing log for the same workout & date if any
    _logs.removeWhere((l) => l.id == logId);
    _logs.insert(0, newLog);
    await saveLog(newLog);

    _activeWorkoutSession = null;
    _sessionSeconds = 0;
    notifyListeners();
  }

  Future<void> undoCompletion(String logId) async {
    _logs.removeWhere((l) => l.id == logId);
    await _deleteLog(logId);
    notifyListeners();
  }

  // Helpers
  List<Workout> getTodaysWorkouts() {
    final todayWeekday = DateTime.now().weekday.toString();
    final ids = _weeklySchedule[todayWeekday] ?? [];
    return _workouts.where((w) => !w.archived && ids.contains(w.id)).toList();
  }

  List<Workout> getWorkoutsForDay(int isoWeekday) {
    final ids = _weeklySchedule[isoWeekday.toString()] ?? [];
    return _workouts.where((w) => !w.archived && ids.contains(w.id)).toList();
  }

  bool isWorkoutCompletedToday(String workoutId) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _logs.any((l) => l.workoutId == workoutId && l.date == todayStr);
  }

  int getWeeklyStreak() {
    if (_logs.isEmpty) return 0;
    // Calculate distinct weeks with at least 1 completed workout
    final Set<String> weeksWithWorkouts = {};
    for (final log in _logs) {
      final weekNum =
          (log.completedAt
                      .difference(DateTime(log.completedAt.year, 1, 1))
                      .inDays /
                  7)
              .floor();
      weeksWithWorkouts.add('${log.completedAt.year}-$weekNum');
    }
    return weeksWithWorkouts.length;
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}

Future<void> _openWorkoutSession(
  BuildContext context,
  AppState appState,
  Workout workout,
) async {
  final activeWorkout = appState.activeWorkoutSession;
  if (activeWorkout != null && activeWorkout.id != workout.id) {
    final shouldReplace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace Active Workout?'),
        content: Text(
          '“${activeWorkout.name}” is still in progress. Starting “${workout.name}” will discard that session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Current'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start New'),
          ),
        ],
      ),
    );
    if (shouldReplace != true || !context.mounted) return;
    appState.cancelActiveSession();
  }

  if (!appState.isSessionRunning) {
    appState.startWorkoutSession(workout);
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ActiveSessionScreen()),
  );
}

class _TileMaterial extends StatelessWidget {
  const _TileMaterial({required this.child, required this.borderRadius});

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ==========================================
// ROOT APPLICATION & THEME
// ==========================================

class FitTrackApp extends StatelessWidget {
  const FitTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Pure High-Contrast Monochrome (Black & White) System
    const darkColorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFFFFF),
      onPrimary: Color(0xFF000000),
      primaryContainer: Color(0xFF1C1C21),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFFA1A1AA),
      onSecondary: Color(0xFF000000),
      surface: Color(0xFF0D0D10),
      onSurface: Color(0xFFF4F4F5),
      surfaceContainer: Color(0xFF141418),
      surfaceContainerHigh: Color(0xFF1C1C22),
      outline: Color(0xFF27272A),
      outlineVariant: Color(0xFF3F3F46),
      error: Color(0xFFEF4444),
      onError: Color(0xFFFFFFFF),
    );

    const lightColorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF09090B),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFF4F4F5),
      onPrimaryContainer: Color(0xFF09090B),
      secondary: Color(0xFF71717A),
      onSecondary: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF09090B),
      surfaceContainer: Color(0xFFF4F4F5),
      surfaceContainerHigh: Color(0xFFE4E4E7),
      outline: Color(0xFFE4E4E7),
      outlineVariant: Color(0xFFD4D4D8),
      error: Color(0xFFEF4444),
      onError: Color(0xFFFFFFFF),
    );

    final textThemeLight = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.light().textTheme,
    );
    final textThemeDark = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'FITPLAY',
      debugShowCheckedModeBanner: false,
      themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: lightColorScheme,
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        textTheme: textThemeLight,
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFFFFFFF),
          foregroundColor: const Color(0xFF09090B),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 64,
          titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF09090B),
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFFFF),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE4E4E7), width: 1.2),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE4E4E7),
          thickness: 1,
          space: 1,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          minVerticalPadding: 12,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F4F5),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF09090B), width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF09090B),
            foregroundColor: const Color(0xFFFFFFFF),
            elevation: 0,
            minimumSize: const Size(64, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: -0.2,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF09090B),
            minimumSize: const Size(64, 52),
            side: const BorderSide(color: Color(0xFFD4D4D8), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: const Color(0xFFFFFFFF),
          indicatorColor: const Color(0xFF09090B),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFFFFFFFF), size: 22);
            }
            return const IconThemeData(color: Color(0xFF71717A), size: 22);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF09090B),
              );
            }
            return GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF71717A),
            );
          }),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: darkColorScheme,
        scaffoldBackgroundColor: const Color(0xFF000000), // Pure OLED obsidian
        textTheme: textThemeDark,
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF000000),
          foregroundColor: const Color(0xFFF4F4F5),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 64,
          titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFF4F4F5),
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0D0D10),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF27272A), width: 1.2),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF27272A),
          thickness: 1,
          space: 1,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          minVerticalPadding: 12,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141418),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF27272A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF27272A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFFFFFF), width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFFFFF),
            foregroundColor: const Color(0xFF000000),
            elevation: 0,
            minimumSize: const Size(64, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: -0.2,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF4F4F5),
            minimumSize: const Size(64, 52),
            side: const BorderSide(color: Color(0xFF3F3F46), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: const Color(0xFF000000),
          indicatorColor: const Color(0xFFFFFFFF),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF000000), size: 22);
            }
            return const IconThemeData(color: Color(0xFFA1A1AA), size: 22);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFFFFF),
              );
            }
            return GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFA1A1AA),
            );
          }),
        ),
      ),
      home: !appState.isFirebaseAvailable
          ? (appState.isAuthenticated
                ? const FitTrackMainShell()
                : const AuthScreen())
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasData && snapshot.data != null) {
                  // Restore session in AppState if needed (e.g. after hot restart)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!appState.isAuthenticated) {
                      appState.restoreSession(snapshot.data!);
                    }
                  });
                  return const FitTrackMainShell();
                }
                return const AuthScreen();
              },
            ),
    );
  }
}

// ==========================================
// AUTHENTICATION SCREEN (LOGIN & REGISTER)
// ==========================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isSignUp = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    try {
      if (isSignUp) {
        await appState.register(
          nameController.text.trim(),
          emailController.text.trim(),
          passwordController.text,
        );
      } else {
        await appState.login(
          emailController.text.trim(),
          passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Authentication failed'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await context.read<AppState>().signInWithGoogle();
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.description ?? 'Google authentication failed'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Google authentication failed'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google authentication failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Icon
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFF141418)
                              : const Color(0xFF09090B),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.fitness_center_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'FITPLAY',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'HIGH PERFORMANCE WORKOUT TRACKING',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isSignUp
                          ? 'Create your athlete profile to start tracking sets'
                          : 'Welcome back. Build strength, record progressive overload.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (!appState.isFirebaseAvailable) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Windows Local Mode: Firebase Auth & Firestore run on Android or Web (flutter run -d chrome).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (isSignUp) ...[
                      TextFormField(
                        controller: nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Display Name',
                          prefixIcon: const Icon(Icons.person_outline),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter your name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (v) => (v == null || !v.trim().contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Minimum 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 28),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: (_isLoading || _isGoogleLoading)
                          ? null
                          : _submit,
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Text(
                              isSignUp ? 'Create Account' : 'Sign In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'OR',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 18),

                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: (_isLoading || _isGoogleLoading)
                          ? null
                          : _submitGoogle,
                      icon: _isGoogleLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'G',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: (_isLoading || _isGoogleLoading)
                          ? null
                          : () => setState(() => isSignUp = !isSignUp),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        isSignUp
                            ? 'Already have an account? Sign In'
                            : "Don't have an account? Create one",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MAIN APP SHELL (BOTTOM NAVIGATION)
// ==========================================

class FitTrackMainShell extends StatefulWidget {
  const FitTrackMainShell({super.key});

  @override
  State<FitTrackMainShell> createState() => _FitTrackMainShellState();
}

class _FitTrackMainShellState extends State<FitTrackMainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final pages = [
      const DashboardTab(),
      const ScheduleTab(),
      const HistoryTab(),
      const ProfileTab(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          pages[_currentIndex],
          // Floating active session bar if workout in progress
          if (appState.isSessionRunning)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _ActiveSessionBanner(
                workout: appState.activeWorkoutSession!,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_toggle_off_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  final Workout workout;
  const _ActiveSessionBanner({required this.workout});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final minutes = (appState.sessionSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (appState.sessionSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : const Color(0xFF09090B),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: isDark ? const Color(0xFF27272A) : const Color(0xFF3F3F46),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.timer_outlined,
              color: Colors.black,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  workout.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'IN PROGRESS · $minutes:$seconds',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: const Color(0xFFA1A1AA),
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => _openWorkoutSession(context, appState, workout),
            child: const Text(
              'Resume',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 1: DASHBOARD (TODAY'S WORKOUT & STREAK)
// ==========================================

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late int _selectedIsoWeekday;

  @override
  void initState() {
    super.initState();
    _selectedIsoWeekday = DateTime.now().weekday;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final today = DateTime.now();
    final currentIsoWeekday = today.weekday;
    final isViewingToday = _selectedIsoWeekday == currentIsoWeekday;

    final selectedDayWorkouts = appState.getWorkoutsForDay(_selectedIsoWeekday);
    final streak = appState.getWeeklyStreak();

    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final selectedDayName = dayNames[_selectedIsoWeekday - 1];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi, ${appState.displayName} 👋',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              DateFormat('EEEE, MMMM d').format(today),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: appState.isDarkMode ? 'Light mode' : 'Dark mode',
            icon: Icon(
              appState.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () => appState.toggleTheme(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Weekly Mon-Sun Interactive Day Selector
          _buildWeeklyInteractiveStrip(context, appState, currentIsoWeekday),
          const SizedBox(height: 16),

          // Streak & Overview Card
          _buildStreakCard(context, streak),
          const SizedBox(height: 24),

          // Selected Day Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    isViewingToday ? "Today's Plan" : "$selectedDayName's Plan",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (!isViewingToday) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        'PREVIEWING',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!isViewingToday)
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedIsoWeekday = currentIsoWeekday),
                  child: const Text(
                    'Back to Today',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else if (selectedDayWorkouts.isNotEmpty)
                Text(
                  '${selectedDayWorkouts.length} scheduled',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Selected Day Workout Cards or Rest Day
          if (selectedDayWorkouts.isEmpty)
            _buildRestDayCard(
              context,
              isViewingToday ? 'Today' : selectedDayName,
            )
          else
            ...selectedDayWorkouts.map((workout) {
              final isDone =
                  isViewingToday &&
                  appState.isWorkoutCompletedToday(workout.id);
              return _WorkoutTodayCard(
                workout: workout,
                isDone: isDone,
                isToday: isViewingToday,
                dayLabel: isViewingToday ? 'Today' : selectedDayName,
              );
            }),

          const SizedBox(height: 28),

          // ----------------------------------------------------
          // UPCOMING DAYS & CORRESPONDING PROGRAMS OVERVIEW
          // ----------------------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_view_week_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Upcoming Days & Programs',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              Text(
                'Next 6 days',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Upcoming Days Cards List
          ..._buildUpcomingDaysOverview(context, appState, today),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildWeeklyInteractiveStrip(
    BuildContext context,
    AppState appState,
    int currentIsoWeekday,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D10) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WEEKLY SCHEDULE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.secondary,
                ),
              ),
              Text(
                'Tap day to inspect',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final isoDay = index + 1;
              final isToday = isoDay == currentIsoWeekday;
              final isSelected = isoDay == _selectedIsoWeekday;
              final scheduled =
                  appState.weeklySchedule[isoDay.toString()] ?? [];
              final hasScheduledWorkout = scheduled.isNotEmpty;

              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  setState(() {
                    _selectedIsoWeekday = isoDay;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        days[index],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: (isToday || isSelected)
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? theme.colorScheme.onSurface
                              : isToday
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : isToday
                              ? (isDark
                                    ? const Color(0xFF1E1E24)
                                    : const Color(0xFFF4F4F5))
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : isToday
                                ? theme.colorScheme.onSurface
                                : hasScheduledWorkout
                                ? theme.colorScheme.outlineVariant
                                : theme.colorScheme.outline.withValues(
                                    alpha: 0.5,
                                  ),
                            width: (isSelected || isToday) ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            hasScheduledWorkout
                                ? Icons.fitness_center_rounded
                                : Icons.bed_rounded,
                            size: 16,
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : (hasScheduledWorkout || isToday)
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.secondary.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(height: 5),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, int streak) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D10) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.bolt_rounded,
                color: isDark ? Colors.black : Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$streak WEEKS ACTIVE',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF27272A)
                            : const Color(0xFFE4E4E7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'STREAK',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  streak > 0 ? 'Consistency is king. Unbroken weekly rhythm.' : 'Complete scheduled routines to begin your weekly streak.',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestDayCard(BuildContext context, String dayTitle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D10) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline, width: 1.2),
      ),
      child: Column(
        children: [
          Icon(
            Icons.nightlight_round,
            size: 44,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            '$dayTitle is a Rest & Recovery Day',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'No workout routines assigned. Muscles repair and build during recovery.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.secondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildUpcomingDaysOverview(
    BuildContext context,
    AppState appState,
    DateTime today,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final upcomingWidgets = <Widget>[];

    for (int i = 1; i <= 3; i++) {
      final date = today.add(Duration(days: i));
      final isoWeekday = date.weekday;
      final isTomorrow = i == 1;
      final dayLabel = isTomorrow
          ? 'Tomorrow (${DateFormat('EEEE').format(date)})'
          : DateFormat('EEEE, MMM d').format(date);
      final scheduledWorkouts = appState.getWorkoutsForDay(isoWeekday);

      upcomingWidgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D0D10) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outline, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isTomorrow
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark
                                    ? const Color(0xFF1E1E24)
                                    : const Color(0xFFF4F4F5)),
                          borderRadius: BorderRadius.circular(6),
                          border: isTomorrow
                              ? null
                              : Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                        ),
                        child: Text(
                          isTomorrow
                              ? 'TOMORROW'
                              : DateFormat('EEE, MMM d')
                                    .format(date)
                                    .toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: isTomorrow
                                ? (isDark ? Colors.black : Colors.white)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE').format(date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (scheduledWorkouts.isNotEmpty)
                    Text(
                      '${scheduledWorkouts.length} routine',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Routines for this day or Rest Day
              if (scheduledWorkouts.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF141418)
                        : const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bed_rounded,
                        size: 18,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Rest Day · Recovery scheduled',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...scheduledWorkouts.map((workout) {
                  final exerciseCount = workout.exercises.length;
                  final totalSets = workout.exercises.fold<int>(
                    0,
                    (total, e) => total + e.sets,
                  );
                  final previewExercises = workout.exercises
                      .take(3)
                      .map((e) => e.name)
                      .join(' · ');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF141418)
                          : const Color(0xFFF9F9FB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E1E24)
                                    : const Color(0xFFE4E4E7),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                workout.category.toUpperCase(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                workout.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$exerciseCount Exercises · $totalSets Total Sets',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                        if (previewExercises.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            previewExercises,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.secondary.withValues(
                                alpha: 0.8,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 44),
                              ),
                              onPressed: () {
                                _showProgramPreviewModal(
                                  context,
                                  workout,
                                  dayLabel,
                                );
                              },
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 15,
                              ),
                              label: const Text(
                                'Preview',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 44),
                              ),
                              onPressed: () => _openWorkoutSession(
                                context,
                                appState,
                                workout,
                              ),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 15,
                              ),
                              label: const Text(
                                'Start Early',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return upcomingWidgets;
  }

  void _showProgramPreviewModal(
    BuildContext context,
    Workout workout,
    String dayLabel,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.read<AppState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? const Color(0xFF0D0D10)
          : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1E24)
                                : const Color(0xFFE4E4E7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            workout.category.toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            workout.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Program for $dayLabel',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Exercises (${workout.exercises.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: workout.exercises.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 12),
                        itemBuilder: (context, idx) {
                          final ex = workout.exercises[idx];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: isDark
                                  ? const Color(0xFF1E1E24)
                                  : const Color(0xFFE4E4E7),
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            subtitle: Text(
                              '${ex.sets} Sets × ${ex.reps} Reps${ex.formatWeightsSummary(appState.units).isNotEmpty ? ' · ${ex.formatWeightsSummary(appState.units)}' : ''}${ex.notes != null ? '\nNote: ${ex.notes}' : ''}',
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _openWorkoutSession(
                                context,
                                appState,
                                workout,
                              );
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start Workout'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WorkoutTodayCard extends StatelessWidget {
  final Workout workout;
  final bool isDone;
  final bool isToday;
  final String dayLabel;

  const _WorkoutTodayCard({
    required this.workout,
    required this.isDone,
    this.isToday = true,
    this.dayLabel = 'Today',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.read<AppState>();
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D10) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDone
              ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8))
              : theme.colorScheme.outline,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E24)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFE4E4E7),
                  ),
                ),
                child: Text(
                  workout.category.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E24)
                        : const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    dayLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              const Spacer(),
              if (isDone)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        color: isDark ? Colors.black : Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'COMPLETED',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            workout.name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${workout.exercises.length} Exercises · ${workout.exercises.fold<int>(0, (total, e) => total + e.sets)} Sets',
            style: TextStyle(fontSize: 14, color: theme.colorScheme.secondary),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    minimumSize: const Size(0, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkoutEditorScreen(workout: workout),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text(
                    'View Routine',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    minimumSize: const Size(0, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () =>
                      _openWorkoutSession(context, appState, workout),
                  icon: Icon(
                    isDone ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isDone
                        ? 'Repeat Session'
                        : isToday
                        ? 'Start Workout'
                        : 'Start Early',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2: SCHEDULE (WEEKLY PLANNER & WORKOUTS)
// ==========================================

class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Split & Routines'),
        actions: [
          IconButton(
            tooltip: 'Add New Workout',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WorkoutEditorScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Text(
            'WEEKLY ASSIGNMENT',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a day to configure its workouts',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.secondary),
          ),
          const SizedBox(height: 12),

          // Monday - Sunday Schedule Rows
          ...List.generate(7, (index) {
            final isoDay = index + 1;
            final dayKey = isoDay.toString();
            final assignedIds = appState.weeklySchedule[dayKey] ?? [];
            final assignedWorkouts = appState.workouts
                .where((w) => assignedIds.contains(w.id))
                .toList();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF0D0D10)
                    : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: _TileMaterial(
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  title: Text(
                    dayNames[index],
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      assignedWorkouts.isEmpty
                          ? 'Rest Day'
                          : assignedWorkouts.map((w) => w.name).join(', '),
                      style: TextStyle(
                        fontSize: 13,
                        color: assignedWorkouts.isEmpty
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  trailing: assignedWorkouts.isEmpty
                      ? Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: theme.colorScheme.secondary,
                        )
                      : IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: theme.colorScheme.secondary,
                            size: 22,
                          ),
                          onPressed: () => appState.setDayWorkouts(isoDay, []),
                          tooltip: 'Clear Setup',
                        ),
                  onTap: () =>
                      _showAssignDayDialog(context, isoDay, dayNames[index]),
                ),
              ),
            );
          }),

          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MY ROUTINES LIBRARY',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  Text(
                    '${appState.workouts.length} routines',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WorkoutEditorScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // List of all routines
          ...appState.workouts.map(
            (workout) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF0D0D10)
                    : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: _TileMaterial(
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF1E1E24)
                        : const Color(0xFFF4F4F5),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: theme.colorScheme.onSurface,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    workout.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${workout.category.toUpperCase()} · ${workout.exercises.length} EXERCISES',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 22),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  WorkoutEditorScreen(workout: workout),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: theme.colorScheme.secondary,
                          size: 22,
                        ),
                        onPressed: () =>
                            _confirmDeleteWorkout(context, appState, workout),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkoutEditorScreen(workout: workout),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showAssignDayDialog(BuildContext context, int isoDay, String dayName) {
    final appState = context.read<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentAssigned = List<String>.from(
      appState.weeklySchedule[isoDay.toString()] ?? [],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? const Color(0xFF0D0D10)
          : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Assign Workouts for $dayName',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select which routines you perform on this day.',
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (appState.workouts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No workout routines available. Create one first!',
                          style: TextStyle(color: theme.colorScheme.secondary),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: appState.workouts.map((workout) {
                            final isChecked = currentAssigned.contains(
                              workout.id,
                            );
                            return CheckboxListTile(
                              value: isChecked,
                              activeColor: isDark ? Colors.white : Colors.black,
                              checkColor: isDark ? Colors.black : Colors.white,
                              title: Text(
                                workout.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                workout.category.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                              onChanged: (isSelected) {
                                setModalState(() {
                                  if (isSelected == true) {
                                    currentAssigned.add(workout.id);
                                  } else {
                                    currentAssigned.remove(workout.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            appState.setDayWorkouts(isoDay, currentAssigned);
                            Navigator.pop(ctx);
                          },
                          child: const Text('Save Schedule'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteWorkout(
    BuildContext context,
    AppState appState,
    Workout workout,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Routine?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to delete "${workout.name}"? This will remove it from your schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              appState.archiveWorkout(workout.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// WORKOUT CREATOR & EDITOR SCREEN
// ==========================================

class WorkoutEditorScreen extends StatefulWidget {
  final Workout? workout;
  const WorkoutEditorScreen({super.key, this.workout});

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late TextEditingController _nameController;
  late String _category;
  late List<Exercise> _exercises;

  final categories = ['push', 'pull', 'legs', 'upper', 'lower', 'custom'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workout?.name ?? '');
    _category = widget.workout?.category ?? 'push';
    _exercises = widget.workout != null
        ? widget.workout!.exercises.map((e) => e.copyWith()).toList()
        : [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    if (widget.workout == null) {
      return _nameController.text.trim().isNotEmpty ||
          _category != 'push' ||
          _exercises.isNotEmpty;
    }
    if (_nameController.text.trim() != widget.workout!.name ||
        _category != widget.workout!.category ||
        _exercises.length != widget.workout!.exercises.length) {
      return true;
    }
    for (var index = 0; index < _exercises.length; index++) {
      if (!_exerciseMatches(
        _exercises[index],
        widget.workout!.exercises[index],
      )) {
        return true;
      }
    }
    return false;
  }

  bool _exerciseMatches(Exercise first, Exercise second) {
    final firstWeights = first.getEffectiveSetWeights();
    final secondWeights = second.getEffectiveSetWeights();
    if (first.id != second.id ||
        first.name != second.name ||
        first.sets != second.sets ||
        first.reps != second.reps ||
        first.notes != second.notes ||
        firstWeights.length != secondWeights.length) {
      return false;
    }
    for (var index = 0; index < firstWeights.length; index++) {
      if (firstWeights[index] != secondWeights[index]) return false;
    }
    return true;
  }

  void _handleBack(BuildContext context) {
    if (!_hasUnsavedChanges) {
      Navigator.pop(context);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Discard Routine?'),
        content: const Text(
          'You have unsaved changes in this routine. Are you sure you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Editing'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Pop editor
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _saveRoutine() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a routine name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one exercise to your routine'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final appState = context.read<AppState>();
    if (widget.workout != null) {
      final updated = widget.workout!.copyWith(
        name: name,
        category: _category,
        exercises: _exercises,
      );
      appState.updateWorkout(updated);
    } else {
      final newWorkout = Workout(
        id: UniqueKey().toString(),
        name: name,
        category: _category,
        exercises: _exercises,
      );
      appState.addWorkout(newWorkout);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Routine "$name" saved successfully!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to Routines',
            onPressed: () => _handleBack(context),
          ),
          title: Text(widget.workout == null ? 'New Routine' : 'Edit Routine'),
          actions: [
            if (widget.workout != null)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                tooltip: 'Delete Routine',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text('Delete Routine?'),
                      content: Text(
                        'Are you sure you want to delete "${widget.workout!.name}"?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () {
                            appState.archiveWorkout(widget.workout!.id);
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            // Prominent Top Done Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _saveRoutine,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Routine Name',
                hintText: 'e.g. Heavy Push Day A',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: categories
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: 28),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXERCISES',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    Text(
                      '${_exercises.length} added',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () =>
                      _showAddOrEditExerciseDialog(context, appState.units),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    'Add Exercise',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_exercises.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141418)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFE4E4E7),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      size: 40,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No exercises added yet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "Add Exercise" above to configure your sets, reps, and custom weights per set.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.secondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _exercises.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) newIndex--;
                    final item = _exercises.removeAt(oldIndex);
                    _exercises.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final ex = _exercises[index];
                  final effWeights = ex.getEffectiveSetWeights();

                  return Card(
                    key: ValueKey(ex.id),
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF27272A)
                            : const Color(0xFFE4E4E7),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showAddOrEditExerciseDialog(
                        context,
                        appState.units,
                        existing: ex,
                        editIndex: index,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 22,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ex.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
                                  tooltip: 'Edit Exercise & Weights',
                                  onPressed: () => _showAddOrEditExerciseDialog(
                                    context,
                                    appState.units,
                                    existing: ex,
                                    editIndex: index,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete',
                                  onPressed: () {
                                    setState(() => _exercises.removeAt(index));
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF202026)
                                    : const Color(0xFFE4E4E7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${ex.sets} Sets × ${ex.reps} Reps',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Per-set individual weight badges
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: List.generate(ex.sets, (setIdx) {
                                final w = setIdx < effWeights.length
                                    ? effWeights[setIdx]
                                    : 0.0;
                                final wText = w > 0
                                    ? '${w.truncateToDouble() == w ? w.toInt() : w} ${appState.units}'
                                    : 'Bodyweight';
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF16161A)
                                        : const Color(0xFFF4F4F5),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF2C2C32)
                                          : const Color(0xFFD4D4D8),
                                    ),
                                  ),
                                  child: Text(
                                    'Set ${setIdx + 1}: $wText',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            if (ex.notes != null && ex.notes!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                ex.notes!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // Bottom Action Buttons: Done / Finish Routine & Back
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: _saveRoutine,
              icon: const Icon(Icons.check_circle_rounded, size: 22),
              label: Text(
                widget.workout == null
                    ? 'Finish & Save Routine'
                    : 'Done · Update Routine',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () => _handleBack(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text(
                'Back to Routines',
                style: TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _showAddOrEditExerciseDialog(
    BuildContext context,
    String units, {
    Exercise? existing,
    int? editIndex,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExerciseDialog(
        initial: existing,
        units: units,
        onSave: (exercise) {
          setState(() {
            if (editIndex != null && editIndex < _exercises.length) {
              _exercises[editIndex] = exercise;
            } else {
              _exercises.add(exercise);
            }
          });
        },
      ),
    );
  }
}

class _ExerciseDialog extends StatefulWidget {
  final Exercise? initial;
  final String units;
  final ValueChanged<Exercise> onSave;

  const _ExerciseDialog({
    this.initial,
    required this.units,
    required this.onSave,
  });

  @override
  State<_ExerciseDialog> createState() => _ExerciseDialogState();
}

class _ExerciseDialogState extends State<_ExerciseDialog> {
  late TextEditingController _nameCtl;
  late TextEditingController _notesCtl;
  int _sets = 3;
  int _reps = 10;
  late List<TextEditingController> _setWeightControllers;
  String? _validationError;

  final List<String> _suggestions = [
    'Bench Press',
    'Incline Dumbbell Press',
    'Squat',
    'Deadlift',
    'Overhead Press',
    'Barbell Row',
    'Lat Pulldown',
    'Bicep Curl',
    'Lateral Raise',
    'Leg Extension',
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtl = TextEditingController(text: init?.name ?? '');
    _notesCtl = TextEditingController(text: init?.notes ?? '');
    _sets = init?.sets ?? 3;
    _reps = init?.reps ?? 10;

    final existingWeights = init?.getEffectiveSetWeights() ?? [];
    _setWeightControllers = List.generate(
      _sets,
      (i) => TextEditingController(
        text: (i < existingWeights.length && existingWeights[i] > 0)
            ? (existingWeights[i].truncateToDouble() == existingWeights[i]
                  ? existingWeights[i].toInt().toString()
                  : existingWeights[i].toString())
            : '',
      ),
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _notesCtl.dispose();
    for (final c in _setWeightControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _changeSets(int delta) {
    final next = (_sets + delta).clamp(1, 20);
    if (next == _sets) return;
    setState(() {
      _sets = next;
      while (_setWeightControllers.length < _sets) {
        final last = _setWeightControllers.isNotEmpty
            ? _setWeightControllers.last.text
            : '';
        _setWeightControllers.add(TextEditingController(text: last));
      }
      while (_setWeightControllers.length > _sets) {
        final c = _setWeightControllers.removeLast();
        c.dispose();
      }
    });
  }

  void _copyFirstSetToAll() {
    if (_setWeightControllers.isEmpty) return;
    final firstVal = _setWeightControllers.first.text.trim();
    setState(() {
      for (int i = 1; i < _setWeightControllers.length; i++) {
        _setWeightControllers[i].text = firstVal;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            widget.initial == null
                ? Icons.add_circle_outline_rounded
                : Icons.edit_note_rounded,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 10),
          Text(widget.initial == null ? 'Add Exercise' : 'Edit Exercise'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Exercise Name
              TextField(
                controller: _nameCtl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Exercise Name',
                  hintText: 'e.g. Bench Press',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Quick suggestions chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _suggestions.map((s) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _nameCtl.text = s;
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),

              // Sets & Reps Counters
              Row(
                children: [
                  // Sets Stepper
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C22)
                            : const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF2C2C32)
                              : const Color(0xFFE4E4E7),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SETS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.remove, size: 16),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _changeSets(-1),
                              ),
                              Text(
                                '$_sets',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.add, size: 16),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _changeSets(1),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Reps Stepper
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C22)
                            : const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF2C2C32)
                              : const Color(0xFFE4E4E7),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'REPS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.remove, size: 16),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  if (_reps > 1) setState(() => _reps--);
                                },
                              ),
                              Text(
                                '$_reps',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.add, size: 16),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  if (_reps < 100) setState(() => _reps++);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Weight Per Set Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'WEIGHT PER SET (${widget.units.toUpperCase()})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  if (_sets > 1)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _copyFirstSetToAll,
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text(
                        'Copy Set 1 to all',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Individual Set Weights Table
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141418)
                      : const Color(0xFFF9F9FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFE4E4E7),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _sets,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: isDark
                        ? const Color(0xFF202024)
                        : const Color(0xFFE4E4E7),
                  ),
                  itemBuilder: (context, i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF222228)
                                  : const Color(0xFFEAEAEA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Set ${i + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _setWeightControllers[i],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '0 (Bodyweight)',
                                suffixText: widget.units,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              // Notes / Cue
              TextField(
                controller: _notesCtl,
                decoration: InputDecoration(
                  labelText: 'Notes / Form cue (Optional)',
                  hintText: 'e.g. Pause 1 sec at bottom',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _validationError!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtl.text.trim();
            if (name.isEmpty) {
              setState(() => _validationError = 'Enter an exercise name.');
              return;
            }

            final rawWeights = _setWeightControllers
                .map((controller) => controller.text.trim())
                .toList();
            if (rawWeights.any(
              (weight) => weight.isNotEmpty && double.tryParse(weight) == null,
            )) {
              setState(() => _validationError = 'Enter valid numeric weights.');
              return;
            }
            final parsedWeights = rawWeights
                .map((weight) => double.tryParse(weight) ?? 0.0)
                .toList();
            if (parsedWeights.any((weight) => weight < 0)) {
              setState(() => _validationError = 'Weights cannot be negative.');
              return;
            }

            final firstWeight = parsedWeights.isNotEmpty
                ? parsedWeights.first
                : null;

            final exercise = Exercise(
              id: widget.initial?.id ?? UniqueKey().toString(),
              name: name,
              sets: _sets,
              reps: _reps,
              weight: firstWeight != null && firstWeight > 0
                  ? firstWeight
                  : null,
              setWeights: parsedWeights,
              notes: _notesCtl.text.trim().isEmpty
                  ? null
                  : _notesCtl.text.trim(),
            );

            widget.onSave(exercise);
            Navigator.pop(context);
          },
          child: Text(widget.initial == null ? 'Add Exercise' : 'Save Changes'),
        ),
      ],
    );
  }
}

// ==========================================
// ACTIVE WORKOUT SESSION SCREEN (LIVE TIMER & CHECKS)
// ==========================================

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  bool _isCompleting = false;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.activeWorkoutSession;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('No Active Workout')),
        body: const Center(child: Text('No active session in progress.')),
      );
    }

    final minutes = (appState.sessionSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (appState.sessionSeconds % 60).toString().padLeft(2, '0');
    final completedCount = session.exercises.where((e) => e.isCompleted).length;
    final progress = session.exercises.isEmpty
        ? 0.0
        : completedCount / session.exercises.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
          IconButton(
            tooltip: 'Cancel Session',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Discard Workout?'),
                  content: const Text(
                    'Are you sure you want to quit without saving progress?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Continue'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () {
                        appState.cancelActiveSession();
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Live Timer Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFE4E4E7),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E1E24)
                            : const Color(0xFFF4F4F5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFE4E4E7),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.timer_outlined,
                        size: 22,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ELAPSED TIME',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$minutes:$seconds',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E24)
                        : const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF27272A)
                          : const Color(0xFFE4E4E7),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'PROGRESS',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$completedCount / ${session.exercises.length}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark
                ? const Color(0xFF18181B)
                : const Color(0xFFE4E4E7),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.onSurface,
            ),
            minHeight: 3,
          ),

          // Exercise checklist
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: session.exercises.length,
              itemBuilder: (context, index) {
                final ex = session.exercises[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: ex.isCompleted
                        ? (isDark
                              ? const Color(0xFF121216)
                              : const Color(0xFFF9F9FA))
                        : (isDark ? const Color(0xFF18181C) : Colors.white),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ex.isCompleted
                          ? (isDark
                                ? const Color(0xFF3F3F46)
                                : const Color(0xFFD4D4D8))
                          : (isDark
                                ? const Color(0xFF27272A)
                                : const Color(0xFFE4E4E7)),
                      width: 1,
                    ),
                  ),
                  child: _TileMaterial(
                    borderRadius: BorderRadius.circular(16),
                    child: CheckboxListTile(
                      value: ex.isCompleted,
                      activeColor: theme.colorScheme.onSurface,
                      checkColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      onChanged: (_) => appState.toggleExerciseInSession(index),
                      title: Text(
                        ex.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          decoration: ex.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: ex.isCompleted
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                )
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text(
                            '${ex.sets} Sets × ${ex.reps} Reps${ex.formatWeightsSummary(appState.units).isNotEmpty ? ' · ${ex.formatWeightsSummary(appState.units)}' : ''}',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                          if (ex.notes != null && ex.notes!.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              ex.notes!,
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Complete Workout Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFE4E4E7),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: theme.colorScheme.onSurface,
                  foregroundColor: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isCompleting
                    ? null
                    : () async {
                        setState(() => _isCompleting = true);
                        await appState.completeActiveSession();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Workout completed! Saved to your history.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            backgroundColor: isDark
                                ? const Color(0xFF27272A)
                                : const Color(0xFF18181B),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                label: Text(
                  _isCompleting ? 'Saving Workout…' : 'Complete & Save Workout',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 3: WORKOUT HISTORY & LOGS
// ==========================================

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final logs = appState.logs;

    return Scaffold(
      appBar: AppBar(title: const Text('Workout History')),
      body: logs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF18181C)
                            : const Color(0xFFF4F4F5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFE4E4E7),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.history_rounded,
                        size: 48,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'NO SESSIONS LOGGED',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete your first workout from the Today tab to record your training history.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final durationMin = (log.durationSeconds / 60).round();
                final formattedDate = DateFormat('EEE, MMM d, yyyy · h:mm a')
                    .format(log.completedAt);
                final completedExercises = log.exercises
                    .where((e) => e.isCompleted)
                    .length;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF18181C) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF27272A)
                          : const Color(0xFFE4E4E7),
                      width: 1,
                    ),
                  ),
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: _TileMaterial(
                      borderRadius: BorderRadius.circular(18),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF27272A)
                                : const Color(0xFFF4F4F5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 22,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        title: Text(
                          log.workoutName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '$formattedDate · ${durationMin}m',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ),
                        trailing: PopupMenuButton(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'undo',
                              child: Text('Undo / Remove Log'),
                            ),
                          ],
                          onSelected: (val) {
                            if (val == 'undo') {
                              appState.undoCompletion(log.id);
                            }
                          },
                        ),
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF27272A)
                                      : const Color(0xFFE4E4E7),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'COMPLETED EXERCISES',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Text(
                                      '$completedExercises / ${log.exercises.length}',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                ...log.exercises.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          e.isCompleted
                                              ? Icons.check_circle_rounded
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                          color: e.isCompleted
                                              ? theme.colorScheme.onSurface
                                              : theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.3),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '${e.name} (${e.sets}×${e.reps}${e.formatWeightsSummary(appState.units).isNotEmpty ? ' @ ${e.formatWeightsSummary(appState.units)}' : ''})',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(
                                                    alpha: e.isCompleted
                                                        ? 0.9
                                                        : 0.5,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
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
              },
            ),
    );
  }
}

// ==========================================
// TAB 4: PROFILE & SETTINGS
// ==========================================

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // User card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF18181C) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF27272A)
                    : const Color(0xFFE4E4E7),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: theme.colorScheme.onSurface,
                  foregroundColor: theme.colorScheme.surface,
                  child: Text(
                    appState.displayName.isNotEmpty
                        ? appState.displayName[0].toUpperCase()
                        : 'A',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appState.displayName,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        appState.userEmail,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 22),
                  onPressed: () => _showEditProfileDialog(context, appState),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Preferences section
          Text(
            'PREFERENCES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF18181C) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF27272A)
                    : const Color(0xFFE4E4E7),
                width: 1,
              ),
            ),
            child: _TileMaterial(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    title: const Text(
                      'Dark Mode Theme',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    secondary: const Icon(Icons.dark_mode_outlined, size: 22),
                    value: appState.isDarkMode,
                    activeThumbColor: theme.colorScheme.onSurface,
                    onChanged: (_) => appState.toggleTheme(),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFE4E4E7),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    leading: const Icon(Icons.scale_outlined, size: 22),
                    title: const Text(
                      'Weight Units',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Currently set to ${appState.units.toUpperCase()}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    trailing: SegmentedButton<String>(
                      style: ButtonStyle(
                        textStyle: WidgetStatePropertyAll(
                          GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(value: 'kg', label: Text('KG')),
                        ButtonSegment(value: 'lb', label: Text('LB')),
                      ],
                      selected: {appState.units},
                      onSelectionChanged: (set) {
                        appState.updateProfile(
                          name: appState.displayName,
                          units: set.first,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Backend / Cloud Status Section
          Text(
            'CLOUD & BACKEND STATUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF18181C) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF27272A)
                    : const Color(0xFFE4E4E7),
                width: 1,
              ),
            ),
            child: _TileMaterial(
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_done_rounded,
                    size: 20,
                    color: Color(0xFF10B981),
                  ),
                ),
                title: const Text(
                  'Firebase Cloud Sync',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    appState.isFirebaseAvailable
                        ? (appState.isAuthenticated
                              ? 'Active · Syncing to Firestore'
                              : 'Connecting...')
                        : 'Windows Desktop Mode (Local Preview) · Active on Android & Chrome',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFFA1A1AA)
                          : const Color(0xFF71717A),
                    ),
                  ),
                ),
                trailing: const Icon(Icons.info_outline_rounded, size: 20),
                onTap: () => _showFirebaseGuideDialog(context, appState),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Logout Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF3F3F46)
                    : const Color(0xFFD4D4D8),
                width: 1,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _confirmLogout(context, appState),
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: const Text(
              'Sign Out',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 56),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AppState appState) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out?'),
        content: Text(
          appState.isSessionRunning
              ? 'Signing out will discard your active workout session.'
              : 'You can sign back in at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (shouldLogout != true) return;
    try {
      await appState.logout();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $error')));
    }
  }

  void _showEditProfileDialog(BuildContext context, AppState appState) {
    final nameCtl = TextEditingController(text: appState.displayName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: TextField(
          controller: nameCtl,
          decoration: const InputDecoration(labelText: 'Display Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtl.text.trim().isNotEmpty) {
                appState.updateProfile(
                  name: nameCtl.text.trim(),
                  units: appState.units,
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(nameCtl.dispose);
  }

  void _showFirebaseGuideDialog(BuildContext context, AppState appState) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_done_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Firestore Cloud Sync',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your workout data, routines, and activity logs are synced with Google Cloud Firestore:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFFA1A1AA)
                      : const Color(0xFF52525B),
                ),
              ),
              const SizedBox(height: 16),
              _buildSyncTile(
                icon: Icons.person_outline,
                title: 'User Profile',
                desc: appState.userEmail.isNotEmpty
                    ? appState.userEmail
                    : 'Logged in',
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildSyncTile(
                icon: Icons.fitness_center_rounded,
                title: 'Workouts Collection',
                desc: 'users/{uid}/workouts',
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildSyncTile(
                icon: Icons.history_rounded,
                title: 'Activity Logs Collection',
                desc: 'users/{uid}/logs',
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildSyncTile(
                icon: Icons.calendar_today_rounded,
                title: 'Weekly Schedule',
                desc: 'users/{uid}/meta/schedule',
                isDark: isDark,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _buildSyncTile({
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222226) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF10B981)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : const Color(0xFF71717A),
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
