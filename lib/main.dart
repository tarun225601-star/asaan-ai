import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SamajhAayaApp());
}

class SamajhAayaApp extends StatelessWidget {
  const SamajhAayaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SamajhAaya',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          surface: const Color(0xFFF4F6F9),
        ),
        useMaterial3: true,
      ),
      home: const SolverHomePage(),
    );
  }
}

const List<String> kAllCourses = [
  '10th Board',
  '12th Board',
  'Delhi Police',
  'UP Police',
  'SSC GD',
  'SSC CGL / CHSL',
  'Railway RRB / NTPC / Group D',
  'Army Agniveer',
  'UP Board',
  'Bihar Board',
  'Haryana Board',
  'MP / Rajasthan Board',
  'CTET / TET',
  'NDA / Defence',
  'NEET / Medical Foundation',
  'JEE / Maths Foundation',
  'English Grammar & Spoken',
  'Hindi Grammar & Sahitya',
  'General Knowledge & Constitution',
  'General Competition',
];

class SolvedItem {
  final String question;
  final String answerText;
  final List<String> extraMethods;
  final bool understood;
  final String date;

  SolvedItem({
    required this.question,
    required this.answerText,
    required this.extraMethods,
    required this.understood,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'question': question,
        'answerText': answerText,
        'extraMethods': extraMethods,
        'understood': understood,
        'date': date,
      };

  factory SolvedItem.fromJson(Map<String, dynamic> json) => SolvedItem(
        question: json['question'] ?? '',
        answerText: json['answerText'] ?? '',
        extraMethods: List<String>.from(json['extraMethods'] ?? []),
        understood: json['understood'] ?? false,
        date: json['date'] ?? '',
      );
}

class DayPlanStep {
  final int day;
  final String title;
  final String focus;
  final String hoursAllocation;
  final int targetQuestions;
  final bool completed;

  DayPlanStep({
    required this.day,
    required this.title,
    required this.focus,
    required this.hoursAllocation,
    required this.targetQuestions,
    required this.completed,
  });

  DayPlanStep copyWith({bool? completed}) => DayPlanStep(
        day: day,
        title: title,
        focus: focus,
        hoursAllocation: hoursAllocation,
        targetQuestions: targetQuestions,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'title': title,
        'focus': focus,
        'hoursAllocation': hoursAllocation,
        'targetQuestions': targetQuestions,
        'completed': completed,
      };

  factory DayPlanStep.fromJson(Map<String, dynamic> json) => DayPlanStep(
        day: (json['day'] as num?)?.toInt() ?? 1,
        title: json['title']?.toString() ?? '',
        focus: json['focus']?.toString() ?? '',
        hoursAllocation:
            json['hoursAllocation']?.toString() ?? 'मुख्य विषय 2h • PYQ 1.5h • रिवीजन 1.5h',
        targetQuestions: (json['targetQuestions'] as num?)?.toInt() ?? 25,
        completed: json['completed'] == true,
      );
}

class OfflineCoursePackItem {
  final String courseTag;
  final String durationTag;
  final String topic;
  final String question;
  final String answerText;

  const OfflineCoursePackItem({
    required this.courseTag,
    required this.durationTag,
    required this.topic,
    required this.question,
    required this.answerText,
  });
}

const List<OfflineCoursePackItem> kOfflineCoursePack = [
  OfflineCoursePackItem(
    courseTag: '10th Board',
    durationTag: '6 Months',
    topic: 'PYQ पैटर्न - प्रतिशत व अनुपात',
    question: 'यदि किसी संख्या का 25% हिस्सा 40 है, तो वह संख्या क्या होगी?',
    answerText:
        '1. पक्का उत्तर और तेज़ हल: 25% = 25/100 = 1/4। यदि (1/4) * x = 40, तो x = 40 * 4 = 160। सही उत्तर 160 है।\n\n'
        '2. 10x तेज़ समझ: बोर्ड और प्रतियोगी परीक्षाओं में प्रतिशत से भिन्न बनाकर हल करने से समय बचता है। चौथा हिस्सा 40 है तो पूरा हिस्सा 4 गुना होगा।\n\n'
        '3. टेस्ट प्वाइंट और शॉर्ट निचोड़: 25% = 1/4 -> सीधे 40 * 4 = 160।',
  ),
  OfflineCoursePackItem(
    courseTag: '12th Board',
    durationTag: '1 Year',
    topic: 'PYQ पैटर्न - ओम का नियम व प्रतिरोध',
    question: 'ओम का नियम क्या है और V = I * R का अर्थ समझाइए?',
    answerText:
        '1. पक्का उत्तर और तेज़ हल: स्थिर ताप पर चालक के सिरों के बीच विभवांतर (V) उसमें बहने वाली धारा (I) के समानुपाती होता है। सूत्र: V = I * R।\n\n'
        '2. 10x तेज़ समझ: परीक्षा में मुख्य शर्त "स्थिर ताप" पूछी जाती है। V और I में से दो मान दिए हों तो तीसरा मान सीधे V = I * R से निकलता है।\n\n'
        '3. टेस्ट प्वाइंट और शॉर्ट निचोड़: स्थिर ताप पर V = I * R। प्रतिरोध R = V / I।',
  ),
  OfflineCoursePackItem(
    courseTag: 'Delhi Police',
    durationTag: '6 Months',
    topic: 'PYQ पैटर्न - भारतीय संविधान भाग-3',
    question: 'भारतीय संविधान में मौलिक अधिकार किस भाग में दिए गए हैं?',
    answerText:
        '1. पक्का उत्तर और पूरा हल: मौलिक अधिकार संविधान के भाग-3 (अनुच्छेद 12 से 35) में दिए गए हैं। सही उत्तर भाग-3 है।\n\n'
        '2. 10x तेज़ समझ: पुलिस परीक्षा में संविधान के भाग और अनुच्छेद की सीमा बार-बार पूछी जाती है। मौलिक अधिकार अनुच्छेद 12 से 35 तक विस्तृत हैं।\n\n'
        '3. टेस्ट प्वाइंट और शॉर्ट निचोड़: मौलिक अधिकार = भाग-3 (अनुच्छेद 12-35)।',
  ),
  OfflineCoursePackItem(
    courseTag: 'UP Police',
    durationTag: '1 Year',
    topic: 'PYQ पैटर्न - चाल, समय और दूरी',
    question: 'एक व्यक्ति 60 किमी/घंटा की चाल से 3 घंटे चलता है, तो कुल दूरी कितनी होगी?',
    answerText:
        '1. पक्का उत्तर और पूरा हल: दूरी = चाल * समय = 60 * 3 = 180 किमी। सही उत्तर 180 किमी है।\n\n'
        '2. 10x तेज़ समझ: पुलिस भर्ती के अंकगणित में चाल, समय और दूरी के सीधे प्रश्न आते हैं। इकाई समान हो तो सीधा गुणनफल दूरी देता है।\n\n'
        '3. टेस्ट प्वाइंट और शॉर्ट निचोड़: दूरी = चाल * समय -> 60 * 3 = 180 किमी।',
  ),
];

String cleanDisplayText(String raw) {
  var text = raw;
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
  text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '');
  text = text.replaceAll('**', '');
  text = text.replaceAll('*', '');
  text = text.replaceAll('`', '');
  text = text.replaceAll('\$', '');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

class SolverHomePage extends StatefulWidget {
  const SolverHomePage({super.key});

