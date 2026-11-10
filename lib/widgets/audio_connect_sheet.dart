import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform, debugPrint;
import 'package:flutter/services.dart';
import '../services/orchid_connect.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as mini;

import '../services/player_service.dart';
import 'content_drawer.dart';

/// Device outputs, Orchid Connect handoff and shared listening controls.
void showAudioConnectSheet(BuildContext context, PlayerService player) {
  showOrchidActionDrawer(
    context,
    maxHeightFraction: .84,
    builder: (sheetContext, close) => _AudioConnectSheet(
      player: player,
      close: close,
    ),
  );
}

class _AudioConnectSheet extends StatefulWidget {
  final PlayerService player;
  final VoidCallback close;
  const _AudioConnectSheet({required this.player, required this.close});

  @override
  State<_AudioConnectSheet> createState() => _AudioConnectSheetState();
}

class _AudioConnectSheetState extends State<_AudioConnectSheet> {
  static const _platform = MethodChannel('orchid/audio_routes');
  String? _message;
  bool _pipeline = false;
  bool _jamExpanded = false;
  String _jamCode = '';
  bool _networkExpanded = false;
  bool _refreshing = false;
  List<mini.AudioDevice> _audioOutputs=[];
  bool _outputsLoading=false;
  String? _outputError;
  @override
  void initState(){
    super.initState();
    _loadOutputs();
  }
  Future<void> _loadOutputs() async{
    if(kIsWeb)return;
    setState(()=>_outputsLoading=true);
    try{
      final outputs=await widget.player.player.getAudioDevices();
      if(mounted)setState((){
        _audioOutputs=outputs;
        _outputError=null;
      });
    }catch(e){
      if(mounted)setState(()=>_outputError='Audio output discovery unavailable: $e');
    }finally{
      if(mounted)setState(()=>_outputsLoading=false);
    }
  }
  Future<void> _selectOutput(mini.AudioDevice device) async{
    await _run(()=>widget.player.player.setAudioDevice(device));
    if(mounted)setState(()=>_networkExpanded=false);
  }

  Future<void> _refreshDevices() async {
    final connect=OrchidConnect.active;
    if(connect==null)return;
    setState(()=>_refreshing=true);
    try{await connect.refresh();}finally{if(mounted)setState(()=>_refreshing=false);}
  }

  Future<void> _run(Future<void> Function() action) async {
    try{await action();}
    catch(e){debugPrint('[Orchid Connect] $e');if(mounted)setState(()=>_message='$e');}
  }

