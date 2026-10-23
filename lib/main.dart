import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const GlobalFrequencyApp());

const bg = Color(0xFF050B18);
const panel = Color(0xFF0C1729);
const cyan = Color(0xFF00D9FF);
const violet = Color(0xFF8B5CF6);

class Station {
  final String id, name, country, url, codec;
  final double? lat, lon;
  final int votes, bitrate;
  const Station({required this.id, required this.name, required this.country,
    required this.url, required this.codec, required this.lat, required this.lon,
    required this.votes, required this.bitrate});
  factory Station.fromJson(Map<String, dynamic> j) => Station(
    id: '${j['stationuuid'] ?? j['url'] ?? j['name'] ?? ''}',
    name: '${j['name'] ?? 'Unknown station'}'.trim(),
    country: '${j['country'] ?? 'Unknown country'}'.trim(),
    url: '${j['url_resolved'] ?? j['url'] ?? ''}',
    codec: '${j['codec'] ?? ''}',
    lat: double.tryParse('${j['geo_lat'] ?? ''}'),
    lon: double.tryParse('${j['geo_long'] ?? ''}'),
    votes: int.tryParse('${j['votes'] ?? 0}') ?? 0,
    bitrate: int.tryParse('${j['bitrate'] ?? 0}') ?? 0,
  );
}

class RadioApi {
  static const base = 'https://de1.api.radio-browser.info/json';
  static Future<List<Station>> search({String query = '', String country = ''}) async {
    final params = <String, String>{'limit': '150', 'hidebroken': 'true', 'order': 'votes', 'reverse': 'true'};
    if (query.trim().isNotEmpty) params['name'] = query.trim();
    if (country.trim().isNotEmpty) params['country'] = country.trim();
    final uri = Uri.parse('$base/stations/search').replace(queryParameters: params);
    final response = await http.get(uri, headers: {'User-Agent': 'GlobalFrequencyExplorer/0.1'});
    if (response.statusCode != 200) throw Exception('Radio service returned ${response.statusCode}');
    final raw = jsonDecode(response.body);
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map(Station.fromJson)
      .where((s) => s.name.isNotEmpty && s.url.startsWith('http')).toList();
  }
}

class GlobalFrequencyApp extends StatelessWidget {
  const GlobalFrequencyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Global Frequency Explorer',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: cyan, secondary: violet, surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: Colors.white),
    ),
    home: const ExplorerHome(),
  );
}

class ExplorerHome extends StatefulWidget {
  const ExplorerHome({super.key});
  @override
  State<ExplorerHome> createState() => _ExplorerHomeState();
}

