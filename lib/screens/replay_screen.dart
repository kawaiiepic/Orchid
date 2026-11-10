import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';

import '../services/orchid_account.dart';
import '../widgets/orchid_style.dart';
import '../widgets/apple_cover.dart';
import '../widgets/artist_artwork.dart';

/// Replay is based on Orchid's own recorded listens, not Last.fm totals.
class ReplayScreen extends StatefulWidget {
  final OrchidAccount account;
  const ReplayScreen({super.key,required this.account});

  @override
  State<ReplayScreen> createState()=>_ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  static const months=['Year','January','February','March','April','May','June',
    'July','August','September','October','November','December'];
  late int year;
  late int month;
  Map<String,dynamic>? data;
  bool loading=true;
  String? error;
  int request=0;
  List<String> availablePeriods = [];

  @override
  void initState() {
    super.initState();
    final now=DateTime.now().toUtc();
    year=now.year;
    month=now.month;
    _load();
  }

  @override
  void dispose(){request++;super.dispose();}

  Future<void> _load() async {
    final id = ++request;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.account.replay(year: year, month: month);
      if (!mounted || id != request) return;
      final raw = result['periods'];
      final periods = raw is List
          ? raw.map((item) => item.toString()).toList()
          : <String>[];
      final selectedPeriod =
          year.toString() + '-' + month.toString().padLeft(2, '0');
      if (month != 0 && periods.isNotEmpty &&
          !periods.contains(selectedPeriod)) {
        final sorted = periods.where((p) =>
            RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(p)).toList()..sort();
        if (sorted.isNotEmpty) {
          final sameYear = sorted.where(
            (p) => p.startsWith(year.toString() + '-')).toList();
          final latest = (sameYear.isNotEmpty
              ? sameYear.last : sorted.last).split('-');
          year = int.parse(latest[0]);
          month = int.parse(latest[1]);
          availablePeriods = periods;
          _load();
          return;
        }
      }
      setState(() {
        availablePeriods = periods;
        data = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted || id != request) return;
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  void _select(int y,int m) {
    if(y==year&&m==month)return;
    year=y;month=m;_load();
  }

  int _number(Object? value) => value is num?value.toInt():int.tryParse('$value')??0;
  String _format(int n)=>n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),(m)=>',');
  Map<String,dynamic> _map(Object? item)=>item is Map
      ?Map<String,dynamic>.from(item):<String,dynamic>{};
  List<Map<String,dynamic>> _items(String key){
    final value=data?[key];
    return value is List?value.whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList():[];
  }

