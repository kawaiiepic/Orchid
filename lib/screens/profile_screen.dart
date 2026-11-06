import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/cupertino.dart' as ios;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:file_picker/file_picker.dart';
import '../services/orchid_account.dart';
import '../widgets/avatar_crop_dialog.dart';

class ProfileScreen extends StatefulWidget {
 final OrchidAccount account;
 final bool embedded;
 const ProfileScreen({super.key,required this.account,this.embedded=false});
 @override State<ProfileScreen> createState()=>_ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
 final email=TextEditingController(),password=TextEditingController(),username=TextEditingController();
 bool registering=false,busy=false;
 String? error;
 @override void initState(){super.initState();widget.account.addListener(_changed);}
 void _changed(){if(mounted)setState((){});}
 @override void dispose(){widget.account.removeListener(_changed);email.dispose();password.dispose();username.dispose();super.dispose();}
 Widget _accountInput(TextEditingController controller, String hint, {bool password = false}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
   return ios.CupertinoTextField(
    controller: controller,
    placeholder: hint,
    obscureText: password,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    decoration: BoxDecoration(
     color: const Color(0xFF24202D),
     borderRadius: BorderRadius.circular(10),
    ),
    style: const TextStyle(color: Color(0xFFF3EAF7)),
    placeholderStyle: const TextStyle(color: Color(0xFF978A9E)),
   );
  }
  return TextField(controller:controller,obscureText:password,placeholder:Text(hint));
 }
 Future<void> _chooseAvatar() async {
  try {
   final result=await FilePicker.platform.pickFiles(
    type:FileType.custom,
    allowedExtensions:['png','jpg','jpeg','webp'],
    withData:true,
   );
   if(!mounted||result==null||result.files.isEmpty)return;
   final file=result.files.single;
   // Desktop file_picker may return a path without eagerly loading bytes.
   // XFile works for Linux/Windows/mobile/web without a dart:io dependency.
   final bytes=file.bytes ?? await file.xFile.readAsBytes();
   if(bytes.isEmpty) {
    setState(()=>error='Could not read the selected image.');
    return;
   }
   if(bytes.lengthInBytes>10*1024*1024) {
    setState(()=>error='Please choose an image smaller than 10 MB.');
    return;
   }
   setState(()=>error=null);
   // Match Petal's circular crop workflow, but upload the account avatar
   // (not Petal's separate viewing-profile avatar).
   showOverlay(context, const DialogConfiguration(),
    builder:(_) => AvatarCropDialog(
     image:bytes,
     onSave:(cropped) async {
      if(cropped.lengthInBytes>5*1024*1024) {
       throw StateError('Cropped avatar must be smaller than 5 MB.');
      }
      // crop_your_image 2.x preserves JPEG/PNG/WebP source encoding.
      // Sending JPEG bytes labeled PNG can break serving the new avatar.
      final mime = OrchidAccount.avatarMimeType(cropped);
      if(mime==null) {
       throw StateError('Unsupported cropped image format. Choose a PNG or JPEG.');
      }
      try {
       await widget.account.uploadAccountAvatar(cropped,mime);
       if(mounted)setState(()=>error=null);
      }catch(uploadError) {
       debugPrint('[Orchid Avatar] Upload failed: $uploadError');
       rethrow;
      }
     },
    ),
   );
  }catch(e){
   if(mounted)setState(()=>error='Could not select an avatar: $e');
  }
 }
 Future<void> _run(Future<void> Function() action) async{
  setState((){busy=true;error=null;});
  try{await action();}catch(e){if(mounted)setState(()=>error=e.toString());}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final a=widget.account;
  final children=<Widget>[
   const Text('Your account').x2Large().semiBold(),
   const SizedBox(height:8),
   const Text('One Petal account for Petal and Orchid.').muted(),
   const SizedBox(height:24),
   if(a.loading)const Text('Loading account…')
   else if(!a.signedIn)...[
    if(registering)...[
     const Text('Username'),const SizedBox(height:6),
     _accountInput(username, 'Username'),
     const SizedBox(height:12),
    ],
    const Text('Email'),const SizedBox(height:6),
    _accountInput(email, 'you@example.com'),
    const SizedBox(height:12),
    const Text('Password'),const SizedBox(height:6),
    _accountInput(password, 'Password', password:true),
    const SizedBox(height:14),
    PrimaryButton(onPressed:busy?null:()=>_run(()=>registering?
      a.register(username.text,email.text,password.text):a.login(email.text,password.text)),
      child:Text(busy?'Working…':registering?'Create account':'Sign in')),
    const SizedBox(height:8),
    GhostButton(onPressed:busy?null:()=>setState(()=>registering=!registering),
      child:Text(registering?'Already have a Petal account? Sign in':'Create a Petal account')),
   ]else...[
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
     crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
       ClipOval(child:SizedBox(width:64,height:64,child:
        a.avatarUrl==null
          ? Container(color:const Color(0xFF69468F),
              child:const Icon(LucideIcons.user,size:30))
          : Image.network(a.avatarUrl!,fit:BoxFit.cover,
              errorBuilder:(_,__,___)=>const Icon(LucideIcons.user,size:30)),
       )),
       const SizedBox(width:14),
       Expanded(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Account avatar').semiBold(),
          const Text('Shared across Petal and Orchid').small().muted(),
          const SizedBox(height:8),
          Wrap(spacing:8,runSpacing:8,children:[
           OutlineButton(onPressed:busy?null:_chooseAvatar,
             child:const Text('Change avatar')),
           if(a.avatarUrl!=null)
             GhostButton(
               onPressed:busy?null:()=>_run(a.removeAccountAvatar),
               child:const Text('Remove')),
          ]),
        ],
       )),
      ]),
      const SizedBox(height:16),
      Text(a.username??'Account').large().semiBold(),
      Text(a.email??'').muted(),
      const SizedBox(height:12),
      OutlineButton(onPressed:busy?null:()=>_run(a.logout),child:const Text('Sign out')),
    ]))),
    const SizedBox(height:22),
    const Text('Connected services').large().semiBold(),
    const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
     crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Last.fm').large().semiBold(),
      const SizedBox(height:5),
      Text(a.lastfmConnected?'Connected as ${a.lastfmUsername}':'Connect Last.fm to scrobble music you play.').muted(),
      const SizedBox(height:12),
      if(a.lastfmConnected)
       OutlineButton(onPressed:busy?null:()=>_run(a.unlinkLastfm),child:const Text('Disconnect'))
      else ...[
       PrimaryButton(onPressed:busy?null:()=>_run(a.startLastfm),child:const Text('Authorize Last.fm')),
       if(a.connecting)...[
        const SizedBox(height:10),
        const Text('After approving access in your browser, return here.').small().muted(),
        const SizedBox(height:8),
        OutlineButton(onPressed:busy?null:()=>_run(a.completeLastfm),child:const Text('I approved, finish linking')),
       ]
      ],
     ]))),
   ],
   if(error!=null)...[const SizedBox(height:14),Text(error!).small()],
  ];
  return widget.embedded
    ? Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:children)
    : ListView(padding:const EdgeInsets.all(20),children:children);
 }
}
