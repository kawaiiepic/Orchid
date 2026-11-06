import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../services/player_service.dart';
import '../services/orchid_account.dart';
import '../models/addon.dart';

class OrchidHomeScreen extends StatelessWidget {
 final PlayerService player;
 final OrchidAccount account;
 final VoidCallback openExplore,openProfile;
 const OrchidHomeScreen({super.key,required this.player,required this.account,required this.openExplore,required this.openProfile});
 @override Widget build(BuildContext context){
  return AnimatedBuilder(animation:Listenable.merge([player,account]),builder:(context,_){
   final recent=player.history.reversed.toList();
   final current=player.current;
   return ListView(padding:const EdgeInsets.all(20),children:[
    Text(account.username==null?'Welcome to Orchid':'Welcome back, ${account.username}').x2Large().semiBold(),
    const SizedBox(height:5),
    const Text('Your music, your space.').muted(),
    const SizedBox(height:24),
    const Text('Jump back in').large().semiBold(),
    const SizedBox(height:12),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
     crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(current?.title??'Nothing playing yet').semiBold(),
      const SizedBox(height:4),
      Text(current?.artist??'Find something you love and press play.').muted(),
      const SizedBox(height:12),
      PrimaryButton(onPressed:current==null?openExplore:()=>player.togglePlayPause(),
       child:Text(current==null?'Explore music':player.player.playing?'Pause':'Resume')),
     ]))),
    const SizedBox(height:24),
    Row(children:[const Expanded(child:Text('Recently played').large().semiBold()),
     GhostButton(onPressed:openExplore,child:const Text('Explore'))]),
    const SizedBox(height:10),
    if(recent.isEmpty)const Text('Your listening history will appear here.').muted()
    else ...recent.take(8).map((track)=>_item(track)),
    const SizedBox(height:24),
    const Text('Your connections').large().semiBold(),
    const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
     Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(account.signedIn?'Petal account connected':'Sign in to Petal').semiBold(),
      Text(account.lastfmConnected?'Last.fm: ${account.lastfmUsername}':
       'Link Last.fm for listening stats and scrobbles.').small().muted(),
     ])),
     OutlineButton(onPressed:openProfile,child:const Text('Manage')),
    ]))),
   ]);
  });
 }
 Widget _item(TrackResult t)=>Button(style:const ButtonStyle.ghost(),
  onPressed:()=>player.playTrack(t),child:Padding(padding:const EdgeInsets.symmetric(vertical:7),
  child:Row(children:[
   if(t.artworkUrl!=null)ClipRRect(borderRadius:BorderRadius.circular(6),
    child:CachedNetworkImage(imageUrl:t.artworkUrl!,width:44,height:44,fit:BoxFit.cover))
   else const SizedBox(width:44,height:44),
   const SizedBox(width:12),
   Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(t.title).semiBold(),Text(t.artist).small().muted(),
   ])),
  ])));
}
