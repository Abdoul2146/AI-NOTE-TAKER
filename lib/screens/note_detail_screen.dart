import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart'; // Keep this for PdfColor, even if PdfGoogleFonts isn't used
import 'package:docx_template/docx_template.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:translator/translator.dart'; // No longer needed
import 'package:http/http.dart' as http;
// import 'package:dio/dio.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:txt_docx/txt_docx.dart'; // Add this import

const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final bool isFromRecording;

  const NoteDetailScreen({
    super.key,
    required this.note,
    this.isFromRecording = false,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  final FlutterTts flutterTts = FlutterTts();
  // final translator = GoogleTranslator(); // No longer needed

  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _translationController = TextEditingController();

  bool _isSummarizing = false;
  bool _isTranslating = false;
  bool _isSavingSummary = false;
  bool _isSavingTranslation = false;

  String _targetLang = 'ha'; // Hausa default
  final Map<String, String> _langs = const {'Hausa': 'ha', 'Yoruba': 'yo'};

  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _translationController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    // Wait for engine binding on Android
    await flutterTts.awaitSpeakCompletion(true);
    await flutterTts.setSpeechRate(0.5);
    // Touch engines/languages to force bind
    try {
      await flutterTts.getEngines;
      await flutterTts.getLanguages;
    } catch (_) {}
    _ttsReady = true;
  }

  Future<String> _resolveLang(String? lang) async {
    final desired = switch (lang ?? 'en') {
      'ha' => 'ha-NG',
      'yo' => 'yo-NG',
      'fr' => 'fr-FR',
      _ => 'en-US',
    };
    try {
      final ok = await flutterTts.isLanguageAvailable(desired);
      if (ok == true) return desired;
    } catch (_) {}
    // Fallbacks (most devices have these)
    return (lang == 'fr') ? 'fr-FR' : 'en-US';
  }

  Future<void> _speak(String text, {String? lang}) async {
    if (text.trim().isEmpty) return;
    if (!_ttsReady) await _initTts();
    final code = await _resolveLang(lang);
    try {
      await flutterTts.setLanguage(code);
    } catch (_) {
      await flutterTts.setLanguage('en-US');
    }
    await flutterTts.setPitch(1.0);
    await flutterTts.speak(text);
  }

  void _playNote() => _speak(widget.note.content, lang: 'en');
  // void _playSummary() { if (_summaryController.text.isNotEmpty) _speak(_summaryController.text, lang: 'en'); }
  // void _playTranslation() { if (_translationController.text.isNotEmpty) _speak(_translationController.text, lang: _targetLang); }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: secondaryColor,
            title: const Text(
              'Export as',
              style: TextStyle(color: accentColor),
            ),
            content: const Text(
              'Choose a format to export your note:',
              style: TextStyle(color: accentColor),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _exportAsPDFToFiles(context);
                },
                child: const Text('PDF', style: TextStyle(color: accentColor)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _exportAsDocxToFiles(context);
                },
                child: const Text('DOCX', style: TextStyle(color: accentColor)),
              ),
            ],
          ),
    );
  }

  Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      // Request storage permission
      if (await Permission.manageExternalStorage.isGranted == false) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied')),
            );
          }
          throw Exception('Storage permission denied');
        }
      }
      final dir = Directory('/storage/emulated/0/Document/AI Note Taker');
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }
      return dir;
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  // Helper to parse simple markdown to pw.TextSpan for rich text
  List<pw.TextSpan> _parseInlinePdfMarkdown(
    String text,
    pw.TextStyle defaultStyle,
    pw.TextStyle boldStyle,
  ) {
    final List<pw.TextSpan> spans = [];
    final RegExp boldRegex = RegExp(r'\*\*(.*?)\*\*');
    final List<RegExpMatch> matches = boldRegex.allMatches(text).toList();

    int currentPosition = 0;

    for (final match in matches) {
      // Add text before the bold part
      if (match.start > currentPosition) {
        spans.add(
          pw.TextSpan(
            text: text.substring(currentPosition, match.start),
            style: defaultStyle,
          ),
        );
      }
      // Add the bold part
      spans.add(pw.TextSpan(text: match.group(1), style: boldStyle));
      currentPosition = match.end;
    }

    // Add any remaining text
    if (currentPosition < text.length) {
      spans.add(
        pw.TextSpan(text: text.substring(currentPosition), style: defaultStyle),
      );
    }
    return spans;
  }

  // Helper to convert markdown string to pw.Widget list for PDF
  List<pw.Widget> _buildPdfContent(String markdownContent, pw.Font font) {
    final List<pw.Widget> widgets = [];
    final lines = markdownContent.split('\n');

    final pw.TextStyle defaultTextStyle = pw.TextStyle(
      fontSize: 14,
      font: font,
    );
    final pw.TextStyle boldTextStyle = pw.TextStyle(
      fontSize: 14,
      font: font,
      fontWeight: pw.FontWeight.bold,
      color: PdfColor.fromInt(highlightColor.value),
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
      } else if (RegExp(r'^(\s*)([-*]|\d+\.)\s+').hasMatch(line)) {
        // Bullet or numbered list detection
        final match = RegExp(r'^(\s*)([-*]|\d+\.)\s+(.*)').firstMatch(line);
        final indent = match?.group(1)?.length ?? 0;
        final bullet = match?.group(2) ?? '•';
        final content = match?.group(3) ?? trimmed;
        widgets.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(left: 16.0 * (indent ~/ 2)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  bullet == '-' || bullet == '*' ? '• ' : '$bullet ',
                  style: defaultTextStyle,
                ),
                pw.Expanded(
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: _parseInlinePdfMarkdown(
                        content,
                        defaultTextStyle,
                        boldTextStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 4));
      } else if (trimmed.startsWith('# ')) {
        final titleContent = trimmed.substring(2).trim();
        widgets.add(
          pw.Text(
            titleContent,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              font: font,
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 12));
      } else {
        widgets.add(
          pw.RichText(
            text: pw.TextSpan(
              children: _parseInlinePdfMarkdown(
                line,
                defaultTextStyle,
                boldTextStyle,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _savePdfFile(pw.Document pdf, String filename) async {
    try {
      final dir = await _getSaveDirectory();
      final filePath = '${dir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as PDF to $filePath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save PDF: $e')));
      }
    }
  }

  Future<void> _saveDocxFile(List<int> bytes, String filename) async {
    try {
      final dir = await _getSaveDirectory();
      final filePath = '${dir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as DOCX to $filePath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save DOCX: $e')));
      }
    }
  }

  Future<void> _exportAsPDFToFiles(BuildContext context) async {
    final pdf = pw.Document();
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    ); // Using a built-in font

    pdf.addPage(
      pw.Page(
        build:
            (pw.Context context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  widget.note.title,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    font: font,
                  ),
                ),
                pw.SizedBox(height: 16),
                // Directly use the note content which may have markdown
                ..._buildPdfContent(widget.note.content, font),
              ],
            ),
      ),
    );
    await _savePdfFile(pdf, '${widget.note.title}.pdf');
  }

  Future<void> _exportAsDocxToFiles(BuildContext context) async {
    try {
      final ByteData bytes = await DefaultAssetBundle.of(
        context,
      ).load('assets/template.docx');
      final DocxTemplate docx = await DocxTemplate.fromBytes(
        bytes.buffer.asUint8List(),
      );

      // Ensure your template.docx has placeholders like {{title}} and {{content}}
      Content c = Content();
      c.add(TextContent("title", widget.note.title));
      c.add(TextContent("content", widget.note.content));

      final List<int>? d = await docx.generate(c);
      if (d != null) {
        await _saveDocxFile(d, '${widget.note.title}.docx');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to generate DOCX. Check template placeholders.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export DOCX: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _fetchGeminiResponse(String prompt, String userInput) async {
    const modelName =
        'gemini-1.5-flash'; // Use the correct model name for Gemini 1.5 Flash
    const apiKey = ''; // Replace with your actual API key

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
    );

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": '$prompt\n$userInput'},
            ],
          },
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // The structure for the response is likely the same, but it's good to be aware of potential changes.
      return data['candidates'][0]['content']['parts'][0]['text'];
    } else {
      throw Exception(
        'Failed to get response from Gemini API: ${response.statusCode}',
      );
    }
  }

  Future<void> _summarize() async {
    final text = widget.note.content.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to summarize')));
      return;
    }
    setState(() => _isSummarizing = true);
    try {
      final summary = await _fetchGeminiResponse('''
      Structure the following transcription as a clear, organized note to be studied for test/exam.
      - Start with a title if possible.
      - Use sections and bullet points for key ideas.
      - Highlight important details, actions, or decisions.
      - Make it easy to read and reference later.
      Transcription:
      ''', text);
      setState(() => _summaryController.text = summary.trim());
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Summarize failed: $e')));
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  // Helper function to translate text while preserving inline markdown using Gemini
  Future<String> _translateWithGemini(String text, String targetLang) async {
    if (text.trim().isEmpty) return '';

    // Map language codes to full names for Gemini
    final langMap = {
      'ha': 'Hausa',
      'yo': 'Yoruba',
      'fr': 'French',
      'en': 'English',
    };
    final langName = langMap[targetLang] ?? targetLang;

    final prompt = '''
      Translate the following text into $langName language.
      Maintain all Markdown formatting (e.g., **bold**, *italic*, `code`, - list item, # heading, etc.) exactly as it is, only translating the actual words.
      Do not add any additional explanations or text, just the translated content.

      Text to translate:
      $text
    ''';

    try {
      final translatedText = await _fetchGeminiResponse(prompt, '');
      return translatedText.trim();
    } catch (e) {
      throw Exception('Gemini translation failed: $e');
    }
  }

  Future<void> _translate() async {
    final summaryMarkdown = _summaryController.text.trim();
    if (summaryMarkdown.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to translate')));
      return;
    }
    setState(() => _isTranslating = true);
    try {
      final translatedFullText = await _translateWithGemini(
        summaryMarkdown,
        _targetLang,
      );
      setState(() => _translationController.text = translatedFullText);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Translate failed: $e')));
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _saveSummaryDocx() async {
    final summaryMarkdown = _summaryController.text.trim();
    if (summaryMarkdown.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No summary to save')));
      return;
    }
    setState(() => _isSavingSummary = true);
    try {
      final dir = await _getSaveDirectory();
      final filePath = '${dir.path}/${widget.note.title}_Summary.docx';
      await Stream.value(
        summaryMarkdown,
      ).transform(DocxEncoder()).pipe(File(filePath).openWrite());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as DOCX to $filePath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save summary DOCX: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSummary = false);
    }
  }

  Future<void> _saveTranslationDocx() async {
    final translationMarkdown = _translationController.text.trim();
    if (translationMarkdown.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No translation to save')));
      return;
    }
    setState(() => _isSavingTranslation = true);
    try {
      final dir = await _getSaveDirectory();
      final filePath = '${dir.path}/${widget.note.title}_Translation.docx';
      await Stream.value(
        translationMarkdown,
      ).transform(DocxEncoder()).pipe(File(filePath).openWrite());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as DOCX to $filePath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save translation DOCX: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingTranslation = false);
    }
  }

  Future<void> _saveSummary() async {
    final summary = _summaryController.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No summary to save')));
      return;
    }
    final pdf = pw.Document();
    final font = pw.Font.helvetica(); // Using a built-in font

    pdf.addPage(
      pw.Page(
        build:
            (pw.Context context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${widget.note.title} - Summary',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    font: font,
                  ),
                ),
                pw.SizedBox(height: 16),
                ..._buildPdfContent(summary, font),
              ],
            ),
      ),
    );
    await _savePdfFile(pdf, '${widget.note.title}_Summary.pdf');
  }

  Future<void> _saveTranslation() async {
    final translation = _translationController.text.trim();
    if (translation.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No translation to save')));
      return;
    }
    final pdf = pw.Document();
    final font = pw.Font.helvetica(); // Using a built-in font

    pdf.addPage(
      pw.Page(
        build:
            (pw.Context context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${widget.note.title} - Translation',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    font: font,
                  ),
                ),
                pw.SizedBox(height: 16),
                ..._buildPdfContent(translation, font),
              ],
            ),
      ),
    );
    await _savePdfFile(pdf, '${widget.note.title}_Translation.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: accentColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.note.title,
                style: const TextStyle(
                  color: accentColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Main content + TTS action
              Container(
                constraints: BoxConstraints(
                  minHeight: 80,
                  maxHeight: MediaQuery.of(context).size.height * 0.25,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.note.content,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _playNote,
                    icon: const Icon(Icons.volume_up, color: primaryColor),
                    label: const Text('Read content'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                      foregroundColor: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async => await flutterTts.stop(),
                    icon: const Icon(Icons.stop, color: Colors.white),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // AI: Summarize + Translate row
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSummarizing ? null : _summarize,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: secondaryColor,
                    ),
                    icon:
                        _isSummarizing
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.summarize, color: accentColor),
                    label: const Text(
                      'Arrange Note',
                      style: TextStyle(color: accentColor),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: secondaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _targetLang,
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: accentColor,
                        ),
                        dropdownColor: secondaryColor,
                        items:
                            _langs.entries
                                .map(
                                  (e) => DropdownMenuItem<String>(
                                    value: e.value,
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(
                                        color: accentColor,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (v) => setState(() => _targetLang = v ?? 'ha'),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isTranslating ? null : _translate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                    ),
                    icon:
                        _isTranslating
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.translate, color: Colors.white),
                    label: const Text(
                      'Translate',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Summary block with Save + Read
              Container(
                constraints: const BoxConstraints(
                  minHeight: 80,
                  maxHeight: 160,
                ),
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Markdown(
                    // This is now correctly imported
                    data: _summaryController.text,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: accentColor, fontSize: 16),
                      h1: const TextStyle(
                        color: accentColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: highlightColor,
                        fontWeight: FontWeight.bold,
                      ),
                      listBullet: const TextStyle(color: accentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSavingSummary ? null : _saveSummary,
                    icon:
                        _isSavingSummary
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.save, color: Colors.white),
                    label: const Text('Save Summary (PDF)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSavingSummary ? null : _saveSummaryDocx,
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    label: const Text('Save Summary (DOCX)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Translation block with Save + Read
              Container(
                constraints: const BoxConstraints(
                  minHeight: 80,
                  maxHeight: 160,
                ),
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Markdown(
                    data: _translationController.text,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: accentColor, fontSize: 16),
                      h1: const TextStyle(
                        color: accentColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: highlightColor,
                        fontWeight: FontWeight.bold,
                      ),
                      listBullet: const TextStyle(color: accentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSavingTranslation ? null : _saveTranslation,
                    icon:
                        _isSavingTranslation
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.save, color: Colors.white),
                    label: const Text('Save Translation (PDF)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        _isSavingTranslation ? null : _saveTranslationDocx,
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    label: const Text('Save Translation (DOCX)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                    ),
                  ),
                  // ...other buttons...
                ],
              ),

              const SizedBox(height: 16),

              // Bottom actions: Export/Delete (kept as-is)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      CircleAvatar(
                        backgroundColor: secondaryColor,
                        child: IconButton(
                          icon: const Icon(Icons.download, color: accentColor),
                          onPressed: () => _showExportDialog(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Export',
                        style: TextStyle(color: accentColor),
                      ),
                    ],
                  ),
                  const SizedBox(width: 40),
                  Column(
                    children: [
                      CircleAvatar(
                        backgroundColor: secondaryColor,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: accentColor),
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if ((widget.note.id?.isNotEmpty ?? false)) {
                              if (widget.isFromRecording) {
                                await FirebaseFirestore.instance
                                    .collection('recordings')
                                    .doc(widget.note.id)
                                    .delete();
                              } else if (user != null) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .collection('notes')
                                    .doc(widget.note.id)
                                    .delete();
                              }
                              if (mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Deleted'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Delete',
                        style: TextStyle(color: accentColor),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
