import 'dart:typed_data';

import './client.dart';
import './mumble.pb.dart' as mpb;

class MumbleUser {
  int id; // persistent user id
  int sessionId; // current session id
  String hash; // hash of the user's certificate

  String name = '';
  String comment = '';

  bool voiceActive = false; // is the user currently talking

  bool muted = false; // muted by admin
  bool deafened = false; // deafened by admin
  bool suppressed = false; // suppressed by server permissions
  bool selfMuted = false; // muted self
  bool selfDeafened = false; // deafened self
  bool prioritySpeaker = false; // true when the user is a priority speaker
  bool recording = false; // true when the user is recording

  Uint8List texture;

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
    id = pb.hasUserId() ? pb.userId : id;
    sessionId = pb.hasSession() ? pb.session : sessionId;
    hash = pb.hasHash() ? pb.hash : hash;

    name = pb.hasName() ? pb.name : name;
    comment = pb.hasComment() ? pb.comment : comment;

    muted = pb.hasMute() ? pb.mute : muted;
    deafened = pb.hasDeaf() ? pb.deaf : deafened;
    suppressed = pb.hasSuppress() ? pb.suppress : suppressed;
    selfDeafened = pb.hasSelfDeaf() ? pb.selfDeaf : pb.selfDeaf;
    selfMuted = pb.hasSelfMute() ? pb.selfMute : selfMuted;
    prioritySpeaker = pb.hasPrioritySpeaker() ? pb.prioritySpeaker : prioritySpeaker;
    recording = pb.hasRecording() ? pb.recording : recording;

    texture = pb.hasTexture() ? Uint8List.fromList(pb.texture) : texture;
    channelId = pb.hasChannelId() ? pb.channelId : channelId;
  }
}