  @override
  State<SolverHomePage> createState() => _SolverHomePageState();
}

class _SolverHomePageState extends State<SolverHomePage> {
  static const int dailyFreeLimit = 5;
  static const String _keyApi = 'user_gemini_api_key';
  static const String _keyDate = 'free_quota_date';
  static const String _keyCount = 'free_quota_count';
  static const String _keySaved = 'saved_questions_list';
  static const String _keyLang = 'selected_lang_mode';
  static const String _keyCoins = 'user_unlock_coins';
  static const String _keyCourseTrack = 'selected_course_track';
  static const String _keyCourseDuration = 'selected_course_duration';
  static const String _keyPlanSubject = 'study_plan_subject';
  static const String _keyPlanSteps = 'study_plan_steps';
  static const String _keyDailyHours = 'daily_study_hours';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _planCourseController = TextEditingController();
  final TextEditingController _courseSearchController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  bool _isListening = false;
  bool _isSpeaking = false;

  String _apiKey = '';
  String _langMode = 'hi-IN';
  String _courseTrack = '10th Board';
  String _courseDuration = '6 Months';
  int _dailyHours = 5;
  int _usedToday = 0;
  int _coins = 0;
  bool _isLoading = false;
  bool _isGeneratingPlan = false;

  String _planSubject = '';
  List<DayPlanStep> _dayPlan = [];

  bool _isTestMode = false;
  String? _activeTestQuestion;
  int _testAttempts = 0;

  File? _pickedImageFile;
  String? _pickedImageMime;

  String? _currentQuestion;
  String? _currentAnswer;
  final List<String> _extraMethods = [];
  bool? _understood;
  List<SolvedItem> _savedItems = [];

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadState();
  }