  Widget _metric(String title,String number,IconData icon){
    return OrchidGlassPanel(
      radius:16,
      child:SizedBox(
        width:164,height:105,
        child:Padding(
          padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(icon,size:19,color:OrchidStyle.lilac),
        const Spacer(),
        Text(number).large().semiBold(),
        Text(title).xSmall().muted(),
          ]),
        ),
      ),
    );
  }

  Widget _ranking(String title, List<Map<String, dynamic>> items,
      {bool artists = false, bool albums = false, bool genres = false}) {
    if (items.isEmpty) return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title).large().semiBold(),
        const SizedBox(height: 8),
        const Text('No listening data for this period.').muted(),
        const SizedBox(height: 24),
      ],
    );
    Widget artwork(Map<String, dynamic> item, double size) {
      final name = (item['name'] ?? 'Unknown').toString();
      final artist = (item['artist'] ?? name).toString();
      if (artists) {
        return ClipOval(child: ArtistArtwork(
          artist: name, size: size, radius: size / 2));
      }
      if (genres) {
        return SizedBox(width: size, height: size,
          child: ColoredBox(color: const Color(0x3C674D88),
            child: Icon(LucideIcons.audioLines, color: OrchidStyle.lilac,
              size: size * .4)));
      }
      return AppleCover(
        artist: artist,
        name: name,
        isAlbum: albums,
        fallbackUrl: item['image']?.toString(),
        size: size,
        radius: albums ? 10 : 7,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title).large().semiBold(),
      const SizedBox(height: 12),
      if (artists || albums)
        SizedBox(height: 190, child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(width: 146, child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  crossAxisAlignment: artists
                    ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    artwork(items[i], 118),
                    const SizedBox(height: 7),
                    Text(items[i]['name']?.toString() ?? 'Unknown',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: artists ? TextAlign.center : TextAlign.start)
                      .semiBold(),
                    if (albums)
                      Text((items[i]['artist'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                        .small().muted(),
                    Text('${_format(_number(items[i]['plays']))} plays',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: artists ? TextAlign.center : TextAlign.start)
                      .xSmall().muted(),
                  ],
                ),
              )),
          ],
        ))
      else
        Column(children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${i+1}').small().muted()),
                artwork(items[i], 42),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((items[i]['name'] ?? 'Unknown').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
                    if (!genres)
                      Text((items[i]['artist'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                        .small().muted(),
                  ],
                )),
                const SizedBox(width: 8),
                Text('${_format(_number(items[i]['plays']))} plays')
                  .small().muted(),
              ]),
            ),
        ]),
      const SizedBox(height: 24),
    ]);
  }

  @override
  Widget build(BuildContext context){
    final stats=_map(data?['stats']);
    final previous=_map(data?['previous']);
    final seconds=_number(stats['seconds']);
    final previousSeconds=_number(previous['seconds']);
    final difference=seconds-previousSeconds;
    final isAnnual=month==0;
    final periods=availablePeriods;
    final years=<int>{};
    for(final period in periods){
      final y=int.tryParse(period.split('-').first);
      if(y!=null)years.add(y);
    }
    if (years.isEmpty) years.add(year);
    final sortedYears=years.toList()..sort((a,b)=>b.compareTo(a));
    return ListView(padding:const EdgeInsets.all(24),children:[
      const OrchidHero(
        eyebrow:'Made for You',
        title:'Replay',
        description:'Your listening story, month by month and year by year.',
        icon:LucideIcons.audioLines,
      ),
      const SizedBox(height:22),
      const Text('Choose your year').small().muted(),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[
        for(final y in sortedYears)
          if(y==year)OrchidAdaptiveControls.button(prominent: true, onPressed:()=>_select(y,month),child:Text('$y'))
          else OrchidAdaptiveControls.button(onPressed:()=>_select(y,month),child:Text('$y')),
      ]),
      const SizedBox(height:16),
      const Text('Choose a period').small().muted(),
      const SizedBox(height:8),
      Wrap(spacing:7,runSpacing:8,children:[
        for(var m=0;m<months.length;m++)
          if (m == 0 || periods.contains(
              year.toString() + '-' + m.toString().padLeft(2, '0')))
          if(m==month)OrchidAdaptiveControls.button(prominent: true, 
            onPressed:()=>_select(year,m),child:Text(m==0?'Full year':months[m]))
          else OrchidAdaptiveControls.button(
            onPressed:()=>_select(year,m),child:Text(m==0?'Full year':months[m])),
      ]),
      const SizedBox(height:24),
      Text(isAnnual?'$year in music':'${months[month]} $year').x2Large().semiBold(),
      const SizedBox(height:6),
      const Text('Based on plays recorded by Orchid. Dates use UTC.').small().muted(),
      const SizedBox(height:18),
      if(loading)const Center(child:Text('Loading…'))
      else if(error!=null)...[
        Text(error!).small(),
        const SizedBox(height:10),
        OrchidAdaptiveControls.button(onPressed:_load,child:const Text('Try again')),
      ]else...[
        Wrap(spacing:10,runSpacing:10,children:[
          _metric('Total plays',_format(_number(stats['plays'])),LucideIcons.play),
          _metric('Unique songs',_format(_number(stats['songs'])),LucideIcons.music2),
          _metric('Unique artists',_format(_number(stats['artists'])),LucideIcons.users),
          _metric('Estimated hours',(seconds/3600).toStringAsFixed(1),LucideIcons.clock),
        ]),
        const SizedBox(height:10),
        Text('${_number(stats['timedPlays'])} of ${_number(stats['plays'])} plays include a duration. Listening time is estimated from full track lengths.').xSmall().muted(),
        const SizedBox(height:22),
        if(!isAnnual)...[
          const Text('Compared with the previous month').large().semiBold(),
          const SizedBox(height:10),
          OrchidGlassPanel(
            radius:16,
            child:Padding(
              padding:const EdgeInsets.all(16),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(difference==0?'No change':difference>0?'More listening time':'Less listening time').semiBold(),
              const SizedBox(height:4),
              Text('${difference>0?'+':''}${(difference/3600).toStringAsFixed(1)} estimated hours').large(),
              Text('Previous month: ${(previousSeconds/3600).toStringAsFixed(1)} h · Selected month: ${(seconds/3600).toStringAsFixed(1)} h').small().muted(),
              if(previousSeconds>0)Text('${difference>=0?'+':''}${(difference*100/previousSeconds).toStringAsFixed(1)}% versus last month').small().muted(),
              ]),
            ),
          ),
          const SizedBox(height:25),
        ],
        _ranking('Top songs',_items('topSongs')),
        _ranking('Top artists',_items('topArtists'),artists:true),
        _ranking('Top albums',_items('topAlbums'),albums:true),
        if(_items('topGenres').isEmpty)...[
          const Text('Top genres').large().semiBold(),
          const SizedBox(height:8),
          const Text('No genre metadata matched the tracks in this period yet.').muted(),
        ]else _ranking('Top genres',_items('topGenres'),genres:true),
        const SizedBox(height:25),
      ],
    ]);
  }
}
