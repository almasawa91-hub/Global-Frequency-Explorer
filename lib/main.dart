import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const OfflineFrequencyApp());

const bg = Color(0xFF05080D);
const panel = Color(0xFF101923);
const panel2 = Color(0xFF172532);
const neon = Color(0xFFB8FF4D);
const cyan = Color(0xFF42E8F5);
const muted = Color(0xFF8194A4);

class OfflineFrequencyApp extends StatelessWidget {
  const OfflineFrequencyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Offline Frequency & FM Explorer',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: neon, secondary: cyan, surface: panel),
      useMaterial3: true,
    ),
    home: const TunerHome(),
  );
}

class TunerHome extends StatefulWidget {
  const TunerHome({super.key});
  @override
  State<TunerHome> createState() => _TunerHomeState();
}

class _TunerHomeState extends State<TunerHome> {
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  double _frequency = 99.5;
  bool _noiseMode = false;
  bool _recording = false;
  bool _playing = false;
  bool _scanning = false;
  String _status = 'جاهز للعمل دون إنترنت';
  String? _audioPath;
  String? _recordPath;
  List<String> _savedFrequencies = [];
  List<String> _recordings = [];
  int _tab = 0;
  double _volume = .65;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
    });
  }

  Future<void> _loadLocalData() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _savedFrequencies = p.getStringList('saved_frequencies') ?? [];
      _recordings = p.getStringList('local_recordings') ?? [];
    });
  }

  Future<void> _persistLists() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('saved_frequencies', _savedFrequencies);
    await p.setStringList('local_recordings', _recordings);
  }

  String get _frequencyLabel => _frequency.toStringAsFixed(1);

  Future<File> _makeNoiseFile() async {
    const sampleRate = 22050;
    const seconds = 5;
    const count = sampleRate * seconds;
    final random = Random();
    final bytes = BytesBuilder();
    final header = ByteData(44);
    void putText(int offset, String value) {
      for (var i = 0; i < value.length; i++) { header.setUint8(offset + i, value.codeUnitAt(i)); }
    }
    putText(0, 'RIFF');
    header.setUint32(4, 36 + count * 2, Endian.little);
    putText(8, 'WAVE');
    putText(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    putText(36, 'data');
    header.setUint32(40, count * 2, Endian.little);
    bytes.add(header.buffer.asUint8List());
    final pcm = ByteData(count * 2);
    var pinkState = 0.0;
    for (var i = 0; i < count; i++) {
      final white = random.nextDouble() * 2 - 1;
      pinkState = (pinkState * .97) + (white * .03);
      final sample = (_noiseMode ? pinkState * 2.2 : white) * 0.22;
      pcm.setInt16(i * 2, (sample.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    bytes.add(pcm.buffer.asUint8List());
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/radio_noise.wav');
    await file.writeAsBytes(bytes.takeBytes(), flush: true);
    return file;
  }

  Future<void> _playNoise() async {
    try {
      final file = await _makeNoiseFile();
      await _player.setFilePath(file.path);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(_volume);
      await _player.play();
      if (mounted) setState(() => _status = 'تشويش اصطناعي • لا يوجد استقبال FM مؤكد');
    } catch (e) {
      _message('تعذر تشغيل التشويش: $e');
    }
  }

  Future<void> _toggleNoise() async {
    if (_playing && _noiseMode) {
      await _player.pause();
      if (mounted) setState(() { _noiseMode = false; _status = 'تم إيقاف الصوت'; });
      return;
    }
    setState(() => _noiseMode = true);
    await _playNoise();
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = result?.files.single.path;
      if (path == null) return;
      await _player.setLoopMode(LoopMode.off);
      await _player.setFilePath(path);
      await _player.setVolume(_volume);
      setState(() { _audioPath = path; _noiseMode = false; _status = 'ملف محلي: ${path.split('/').last}'; _tab = 1; });
      await _player.play();
    } catch (e) {
      _message('تعذر فتح الملف الصوتي: $e');
    }
  }

  Future<void> _togglePlayback() async {
    if (_player.playing) {
      await _player.pause();
    } else if (_player.audioSource != null) {
      await _player.play();
    } else {
      await _pickAudio();
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (path != null) {
        _recordPath = path;
        if (!_recordings.contains(path)) _recordings.insert(0, path);
        await _persistLists();
      }
      if (mounted) setState(() { _recording = false; _status = 'حُفظ التسجيل محليًا'; });
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _message('يجب السماح باستخدام الميكروفون لبدء التسجيل.');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final path = '${dir.path}/recording_${_frequencyLabel}MHz_$stamp.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (mounted) setState(() { _recording = true; _status = 'يسجل من ميكروفون الهاتف • ليس تسجيلًا مباشرًا من مستقبل FM'; });
    } catch (e) {
      _message('تعذر بدء التسجيل: $e');
    }
  }

  Future<void> _saveFrequency() async {
    final item = _frequencyLabel;
    if (_savedFrequencies.contains(item)) {
      _savedFrequencies.remove(item);
    } else {
      _savedFrequencies.insert(0, item);
    }
    await _persistLists();
    if (mounted) setState(() {});
  }

  Future<void> _scanNotice() async {
    setState(() => _scanning = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _status = 'لم يبدأ مسح الأثير: Android لا يوفّر واجهة FM عامة لكل الهواتف. يلزم دعم الشركة المصنّعة.';
    });
    _message('لم نعرض محطات وهمية. الوصول إلى رقاقة FM يعتمد على تعريف الجهاز وواجهة الشركة المصنّعة.');
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: bg,
      title: const Row(children: [
        Icon(Icons.settings_input_antenna, color: neon),
        SizedBox(width: 10),
        Expanded(child: Text('OFFLINE FREQUENCY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.1))),
      ]),
      actions: [
        Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: neon.withValues(alpha: .12), border: Border.all(color: neon.withValues(alpha: .5)), borderRadius: BorderRadius.circular(8)),
          child: const Text('OFFLINE', style: TextStyle(color: neon, fontSize: 10, fontWeight: FontWeight.bold)),
        ))),
      ],
    ),
    body: SafeArea(child: IndexedStack(index: _tab, children: [
      _tunerScreen(),
      _libraryScreen(),
      _recordingsScreen(),
    ])),
    bottomNavigationBar: NavigationBar(
      backgroundColor: panel,
      indicatorColor: neon.withValues(alpha: .13),
      selectedIndex: _tab,
      onDestinationSelected: (v) => setState(() => _tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.radio), label: 'الموالف'),
        NavigationDestination(icon: Icon(Icons.library_music), label: 'الملفات'),
        NavigationDestination(icon: Icon(Icons.fiber_manual_record), label: 'التسجيلات'),
      ],
    ),
    bottomSheet: _player.audioSource == null ? null : _miniPlayer(),
  );

  Widget _tunerScreen() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
    children: [
      _sectionHeader('LOCAL FM RECEIVER', '01 / TUNER'),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF172633), Color(0xFF0A1018)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: neon.withValues(alpha: .38)),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: neon.withValues(alpha: .05), blurRadius: 22)],
        ),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.graphic_eq, color: neon, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('FM BROADCAST BAND', style: TextStyle(fontSize: 11, color: muted, letterSpacing: 1.4))),
            Text(_scanning ? 'SCANNING' : '87.5 — 108.0', style: const TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 24),
          Text(_frequencyLabel, style: const TextStyle(fontSize: 66, height: 1, fontWeight: FontWeight.w200, color: neon, letterSpacing: -2)),
          const Text('MHz', style: TextStyle(color: muted, letterSpacing: 5, fontSize: 12)),
          const SizedBox(height: 22),
          _frequencyScale(),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: neon, inactiveTrackColor: panel2,
              thumbColor: neon, overlayColor: neon.withValues(alpha: .12),
              trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              min: 87.5, max: 108, divisions: 410, value: _frequency,
              onChanged: (v) => setState(() { _frequency = (v * 10).round() / 10; _noiseMode = false; }),
            ),
          ),
          Row(children: [
            IconButton.filledTonal(onPressed: () => setState(() => _frequency = max(87.5, _frequency - .1)), icon: const Icon(Icons.remove)),
            const Spacer(),
            TextButton.icon(onPressed: _saveFrequency, icon: Icon(_savedFrequencies.contains(_frequencyLabel) ? Icons.bookmark : Icons.bookmark_add_outlined, color: neon), label: Text(_savedFrequencies.contains(_frequencyLabel) ? 'SAVED' : 'SAVE')),
            const Spacer(),
            IconButton.filledTonal(onPressed: () => setState(() => _frequency = min(108, _frequency + .1)), icon: const Icon(Icons.add)),
          ]),
          const Divider(color: Color(0xFF293947), height: 30),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _scanning ? null : _scanNotice,
              icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar),
              label: const Text('AUTO SCAN'),
              style: OutlinedButton.styleFrom(foregroundColor: cyan, side: const BorderSide(color: cyan)),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _toggleNoise,
              icon: Icon(_playing && _noiseMode ? Icons.stop : Icons.graphic_eq),
              label: Text(_playing && _noiseMode ? 'STOP NOISE' : 'NOISE TEST'),
              style: FilledButton.styleFrom(backgroundColor: neon, foregroundColor: bg),
            )),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      _statusCard(),
      const SizedBox(height: 14),
      _sectionHeader('QUICK FREQUENCIES', 'LOCAL MEMORY'),
      const SizedBox(height: 8),
      if (_savedFrequencies.isEmpty)
        const _EmptyPanel(icon: Icons.bookmark_border, text: 'احفظ الترددات المفضلة لتظهر هنا.')
      else
        Wrap(spacing: 8, runSpacing: 8, children: _savedFrequencies.map((f) => ActionChip(
          avatar: const Icon(Icons.radio, size: 16, color: neon),
          label: Text('$f MHz'),
          onPressed: () => setState(() => _frequency = double.tryParse(f) ?? _frequency),
        )).toList()),
      const SizedBox(height: 18),
      _sectionHeader('AUDIO TOOLS', '02 / UTILITIES'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _toolCard(Icons.folder_open, 'Local audio', 'تشغيل الملفات', _pickAudio)),
        const SizedBox(width: 10),
        Expanded(child: _toolCard(_recording ? Icons.stop_circle : Icons.fiber_manual_record, _recording ? 'Stop recording' : 'Recorder', 'تسجيل من الميكروفون', _toggleRecording)),
      ]),
    ],
  );

  Widget _frequencyScale() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: List.generate(6, (i) {
      final f = 87.5 + (i * 4.1);
      return Column(children: [
        Container(width: 1, height: i == 2 || i == 3 ? 18 : 10, color: i == 2 || i == 3 ? neon : muted),
        const SizedBox(height: 6),
        Text(f.toStringAsFixed(1), style: const TextStyle(color: muted, fontSize: 9)),
      ]);
    }),
  );

  Widget _statusCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF263847))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, color: cyan, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('RECEIVER STATUS', style: TextStyle(fontSize: 10, letterSpacing: 1.3, color: cyan, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(_status, style: const TextStyle(fontSize: 12, height: 1.45, color: Colors.white70)),
      ])),
    ]),
  );

  Widget _libraryScreen() => ListView(padding: const EdgeInsets.all(18), children: [
    _sectionHeader('OFFLINE AUDIO VAULT', '03 / LIBRARY'),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF2B3B49))),
      child: Column(children: [
        const Icon(Icons.audio_file, color: cyan, size: 46),
        const SizedBox(height: 12),
        const Text('LOCAL FILE PLAYER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.4)),
        const SizedBox(height: 8),
        const Text('اختر ملفًا صوتيًا من الهاتف لتشغيله دون اتصال. يدعم التشغيل عبر مشغل النظام داخل التطبيق.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.5)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _pickAudio, icon: const Icon(Icons.folder_open), label: const Text('اختيار ملف صوتي')),
      ]),
    ),
    const SizedBox(height: 16),
    if (_audioPath != null) ListTile(
      leading: const Icon(Icons.music_note, color: neon),
      title: Text(_audioPath!.split('/').last, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: const Text('ملف محلي'),
      trailing: IconButton(onPressed: _togglePlayback, icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, color: neon, size: 32)),
    ),
    const SizedBox(height: 12),
    _sectionHeader('PLAYBACK LEVEL', 'OUTPUT'),
    Slider(value: _volume, onChanged: (v) { setState(() => _volume = v); _player.setVolume(v); }),
    const Text('مستوى الصوت', style: TextStyle(color: muted, fontSize: 12)),
  ]);

  Widget _recordingsScreen() => ListView(padding: const EdgeInsets.all(18), children: [
    _sectionHeader('RECORDER VAULT', '04 / RECORDINGS'),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: _recording ? Colors.redAccent : const Color(0xFF2B3B49))),
      child: Column(children: [
        Icon(_recording ? Icons.fiber_manual_record : Icons.mic_none, color: _recording ? Colors.redAccent : neon, size: 40),
        const SizedBox(height: 8),
        Text(_recording ? 'RECORDING IN PROGRESS' : 'VOICE RECORDER', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        const Text('التسجيل من ميكروفون الهاتف. لا يمكن تسجيل بث FM مباشرة إلا إذا أتاح الجهاز مسار الصوت لذلك.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _toggleRecording,
          icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
          label: Text(_recording ? 'إيقاف وحفظ التسجيل' : 'بدء التسجيل'),
          style: FilledButton.styleFrom(backgroundColor: _recording ? Colors.redAccent : neon, foregroundColor: bg),
        ),
      ]),
    ),
    const SizedBox(height: 18),
    _sectionHeader('SAVED RECORDINGS', '${_recordings.length} FILES'),
    const SizedBox(height: 8),
    if (_recordings.isEmpty) const _EmptyPanel(icon: Icons.library_music, text: 'لا توجد تسجيلات بعد.')
    else ..._recordings.map((path) => Card(
      color: panel,
      child: ListTile(
        leading: const Icon(Icons.audio_file, color: cyan),
        title: Text(path.split('/').last, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(File(path).existsSync() ? 'متاح على الجهاز' : 'الملف غير موجود'),
        trailing: IconButton(
          tooltip: 'تشغيل التسجيل',
          onPressed: () async {
            if (File(path).existsSync()) {
              await _player.setLoopMode(LoopMode.off);
              await _player.setFilePath(path);
              await _player.play();
              if (mounted) setState(() { _audioPath = path; _noiseMode = false; });
            }
          },
          icon: const Icon(Icons.play_circle, color: neon, size: 30),
        ),
      ),
    )),
  ]);

  Widget _miniPlayer() => Material(
    color: const Color(0xFF1A2A35),
    child: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.graphic_eq, color: neon),
        const SizedBox(width: 10),
        Expanded(child: Text(_noiseMode ? 'Radio static • $_frequencyLabel MHz' : (_audioPath?.split('/').last ?? 'Local audio'), maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(onPressed: _togglePlayback, icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: neon)),
        IconButton(onPressed: () async { await _player.stop(); setState(() { _noiseMode = false; _audioPath = null; }); }, icon: const Icon(Icons.close)),
      ]),
    )),
  );

  Widget _sectionHeader(String title, String meta) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: cyan))),
    Text(meta, style: const TextStyle(fontSize: 9, color: muted, letterSpacing: .8)),
  ]);

  Widget _toolCard(IconData icon, String title, String subtitle, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: panel, border: Border.all(color: const Color(0xFF2B3B49)), borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: neon, size: 25),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
      ]),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyPanel({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF263847))),
    child: Column(children: [
      Icon(icon, color: muted, size: 30),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
    ]),
  );
}
