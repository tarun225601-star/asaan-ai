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

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;

  String _apiKey = '';
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
    // Android पर Google TTS इंजन को प्राथमिकता देने का प्रयास (उपलब्ध होने पर)
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

    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.95);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
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
      setState(() => _isSpeaking = true);
      await _tts.speak(fullText);
    }
  }

  String _buildSpokenText() {
    if (_currentAnswer == null) return '';
    final buffer = StringBuffer(_currentAnswer!);
    for (int i = 0; i < _extraMethods.length; i++) {
      buffer.write('\n\nअतिरिक्त तरीका ${i + 5}: ${_extraMethods[i]}');
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
        .map((e) => SolvedItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();

    setState(() {
      _apiKey = savedKey;
      _apiKeyController.text = savedKey;
      _usedToday = count;
      _savedItems = parsed;
    });
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

    return text.isEmpty ? 'खाली जवाब आया।' : text;
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
            'दिन के 5 फ़्री सवाल पूरे हो गए हैं। आगे बढ़ने के लिए अपनी Gemini API Key डालें या पेड/अनलॉक विकल्प चुनें।',
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

    final prompt = '''
तुम एक अनुभवी पढ़ाई टीचर हो जो हर विषय (गणित, विज्ञान, इतिहास, भूगोल, भाषा, या कोई भी एकेडमिक पढ़ाई) को आसान भाषा में समझाता है।
छात्र ने जिस भाषा (Hindi, English, या Hinglish) में पूछा है, उसी भाषा में जवाब दो।
किसी भी विषय का सवाल हो, जवाब को ठीक 4 साफ़ हिस्सों में बाँटो:
1. सीधा और छोटा जवाब
2. स्टेप-बाय-स्टेप समझ
3. रोज़मर्रा / देसी उदाहरण
4. शॉर्ट तरीका / जल्दी याद रखने की ट्रिक

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

    final nextNum = _extraMethods.length + 5;
    final prompt = '''
छात्र को यह पढ़ाई का टॉपिक/सवाल अभी पूरी तरह समझ नहीं आया है। उसी भाषा में एक बिल्कुल नया, और आसान तरीका (तरीका #$nextNum) और साथ में एक छोटा "शॉर्ट तरीका" (Quick Short Way) दो—जैसे नई तुलना, आसान कहानी/उदाहरण, या बिना रटे याद रखने का छोटा तरीका।

सवाल: $_currentQuestion
पिछला समझाया गया हिस्सा: $_currentAnswer
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
      const SnackBar(content: Text('बढ़िया, सवाल सेव हो गया। अब अगला सवाल डालो।')),
    );
  }

  Future<void> _persistCurrentItem({required bool understood}) async {
    if (_currentQuestion == null || _currentAnswer == null) return;
    final item = SolvedItem(
      question: _currentQuestion!,
      answerText: _currentAnswer!,
      extraMethods: List<String>.from(_extraMethods),
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
                title: Text(item.question),
                subtitle: Text(
                  '${item.date} • ${item.understood ? "समझ आ गया" : "अभ्यास जारी"}',
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _currentQuestion = item.question;
                    _currentAnswer = item.answerText;
                    _extraMethods
                      ..clear()
                      ..addAll(item.extraMethods);
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
                              _currentQuestion ?? '',
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
                      Text(_currentAnswer!),
                      for (int i = 0; i < _extraMethods.length; i++) ...[
                        const Divider(),
                        Text(
                          'तरीका #${i + 5}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(_extraMethods[i]),
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
