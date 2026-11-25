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
  static const String _keyCoins = 'user_unlock_coins';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  bool _isListening = false;
  bool _isSpeaking = false;

  String _apiKey = '';
  String _langMode = 'hi-IN';
  int _usedToday = 0;
  int _coins = 0;
  bool _isLoading = false;

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
    final savedCoins = await _prefs.getInt(_keyCoins) ?? 0;
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
      _coins = savedCoins;
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
      return 'Respond in simple, clear English suitable for both children and elders worldwide.';
    }
    if (_langMode == 'auto') {
      return 'Reply in the same language the user asked in (Hindi, English, or any global language), keeping words simple and clear for all ages.';
    }
    return 'सवाल जिस भी भाषा में हो, जवाब आसान बोलचाल की हिंदी में दो ताकि बच्चा हो या बूढ़ा, हर कोई एक बार में समझ जाए।';
  }

  Future<String> _callGemini(String prompt, {File? imageFile, String? mimeType}) async {
    if (_apiKey.isEmpty) {
      throw Exception('कृपया ऊपर गियर आइकन (सेटिंग्स) में अपनी Gemini API Key सेव करें।');
    }

    const model = 'gemini-3.5-flash-lite';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

        final partsList = [
      {'text': prompt},
    ];

    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      partsList.add({
        'inline_data': {
          'mime_type': mimeType ?? 'image/jpeg',
          'data': base64Encode(bytes),
        }
      });
    }


    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': partsList,
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
    final qText = _questionController.text.trim();
    final hasImg = _pickedImageFile != null;
    if (qText.isEmpty && !hasImg) return;

    final displayQ = qText.isNotEmpty ? qText : 'फ़ोटो में दिख रहा सवाल / चीज़ समझाओ';

    await _tts.stop();
    setState(() => _isSpeaking = false);

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
      _currentQuestion = displayQ;
      _currentAnswer = null;
      _extraMethods.clear();
      _understood = null;
    });

    final langRule = _buildLanguageInstruction();
    final prompt = '''
तुम एक बहुत ही सरल, देसी और ज़मीन से जुड़े शिक्षक हो। बच्चा हो या बूढ़ा, भारत या विदेश—हर कोई एक ही बार में समझ जाए।
$langRule
बिल्कुल सीधा, छोटा और आसान जवाब दो। भारी किताबी शब्द कम रखो। यदि फ़ोटो दी गई है तो फ़ोटो देखकर उसका मुख्य अर्थ/सवाल भी समझो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।
सिर्फ़ इन 3 हिस्सों में छोटा जवाब दो:

1. एक लाइन में मतलब: (एकदम सीधा और छोटा सार)
2. घर-बाहर की मिसाल: (रोज़मर्रा की एक आसान और जानी-पहचानी मिसाल)
3. दिमाग में बिठाने की बात: (सिर्फ़ एक छोटी और पक्की याद रखने वाली लाइन)

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
बच्चा या बुजुर्ग इसे अभी भी पूरी तरह नहीं समझ पाया है।
$langRule
पहले बताए गए तरीकों को बिल्कुल मत दोहराओ। एक एकदम नई रोज़मर्रा की मिसाल और एक छोटी याद रखने वाली लाइन दो।
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

  void _openSettingsSheet() {
    final remainingFree = (dailyFreeLimit - _usedToday).clamp(0, dailyFreeLimit);
    _apiKeyController.text = _apiKey;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'सेटिंग्स',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'फ़्री सवाल बाकी: $remainingFree / $dailyFreeLimit • कॉइन्स: $_coins • 0.30x धीमी आवाज़',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
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
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Key सेव करें'),
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
    return Scaffold(
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _questionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'सवाल लिखें, बोलें या फ़ोटो खींचें / चुनें...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  if (_pickedImageFile != null) ...[
                    const SizedBox(height: 10),
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _pickedImageFile!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
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
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('कैमरा'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('गैलरी'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _isLoading ? null : _toggleListen,
                        icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                        tooltip: _isListening ? 'रोकें' : 'बोलकर पूछें',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _isLoading ? null : _solveQuestion,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _isLoading ? 'समझा रहा हूँ...' : 'समझाओ',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (_currentAnswer != null) ...[
              const SizedBox(height: 18),
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
                    const SizedBox(height: 14),
                    ConceptVisualBox(question: _currentQuestion ?? ''),
                    for (int i = 0; i < _extraMethods.length; i++) ...[
                      const Divider(height: 20),
                      Text(
                        'और आसान तरीका #${i + 2}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cleanDisplayText(_extraMethods[i]),
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ],
                    const Divider(height: 20),
                    const Text(
                      'समझ आया क्या?',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
                            child: const Text('हाँ, समझ आ गया'),
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

  String _detectTopic(String raw) {
    final q = raw.toLowerCase();
    if (q.contains('delta') || q.contains('डेल्टा')) return 'delta';
    if (q.contains('square') ||
        q.contains('स्क्वायर') ||
        q.contains('वर्ग') ||
        q.contains('^2') ||
        q.contains('a + b')) {
      return 'square';
    }
    if (q.contains('energy') ||
        q.contains('mc2') ||
        q.contains('mc^2') ||
        q.contains('e=mc') ||
        q.contains('ऊर्जा') ||
        q.contains('बिजली') ||
        q.contains('आग') ||
        q.contains('गर्मी') ||
        q.contains('heat') ||
        q.contains('light') ||
        q.contains('प्रकाश')) {
      return 'energy';
    }
    if (q.contains('water') ||
        q.contains('पानी') ||
        q.contains('नदी') ||
        q.contains('बारिश') ||
        q.contains('rain') ||
        q.contains('wave') ||
        q.contains('लहर')) {
      return 'water';
    }
    if (q.contains('speed') ||
        q.contains('train') ||
        q.contains('ट्रेन') ||
        q.contains('गति') ||
        q.contains('चाल') ||
        q.contains('दूरी') ||
        q.contains('motion') ||
        q.contains('force') ||
        q.contains('बल')) {
      return 'motion';
    }
    if (q.contains('plant') ||
        q.contains('tree') ||
        q.contains('पौधा') ||
        q.contains('पेड़') ||
        q.contains('sun') ||
        q.contains('सूरज') ||
        q.contains('photosynthesis')) {
      return 'nature';
    }
    if (q.contains('cycle') ||
        q.contains('चक्र') ||
        q.contains('process') ||
        q.contains('प्रक्रिया')) {
      return 'cycle';
    }
    return 'concept';
  }

  Map<String, String> _topicInfo(String topic, String question) {
    switch (topic) {
      case 'delta':
        return {
          'title': 'चित्र: डेल्टा कैसे बनता है',
          'left': 'नदी का बहाव',
          'mid': 'मिट्टी जमा',
          'right': 'तिकोना डेल्टा',
          'note': 'नदी रुकती है, मिट्टी जमती है और धारा बँट जाती है।',
        };
      case 'square':
        return {
          'title': 'चित्र: वर्ग और हिस्सों का जोड़',
          'left': 'अलग वर्ग',
          'mid': 'जोड़ी का गुणन',
          'right': 'पूरा हिस्सा',
          'note': 'हर टुकड़े का क्षेत्रफल जोड़कर पूरा हिस्सा बनता है।',
        };
      case 'energy':
        return {
          'title': 'चित्र: वजन (m) से ऊर्जा (E)',
          'left': 'थोड़ा वजन (m)',
          'mid': 'तेज़ रफ़्तार (c²)',
          'right': 'बड़ी ऊर्जा (E)',
          'note': 'छोटे से हिस्से में भी बड़ी ताकत छिपी हो सकती है।',
        };
      case 'water':
        return {
          'title': 'चित्र: पानी और लहर का असर',
          'left': 'शुरुआत',
          'mid': 'लहर / बहाव',
          'right': 'बदलाव',
          'note': 'पानी की चाल और रुकावट से उसका रूप बदलता है।',
        };
      case 'motion':
        return {
          'title': 'चित्र: चाल, दिशा और दूरी',
          'left': 'शुरुआती जगह',
          'mid': 'रफ़्तार / बल',
          'right': 'तय दूरी',
          'note': 'रफ़्तार जितनी तेज़ होगी, असर और दूरी उतनी ज़्यादा होगी।',
        };
      case 'nature':
        return {
          'title': 'चित्र: सूरज और पौधे का विकास',
          'left': 'सूरज / हवा',
          'mid': 'पौधा / पत्तियाँ',
          'right': 'बढ़त / जीवन',
          'note': 'रोशनी और सही चीज़ें मिलकर चीज़ों को बढ़ाती हैं।',
        };
      case 'cycle':
        return {
          'title': 'चित्र: घूमता हुआ चक्र',
          'left': 'पहला चरण',
          'mid': 'बीच का बदलाव',
          'right': 'वापसी / नया रूप',
          'note': 'यह क्रम घूमता रहता है और आगे बढ़ता है।',
        };
      default:
        final cleanQ = question.trim();
        final shortQ = cleanQ.length > 24 ? '${cleanQ.substring(0, 24)}...' : cleanQ;
        return {
          'title': 'चित्र: "$shortQ" का आसान सार',
          'left': 'मुख्य बात',
          'mid': 'कैसे होता है',
          'right': 'नतीजा',
          'note': '$shortQ को समझने के लिए कारण और नतीजे को जोड़कर देखें।',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final topic = _detectTopic(question);
    final info = _topicInfo(topic, question);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info['title']!,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 95,
            width: double.infinity,
            child: CustomPaint(
              painter: _ConceptDiagramPainter(
                topic: topic,
                seed: question.codeUnits.fold<int>(0, (a, b) => a + b),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  info['left']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Text(
                  info['mid']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Text(
                  info['right']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'आसान समझ: ${info['note']!}',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptDiagramPainter extends CustomPainter {
  final String topic;
  final int seed;

  _ConceptDiagramPainter({
    required this.topic,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final blueStroke = Paint()
      ..color = const Color(0xFF1A73E8)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final amberFill = Paint()
      ..color = const Color(0xFFD97706).withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    final greenFill = Paint()
      ..color = const Color(0xFF16A34A).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final darkStroke = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (topic == 'delta') {
      canvas.drawLine(
        Offset(16, size.height * 0.5),
        Offset(size.width * 0.48, size.height * 0.5),
        blueStroke,
      );
      final tri = Path()
        ..moveTo(size.width * 0.48, size.height * 0.5)
        ..lineTo(size.width * 0.88, size.height * 0.14)
        ..lineTo(size.width * 0.88, size.height * 0.86)
        ..close();
      canvas.drawPath(tri, amberFill);
      canvas.drawPath(tri, darkStroke);

      canvas.drawLine(
        Offset(size.width * 0.48, size.height * 0.5),
        Offset(size.width * 0.88, size.height * 0.25),
        blueStroke..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(size.width * 0.48, size.height * 0.5),
        Offset(size.width * 0.88, size.height * 0.75),
        blueStroke..strokeWidth = 2,
      );
    } else if (topic == 'square') {
      final box = Rect.fromLTWH(
        size.width * 0.28,
        10,
        size.width * 0.44,
        size.height - 20,
      );
      canvas.drawRect(box, amberFill);
      canvas.drawRect(box, darkStroke);
      canvas.drawLine(
        Offset(box.center.dx, box.top),
        Offset(box.center.dx, box.bottom),
        darkStroke..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(box.left, box.center.dy),
        Offset(box.right, box.center.dy),
        darkStroke..strokeWidth = 1.5,
      );
    } else if (topic == 'energy') {
      final massCircle = Offset(size.width * 0.22, size.height * 0.55);
      canvas.drawCircle(massCircle, 18, amberFill);
      canvas.drawCircle(massCircle, 18, darkStroke);

      final burst = Path()
        ..moveTo(size.width * 0.54, size.height * 0.16)
        ..lineTo(size.width * 0.68, size.height * 0.44)
        ..lineTo(size.width * 0.58, size.height * 0.46)
        ..lineTo(size.width * 0.78, size.height * 0.84)
        ..lineTo(size.width * 0.48, size.height * 0.55)
        ..lineTo(size.width * 0.58, size.height * 0.53)
        ..close();
      canvas.drawPath(
        burst,
        Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(burst, darkStroke);
      canvas.drawLine(
        Offset(size.width * 0.22 + 22, size.height * 0.55),
        Offset(size.width * 0.50, size.height * 0.52),
        blueStroke,
      );
    } else if (topic == 'water') {
      for (int row = 0; row < 3; row++) {
        final yBase = 22.0 + row * 24.0;
        final wave = Path()..moveTo(14, yBase);
        for (double x = 14; x < size.width - 14; x += 24) {
          wave.quadraticBezierTo(x + 6, yBase - 9, x + 12, yBase);
          wave.quadraticBezierTo(x + 18, yBase + 9, x + 24, yBase);
        }
        canvas.drawPath(wave, blueStroke..strokeWidth = row == 1 ? 3.2 : 2.0);
      }
    } else if (topic == 'motion') {
      final yLine = size.height * 0.68;
      canvas.drawLine(Offset(16, yLine), Offset(size.width - 18, yLine), darkStroke);
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.35, yLine - 32, 62, 22),
        const Radius.circular(6),
      );
      canvas.drawRRect(body, amberFill);
      canvas.drawRRect(body, darkStroke);
      canvas.drawCircle(Offset(size.width * 0.35 + 14, yLine - 6), 5.5, darkStroke);
      canvas.drawCircle(Offset(size.width * 0.35 + 48, yLine - 6), 5.5, darkStroke);
      canvas.drawLine(
        Offset(size.width * 0.35 + 70, yLine - 20),
        Offset(size.width - 20, yLine - 20),
        blueStroke,
      );
    } else if (topic == 'nature') {
      final sunCenter = Offset(size.width * 0.22, size.height * 0.32);
      canvas.drawCircle(
        sunCenter,
        15,
        Paint()
          ..color = const Color(0xFFFACC15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(sunCenter, 15, darkStroke);

      final stemBase = Offset(size.width * 0.65, size.height - 10);
      final stemTop = Offset(size.width * 0.65, 20);
      canvas.drawLine(
        stemBase,
        stemTop,
        Paint()
          ..color = const Color(0xFF15803D)
          ..strokeWidth = 4,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(size.width * 0.65 - 15, 42), width: 24, height: 13),
        greenFill,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(size.width * 0.65 + 15, 32), width: 24, height: 13),
        greenFill,
      );
    } else if (topic == 'cycle') {
      final rect = Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.5),
        width: 64,
        height: 64,
      );
      canvas.drawArc(rect, 0.2, 5.5, false, blueStroke);
    } else {
      final leftNode = Offset(size.width * 0.20, size.height * 0.55);
      final midNode = Offset(size.width * 0.50, size.height * 0.28 + (seed % 6));
      final rightNode = Offset(size.width * 0.80, size.height * 0.55);

      canvas.drawLine(leftNode, midNode, darkStroke);
      canvas.drawLine(midNode, rightNode, darkStroke);
      canvas.drawLine(leftNode, rightNode, blueStroke);

      canvas.drawCircle(leftNode, 16, amberFill);
      canvas.drawCircle(leftNode, 16, darkStroke);
      canvas.drawCircle(midNode, 13, Paint()..color = const Color(0xFFDBEAFE)..style = PaintingStyle.fill);
      canvas.drawCircle(midNode, 13, darkStroke);
      canvas.drawCircle(rightNode, 16, greenFill);
      canvas.drawCircle(rightNode, 16, darkStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ConceptDiagramPainter oldDelegate) {
    return oldDelegate.topic != topic || oldDelegate.seed != seed;
  }
}
