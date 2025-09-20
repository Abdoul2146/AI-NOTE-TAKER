import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:translator/translator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scribesync/models/recording_model.dart';
import 'package:dio/dio.dart';

final translator = GoogleTranslator();

const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class TakeNoteScreen extends StatefulWidget {
  final Recording? recording;

  const TakeNoteScreen({super.key, this.recording});

  @override
  State<TakeNoteScreen> createState() => _TakeNoteScreenState();
}

class _TakeNoteScreenState extends State<TakeNoteScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Recording components
  final AudioRecorder _recorder = AudioRecorder();
  late final AudioPlayer _player;
  late WhisperController _whisperController;

  // Translation/Summary
  final TextEditingController _translationController = TextEditingController();
  String _targetLang = 'en';
  bool _isTranslating = false;
  // bool _isSummarizing = false;
  bool _saveTranslation = false;
  final Map<String, String> _langs = const {
    'English': 'en',
    'Hausa': 'ha',
    'Yoruba': 'yo',
    'French': 'fr',
  };

  // State variables
  bool _isRecording = false;
  bool _isTranscribing = false;
  // bool _isPlaying = false;
  String _audioPath = '';
  String _partial = '';
  bool _modelLoaded = false;
  late PlayerState _playerState;
  String _modelStatus = "Loading Whisper model...";
  // Recording? _currentRecording;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _playerState = _player.playerState;
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });

    _initWhisper();
    _requestPermissions();

    // If a recording was passed, load it
    if (widget.recording != null) {
      // _currentRecording = widget.recording;
      _audioPath = widget.recording!.filePath;
      _titleController.text = widget.recording!.title;
      if (widget.recording!.transcription != null) {
        _contentController.text = widget.recording!.transcription!;
      }
    }
  }

  Future<String> _getWhisperModelDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory(
        '/storage/emulated/0/Download/AI Note Taker/whisper_models',
      );
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
      dir = Directory('${dir.path}/whisper_models');
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }
    }
    return dir.path;
  }

  Future<void> _initWhisper() async {
    try {
      _whisperController = WhisperController();
      final model = WhisperModel.base;

      // Use your custom directory for model storage
      final modelDir = await _getWhisperModelDirectory();
      final modelPath = '$modelDir/ggml-${model.modelName}.bin';
      final modelFile = File(modelPath);

      debugPrint("Whisper model expected at: $modelPath");

      if (!await modelFile.exists()) {
        debugPrint("Model not found locally. Downloading: ${model.modelName}");
        setState(
          () => _modelStatus = "Downloading model: ${model.modelName} ...",
        );

        // Download model using Dio
        final modelUrl = model.modelUri.toString();
        await Dio().download(modelUrl, modelPath);

        if (!await modelFile.exists()) {
          debugPrint(
            "❌ Model download finished but file still missing at: $modelPath",
          );
          setState(() {
            _modelLoaded = false;
            _modelStatus = "❌ Model download failed (file missing).";
          });
          return;
        }
      }

      debugPrint("✅ Whisper model ready at: $modelPath");
      setState(() {
        _modelLoaded = true;
        _modelStatus = "✅ Whisper model ready: ${model.modelName}";
      });

      // Tell WhisperController to use this path
      _whisperController.setModelDir(
        modelDir,
      ); // Set the directory for controller
      await _whisperController.initModel(model);
    } catch (e, st) {
      debugPrint("Whisper initialization error: $e\n$st");
      setState(() {
        _modelLoaded = false;
        _modelStatus = "❌ Initialization error: $e";
      });
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    if (Platform.isAndroid) {
      await Permission.manageExternalStorage.request();
      await Permission.storage.request();
    }
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _recorder.isEncoderSupported(encoder);
    if (!isSupported) {
      debugPrint('${encoder.name} not supported on this device');
    }
    return isSupported;
  }

  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.isGranted) {
        const encoder = AudioEncoder.wav;

        if (!await _isEncoderSupported(encoder)) {
          debugPrint("WAV encoder not supported on this device");
          return;
        }

        final documentsDir = await getApplicationDocumentsDirectory();
        final recordingsDir = Directory('${documentsDir.path}/recordings');
        if (!await recordingsDir.exists()) {
          await recordingsDir.create(recursive: true);
        }

        final path =
            '${recordingsDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

        debugPrint("Starting recording at: $path");

        const config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        );

        await _recorder.start(config, path: path);

        setState(() {
          _isRecording = true;
          _audioPath = path;
          _partial = '';
          _contentController.clear();
        });
      }
    } catch (e) {
      debugPrint("Recording error: $e");
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _audioPath = path ?? _audioPath;
    });

    final file = File(_audioPath);
    if (await file.exists()) {
      final size = await file.length();
      debugPrint("Recording saved: $_audioPath, Size: ${size} bytes");
    } else {
      debugPrint("Error: File not created at $_audioPath");
    }
  }

  Future<void> _playRecording() async {
    if (_audioPath.isEmpty) return;

    final file = File(_audioPath);
    if (!await file.exists()) {
      debugPrint("Playback error: File not found at $_audioPath");
      return;
    }

    await _player.stop();
    await _player.setFilePath(_audioPath);
    await _player.play();
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
  }

  // Future<void> _summarizeNote() async {
  //   final text = _contentController.text.trim();
  //   if (text.isEmpty) {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(const SnackBar(content: Text('Nothing to summarize')));
  //     return;
  //   }
  //   setState(() => _isSummarizing = true);
  //   try {
  //     final summary = await fetchGeminiResponse(
  //       'Summarize the following note clearly. Use concise bullet points where possible.',
  //       text,
  //     );
  //     setState(() {
  //       _contentController.text = summary.trim();
  //     });
  //   } catch (e) {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(SnackBar(content: Text('Summarize failed: $e')));
  //   } finally {
  //     if (mounted) setState(() => _isSummarizing = false);
  //   }
  // }

  Future<void> _translateNote() async {
    final text = _contentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to translate')));
      return;
    }
    setState(() => _isTranslating = true);
    try {
      final res = await translator.translate(text, to: _targetLang);
      setState(() {
        _translationController.text = res.text.trim();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Translate failed: $e')));
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _transcribeAudio() async {
    if (_audioPath.isEmpty || !_modelLoaded) return;

    final audioFile = File(_audioPath);
    if (!await audioFile.exists()) {
      debugPrint("Transcription error: File not found");
      setState(() => _partial = "Error: File not found");
      return;
    }

    final length = await audioFile.length();
    if (length == 0) {
      debugPrint("Transcription error: Empty file");
      setState(() => _partial = "Error: Empty audio file");
      return;
    }

    debugPrint("Transcribing file: $_audioPath, Size: $length bytes");

    setState(() => _isTranscribing = true);

    try {
      final result = await _whisperController.transcribe(
        model: WhisperModel.base,
        audioPath: _audioPath,
        lang: 'en',
      );

      if (result?.transcription.text != null) {
        setState(() {
          _contentController.text = result!.transcription.text;
          _partial = '';
        });
      } else {
        setState(() => _partial = "No transcription generated");
      }
    } catch (e) {
      debugPrint("Transcription error: $e");
      setState(() => _partial = "Error: ${e.toString()}");
    } finally {
      setState(() => _isTranscribing = false);
    }
  }

  Future<String> fetchGeminiResponse(String prompt, String userInput) async {
    const modelName = 'gemini-pro';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent',
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
      return data['candidates'][0]['content']['parts'][0]['text'];
    } else {
      throw Exception('Failed to get response from Gemini API');
    }
  }

  Future<void> _saveNote() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a title')));
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some content')),
      );
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Save note to Firestore
      // Save note to Firestore
      final noteData = {
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'language': 'English',
        'subject': 'General',
        'timestamp': Timestamp.now(),
        'userId': user.uid,
        if (_saveTranslation && _translationController.text.trim().isNotEmpty)
          'translation': {
            'lang': _targetLang,
            'text': _translationController.text.trim(),
          },
      };

      await _firestore.collection('notes').add(noteData);

      // If we have an audio file, save it as a recording
      if (_audioPath.isNotEmpty) {
        final audioFile = File(_audioPath);
        if (await audioFile.exists()) {
          final recordingData = {
            'title': _titleController.text.trim(),
            'filePath': _audioPath,
            'transcription': _contentController.text.trim(),
            'timestamp': Timestamp.now(),
            'duration': Duration.zero.inMilliseconds,
            'userId': user.uid,
            if (_saveTranslation &&
                _translationController.text.trim().isNotEmpty)
              'translation': {
                'lang': _targetLang,
                'text': _translationController.text.trim(),
              },
          };

          await _firestore.collection('recordings').add(recordingData);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error saving note: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error saving note')));
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _translationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: const Text('Take Note', style: TextStyle(color: accentColor)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: accentColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: accentColor),
            onPressed: _saveNote,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Model status
              if (!_modelLoaded)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _modelStatus,
                          style: const TextStyle(
                            color: accentColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // AI actions: Summarize and Translate
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // ElevatedButton.icon(
                  //   onPressed: _isSummarizing ? null : _summarizeNote,
                  //   style: ElevatedButton.styleFrom(
                  //     backgroundColor: secondaryColor,
                  //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  //   ),
                  //   icon: _isSummarizing
                  //       ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  //       : const Icon(Icons.summarize, color: accentColor),
                  //   label: const Text('Summarize', style: TextStyle(color: accentColor)),
                  // ),
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
                            (v) => setState(() => _targetLang = v ?? 'en'),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isTranslating ? null : _translateNote,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _saveTranslation,
                        onChanged:
                            (v) =>
                                setState(() => _saveTranslation = v ?? false),
                        activeColor: highlightColor,
                        checkColor: primaryColor,
                      ),
                      const Text(
                        'Save translation',
                        style: TextStyle(color: accentColor),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Title input
              TextField(
                controller: _titleController,
                style: const TextStyle(color: accentColor),
                decoration: InputDecoration(
                  hintText: 'Enter title...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  filled: true,
                  fillColor: secondaryColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),

              const SizedBox(height: 16),

              // Recording controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isRecording ? null : _startRecording,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text(
                      'Record',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _isRecording ? _stopRecording : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text(
                      'Stop',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Playback and transcription controls
              if (_audioPath.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _playerState.playing ? _stopPlayback : _playRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _playerState.playing ? Colors.orange : Colors.blue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      child: Text(
                        _playerState.playing ? 'Stop Playback' : 'Play',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed:
                          _modelLoaded && !_isTranscribing
                              ? _transcribeAudio
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: highlightColor,
                        disabledBackgroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      child:
                          _isTranscribing
                              ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(
                                'Transcribe',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Audio file info
              if (_audioPath.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.audiotrack,
                        color: accentColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Audio: ${_audioPath.split('/').last}',
                          style: const TextStyle(
                            color: accentColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Content input
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _contentController,
                  style: const TextStyle(color: accentColor),
                  maxLines: null,
                  expands: true,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'Start typing or record your note...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Translation output (appears if any translation is present or user wants to save translation)
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _translationController,
                  style: const TextStyle(color: accentColor),
                  maxLines: null,
                  expands: true,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'Translation will appear here...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),

              // Partial transcription display
              if (_partial.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _partial,
                    style: const TextStyle(color: accentColor, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
