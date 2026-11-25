import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
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
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          surface: const Color(0xFFF8F9FA),
        ),
        useMaterial3: true,
      ),
      home: const SolverHomePage(),
    );
  }
}

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

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;

  String _apiKey = '';
  String _langMode = 'hi-IN'; // 'hi-IN', 'en-US', या 'auto'
  int _usedToday = 0;
  bool _isLoading = false;

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

    setState(() {
      _apiKey = savedKey;
      _apiKeyController.text = savedKey;
      _langMode = savedLang;
      _usedToday = count;
      _savedItems = parsed;
    });
    await _applyTtsSettings();
  }

  Future<void> _changeLangMode(String mode) async {
    await _prefs.setString(_keyLang, mode);
    setState(() => _langMode = mode);
    await _applyTtsSettings();
  }

  Future<void> _saveApiKey() async {
    final cleanKey = _apiKeyController.text.trim();
    await _prefs.setString(_keyApi, cleanKey);
    setState(() => _apiKey = cleanKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key सेव हो गई।')),
    );
  }

  String _buildLanguageInstruction(String question) {
    if (_langMode == 'en-US') {
      return 'Respond in simple, clear English suitable for both children and elders worldwide.';
    }
    if (_langMode == 'auto') {
      return 'Reply in the same language the user asked in (Hindi, English, or any global language), keeping words simple and clear for all ages.';
    }
    return 'सवाल जिस भी भाषा में हो, जवाब आसान बोलचाल की हिंदी में दो ताकि बच्चा हो या बूढ़ा, हर कोई एक बार में समझ जाए।';
  }

  Future<String> _callGemini(String prompt) async {
    if (_apiKey.isEmpty) {
      throw Exception('कृपया पहले अपनी Gemini API Key सेव करें।');
    }

    const model = 'gemini-3.5-flash-lite';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
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

    final cleaned = cleanDisplayText(text);
    return cleaned.isEmpty ? 'जवाब तैयार नहीं हो सका, दोबारा पूछें।' : cleaned;
  }

  Future<void> _solveQuestion() async {
    final q = _questionController.text.trim();
    if (q.isEmpty) return;

    await _tts.stop();
    setState(() => _isSpeaking = false);

    if (_usedToday >= dailyFreeLimit && _apiKey.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('आज के 5 फ़्री सवाल पूरे'),
          content: const Text(
            'दिन के 5 फ़्री सवाल पूरे हो गए हैं। आगे बढ़ने के लिए अपनी Gemini API Key डालें या अनलॉक विकल्प चुनें।',
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

    setState(() {
      _isLoading = true;
      _currentQuestion = q;
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });

    final langRule = _buildLanguageInstruction(q);
    final prompt = '''
तुम एक ऐसे शिक्षक हो जो बच्चा हो या बूढ़ा, भारत या विदेश—हर किसी को एक ही बार में आसान शब्दों में समझा देते हो।
$langRule
जवाब बहुत कम शब्दों में दो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।
जवाब सिर्फ इन 3 छोटे हिस्सों में दो:

1. एक लाइन में मतलब: (10-15 शब्दों में सीधा सार)
2. घर-बाहर की मिसाल: (रोज़मर्रा की एक आसान और सटीक मिसाल)
3. दिमाग में बिठाने की बात: (एक छोटी लाइन या ट्रिक जिसे भूलना मुश्किल हो)

सवाल: $q
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

    final langRule = _buildLanguageInstruction(_currentQuestion!);
    final prompt = '''
बच्चा या बुजुर्ग इसे अभी भी पूरी तरह नहीं समझ पाया है।
$langRule
बिल्कुल कम शब्दों में, एक नई रोज़मर्रा की मिसाल और एक छोटी याद रखने वाली लाइन दो।
Markdown के निशान (**, ##, ---, >) और \$ के निशान बिल्कुल मत लिखो।

सवाल: $_currentQuestion
पिछला जवाब: $_currentAnswer
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
    setState(() {
      _isSpeaking = false;
      _understood = true;
    });
    await _persistCurrentItem(understood: true);
    _questionController.clear();
    setState(() {
      _currentQuestion = null;
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('बढ़िया, सवाल सेव हो गया। अब अगला सवाल पूछो।')),
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
                  '${item.date} • ${item.understood ? "समझ आ गया" : "अभ्यास जारी"}',
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
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
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingFree = (dailyFreeLimit - _usedToday).clamp(0, dailyFreeLimit);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FA),
        title: const Text('SamajhAaya'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _langMode,
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
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'सेव किए हुए सवाल',
            onPressed: _openSavedSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'फ़्री सवाल बाकी: $remainingFree / $dailyFreeLimit',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'अपनी Gemini API Key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saveApiKey,
                      child: const Text('Key सेव करें'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _questionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'सवाल लिखें या बोलें...',
                filled: true,
                fillColor: Colors.white,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                  tooltip: _isListening ? 'रोकें' : 'बोलकर पूछें',
                  onPressed: _toggleListen,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _isLoading ? null : _solveQuestion,
              child: Text(_isLoading ? 'समझा रहा हूँ...' : 'समझाओ'),
            ),
            if (_currentAnswer != null) ...[
              const SizedBox(height: 18),
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cleanDisplayText(_currentQuestion ?? ''),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isSpeaking ? Icons.stop_circle : Icons.volume_up,
                            ),
                            tooltip: _isSpeaking ? 'आवाज़ रोकें' : 'सुनें',
                            onPressed: _toggleSpeak,
                          ),
                        ],
                      ),
                      const Divider(),
                      Text(
                        cleanDisplayText(_currentAnswer!),
                        style: const TextStyle(fontSize: 15, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      ConceptVisualBox(question: _currentQuestion ?? ''),
                      for (int i = 0; i < _extraMethods.length; i++) ...[
                        const Divider(),
                        Text(
                          'और आसान तरीका #${i + 2}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cleanDisplayText(_extraMethods[i]),
                          style: const TextStyle(fontSize: 15, height: 1.45),
                        ),
                      ],
                      const Divider(),
                      const Text(
                        'समझ आया क्या?',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _isLoading ? null : _markUnderstoodAndNext,
                              child: const Text('हाँ, समझ आ गया'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _addAnotherMethod,
                              child: const Text('नहीं, और बताओ'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ConceptVisualBox extends StatelessWidget {
  final String question;

  const ConceptVisualBox({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    final q = question.toLowerCase();
    final isDelta = q.contains('delta') || q.contains('डेल्टा');
    final isSquare = q.contains('square') ||
        q.contains('स्क्वायर') ||
        q.contains('वर्ग') ||
        q.contains('^2') ||
        q.contains('a + b');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDelta
                ? 'चित्र: नदी की धारा और तिकोना डेल्टा'
                : isSquare
                    ? 'चित्र: वर्ग और हिस्सों की बनावट'
                    : 'चित्र: एक नज़र में समझने का रास्ता',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _ConceptDiagramPainter(
                isDelta: isDelta,
                isSquare: isSquare,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptDiagramPainter extends CustomPainter {
  final bool isDelta;
  final bool isSquare;

  _ConceptDiagramPainter({
    required this.isDelta,
    required this.isSquare,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final riverPaint = Paint()
      ..color = const Color(0xFF1A73E8)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final deltaFill = Paint()
      ..color = const Color(0xFFD97706).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (isDelta) {
      canvas.drawLine(
        Offset(16, size.height * 0.5),
        Offset(size.width * 0.48, size.height * 0.5),
        riverPaint,
      );
      final tri = Path()
        ..moveTo(size.width * 0.48, size.height * 0.5)
        ..lineTo(size.width * 0.88, size.height * 0.16)
        ..lineTo(size.width * 0.88, size.height * 0.84)
        ..close();
      canvas.drawPath(tri, deltaFill);
      canvas.drawPath(tri, borderPaint);

      canvas.drawLine(
        Offset(size.width * 0.48, size.height * 0.5),
        Offset(size.width * 0.88, size.height * 0.25),
        riverPaint..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(size.width * 0.48, size.height * 0.5),
        Offset(size.width * 0.88, size.height * 0.75),
        riverPaint..strokeWidth = 2,
      );
    } else if (isSquare) {
      final box = Rect.fromLTWH(
        size.width * 0.25,
        12,
        size.width * 0.5,
        size.height - 24,
      );
      canvas.drawRect(box, deltaFill);
      canvas.drawRect(box, borderPaint);
      canvas.drawLine(
        Offset(box.center.dx, box.top),
        Offset(box.center.dx, box.bottom),
        borderPaint..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(box.left, box.center.dy),
        Offset(box.right, box.center.dy),
        borderPaint..strokeWidth = 1.5,
      );
    } else {
      final r1 = Rect.fromLTWH(12, 24, size.width * 0.26, 56);
      final r2 = Rect.fromLTWH(size.width * 0.37, 24, size.width * 0.26, 56);
      final r3 = Rect.fromLTWH(size.width * 0.72, 24, size.width * 0.22, 56);

      canvas.drawRRect(RRect.fromRectAndRadius(r1, const Radius.circular(8)), deltaFill);
      canvas.drawRRect(RRect.fromRectAndRadius(r1, const Radius.circular(8)), borderPaint);

      canvas.drawRRect(RRect.fromRectAndRadius(r2, const Radius.circular(8)), deltaFill);
      canvas.drawRRect(RRect.fromRectAndRadius(r2, const Radius.circular(8)), borderPaint);

      canvas.drawRRect(RRect.fromRectAndRadius(r3, const Radius.circular(8)), deltaFill);
      canvas.drawRRect(RRect.fromRectAndRadius(r3, const Radius.circular(8)), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConceptDiagramPainter oldDelegate) {
    return oldDelegate.isDelta != isDelta || oldDelegate.isSquare != isSquare;
  }
}
