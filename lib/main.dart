import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: const StudyHomeScreen(),
    );
  }
}

class ChatEntry {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String title;
  final String body;
  final File? imageFile;
  final String? badge;
  final bool isPass;

  ChatEntry({
    required this.id,
    required this.role,
    required this.title,
    required this.body,
    this.imageFile,
    this.badge,
    this.isPass = false,
  });
}

class StudyHomeScreen extends StatefulWidget {
  const StudyHomeScreen({super.key});

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  final ImagePicker _picker = ImagePicker();

  final List<ChatEntry> _entries = [];

  // हर कोर्स के असली विषय
  static const Map<String, List<String>> _courseSubjects = {
    'दिल्ली पुलिस (Delhi Police)': [
      'सामान्य ज्ञान व करंट अफेयर्स',
      'तर्कशक्ति / रीजनिंग',
      'संख्यात्मक योग्यता / गणित',
      'कंप्यूटर फंडामेंटल',
      'संविधान, इतिहास व भूगोल',
    ],
    'SSC GD / Constable': [
      'सामान्य ज्ञान व सामान्य विज्ञान',
      'प्रारंभिक गणित',
      'तर्कशक्ति / रीजनिंग',
      'हिंदी व्याकरण',
      'अंग्रेजी शब्दावली व बोध',
    ],
    '10वीं / 12वीं बोर्ड परीक्षा': [
      'गणित',
      'विज्ञान',
      'सामाजिक विज्ञान',
      'हिंदी',
      'अंग्रेजी',
    ],
    'सामान्य प्रतियोगी परीक्षा': [
      'अंकगणित व संख्या पद्धति',
      'रीजनिंग',
      'सामान्य अध्ययन',
      'सामान्य विज्ञान व करंट अफेयर्स',
      'भाषा व बोध',
    ],
  };

  String _selectedCourse = 'दिल्ली पुलिस (Delhi Police)';
  String _language = 'हिन्दी';
  String _apiKey = '';
  double _speechRate = 0.45;
  bool _isListening = false;
  bool _isBusy = false;
  String _statusText = '';

