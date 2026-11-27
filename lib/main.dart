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
      return 'Respond in simple, clear English suitable for students and learners.';
    }
    if (_langMode == 'auto') {
      return 'Reply in the same language the user asked in (Hindi, English, or any global language), keeping words clear, complete, and easy to follow.';
    }
    return 'सवाल जिस भी भाषा में हो, जवाब आसान और साफ़ बोलचाल की हिंदी में दो ताकि विद्यार्थी एक बार में पूरा समझ जाए।';
  }

  Future<String> _callGemini(String prompt, {File? imageFile, String? mimeType}) async {
    if (_apiKey.isEmpty) {
      throw Exception('कृपया ऊपर गियर आइकन (सेटिंग्स) में अपनी Gemini API Key सेव करें।');
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

    final cleaned = cleanDisplayText(text);
    return cleaned.isEmpty ? 'जवाब तैयार नहीं हो सका, दोबारा पूछें।' : cleaned;
  }

  Future<void> _solveQuestion() async {
    final qText = _questionController.text.trim();
    final hasImg = _pickedImageFile != null;
    if (qText.isEmpty && !hasImg) return;

    final displayQ = qText.isNotEmpty ? qText : 'फ़ोटो में दिख रहा पढ़ाई का सवाल हल करके समझाओ';

    FocusScope.of(context).unfocus();
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
तुम एक अनुभवी कोचिंग सेंटर के शिक्षक हो, जिसके पास विषय की 100 डिग्री गहरी पकड़ है। हर पढ़ाई के सवाल का पहले पूरा और पक्का उत्तर/हल निकालो, पूरा-पूरा नीचे से ऊपर तक स्टेप-बाय-स्टेप समझाओ, और आखिर में शॉर्ट तरीके से भी बताओ।
$langRule
सख्त नियम: यह ऐप केवल पढ़ाई, स्कूल/कॉलेज के विषय, गणित, विज्ञान, भाषा, इतिहास, भूगोल, सामान्य ज्ञान या सीखने-समझाने के सवालों का जवाब देगा।
यदि सवाल पढ़ाई या सीखने से जुड़ा नहीं है (जैसे गपशप, मज़ाक, व्यक्तिगत चैट, या गैर-शैक्षणिक विषय), तो कोई और जवाब मत दो—सिर्फ़ इतना कहो कि यह ऐप केवल पढ़ाई के सवालों के लिए है और पढ़ाई का कोई सवाल पूछने को कहो।
महत्वपूर्ण: जवाब में "घर-बाहर की मिसाल" या घर-परिवार/मसालों/बाहरी चीज़ों की बेमतलब तुलना बिल्कुल मत डालो। सीधे पढ़ाई और विषय की बात करो।
Markdown के निशान (**, ##, ---, >) और LaTeX के \$ निशान बिल्कुल मत लिखो।

हर पढ़ाई के सवाल को इस क्रम में पूरा हल करो और समझाओ:
1. पक्का उत्तर और पूरा हल: (सवाल का अंतिम उत्तर और स्टेप-बाय-स्टेप पूरा हल/विवरण)
2. पूरा समझना (कोचिंग स्टाइल): (नियम, सूत्र या अवधारणा को शुरू से आखिर तक स्पष्ट रूप से समझाओ)
3. शॉर्ट तरीका और निचोड़: (परीक्षा/तेज़ रिवीजन के लिए छोटा तरीका और 1-2 लाइन का पक्का सार)

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
तुम एक अनुभवी कोचिंग सेंटर के शिक्षक हो। इस पढ़ाई के सवाल को पहले से अलग तरीके से समझाओ—पहले पूरा और पक्का हल/समझ दो, फिर आखिर में शॉर्ट तरीका और निचोड़ बताओ।
$langRule
यह ऐप केवल पढ़ाई के सवालों के लिए है। पहले बताए गए तरीकों को मत दोहराओ, और "घर-बाहर की मिसाल" या घर-बाहर की तुलना बिल्कुल मत डालो।
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
                          Text('पूरा हल और समझ तैयार हो रही है...'),
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
                            'और तरीका #${i + 2}',
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
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'सिर्फ़ पढ़ाई के सवाल पूछें',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'नीचे बार में सवाल लिखें, माइक से बोलें या + दबाकर कैमरा/गैलरी से फ़ोटो चुनें।',
                          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
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
                        decoration: const InputDecoration(
                          hintText: 'पढ़ाई का सवाल पूछें...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
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