  Future<void> _initTts() async {
    try {
      final engines = await _tts.getEngines;
      if (engines is List) {
        final googleEngine = engines.firstWhere(
          (e) => e.toString().toLowerCase().contains('google'),
          orElse: () => null,
        );
        if (googleEngine != null) {
          await _tts.setEngine(googleEngine.toString());
        }
      }
    } catch (_) {}

    await _applyTtsSettings();

    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  Future<void> _applyTtsSettings({String? overrideLang}) async {
    final targetLang = overrideLang ?? (_langMode == 'auto' ? 'hi-IN' : _langMode);
    try {
      await _tts.setLanguage(targetLang);
    } catch (_) {
      await _tts.setLanguage('hi-IN');
    }
    await _tts.setSpeechRate(0.30);
    await _tts.setPitch(1.0);
  }

  String _detectLanguageForText(String text) {
    if (_langMode == 'hi-IN' || _langMode == 'en-US') {
      return _langMode;
    }
    final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(text);
    return hasDevanagari ? 'hi-IN' : 'en-US';
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null) return;

      final lower = picked.path.toLowerCase();
      final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';

      setState(() {
        _pickedImageFile = File(picked.path);
        _pickedImageMime = mime;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('फ़ोटो खोलने में समस्या आई। अनुमति जांचें।')),
      );
    }
  }

  void _openAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('कैमरा से फ़ोटो खींचें'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('गैलरी से फ़ोटो चुनें'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearPickedImage() {
    setState(() {
      _pickedImageFile = null;
      _pickedImageMime = null;
    });
  }

  Future<void> _toggleListen() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('माइक उपलब्ध नहीं है या अनुमति नहीं मिली।')),
      );
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: _langMode == 'auto' ? null : _langMode,
      onResult: (result) {
        setState(() {
          _questionController.text = result.recognizedWords;
          _questionController.selection = TextSelection.fromPosition(
            TextPosition(offset: _questionController.text.length),
          );
        });
      },
    );
  }

  Future<void> _toggleSpeak() async {
    final fullText = _buildSpokenText();
    if (fullText.isEmpty) return;

    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
    } else {
      final langToUse = _detectLanguageForText('$fullText ${_currentQuestion ?? ''}');
      await _applyTtsSettings(overrideLang: langToUse);
      setState(() => _isSpeaking = true);
      await _tts.speak(fullText);
    }
  }

  String _buildSpokenText() {
    if (_currentAnswer == null) return '';
    final buffer = StringBuffer(cleanDisplayText(_currentAnswer!));
    for (int i = 0; i < _extraMethods.length; i++) {
      buffer.write('\n\n${cleanDisplayText(_extraMethods[i])}');
    }
    return buffer.toString();
  }

  String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  Future<void> _loadState() async {
    final savedKey = await _prefs.getString(_keyApi) ?? '';
    final savedLang = await _prefs.getString(_keyLang) ?? 'hi-IN';
    final savedTrack = await _prefs.getString(_keyCourseTrack) ?? '10th Board';
    final savedDuration = await _prefs.getString(_keyCourseDuration) ?? '6 Months';
    final savedHours = await _prefs.getInt(_keyDailyHours) ?? 5;
    final savedCoins = await _prefs.getInt(_keyCoins) ?? 0;
    final savedPlanSubject = await _prefs.getString(_keyPlanSubject) ?? '';
    final today = _todayKey();
    final lastDate = await _prefs.getString(_keyDate) ?? today;
    int count = await _prefs.getInt(_keyCount) ?? 0;

    if (lastDate != today) {
      count = 0;
      await _prefs.setString(_keyDate, today);
      await _prefs.setInt(_keyCount, 0);
    }

    final rawList = await _prefs.getStringList(_keySaved) ?? [];
    final parsed = rawList
        .map((e) {
          final item = SolvedItem.fromJson(jsonDecode(e) as Map<String, dynamic>);
          return SolvedItem(
            question: cleanDisplayText(item.question),
            answerText: cleanDisplayText(item.answerText),
            extraMethods: item.extraMethods.map(cleanDisplayText).toList(),
            understood: item.understood,
            date: item.date,
          );
        })
        .toList();

    final rawPlan = await _prefs.getStringList(_keyPlanSteps) ?? [];
    final parsedPlan = rawPlan
        .map((e) => DayPlanStep.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();

    setState(() {
      _apiKey = savedKey;
      _apiKeyController.text = savedKey;
      _langMode = savedLang;
      _courseTrack = savedTrack;
      _courseDuration = savedDuration;
      _dailyHours = savedHours;
      _coins = savedCoins;
      _usedToday = count;
      _savedItems = parsed;
      _planSubject = savedPlanSubject;
      _planCourseController.text = savedPlanSubject;
      _dayPlan = parsedPlan;
    });
    await _applyTtsSettings();
  }

  Future<void> _savePlanToPrefs() async {
    await _prefs.setString(_keyPlanSubject, _planSubject);
    await _prefs.setStringList(
      _keyPlanSteps,
      _dayPlan.map((x) => jsonEncode(x.toJson())).toList(),
    );
  }

  Future<void> _markActiveDayPassed() async {
    final idx = _dayPlan.indexWhere((s) => !s.completed);
    if (idx == -1) return;
    final nextList = List<DayPlanStep>.from(_dayPlan);
    nextList[idx] = nextList[idx].copyWith(completed: true);
    setState(() {
      _dayPlan = nextList;
      _isTestMode = false;
      _activeTestQuestion = null;
      _testAttempts = 0;
    });
    await _savePlanToPrefs();
  }

  Future<void> _generateDayByDayPlan(String courseInput) async {
    final cleanCourse = courseInput.trim().isNotEmpty ? courseInput.trim() : _courseTrack;

    setState(() => _isGeneratingPlan = true);

    final langRule = _buildLanguageInstruction();
    final prompt = '''
तुम एक अनुभवी कोचिंग शिक्षक हो जो पुराने प्रश्नपत्रों (Previous Year Papers) और परीक्षा पैटर्न को देखकर डे-बाय-डे रिवीजन व टेस्ट प्लान बनाता है। फ़ालतू या कम आने वाले टॉपिक्स की बजाय उन्हीं विषयों और सवालों पर फोकस रखो जिनके परीक्षा में आने की सबसे ज़्यादा संभावना है।
$langRule
यह ऐप केवल पढ़ाई के लिए है। "घर-बाहर की मिसाल" या घर-परिवार की तुलना बिल्कुल मत लिखो।
कोर्स: "$cleanCourse" | ट्रैक: "$_courseTrack" | अवधि: "$_courseDuration" | रोज़ पढ़ाई के घंटे: $_dailyHours घंटे

नीचे ठीक 7 दिनों (Day 1 से Day 7) का PYQ-आधारित प्लान सिर्फ़ इस JSON फॉर्मेट में दो (कोई अतिरिक्त शब्द या markdown कोड ब्लॉक मत लगाओ):
[{"day":1,"title":"...","focus":"...","hoursAllocation":"विषय 2h • PYQ 1.5h","targetQuestions":25}]
''';

    try {
      final raw = await _callGemini(prompt, applyClean: false);
      final cleaned = raw.replaceAll(RegExp(r'```json|```', caseSensitive: false), '').trim();
      final startIdx = cleaned.indexOf('[');
      final endIdx = cleaned.lastIndexOf(']');
      List<DayPlanStep> steps = [];

      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonSlice = cleaned.substring(startIdx, endIdx + 1);
        final decoded = jsonDecode(jsonSlice) as List<dynamic>;
        steps = decoded.asMap().entries.map((entry) {
          final map = entry.value as Map<String, dynamic>;
          return DayPlanStep(
            day: (map['day'] as num?)?.toInt() ?? (entry.key + 1),
            title: cleanDisplayText(map['title']?.toString() ?? 'संभावित PYQ अध्याय ${entry.key + 1}'),
            focus: cleanDisplayText(
              map['focus']?.toString() ?? 'पुराने पेपर के सबसे संभावित सवाल व उत्तर',
            ),
            hoursAllocation: cleanDisplayText(
              map['hoursAllocation']?.toString() ?? 'मुख्य PYQ $_dailyHours घंटे',
            ),
            targetQuestions: (map['targetQuestions'] as num?)?.toInt() ?? 25,
            completed: false,
          );
        }).toList();
      }

      if (steps.isEmpty) {
        final h1 = (_dailyHours * 0.45).toStringAsFixed(1);
        final h2 = (_dailyHours * 0.30).toStringAsFixed(1);
        final h3 = (_dailyHours * 0.25).toStringAsFixed(1);
        steps = [
          DayPlanStep(
            day: 1,
            title: '$cleanCourse - पुराने पेपर के उच्च-संभावित (High-Yield) प्रश्न',
            focus: 'पिछले वर्षों में बार-बार पूछे गए मुख्य प्रश्न व उत्तर पक्के करें',
            hoursAllocation: 'संभावित PYQ ${h1}h • हल अभ्यास ${h2}h • रिवीजन ${h3}h',
            targetQuestions: 25,
            completed: false,
          ),
          DayPlanStep(
            day: 2,
            title: '$cleanCourse - दोहराए जाने वाले सूत्र व नियम',
            focus: 'परीक्षा पैटर्न के सबसे संभावित नियमों पर सवाल हल करें',
            hoursAllocation: 'नियम व PYQ ${h1}h • प्रैक्टिस ${h2}h • निचोड़ ${h3}h',
            targetQuestions: 30,
            completed: false,
          ),
          DayPlanStep(
            day: 3,
            title: '$cleanCourse - तेज़ हल करने के शॉर्ट तरीके',
            focus: 'संभावित प्रश्नों को कम समय में हल करने का तरीका अपनाएं',
            hoursAllocation: 'शॉर्ट तरीका ${h1}h • PYQ सेट ${h2}h • रिवीजन ${h3}h',
            targetQuestions: 35,
            completed: false,
          ),
          DayPlanStep(
            day: 4,
            title: '$cleanCourse - ट्रेंडिंग और संभावित परीक्षा प्रश्न',
            focus: 'हालिया पेपर ट्रेंड के अनुसार संभावित प्रश्नों का अभ्यास करें',
            hoursAllocation: 'संभावित प्रश्न ${h1}h • विश्लेषण ${h2}h • रिवीजन ${h3}h',
            targetQuestions: 40,
            completed: false,
          ),
          DayPlanStep(
            day: 5,
            title: '$cleanCourse - कमज़ोर व चूक वाले PYQ सुधारें',
            focus: 'जिन संभावित सवालों में अटकते हैं उन्हें दोबारा पक्का करें',
            hoursAllocation: 'सुधार PYQ ${h1}h • दोबारा हल ${h2}h • रिवीजन ${h3}h',
            targetQuestions: 30,
            completed: false,
          ),
          DayPlanStep(
            day: 6,
            title: '$cleanCourse - संभावित प्रश्नों का पूरा रिवीजन',
            focus: 'सभी उच्च-संभावित सवाल, उत्तर और शॉर्ट निचोड़ दोहराएं',
            hoursAllocation: 'पूरा PYQ रिवीजन ${h1}h • शॉर्ट निचोड़ ${h2}h • अभ्यास ${h3}h',
            targetQuestions: 35,
            completed: false,
          ),
          DayPlanStep(
            day: 7,
            title: '$cleanCourse - संभावित पेपर टेस्ट व पास गेट',
            focus: 'संभावित प्रश्नों का टेस्ट दें और पास होकर अगला चरण खोलें',
            hoursAllocation: 'PYQ टेस्ट ${h1}h • उत्तर जांच ${h2}h • अंतिम रिवीजन ${h3}h',
            targetQuestions: 45,
            completed: false,
          ),
        ];
      }

      setState(() {
        _planSubject = cleanCourse;
        _dayPlan = steps;
        _isTestMode = false;
        _activeTestQuestion = null;
        _testAttempts = 0;
      });
      await _savePlanToPrefs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('पुराने पेपर्स के हिसाब से संभावित रिवीजन प्लान तैयार हो गया।')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingPlan = false);
    }
  }

  Future<void> _generateExpectedPyqRevision() async {
    final currentStep = _dayPlan.cast<DayPlanStep?>().firstWhere(
          (s) => s != null && !s.completed,
          orElse: () => null,
        );

    final topicLabel = currentStep != null
        ? 'Day ${currentStep.day}: ${currentStep.title} (${currentStep.focus})'
        : '${_planSubject.isNotEmpty ? _planSubject : _courseTrack} - सबसे संभावित PYQ रिवीजन';

    setState(() {
      _isLoading = true;
      _isTestMode = false;
      _activeTestQuestion = null;
      _testAttempts = 0;
      _currentQuestion = 'संभावित PYQ रिवीजन ($topicLabel)';
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });

    final langRule = _buildLanguageInstruction();
    final prompt = '''
तुम एक अनुभवी कोचिंग शिक्षक हो जो पुराने प्रश्नपत्रों (Previous Year Papers) के आधार पर सबसे ज़्यादा संभावित (Most Expected) सवाल और उनके पक्के उत्तर देता है। फ़ालतू या कम आने वाले सवाल मत दो।
$langRule
यह ऐप केवल पढ़ाई के लिए है। "घर-बाहर की मिसाल" या घर-परिवार की तुलना बिल्कुल मत लिखो।
कोर्स: "$_courseTrack" ($_courseDuration), विषय: "${_planSubject.isNotEmpty ? _planSubject : _courseTrack}", दिन/फोकस: "$topicLabel"
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।

इस रिवीजन के लिए 2 सबसे संभावित परीक्षा सवाल और उनके उत्तर इन हिस्सों में दो:
1. संभावित सवाल व पक्का उत्तर: (पुराने पेपर के पैटर्न पर सबसे संभावित प्रश्न और सीधा व पूरा उत्तर/हल)
2. 10x तेज़ समझ: (यह प्रश्न क्यों महत्वपूर्ण है और कम समय में कैसे हल होगा, साफ़ समझाओ)
3. शॉर्ट निचोड़: (परीक्षा में सीधे याद रखने वाला छोटा और पक्का सार)
''';

    try {
      final ans = await _callGemini(prompt);
      final nextCount = _usedToday + 1;
      await _prefs.setString(_keyDate, _todayKey());
      await _prefs.setInt(_keyCount, nextCount);

      setState(() {
        _currentAnswer = ans;
        _usedToday = nextCount;
      });
      await _persistCurrentItem(understood: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startDayTest() async {
    final currentStep = _dayPlan.cast<DayPlanStep?>().firstWhere(
          (s) => s != null && !s.completed,
          orElse: () => null,
        );

    final topicLabel = currentStep != null
        ? 'Day ${currentStep.day}: ${currentStep.title} (${currentStep.focus})'
        : '${_planSubject.isNotEmpty ? _planSubject : _courseTrack} - संभावित PYQ टेस्ट';

    setState(() {
      _isLoading = true;
      _isTestMode = true;
      _currentQuestion = null;
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });

    final langRule = _buildLanguageInstruction();
    final prompt = '''
तुम एक कोचिंग टेस्ट परीक्षक हो। पुराने प्रश्नपत्रों के पैटर्न पर सबसे ज़्यादा संभावित परीक्षा सवाल पूछो। फ़ालतू सवाल मत पूछो।
कोर्स: "$_courseTrack" ($_courseDuration), विषय: "${_planSubject.isNotEmpty ? _planSubject : _courseTrack}", लक्ष्य: "$topicLabel"
$langRule
यह ऐप केवल पढ़ाई के लिए है। "घर-बाहर की मिसाल" या घर-परिवार की तुलना बिल्कुल मत लिखो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।

इस टॉपिक पर सबसे संभावित 1 स्पष्ट परीक्षा सवाल पूछो (अभी उत्तर मत दो, सिर्फ़ सवाल पूछो ताकि छात्र अपना उत्तर लिखे):
''';

    try {
      final testQ = await _callGemini(prompt);
      setState(() {
        _activeTestQuestion = testQ;
        _currentQuestion = 'संभावित टेस्ट सवाल: $testQ';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      setState(() => _isTestMode = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _evaluateTestAnswer(String userAttempt) async {
    final testQ = _activeTestQuestion ?? 'इस टॉपिक का संभावित टेस्ट सवाल';
    setState(() {
      _isLoading = true;
      _currentQuestion = 'मेरा टेस्ट उत्तर: $userAttempt';
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });

    final langRule = _buildLanguageInstruction();
    final prompt = '''
तुम एक सख्त लेकिन मददगार कोचिंग शिक्षक हो जो छात्र का टेस्ट जांच रहे हो।
$langRule
यह ऐप केवल पढ़ाई के लिए है। "घर-बाहर की मिसाल" या घर-परिवार की तुलना बिल्कुल मत लिखो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।

टेस्ट सवाल: $testQ
छात्र का उत्तर: $userAttempt

जांचो कि उत्तर सही और पर्याप्त है या नहीं।
सबसे पहली लाइन में ठीक से लिखो:
यदि उत्तर सही और पास होने लायक है: "टेस्ट परिणाम: पास"
यदि उत्तर गलत, अधूरा या सुधार की ज़रूरत वाला है: "टेस्ट परिणाम: फेल (दोबारा अभ्यास ज़रूरी)"

उसके बाद इन हिस्सों में लिखो:
1. पक्का उत्तर और पूरा हल: (सही उत्तर और स्टेप-बाय-स्टेप हल)
2. 10x तेज़ समझ: (कहाँ सही किया या कहाँ सुधार चाहिए, सीधा समझाओ)
3. शॉर्ट निचोड़: (1-2 लाइन का पक्का सार)
''';

    try {
      final resultText = await _callGemini(prompt);
      final nextAttempts = _testAttempts + 1;
      setState(() {
        _currentAnswer = resultText;
        _testAttempts = nextAttempts;
      });
      await _persistCurrentItem(understood: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isCurrentResultTestPass() {
    final ans = _currentAnswer ?? '';
    return ans.contains('टेस्ट परिणाम: पास');
  }

  Future<void> _changeLangMode(String mode) async {
    await _prefs.setString(_keyLang, mode);
    setState(() => _langMode = mode);
    await _applyTtsSettings();
  }

  Future<void> _changeCoursePlan({String? track, String? duration, int? hours}) async {
    final nextTrack = track ?? _courseTrack;
    final nextDuration = duration ?? _courseDuration;
    final nextHours = hours ?? _dailyHours;
    await _prefs.setString(_keyCourseTrack, nextTrack);
    await _prefs.setString(_keyCourseDuration, nextDuration);
    await _prefs.setInt(_keyDailyHours, nextHours);
    setState(() {
      _courseTrack = nextTrack;
      _courseDuration = nextDuration;
      _dailyHours = nextHours;
      if (track != null && _planCourseController.text.trim().isEmpty) {
        _planCourseController.text = nextTrack;
      }
    });
  }

  Future<void> _saveApiKey() async {
    final cleanKey = _apiKeyController.text.trim();
    await _prefs.setString(_keyApi, cleanKey);
    setState(() => _apiKey = cleanKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('कोर्स और API Key सेव हो गई।')),
    );
  }

  Future<void> _addDemoCoins(int amount) async {
    final next = _coins + amount;
    await _prefs.setInt(_keyCoins, next);
    setState(() => _coins = next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('+$amount कॉइन्स जुड़ गए। कुल कॉइन्स: $next')),
    );
  }

  String _buildLanguageInstruction() {
    if (_langMode == 'en-US') {
      return 'Respond in simple, clear English suitable for students and exam aspirants.';
    }
    if (_langMode == 'auto') {
      return 'Reply in the same language the user asked in (Hindi, English, or any global language), keeping words clear, fast to grasp, and complete.';
    }
    return 'सवाल जिस भी भाषा में हो, जवाब आसान और साफ़ बोलचाल की हिंदी में दो ताकि छात्र कम समय में पूरा समझ जाए।';
  }

  Future<String> _callGemini(
    String prompt, {
    File? imageFile,
    String? mimeType,
    bool applyClean = true,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('कृपया ऊपर गियर आइकन (सेटिंग्स) में अपना कोर्स चुनें और Gemini API Key सेव करें।');
    }

    const model = 'gemini-3.5-flash-lite';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    String extraPart = '';
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      final b64 = base64Encode(bytes);
      final mime = mimeType ?? 'image/jpeg';
      extraPart = ',{"inline_data":{"mime_type":"$mime","data":"$b64"}}';
    }

    final payload =
        '{"contents":[{"parts":[{"text":${jsonEncode(prompt)}}$extraPart]}]}';

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
      },
      body: payload,
    );

    if (response.statusCode != 200) {
      throw Exception('API Error (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) {
      throw Exception('जवाब नहीं मिल पाया।');
    }
    final content = candidates.first['content'] as Map<String, dynamic>? ?? {};
    final parts = content['parts'] as List<dynamic>? ?? [];
    final text = parts
        .map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
        .join('\n')
        .trim();

    if (!applyClean) {
      return text.isEmpty ? 'जवाब तैयार नहीं हो सका, दोबारा पूछें।' : text;
    }
    final cleaned = cleanDisplayText(text);
    return cleaned.isEmpty ? 'जवाब तैयार नहीं हो सका, दोबारा पूछें।' : cleaned;
  }

  Future<void> _solveQuestion() async {
    final qText = _questionController.text.trim();
    final hasImg = _pickedImageFile != null;
    if (qText.isEmpty && !hasImg) return;

    FocusScope.of(context).unfocus();
    await _tts.stop();
    setState(() => _isSpeaking = false);

    if (_isTestMode && _activeTestQuestion != null && qText.isNotEmpty) {
      _questionController.clear();
      await _evaluateTestAnswer(qText);
      return;
    }

    final displayQ = qText.isNotEmpty ? qText : 'फ़ोटो में दिख रहा पढ़ाई का सवाल हल करके समझाओ';

    if (_usedToday >= dailyFreeLimit && _apiKey.isEmpty) {
      if (_coins > 0) {
        final nextCoins = _coins - 1;
        await _prefs.setInt(_keyCoins, nextCoins);
        setState(() => _coins = nextCoins);
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('आज के 5 फ़्री सवाल पूरे'),
            content: const Text(
              'दिन के 5 फ़्री सवाल पूरे हो गए हैं। गियर आइकन (सेटिंग्स) में अपनी Gemini API Key डालें या कॉइन पैक जोड़ें।',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ठीक है'),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _isTestMode = false;
      _activeTestQuestion = null;
      _testAttempts = 0;
      _currentQuestion = displayQ;
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });

    final activePlanNote = _planSubject.isNotEmpty
        ? 'विद्यार्थी का कोर्स: "$_courseTrack" ($_courseDuration), विषय/प्लान: "$_planSubject", रोज़ पढ़ाई लक्ष्य: $_dailyHours घंटे।'
        : 'विद्यार्थी का कोर्स: "$_courseTrack" ($_courseDuration), रोज़ पढ़ाई लक्ष्य: $_dailyHours घंटे।';

    final langRule = _buildLanguageInstruction();
    final prompt = '''
तुम एक कोचिंग शिक्षक हो जो पुराने प्रश्नपत्रों (PYQ) के पैटर्न, कोचिंग से 10 गुना तेज़ समझ और टेस्ट में नंबर पक्का कराने वाले उत्तर देता है। फ़ालतू या बाहर की बातें मत करो।
$activePlanNote
$langRule
सख्त नियम: यह ऐप केवल पढ़ाई, स्कूल/कॉलेज के विषय, गणित, विज्ञान, भाषा, इतिहास, भूगोल, सामान्य ज्ञान, परीक्षा तैयारी या सीखने-समझाने के सवालों का जवाब देगा।
यदि सवाल पढ़ाई या सीखने से जुड़ा नहीं है (जैसे गपशप, मज़ाक, व्यक्तिगत चैट, या गैर-शैक्षणिक विषय), तो कोई और जवाब मत दो—सिर्फ़ इतना कहो कि यह ऐप केवल पढ़ाई के सवालों के लिए है और पढ़ाई का कोई सवाल पूछने को कहो।
महत्वपूर्ण: जवाब में "घर-बाहर की मिसाल" या घर-परिवार/मसालों/बाहरी चीज़ों की तुलना बिल्कुल मत डालो। सीधे पढ़ाई और विषय की बात करो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।

हर पढ़ाई के सवाल को इस क्रम में पूरा हल करो और समझाओ:
1. पक्का उत्तर और तेज़ हल: (अंतिम उत्तर और स्टेप-बाय-स्टेप स्पष्ट हल)
2. 10x तेज़ समझ: (मुख्य नियम, फॉर्मूला या वजह को बिना भटकाए सीधा समझाओ)
3. टेस्ट प्वाइंट और शॉर्ट निचोड़: (परीक्षा में गलती से बचने की टिप और 1-2 लाइन का पक्का सार)

सवाल: $displayQ
''';

    try {
      final ans = await _callGemini(
        prompt,
        imageFile: _pickedImageFile,
        mimeType: _pickedImageMime,
      );
      final nextCount = _usedToday + 1;
      await _prefs.setString(_keyDate, _todayKey());
      await _prefs.setInt(_keyCount, nextCount);

      setState(() {
        _currentAnswer = ans;
        _usedToday = nextCount;
      });
      await _persistCurrentItem(understood: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addAnotherMethod() async {
    if (_currentQuestion == null || _currentAnswer == null) return;
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _isLoading = true;
    });

    final previousWays = [
      cleanDisplayText(_currentAnswer!),
      ..._extraMethods.map(cleanDisplayText),
    ].join('\n---\n');

    final langRule = _buildLanguageInstruction();
    final prompt = '''
छात्र को यह अभी पूरी तरह समझ नहीं आया है। एक कोचिंग शिक्षक की तरह पहले से अलग, 10 गुना तेज़ और सरल तरीके से दोबारा समझाओ ताकि टेस्ट में गलती न हो।
$langRule
यह ऐप केवल पढ़ाई के सवालों के लिए है। पहले बताए गए तरीकों को मत दोहराओ, और "घर-बाहर की मिसाल" या घर-बाहर की तुलना बिल्कुल मत डालो। पहले पूरा स्पष्ट हल/समझ दो और आखिर में शॉर्ट निचोड़ लिखो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।

सवाल: $_currentQuestion
पहले बताए गए तरीके:
$previousWays
''';

    try {
      final extra = await _callGemini(prompt);
      setState(() {
        _extraMethods.add(extra);
        _understood = false;
      });
      await _persistCurrentItem(understood: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markUnderstoodAndNext() async {
    await _tts.stop();
    if (_isTestMode) {
      if (!_isCurrentResultTestPass()) {
        setState(() {
          _isSpeaking = false;
          _currentAnswer = null;
          _extraMethods.clear();
        });
        await _startDayTest();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('टेस्ट अभी पूरा पास नहीं हुआ—उसी दिन के संभावित सवाल से दोबारा टेस्ट लिया जा रहा है।')),
        );
        return;
      }
      await _markActiveDayPassed();
      _questionController.clear();
      setState(() {
        _pickedImageFile = null;
        _pickedImageMime = null;
        _currentQuestion = null;
        _currentAnswer = null;
        _extraMethods.clear();
        _understood = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('टेस्ट पास! अगला दिन अनलॉक हो गया।')),
      );
      return;
    }

    setState(() {
      _isSpeaking = false;
      _understood = true;
    });
    await _persistCurrentItem(understood: true);
    _questionController.clear();
    setState(() {
      _pickedImageFile = null;
      _pickedImageMime = null;
      _currentQuestion = null;
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('बढ़िया, सवाल सेव हो गया। अब अगला पढ़ाई का सवाल पूछो।')),
    );
  }

  Future<void> _persistCurrentItem({required bool understood}) async {
    if (_currentQuestion == null || _currentAnswer == null) return;
    final item = SolvedItem(
      question: cleanDisplayText(_currentQuestion!),
      answerText: cleanDisplayText(_currentAnswer!),
      extraMethods: _extraMethods.map(cleanDisplayText).toList(),
      understood: understood,
      date: _todayKey(),
    );

    final updated = [
      item,
      ..._savedItems.where((x) => x.question != item.question),
    ];

    await _prefs.setStringList(
      _keySaved,
      updated.map((x) => jsonEncode(x.toJson())).toList(),
    );
    setState(() => _savedItems = updated);
  }

  void _openOfflineCoursePackSheet() {
    _planCourseController.text =
        _planSubject.isNotEmpty ? _planSubject : _courseTrack;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.94,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            children: [
              const Text(
                'PYQ प्लान, संभावित रिवीजन और टेस्ट गेट',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'कोर्स: $_courseTrack ($_courseDuration) • रोज़ लक्ष्य: $_dailyHours घंटे',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _planCourseController,
                decoration: InputDecoration(
                  labelText: 'कोर्स या विषय लिखें',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isGeneratingPlan
                          ? null
                          : () async {
                              await _generateDayByDayPlan(_planCourseController.text);
                              setModalState(() {});
                            },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        _isGeneratingPlan ? 'प्लान बन रहा है...' : 'PYQ प्लान बनाएं',
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _generateExpectedPyqRevision();
                          },
                    icon: const Icon(Icons.auto_stories_outlined),
                    label: const Text('संभावित रिवीजन'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _startDayTest();
                      },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('आज के संभावित प्रश्नों का टेस्ट दें'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_dayPlan.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'प्रगति: ${_dayPlan.where((s) => s.completed).length}/${_dayPlan.length} दिन टेस्ट पास',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < _dayPlan.length; i++) ...[
                  Builder(
                    builder: (_) {
                      final step = _dayPlan[i];
                      final firstUnfinished = _dayPlan.indexWhere((s) => !s.completed);
                      final isUnlocked =
                          step.completed || i == firstUnfinished || firstUnfinished == -1;
                      return Card(
                        elevation: 0,
                        color: step.completed
                            ? const Color(0xFFECFDF5)
                            : isUnlocked
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFFF1F5F9),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          leading: Icon(
                            step.completed
                                ? Icons.check_circle
                                : isUnlocked
                                    ? Icons.play_circle_outline
                                    : Icons.lock_outline,
                            color: step.completed
                                ? const Color(0xFF15803D)
                                : isUnlocked
                                    ? const Color(0xFF1A73E8)
                                    : const Color(0xFF94A3B8),
                          ),
                          title: Text(
                            'Day ${step.day}: ${step.title}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          subtitle: Text(
                            '${step.hoursAllocation} • संभावित लक्ष्य: ${step.targetQuestions} सवाल\n${step.focus}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ],
              ],
              const Divider(height: 24),
              const Text(
                'ऑफलाइन PYQ पैक (बिना इंटरनेट पढ़ें)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final pack in kOfflineCoursePack)
                Card(
                  elevation: 0,
                  color: const Color(0xFFF8FAFC),
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: ListTile(
                    title: Text(
                      '${pack.courseTag} • ${pack.durationTag}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    subtitle: Text('${pack.topic}\n${pack.question}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.menu_book_outlined),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _isTestMode = false;
                        _activeTestQuestion = null;
                        _currentQuestion = pack.question;
                        _currentAnswer = pack.answerText;
                        _extraMethods.clear();
                        _understood = null;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettingsSheet() {
    final remainingFree = (dailyFreeLimit - _usedToday).clamp(0, dailyFreeLimit);
    _apiKeyController.text = _apiKey;
    _courseSearchController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setModalState) {
          final query = _courseSearchController.text.trim().toLowerCase();
          final allOptions = <String>[
            if (_courseTrack.isNotEmpty && !kAllCourses.contains(_courseTrack)) _courseTrack,
            ...kAllCourses,
          ];
          final filtered = query.isEmpty
              ? allOptions
              : allOptions.where((c) => c.toLowerCase().contains(query)).toList();

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'सेटिंग्स • ऑल कोर्स, सर्च और API Key',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'चयनित: $_courseTrack • फ़्री बाकी: $remainingFree / $dailyFreeLimit • कॉइन्स: $_coins',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _courseSearchController,
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'कोर्स सर्च करें या नया कोर्स नाम लिखें',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                  if (_courseSearchController.text.trim().isNotEmpty && filtered.isEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final customCourse = _courseSearchController.text.trim();
                        await _changeCoursePlan(track: customCourse);
                        _planCourseController.text = customCourse;
                        setModalState(() {});
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text('कस्टम कोर्स चुनें: "${_courseSearchController.text.trim()}"'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 165),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in filtered)
                            ChoiceChip(
                              label: Text(c, style: const TextStyle(fontSize: 12.5)),
                              selected: _courseTrack == c,
                              onSelected: (_) async {
                                await _changeCoursePlan(track: c);
                                _planCourseController.text = c;
                                setModalState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('6 महीने'),
                          selected: _courseDuration == '6 Months',
                          onSelected: (_) async {
                            await _changeCoursePlan(duration: '6 Months');
                            setModalState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('1 साल'),
                          selected: _courseDuration == '1 Year',
                          onSelected: (_) async {
                            await _changeCoursePlan(duration: '1 Year');
                            setModalState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('रोज़ पढ़ाई घंटे: ', style: TextStyle(fontWeight: FontWeight.w600)),
                      for (final h in [3, 5, 8]) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('${h}h'),
                          selected: _dailyHours == h,
                          onSelected: (_) async {
                            await _changeCoursePlan(hours: h);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'अपनी Gemini API Key',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      await _saveApiKey();
                      await _generateDayByDayPlan(_courseTrack);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Key सेव करें और PYQ प्लान बनाएं'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _addDemoCoins(25);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.monetization_on_outlined),
                    label: const Text('अनलॉक कॉइन पैक (+25 कॉइन्स)'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openSavedSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: _savedItems.length,
          itemBuilder: (_, idx) {
            final item = _savedItems[idx];
            return Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(cleanDisplayText(item.question)),
                subtitle: Text(
                  '${item.date} • ${item.understood ? "पक्का समझ आ गया" : "दोबारा रिवीजन ज़रूरी"}',
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isTestMode = false;
                    _activeTestQuestion = null;
                    _currentQuestion = cleanDisplayText(item.question);
                    _currentAnswer = cleanDisplayText(item.answerText);
                    _extraMethods
                      ..clear()
                      ..addAll(item.extraMethods.map(cleanDisplayText));
                    _understood = item.understood;
                  });
                },
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    _apiKeyController.dispose();
    _planCourseController.dispose();
    _courseSearchController.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextStep = _dayPlan.cast<DayPlanStep?>().firstWhere(
          (s) => s != null && !s.completed,
          orElse: () => null,
        );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6F9),
        surfaceTintColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF1A73E8), size: 22),
            SizedBox(width: 8),
            Text(
              'SamajhAaya',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _langMode,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'hi-IN', child: Text('हिन्दी')),
                  DropdownMenuItem(value: 'en-US', child: Text('English')),
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                ],
                onChanged: (val) {
                  if (val != null) _changeLangMode(val);
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'PYQ प्लान और टेस्ट',
            onPressed: _openOfflineCoursePackSheet,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'सेव किए हुए सवाल',
            onPressed: _openSavedSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'सेटिंग्स',
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                if (_pickedImageFile != null) ...[
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          _pickedImageFile!,
                          height: 165,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close, color: Colors.white, size: 16),
                            onPressed: _clearPickedImage,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('संभावित PYQ हल और समझ तैयार हो रही है...'),
                        ],
                      ),
                    ),
                  )
                else if (_currentAnswer != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cleanDisplayText(_currentQuestion ?? ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            IconButton.filledTonal(
                              icon: Icon(
                                _isSpeaking ? Icons.stop_circle : Icons.volume_up,
                              ),
                              tooltip: _isSpeaking ? 'आवाज़ रोकें' : 'सुनें (0.30x)',
                              onPressed: _toggleSpeak,
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Text(
                          cleanDisplayText(_currentAnswer!),
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        for (int i = 0; i < _extraMethods.length; i++) ...[
                          const Divider(height: 20),
                          Text(
                            'और तेज़ तरीका #${i + 2}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cleanDisplayText(_extraMethods[i]),
                            style: const TextStyle(fontSize: 15, height: 1.5),
                          ),
                        ],
                        const Divider(height: 20),
                        Text(
                          _isTestMode
                              ? (_isCurrentResultTestPass()
                                  ? 'टेस्ट पास हो गया! अगला दिन खोलें?'
                                  : 'टेस्ट पूरा पास नहीं हुआ—दोबारा टेस्ट लें या और समझें?')
                              : 'समझ आया क्या?',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _isLoading ? null : _markUnderstoodAndNext,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _isTestMode
                                      ? (_isCurrentResultTestPass()
                                          ? 'पास: अगला दिन खोलें'
                                          : 'दोबारा टेस्ट सवाल लें')
                                      : 'हाँ, समझ आ गया',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isLoading ? null : _addAnotherMethod,
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('नहीं, और बताओ'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else if (_isTestMode && _activeTestQuestion != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF1A73E8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'संभावित PYQ टेस्ट (प्रयास #${_testAttempts + 1})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A73E8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cleanDisplayText(_activeTestQuestion!),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'नीचे अपना उत्तर लिखें या बोलें और तीर दबाकर टेस्ट जमा करें।',
                          style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_courseTrack • $_courseDuration • $_dailyHours घंटे/दिन',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          nextStep != null
                              ? 'Day ${nextStep.day}: ${nextStep.title}\n${nextStep.hoursAllocation} • संभावित लक्ष्य: ${nextStep.targetQuestions} सवाल'
                              : 'सेटिंग्स (गियर आइकन) से कोर्स सर्च/चुनें व API Key डालें, या किताब आइकन से पुराने पेपर्स के हिसाब से रिवीजन व टेस्ट शुरू करें।',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _generateExpectedPyqRevision,
                              icon: const Icon(Icons.auto_stories_outlined),
                              label: const Text('संभावित PYQ रिवीजन'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (nextStep != null)
                              OutlinedButton.icon(
                                onPressed: _isLoading ? null : _startDayTest,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: Text('Day ${nextStep.day} का टेस्ट दें'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6F9),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _isLoading ? null : _openAttachSheet,
                      icon: const Icon(Icons.add),
                      tooltip: 'फ़ोटो जोड़ें',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _questionController,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _isLoading ? null : _solveQuestion(),
                        decoration: InputDecoration(
                          hintText:
                              _isTestMode ? 'टेस्ट का उत्तर लिखें...' : 'पढ़ाई का सवाल पूछें...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isLoading ? null : _toggleListen,
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      tooltip: _isListening ? 'रोकें' : 'बोलें',
                    ),
                    IconButton.filled(
                      onPressed: _isLoading ? null : _solveQuestion,
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      tooltip: 'समझाओ',
                    ),
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