  // विषय व टाइमर स्टेट
  int _dayNumber = 1;
  int _currentSubjectIndex = 0;
  int _subjectSecondsTotal = 3600; // डिफ़ॉल्ट 1 घंटा (60 मिनट)
  int _remainingSeconds = 3600;
  bool _finalTestMode = false;
  bool _currentSubjectTestPassed = false;
  int _subjectAttempts = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _initTts();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _tts.stop();
    super.dispose();
  }

  List<String> get _subjects =>
      _courseSubjects[_selectedCourse] ?? _courseSubjects['सामान्य प्रतियोगी परीक्षा']!;

  String get _formattedTimer {
    final hrs = _remainingSeconds ~/ 3600;
    final mins = (_remainingSeconds % 3600) ~/ 60;
    final secs = _remainingSeconds % 60;
    if (hrs > 0) {
      return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get _currentStageLabel {
    if (_finalTestMode) {
      return 'दिन $_dayNumber • फाइनल टेस्ट (सभी ${_subjects.length} विषय) • $_formattedTimer';
    }
    final subj = _subjects[_currentSubjectIndex.clamp(0, _subjects.length - 1)];
    final testTag = _currentSubjectTestPassed ? 'टेस्ट पास ✓' : 'टेस्ट बाकी';
    return 'दिन $_dayNumber • विषय ${_currentSubjectIndex + 1}/${_subjects.length}: $subj ($testTag) • $_formattedTimer';
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _selectedCourse = prefs.getString('selected_course') ?? 'दिल्ली पुलिस (Delhi Police)';
      if (!_courseSubjects.containsKey(_selectedCourse)) {
        _selectedCourse = 'दिल्ली पुलिस (Delhi Police)';
      }
      _language = prefs.getString('language') ?? 'हिन्दी';
      _speechRate = prefs.getDouble('speech_rate') ?? 0.45;
      _dayNumber = prefs.getInt('day_number') ?? 1;
      _currentSubjectIndex = (prefs.getInt('current_subject_index') ?? 0)
          .clamp(0, _subjects.length - 1);
      _subjectSecondsTotal = prefs.getInt('subject_seconds_total') ?? 3600;
      _remainingSeconds = prefs.getInt('remaining_seconds') ?? _subjectSecondsTotal;
      _finalTestMode = prefs.getBool('final_test_mode') ?? false;
      _currentSubjectTestPassed = prefs.getBool('subject_test_passed') ?? false;
      _subjectAttempts = prefs.getInt('subject_attempts') ?? 0;
    });

    if (_entries.isEmpty) {
      await _loadCourseLineByLine(autoStartTimer: true);
    } else {
      _startTimerLoop();
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKey);
    await prefs.setString('selected_course', _selectedCourse);
    await prefs.setString('language', _language);
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setInt('day_number', _dayNumber);
    await prefs.setInt('current_subject_index', _currentSubjectIndex);
    await prefs.setInt('subject_seconds_total', _subjectSecondsTotal);
    await prefs.setInt('remaining_seconds', _remainingSeconds);
    await prefs.setBool('final_test_mode', _finalTestMode);
    await prefs.setBool('subject_test_passed', _currentSubjectTestPassed);
    await prefs.setInt('subject_attempts', _subjectAttempts);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage(_language == 'English' ? 'en-IN' : 'hi-IN');
    await _tts.setSpeechRate(_speechRate);
  }

  void _startTimerLoop() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds -= 1;
        });
      } else {
        timer.cancel();
        await _onSubjectTimerFinished();
      }
    });
  }

  Future<void> _onSubjectTimerFinished() async {
    if (_finalTestMode) {
      setState(() {
        _remainingSeconds = 0;
        _entries.add(
          ChatEntry(
            id: 'timer_final_${DateTime.now().millisecondsSinceEpoch}',
            role: 'system',
            title: 'फाइनल टेस्ट का समय समाप्त',
            body: 'सभी ${_subjects.length} विषयों का समय पूरा हो गया। नीचे फाइनल टेस्ट का उत्तर दें या "फाइनल टेस्ट" बटन दबाएं।',
            badge: _currentStageLabel,
          ),
        );
      });
      await _savePrefs();
      _scrollToBottom();
      return;
    }

    final finishedSubj = _subjects[_currentSubjectIndex.clamp(0, _subjects.length - 1)];

    setState(() {
      if (_currentSubjectIndex < _subjects.length - 1) {
        _currentSubjectIndex += 1;
        _currentSubjectTestPassed = false;
        _subjectAttempts = 0;
        _remainingSeconds = _subjectSecondsTotal;
        final nextSubj = _subjects[_currentSubjectIndex];
        _entries.add(
          ChatEntry(
            id: 'next_subj_${DateTime.now().millisecondsSinceEpoch}',
            role: 'system',
            title: '$finishedSubj का टाइमर पूरा -> अब $nextSubj शुरू',
            body: 'अगले विषय "$nextSubj" का टाइमर ($_formattedTimer) शुरू हो गया है। इसका टेस्ट पास करें और आगे बढ़ें।',
            badge: _currentStageLabel,
          ),
        );
      } else {
        _finalTestMode = true;
        _remainingSeconds = _subjectSecondsTotal;
        _entries.add(
          ChatEntry(
            id: 'all_done_${DateTime.now().millisecondsSinceEpoch}',
            role: 'system',
            title: 'सभी ${_subjects.length} विषयों का टाइमर पूरा • फाइनल टेस्ट खुला',
            body: 'अब दिन $_dayNumber का फाइनल टेस्ट शुरू करें।',
            badge: _currentStageLabel,
          ),
        );
      }
    });

    await _savePrefs();
    _scrollToBottom();
    _startTimerLoop();
  }

  String _cleanText(String raw) {
    var out = raw;
    out = out.replaceAll(RegExp(r'\*\*|##|---|>'), '');
    out = out.replaceAll(r'$', '');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  String _strictAccuracyRules() {
    final langLine = _language == 'English'
        ? 'Respond clearly in simple English.'
        : 'स्पष्ट और सरल हिन्दी में उत्तर दो।';
    return '''
$langLine
सख्त नियम (बिना गलती का नियम):
1. जवाब लिखने से पहले मन में पूरा गणित और तर्क पक्का कर लो।
2. जवाब के बीच में खुद को बार-बार काटते हुए संख्याएँ मत बदलो। "माफ करना", "रुकिए दोबारा जोड़ते हैं", या रूखी/अपमानजनक भाषा बिल्कुल मत लिखो।
3. सवाल और हल लाइन-बाय-लाइन साफ क्रम में लिखो।
4. Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।
''';
  }

  Future<String> _callGeminiWithFallback(String prompt, {File? imageFile}) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception('ऊपर गियर आइकन (सेटिंग्स) में अपनी Gemini API Key सेव करें।');
    }

    const models = [
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-3.5-flash-lite',
    ];

    String extraPart = '';
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      final b64 = base64Encode(bytes);
      extraPart = ',{"inline_data":{"mime_type":"image/jpeg","data":"$b64"}}';
    }

    final payload =
        '{"contents":[{"parts":[{"text":${jsonEncode(prompt)}}$extraPart]}]}';

    String lastError = 'जवाब प्राप्त नहीं हो सका।';

    for (final model in models) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
      );

      // अधिकतम 2 प्रयास (कोई अनंत लूप नहीं)
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-goog-api-key': _apiKey.trim(),
                },
                body: payload,
              )
              .timeout(const Duration(seconds: 25));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final candidates = data['candidates'] as List<dynamic>? ?? [];
            if (candidates.isNotEmpty) {
              final content =
                  candidates.first['content'] as Map<String, dynamic>? ?? {};
              final parts = content['parts'] as List<dynamic>? ?? [];
              final text = parts
                  .map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
                  .join('\n')
                  .trim();
              if (text.isNotEmpty) {
                return _cleanText(text);
              }
            }
          } else {
            lastError = 'मॉडल $model स्थिति ${response.statusCode}';
          }
        } on TimeoutException {
          lastError = 'समय सीमा समाप्त ($model)';
        } catch (e) {
          lastError = e.toString();
        }
      }
    }

    throw Exception(lastError);
  }

  // कोर्स चुनते ही तुरंत सभी विषयों के सवाल और हल लाइन-बाय-लाइन दिखाना
  Future<void> _loadCourseLineByLine({bool autoStartTimer = true}) async {
    final subjectsList = _subjects.join(', ');
    setState(() {
      _entries.clear();
      _entries.add(
        ChatEntry(
          id: 'course_hdr_${DateTime.now().millisecondsSinceEpoch}',
          role: 'system',
          title: '$_selectedCourse • कुल ${_subjects.length} विषय',
          body: 'विषय: ${_subjects.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join(' | ')}\nटाइमर: $_formattedTimer (खत्म होने पर अपने आप अगला विषय शुरू होगा)',
          badge: _currentStageLabel,
        ),
      );
    });

    if (autoStartTimer) {
      _remainingSeconds = _subjectSecondsTotal;
      _startTimerLoop();
    }

    if (_apiKey.trim().isEmpty) {
      setState(() {
        _entries.add(
          ChatEntry(
            id: 'need_key_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            title: 'लाइन-बाय-लाइन सवाल व हल',
            body: 'कोर्स "$_selectedCourse" के ${_subjects.length} विषय सेट हो गए हैं। लाइव सवाल व हल तुरंत पाने के लिए ऊपर गियर आइकन (सेटिंग्स) में API Key डालें।',
          ),
        );
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _statusText = '$_selectedCourse के सभी ${_subjects.length} विषयों के सवाल व हल तैयार हो रहे हैं...';
    });

    try {
      final prompt = '''
${_strictAccuracyRules()}
कोर्स: $_selectedCourse
विषय (${_subjects.length}): $subjectsList

प्रत्येक विषय के लिए लाइन-बाय-लाइन 2 महत्वपूर्ण परीक्षा सवाल और उनके तुरंत पक्के हल लिखो।
हर लाइन साफ हो:
विषय का नाम:
सवाल 1: ...
हल 1: ...
सवाल 2: ...
हल 2: ...
''';

      final content = await _callGeminiWithFallback(prompt);
      final lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      setState(() {
        _entries.add(
          ChatEntry(
            id: 'line_by_line_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            title: '$_selectedCourse • सवाल व हल (लाइन-बाय-लाइन)',
            body: lines.join('\n'),
            badge: 'कुल ${_subjects.length} विषय तैयार',
          ),
        );
      });
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _isBusy = false;
        _statusText = '';
      });
      _scrollToBottom();
    }
  }

  Future<void> _startSubjectTest({bool isFinal = false}) async {
    if (_isBusy) return;
    final target = isFinal
        ? 'सभी ${_subjects.length} विषय (फाइनल टेस्ट)'
        : _subjects[_currentSubjectIndex.clamp(0, _subjects.length - 1)];

    setState(() {
      _isBusy = true;
      _statusText = '$target का टेस्ट प्रश्न तैयार हो रहा है...';
    });

    try {
      final prompt = '''
${_strictAccuracyRules()}
कोर्स: $_selectedCourse
दिन: $_dayNumber
टेस्ट: $target
प्रयास: ${_subjectAttempts + 1}

परीक्षा पैटर्न के अनुसार एक स्पष्ट और पक्का टेस्ट प्रश्न पूछो।
प्रश्न के साथ उसका उत्तर मत लिखो।
''';

      final qText = await _callGeminiWithFallback(prompt);
      setState(() {
        if (isFinal) _finalTestMode = true;
        _entries.add(
          ChatEntry(
            id: 'q_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            title: isFinal
                ? 'फाइनल टेस्ट (प्रयास #${_subjectAttempts + 1})'
                : 'विषय टेस्ट: $target (प्रयास #${_subjectAttempts + 1})',
            body: qText,
            badge: 'नीचे अपना उत्तर लिखें या बोलें',
          ),
        );
      });
      await _savePrefs();
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _isBusy = false;
        _statusText = '';
      });
      _scrollToBottom();
    }
  }

  Future<void> _handleUserSubmit(String text, {File? imageFile}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && imageFile == null) || _isBusy) return;

    _inputController.clear();

    setState(() {
      _isBusy = true;
      _statusText = 'जवाब जाँचा जा रहा है...';
      _entries.add(
        ChatEntry(
          id: 'u_${DateTime.now().millisecondsSinceEpoch}',
          role: 'user',
          title: 'आपका उत्तर / सवाल',
          body: trimmed.isNotEmpty ? trimmed : 'छवि भेजी गई',
          imageFile: imageFile,
        ),
      );
    });
    _scrollToBottom();

    try {
      final lastAssistant = _entries.reversed
          .firstWhere(
            (e) => e.role == 'assistant',
            orElse: () => ChatEntry(id: '', role: 'assistant', title: '', body: ''),
          )
          .body;

      final prompt = '''
${_strictAccuracyRules()}
कोर्स: $_selectedCourse
वर्तमान स्थिति: $_currentStageLabel
पिछला सवाल/संदर्भ: $lastAssistant
छात्र का उत्तर/सवाल: $trimmed

यदि यह किसी टेस्ट का उत्तर है, तो पहली लाइन में लिखो:
"टेस्ट परिणाम: पास" या "टेस्ट परिणाम: फेल (दोबारा अभ्यास ज़रूरी)"

इसके बाद इन 3 हिस्सों में स्पष्ट उत्तर दो:
1. पक्का उत्तर और सही हल
2. 10x तेज़ समझ
3. शॉर्ट निचोड़
''';

      final answer = await _callGeminiWithFallback(prompt, imageFile: imageFile);
      final passed = answer.contains('टेस्ट परिणाम: पास');

      setState(() {
        if (passed) {
          _subjectAttempts = 0;
          _currentSubjectTestPassed = true;
          if (_finalTestMode) {
            _dayNumber += 1;
            _currentSubjectIndex = 0;
            _finalTestMode = false;
            _currentSubjectTestPassed = false;
            _remainingSeconds = _subjectSecondsTotal;
          } else if (_currentSubjectIndex < _subjects.length - 1) {
            _currentSubjectIndex += 1;
            _currentSubjectTestPassed = false;
            _remainingSeconds = _subjectSecondsTotal;
          } else {
            _finalTestMode = true;
            _remainingSeconds = _subjectSecondsTotal;
          }
        } else {
          _subjectAttempts += 1;
        }

        _entries.add(
          ChatEntry(
            id: 'a_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            title: passed ? 'टेस्ट पास • अगला चरण खुला' : 'दोबारा अभ्यास करें',
            body: answer,
            badge: _currentStageLabel,
            isPass: passed,
          ),
        );
      });

      await _savePrefs();
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _isBusy = false;
        _statusText = '';
      });
      _scrollToBottom();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) {
      await _handleUserSubmit(_inputController.text, imageFile: File(picked.path));
    }
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _stt.stop();
      setState(() => _isListening = false);
      return;
    }

    final available = await _stt.initialize();
    if (!available) {
      _showError('माइक्रोफोन उपलब्ध नहीं है।');
      return;
    }

    setState(() => _isListening = true);
    await _stt.listen(
      localeId: _language == 'English' ? 'en_IN' : 'hi_IN',
      onResult: (res) {
        if (res.recognizedWords.isNotEmpty) {
          _inputController.text = res.recognizedWords;
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        }
        if (res.finalResult) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  Future<void> _speak(String text) async {
    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(text);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 140,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openSettingsDialog() {
    final keyCtrl = TextEditingController(text: _apiKey);
    String tempCourse = _selectedCourse;
    String tempLang = _language;
    double tempRate = _speechRate;
    int tempMinutes = (_subjectSecondsTotal ~/ 60).clamp(1, 180);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('कोर्स, टाइमर व सेटिंग्स'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tempCourse,
                  decoration: const InputDecoration(labelText: 'कोर्स चुनें'),
                  items: _courseSubjects.keys
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => tempCourse = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: tempMinutes,
                  decoration: const InputDecoration(labelText: 'प्रति विषय टाइमर (मिनट)'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 मिनट (क्विक टेस्ट)')),
                    DropdownMenuItem(value: 5, child: Text('5 मिनट')),
                    DropdownMenuItem(value: 30, child: Text('30 मिनट')),
                    DropdownMenuItem(value: 60, child: Text('60 मिनट (1 घंटा)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => tempMinutes = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tempLang,
                  decoration: const InputDecoration(labelText: 'भाषा'),
                  items: const [
                    DropdownMenuItem(value: 'हिन्दी', child: Text('हिन्दी')),
                    DropdownMenuItem(value: 'English', child: Text('English')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => tempLang = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gemini API Key',
                    hintText: 'AIza...',
                  ),
                ),
                const SizedBox(height: 12),
                Text('आवाज़ की गति: ${tempRate.toStringAsFixed(2)}x'),
                Slider(
                  min: 0.25,
                  max: 0.85,
                  value: tempRate,
                  onChanged: (v) => setLocal(() => tempRate = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('रद्द करें'),
            ),
            FilledButton(
              onPressed: () async {
                final courseChanged = _selectedCourse != tempCourse;
                setState(() {
                  _apiKey = keyCtrl.text.trim();
                  _selectedCourse = tempCourse;
                  _language = tempLang;
                  _speechRate = tempRate;
                  _subjectSecondsTotal = tempMinutes * 60;
                  if (courseChanged) {
                    _currentSubjectIndex = 0;
                    _finalTestMode = false;
                    _currentSubjectTestPassed = false;
                    _subjectAttempts = 0;
                  }
                  _remainingSeconds = _subjectSecondsTotal;
                });
                await _savePrefs();
                await _initTts();
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadCourseLineByLine(autoStartTimer: true);
              },
              child: const Text('सेव व लोड करें'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SamajhAaya'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
            tooltip: 'सेटिंग्स',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.indigo.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStageLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isBusy ? null : () => _loadCourseLineByLine(autoStartTimer: false),
                        icon: const Icon(Icons.format_list_numbered, size: 16),
                        label: const Text('सवाल व हल (लाइन-बाय-लाइन)'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _isBusy
                            ? null
                            : () => _startSubjectTest(isFinal: _finalTestMode),
                        icon: const Icon(Icons.quiz, size: 16),
                        label: Text(_finalTestMode ? 'फाइनल टेस्ट' : 'विषय टेस्ट'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_statusText.isNotEmpty) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (ctx, i) {
                final e = _entries[i];
                final isUser = e.role == 'user';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: isUser
                      ? Colors.indigo.shade50
                      : (e.isPass ? Colors.green.shade50 : Colors.white),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                e.title,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (!isUser && e.role == 'assistant')
                              IconButton(
                                icon: const Icon(Icons.volume_up, size: 20),
                                onPressed: () => _speak(e.body),
                              ),
                          ],
                        ),
                        if (e.badge != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            e.badge!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (e.imageFile != null) ...[
                          const SizedBox(height: 8),
                          Image.file(e.imageFile!, height: 150),
                        ],
                        const SizedBox(height: 8),
                        SelectableText(e.body),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _isBusy ? null : () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: _isBusy ? null : () => _pickImage(ImageSource.camera),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: 'टेस्ट उत्तर या सवाल लिखें...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (v) => _handleUserSubmit(v),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    onPressed: _isBusy ? null : _toggleVoice,
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _isBusy ? null : () => _handleUserSubmit(_inputController.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