class _ExplorerHomeState extends State<ExplorerHome> with SingleTickerProviderStateMixin {
  final _audio = AudioPlayer();
  final _search = TextEditingController();
  final _map = MapController();
  late final AnimationController _wave;
  List<Station> _stations = [], _favorites = [];
  Station? _current;
  bool _loading = true, _playing = false, _onlyFavorites = false;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
    _loadFavorites();
    _load();
    _audio.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('favorite_station_ids') ?? [];
    if (mounted) setState(() => _favorites = _stations.where((s) => ids.contains(s.id)).toList());
  }

  Future<void> _saveFavorite(Station s) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('favorite_station_ids') ?? [];
    if (ids.contains(s.id)) { ids.remove(s.id); } else { ids.add(s.id); }
    await prefs.setStringList('favorite_station_ids', ids);
    setState(() {
      if (ids.contains(s.id)) { if (!_favorites.any((x) => x.id == s.id)) _favorites.add(s); }
      else { _favorites.removeWhere((x) => x.id == s.id); }
    });
  }

  Future<void> _load({String query = ''}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await RadioApi.search(query: query);
      if (!mounted) return;
      setState(() { _stations = list; _loading = false; });
      await _loadFavorites();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'تعذر جلب المحطات. تحقق من الإنترنت ثم أعد المحاولة.'; });
    }
  }

  Future<void> _play(Station s) async {
    if (s.url.isEmpty) return;
    setState(() => _current = s);
    try {
      await _audio.setUrl(s.url);
      await _audio.play();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل هذا البث. جرّب محطة أخرى.')));
    }
  }

  @override
  void dispose() {
    _wave.dispose(); _search.dispose(); _audio.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tab == 1 ? _favorites : _stations;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.public, color: cyan, size: 30), SizedBox(width: 10),
          Expanded(child: Text('Global Frequency', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        ]),
        actions: [IconButton(tooltip: 'تحديث المحطات', onPressed: () => _load(query: _search.text), icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 12), child: TextField(
          controller: _search,
          onSubmitted: (v) => _load(query: v),
          decoration: InputDecoration(
            hintText: 'ابحث عن محطة أو دولة…', prefixIcon: const Icon(Icons.search, color: cyan),
            filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            suffixIcon: IconButton(onPressed: () { _search.clear(); _load(); }, icon: const Icon(Icons.close)),
          ),
        )),
        Expanded(child: _tab == 0 ? _mapView() : _stationList(visible)),
      ])),
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel, indicatorColor: cyan.withOpacity(.16), selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: 'الخريطة'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: 'المفضلة'),
          NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), label: 'الشائعة'),
        ],
      ),
      bottomSheet: _current == null ? null : _playerBar(),
    );
  }

  Widget _mapView() => Column(children: [
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: FlutterMap(
      mapController: _map,
      options: const MapOptions(initialCenter: LatLng(20, 0), initialZoom: 2.1, minZoom: 1.5, maxZoom: 12),
      children: [
        TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a','b','c','d'], userAgentPackageName: 'com.globalfrequency.explorer'),
        MarkerLayer(markers: _stations.where((s) => s.lat != null && s.lon != null && s.lat!.abs() <= 90 && s.lon!.abs() <= 180)
          .take(500).map((s) => Marker(point: LatLng(s.lat!, s.lon!), width: 42, height: 42,
            child: GestureDetector(onTap: () => _stationDetails(s), child: Container(
              decoration: BoxDecoration(color: cyan.withOpacity(.18), shape: BoxShape.circle, border: Border.all(color: cyan, width: 1.5)),
              child: const Icon(Icons.radio, color: cyan, size: 22),
            )),
          )).toList()),
      ],
    ))),
    if (_loading) const LinearProgressIndicator(color: cyan, minHeight: 2),
    if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))),
    Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      const Icon(Icons.radar, color: cyan), const SizedBox(width: 8),
      Expanded(child: Text('${_stations.length} محطة محمّلة • ${_stations.where((s) => s.lat != null && s.lon != null).length} على الخريطة',
        style: const TextStyle(color: Colors.white70))),
      TextButton(onPressed: () => _load(query: _search.text), child: const Text('تحديث')),
    ])),
  ]);

  Widget _stationList(List<Station> stations) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: cyan));
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12),
      FilledButton(onPressed: () => _load(query: _search.text), child: const Text('إعادة المحاولة')),
    ]));
    final list = _tab == 2 ? (List<Station>.from(stations)..sort((a,b) => b.votes.compareTo(a.votes))) : stations;
    if (list.isEmpty) return const Center(child: Text('لا توجد محطات هنا بعد.'));
    return ListView.builder(padding: const EdgeInsets.only(bottom: 105), itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i], fav = _favorites.any((x) => x.id == s.id);
        return Card(color: panel, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cyan.withOpacity(.12))),
          child: ListTile(
            leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: violet.withOpacity(.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.radio, color: cyan)),
            title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${s.country}  •  ${s.codec} ${s.bitrate > 0 ? '${s.bitrate} kbps' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Wrap(spacing: 0, children: [
              IconButton(onPressed: () => _saveFavorite(s), icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.pinkAccent : Colors.white70)),
              IconButton(onPressed: () => _play(s), icon: const Icon(Icons.play_circle_fill, color: cyan, size: 30)),
            ]),
            onTap: () => _stationDetails(s),
          ),
        );
      });
  }

  Widget _playerBar() => Container(
    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFF101D33), borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cyan.withOpacity(.45)), boxShadow: [BoxShadow(color: cyan.withOpacity(.08), blurRadius: 20)]),
    child: Row(children: [
      const Icon(Icons.graphic_eq, color: cyan, size: 32), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(_current!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(_current!.country, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ])),
      IconButton(onPressed: () => _playing ? _audio.pause() : _audio.play(),
        icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: cyan, size: 36)),
      IconButton(onPressed: () => _saveFavorite(_current!), icon: Icon(_favorites.any((s) => s.id == _current!.id) ? Icons.favorite : Icons.favorite_border, color: Colors.pinkAccent)),
    ]),
  );

  void _stationDetails(Station s) {
    showModalBottomSheet(context: context, backgroundColor: panel, showDragHandle: true, builder: (ctx) => Padding(
      padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6), Text(s.country, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16), Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () { Navigator.pop(ctx); _play(s); }, icon: const Icon(Icons.play_arrow), label: const Text('استمع الآن'))),
          const SizedBox(width: 10), OutlinedButton.icon(onPressed: () => _saveFavorite(s), icon: const Icon(Icons.favorite_border), label: const Text('المفضلة')),
        ]),
      ]),
    ));
  }
}
