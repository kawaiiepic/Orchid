import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/orchid_account.dart';
import '../widgets/orchid_style.dart';

/// A chat shell for the future AI DJ. The backend currently returns "...".
class AiDjScreen extends StatefulWidget {
  final OrchidAccount account;
  const AiDjScreen({super.key,required this.account});

  @override
  State<AiDjScreen> createState()=>_AiDjScreenState();
}

class _AiDjScreenState extends State<AiDjScreen> {
  final _input=TextEditingController();
  final _scroll=ScrollController();
  final List<({String text,bool fromUser})> _messages=[];
  bool _sending=false;
  String? _error;

  @override
  void dispose(){
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom(){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&_scroll.hasClients){
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration:const Duration(milliseconds:250),curve:Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    if(_sending)return;
    final message=_input.text.trim();
    if(message.isEmpty)return;
    if(message.length>4000){
      setState(()=>_error='Messages must be at most 4000 characters.');
      return;
    }
    _input.clear();
    setState((){
      _error=null;
      _sending=true;
      _messages.add((text:message,fromUser:true));
    });
    _scrollToBottom();
    try{
      final answer=await widget.account.sendAiDjMessage(message);
      if(!mounted)return;
      setState(()=>_messages.add((text:answer,fromUser:false)));
      _scrollToBottom();
    }catch(e){
      if(!mounted)return;
      setState(()=>_error=e.toString().replaceFirst('Exception: ',''));
    }finally{
      if(mounted)setState(()=>_sending=false);
    }
  }

  @override
  Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.all(20),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const OrchidHero(
        eyebrow:'Made for You',
        title:'AI DJ',
        description:'Chat with your music companion.',
        icon:LucideIcons.bot,
      ),
      const SizedBox(height:12),
      const Text('Preview mode: the DJ currently replies with “...”.').small().muted(),
      const SizedBox(height:14),
      Expanded(child:Container(
        decoration:OrchidStyle.panelDecoration(radius:18),
        child:_messages.isEmpty
          ?Center(child:Padding(
            padding:const EdgeInsets.all(24),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Icon(LucideIcons.messagesSquare,size:34,color:OrchidStyle.lilac),
              const SizedBox(height:12),
              const Text('Start a conversation').large().semiBold(),
              const SizedBox(height:6),
              const Text('Ask for music, share a mood, or just say hello.').muted(),
            ]),
          ))
          :ListView.builder(
            controller:_scroll,
            padding:const EdgeInsets.all(16),
            itemCount:_messages.length+(_sending?1:0),
            itemBuilder:(context,index){
              final pending=index==_messages.length;
              final item=pending?(text:'...',fromUser:false):_messages[index];
              return Padding(
                padding:const EdgeInsets.only(bottom:12),
                child:ChatBubble(
                  alignment:item.fromUser?AxisAlignment.right:AxisAlignment.left,
                  color:item.fromUser?OrchidStyle.violet:OrchidStyle.panel,
                  child:Text(item.text),
                ),
              );
            },
          ),
      )),
      if(_error!=null)...[
        const SizedBox(height:8),
        Text(_error!).small(),
      ],
      const SizedBox(height:12),
      Row(children:[
        Expanded(child:TextField(
          controller:_input,
          placeholder:const Text('Message AI DJ...'),
          enabled:!_sending,
        )),
        const SizedBox(width:10),
        PrimaryButton(
          onPressed:_sending?null:_send,
          child:const Icon(LucideIcons.send,size:19),
        ),
      ]),
    ]),
  );
}
