import 'dart:typed_data';

import './client.dart';
import './mumble.pb.dart' as mpb;

class MumbleUser {
  int id; // persistent user id
  String name;
  String comment;
  String hash; // hash of the user's certificate

  bool voiceActive = false; // is the user currently talking

  bool muted; // muted by admin
  bool deafened; // deafened by admin
  bool suppressed; // suppressed by server permissions
  bool selfMuted; // muted self
  bool selfDeafened; // deafened self
  bool prioritySpeaker; // true when the user is a priority speaker
  bool recording; // true when the user is recording

  Uint8List texture;
  int sessionId; // current session id

  MumbleClient client; // client that owns this user (is this necessary?)
  int channelId; // user's current channel
  List<int> listenChannels = []; // additional channels user can hear

  mpb.UserState pb;

  MumbleUser(this.pb) {
    voiceActive = false;
    updateFromProto(pb);
  }

  void updateFromProto(mpb.UserState pb) {
    this.pb = pb;
    sessionId = pb.session;
    name = pb.name;
    id = pb.userId;
    channelId = pb.channelId;
    muted = pb.mute;
    deafened = pb.deaf;
    selfDeafened = pb.selfDeaf;
    selfMuted = pb.selfMute;
    suppressed = pb.suppress;
    texture = Uint8List.fromList(pb.texture);
    comment = pb.comment;
    hash = pb.hash;
    prioritySpeaker = pb.prioritySpeaker;
    recording = pb.recording;
  }
}