  Widget _connectContent(OrchidConnect connect) => ListenableBuilder(
    listenable:connect,
    builder:(context,_) {
      final others=connect.devices.where((d)=>d['id']!=connect.deviceId).toList();
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        _section('Your Devices'),
        if(!connect.account.signedIn)
          _tile(LucideIcons.logIn,'Sign in to Orchid',
            'Your account is required for device transfer and Jams')
        else if(others.isEmpty)
          _tile(LucideIcons.monitor,'No other Orchid devices',
            'Open Orchid on another signed-in device'),
        for(final device in others)
          _tile(
            device['platform']=='web'?LucideIcons.globe:
              device['platform']=='ios'||device['platform']=='android'
                ?LucideIcons.smartphone:LucideIcons.monitor,
            device['name']?.toString()??'Orchid device',
            (device['playback'] is Map&&
             (device['playback'] as Map)['playing']==true)
              ? 'Currently playing · Tap to transfer'
              : 'Tap to play here',
            onTap:connect.working?null:()=>_run(()=>connect.transferTo(device['id'] as String)),
            trailing:const Icon(LucideIcons.chevronRight,color:Color(0xFF99999F)),
          ),
        if(connect.error!=null)
          Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:6),
            child:Text(connect.error!,style:const TextStyle(fontSize:12,color:Color(0xFFF6B1B1)))),
        _section('Listen Together'),
        _tile(LucideIcons.radio,connect.jamId==null?'Start a Jam':
          'Jam · ${connect.jamId}',
          connect.jamId==null?'Listen together in real time':
            '${connect.jamListeners} listening · ${connect.jamHost?'Hosting':'Joined'}',
          onTap:()=>setState(()=>_jamExpanded=!_jamExpanded),
          trailing:Icon(_jamExpanded?LucideIcons.chevronDown:LucideIcons.chevronRight,
            color:const Color(0xFF99999F))),
        if(_jamExpanded)Padding(
          padding:const EdgeInsets.fromLTRB(22,4,22,16),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            if(connect.jamId==null)...[
              _action('Create Jam',()=>_run(connect.createJam)),
              const SizedBox(height:12),
              TextField(placeholder:const Text('Invite code'),
                onChanged:(value)=>_jamCode=value),
              const SizedBox(height:8),
              _action('Join Jam',()=>_run(()=>connect.joinJam(_jamCode))),
            ]else...[
              Text('Invite code: ${connect.jamId}',
                style:const TextStyle(fontSize:15)),
              const SizedBox(height:8),
              _action('Copy invite code',()=>Clipboard.setData(
                ClipboardData(text:connect.jamId!))),
              const SizedBox(height:8),
              _action(connect.jamHost?'End Jam':'Leave Jam',
                ()=>_run(connect.leaveJam)),
            ],
          ]),
        ),
      ]);
    },
  );

  Widget _action(String title,VoidCallback onTap) => GestureDetector(
    behavior:HitTestBehavior.opaque,onTap:onTap,
    child:Padding(padding:const EdgeInsets.symmetric(vertical:10),
      child:Text(title,style:const TextStyle(
        color:Color(0xFFE35C9B),fontSize:15,fontWeight:FontWeight.w600))),
  );

  Future<void> _openSystemAudioSettings() async {
    try {
      await _platform.invokeMethod<void>('openAudioSettings');
    } catch (_) {
      if (mounted) setState(() =>
          _message = 'Audio output settings are unavailable on this device.');
    }
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 9),
    child: Text(label, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: Color(0xFF9C9CA4))),
  );

  Widget _tile(IconData icon, String name, String description, {
    VoidCallback? onTap, Widget? trailing, Color? subtitleColor,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        SizedBox(width: 54, child: Icon(icon, size: 26,
          color: const Color(0xFFF1F2F0))),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(
              color: Color(0xFFF7F7F4), fontSize: 17,
              fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(
              color: subtitleColor ?? const Color(0xFF96979B),
              fontSize: 13)),
          ],
        )),
        if (trailing != null) trailing,
      ]),
    ),
  );

  Widget _pipelineControls() => ListenableBuilder(
    listenable: widget.player,
    builder: (_, __) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(LucideIcons.volume2, size: 17),
            const SizedBox(width: 12),
            Expanded(child: Slider(
              min: 0, max: 1,
              value: SliderValue.single(widget.player.volume),
              onChanged: (v) => widget.player.setVolume(v.value),
            )),
            const SizedBox(width: 12),
            Text('${(widget.player.volume * 100).round()}%',
              style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.player.toggleShuffle,
              child: Row(children: [
                Icon(LucideIcons.shuffle, size: 18,
                  color: widget.player.shuffleEnabled
                      ? const Color(0xFFD95A9C) : null),
                const SizedBox(width: 8),
                Text(widget.player.shuffleEnabled
                    ? 'Shuffle on' : 'Shuffle off'),
              ]),
            )),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.player.cycleRepeatMode,
              child: Row(children: [
                Icon(widget.player.repeatMode == OrchidRepeatMode.one
                    ? LucideIcons.repeat1 : LucideIcons.repeat,
                  size: 18,
                  color: widget.player.repeatMode != OrchidRepeatMode.off
                      ? const Color(0xFFD95A9C) : null),
                const SizedBox(width: 8),
                Text(widget.player.repeatMode == OrchidRepeatMode.one
                    ? 'Repeat one' : widget.player.repeatMode ==
                        OrchidRepeatMode.all ? 'Repeat all' : 'Repeat off'),
              ]),
            ),
          ]),
          const SizedBox(height:16),
          Row(children:[
            const Expanded(child:Text('Equalizer',style:TextStyle(fontWeight:FontWeight.w600))),
            _action(widget.player.eqEnabled?'On · Disable':'Off · Enable',
              ()=>_run(()=>widget.player.setEqEnabled(!widget.player.eqEnabled))),
          ]),
          Wrap(spacing:12,runSpacing:4,children:[
            for(final preset in PlayerService.eqPresets.keys)
              GestureDetector(
                onTap:()=>_run(()=>widget.player.setEqPreset(preset)),
                child:Padding(padding:const EdgeInsets.symmetric(vertical:6),
                  child:Text(preset,style:TextStyle(fontSize:12,
                    fontWeight:widget.player.eqPreset==preset?
                      FontWeight.w700:FontWeight.w400,
                    color:widget.player.eqPreset==preset?
                      const Color(0xFFE35C9B):const Color(0xFFAAAAAF)))),
              ),
          ]),
          if(widget.player.eqEnabled)...[
            const SizedBox(height:8),
            for(var i=0;i<10;i++)
              Row(children:[
                SizedBox(width:56,child:Text(
                  const ['31Hz','63Hz','125Hz','250Hz','500Hz','1k','2k','4k','8k','16k'][i],
                  style:const TextStyle(fontSize:11))),
                Expanded(child:Slider(
                  min:-12,max:12,
                  value:SliderValue.single(widget.player.activeEqBands[i]),
                  onChanged:(v)=>_run(()=>widget.player.setEqBand(i,v.value)),
                )),
                SizedBox(width:45,child:Text(
                  '${widget.player.activeEqBands[i].toStringAsFixed(1)}dB',
                  textAlign:TextAlign.end,
                  style:const TextStyle(fontSize:11))),
              ]),
          ],
          const SizedBox(height:8),
          Row(children:[
            const Expanded(child:Text('Volume normalization')),
            _action(widget.player.normalizationEnabled?'On':'Off',
              ()=>_run(()=>widget.player.setNormalization(!widget.player.normalizationEnabled))),
          ]),
          const SizedBox(height:10),
          Row(children:[
            const Text('Crossfade',style:TextStyle(fontWeight:FontWeight.w600)),
            const Spacer(),
            Text('${widget.player.crossfadeSeconds.toStringAsFixed(1)}s',
              style:const TextStyle(fontSize:12)),
          ]),
          Slider(
            min:0,max:12,
            value:SliderValue.single(widget.player.crossfadeSeconds),
            onChanged:(v)=>_run(()=>widget.player.setCrossfade(v.value)),
          ),
          const SizedBox(height: 12),
          Text('Pipeline: ${widget.player.eqEnabled?'EQ · ':''}${widget.player.normalizationEnabled?'Normalized · ':''}${widget.player.crossfadeSeconds>0?'Crossfade':'Untouched'}',
            style: const TextStyle(fontSize: 12,
              color: Color(0xFFAAA5B0))),
          const SizedBox(height:4),
          Text('Source: ${widget.player.sourceLabel}',
            style: const TextStyle(fontSize: 12,
              color: Color(0xFFAAA5B0))),
          if(widget.player.qualityLabel!=null)
            Text('Quality: ${widget.player.qualityLabel}',
              style: const TextStyle(fontSize: 12,
                color: Color(0xFFAAA5B0))),
          if(widget.player.streamCodec!=null)
            Text('Codec: ${widget.player.streamCodec}',
              style: const TextStyle(fontSize: 12,
                color: Color(0xFFAAA5B0))),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.player,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.only(bottom: 22),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 14, 12),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connect to a device', style: TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF))),
                const SizedBox(height: 5),
                const Text('Choose where Orchid plays audio',
                  style: TextStyle(fontSize: 14,
                    color: Color(0xFF9E9EA4))),
              ],
            )),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _refreshDevices,
              child:Padding(padding:const EdgeInsets.all(8),
                child:Icon(LucideIcons.refreshCw,size:19,
                  color:_refreshing?const Color(0xFF777777):const Color(0xFFE35C9B))),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.close,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text('Done', style: TextStyle(
                  color: Color(0xFFE35C9B), fontSize: 17,
                  fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
        const Divider(),
        _tile(LucideIcons.smartphone, 'This device',
          widget.player.player.playing?'Currently playing':'Ready to play',
          subtitleColor: const Color(0xFFE35C9B),
          trailing: const Icon(LucideIcons.volume2,
            color: Color(0xFFE35C9B), size: 20)),
        if(OrchidConnect.active!=null)
          _connectContent(OrchidConnect.active!)
        else _tile(LucideIcons.monitor,'Orchid Connect',
          'Session service not ready'),
        _section('AirPlay & Bluetooth'),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Expanded(child: _tile(
                LucideIcons.speaker, 'Speaker & TV',
                'AirPlay, Bluetooth & other devices')),
              const SizedBox(
                width: 54, height: 52,
                child: UiKitView(
                  viewType: 'orchid/airplay-route-picker'),
              ),
            ]),
          )
        else
          _tile(LucideIcons.speaker, 'Speaker & TV',
            'Open system audio & Bluetooth settings',
            onTap: _openSystemAudioSettings,
            trailing: const Icon(LucideIcons.chevronRight,
              color: Color(0xFF99999F))),
        _section('Network Speakers'),
        _tile(LucideIcons.speaker,'Audio outputs',
          kIsWeb?'Select audio in your browser or operating system':
          defaultTargetPlatform==TargetPlatform.iOS
            ? 'AirPlay and Bluetooth use the native Speaker & TV picker'
            : 'Choose a connected speaker, DAC or audio output',
          onTap:()=>setState(()=>_networkExpanded=!_networkExpanded),
          trailing:Icon(_networkExpanded?LucideIcons.chevronDown:
            LucideIcons.chevronRight,color:const Color(0xFF99999F))),
        if(_networkExpanded)Padding(
          padding:const EdgeInsets.fromLTRB(20,0,20,14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            if(_outputsLoading)const Text('Searching system audio outputs…'),
            if(_outputError!=null)
              Text(_outputError!,style:const TextStyle(fontSize:12)),
            for(final output in _audioOutputs)
              _action(output.name,
                ()=>_run(()=>_selectOutput(output))),
            if(_audioOutputs.isEmpty&&!_outputsLoading)
              const Text('No selectable native outputs found. AirPlay/Bluetooth routes may be managed by your operating system.',
                style:TextStyle(fontSize:12,color:Color(0xFFAAAAAF))),
            _action('Refresh audio outputs',_loadOutputs),
          ]),
        ),
        const Divider(),
        _tile(LucideIcons.audioLines, 'Audio Pipeline',
          widget.player.eqEnabled||widget.player.normalizationEnabled||widget.player.crossfadeSeconds>0
            ? 'Custom audio effects' : 'Untouched',
          onTap: () => setState(() => _pipeline = !_pipeline),
          trailing: Icon(_pipeline ? LucideIcons.chevronDown
              : LucideIcons.chevronRight,
              color: const Color(0xFF99999F))),
        if (_pipeline) _pipelineControls(),
        if (_message != null) Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_message!, style: const TextStyle(
            color: Color(0xFFF6B1B1), fontSize: 12)),
        ),
      ],
    ),
  );
}
