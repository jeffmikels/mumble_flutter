import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessage;

import './mumble.pb.dart' as mpb;
import './varint.dart';

// typedef S MumbleMessageCreator<S>();

enum MumbleUDPPacketType { celta, ping, speex, celtb, opus }

/// Documented here:
/// https://mumble-protocol.readthedocs.io/en/latest/voice_data.html
class MumbleUDPPacket {
  int header;
  MumbleUDPPacketType type;
  int target;

  MumbleVarInt timestamp;

  MumbleVarInt session;
  MumbleVarInt sequence;

  Uint8List payload;
  Float32List position = Float32List(3);

  Uint8List get encodedAudioPacket {
    List<int> retval = [];
    switch (type) {
      case MumbleUDPPacketType.opus:
        // make sure the payload length is less than 8191 (0x1fff)
        // and should we add the opus terminator bit
        // var payloadHeaderWithTerminatorBit = MumbleVarInt.fromInt((audioData.lengthInBytes & 0x1FFF) | 0x2000);
        var payloadHeader = MumbleVarInt.fromInt(payload.length & 0x1FFF);
        retval.addAll(payloadHeader.bytes);
        retval.addAll(payload);
        break;
      default:
    }
    return Uint8List.fromList(retval);
  }

  Uint8List writeToBuffer() {
    // List<int> bytes = [];
    // var positionBytes =
    // var eap = encodedAudioPacket;
  }

  MumbleUDPPacket({
    this.type,
    this.target,
    this.timestamp,
    this.sequence,
    this.payload,
    this.position,
  });

  MumbleUDPPacket.received(Uint8List data) {
    List<int> payloadList = [];
    header = data[0];
    type = MumbleUDPPacketType.values[header >> 5];

    // normal talking = 0
    // whisper targets 1-30 when sending audio
    // will be 1 if receiving a whisper to a channel
    // will be 2 if receiving a direct whisper
    // Server Loopback 31
    target = (header & 0x1F); // 00011111 (preserve the lower 5 bits)

    // handle ping packets
    if (type == MumbleUDPPacketType.ping) {
      timestamp = MumbleVarInt.fromBuffer(data, 1);
      return;
    }

    // parse encoded audio data packet into payload
    session = MumbleVarInt.fromBuffer(data, 1);
    sequence = MumbleVarInt.fromBuffer(data, 1 + session.length);

    // payload requires the codec to be self-delimiting
    // because the payload is followed by position info
    data = data.sublist(1 + session.length + sequence.length);

    // Read the audio frames.
    var moreFrames = true;
    while (moreFrames && data.lengthInBytes > 0) {
      // Audio frame header.
      bool terminateAudio; // used by the jitter buffer in the node-mumble code
      int headerLength, frameLength, frameHeader;

      // we only support opus audio
      if (type == MumbleUDPPacketType.opus) {
        // Opus header is varint
        var headerVarInt = MumbleVarInt.fromBuffer(data);
        frameHeader = headerVarInt.value;
        headerLength = headerVarInt.length;
        frameLength = frameHeader & 0x1FFF;
        terminateAudio = (frameHeader & 0x2000) != 0;
        moreFrames = false;
      }

      payloadList.addAll(data.sublist(
        headerLength,
        headerLength + frameLength,
      ));

      // // Put the packet in the jitter buffer.
      // var jitterPacket = {
      //     data: frame,
      //     timestamp: sequence.value * this.FRAME_LENGTH,
      //     span: this.FRAME_LENGTH,
      //     sequence: sequence++,
      //     userData: ( terminateAudio << 7 ) | type,
      // };
      // user.buffer.put( jitterPacket );
      // user.voiceActive = true;

      // Slice the current packet off the buffer and repeat.
      data = data.sublist(headerLength + frameLength);
    }

    // there might be positional audio left over
    // positional audio is three floats (I'm guessing they are 32 bit floats)
    if (data.lengthInBytes >= 24) {
      var view = ByteData.view(data.buffer);
      position[0] = view.getFloat64(0);
      position[1] = view.getFloat64(8);
      position[2] = view.getFloat64(16);
    } else if (data.lengthInBytes >= 12) {
      var view = ByteData.view(data.buffer);
      position[0] = view.getFloat32(0);
      position[1] = view.getFloat32(4);
      position[2] = view.getFloat32(8);
    }

    payload = Uint8List.fromList(payloadList);
  }
}

class MumbleMessage {
  int type;
  Uint8List data;
  GeneratedMessage _generatedMessage;
  MumbleUDPPacket _udpPacket;

  static const Map<int, String> mapFromId = {
    0: 'Version',
    1: 'UDPTunnel',
    2: 'Authenticate',
    3: 'Ping',
    4: 'Reject',
    5: 'ServerSync',
    6: 'ChannelRemove',
    7: 'ChannelState',
    8: 'UserRemove',
    9: 'UserState',
    10: 'BanList',
    11: 'TextMessage',
    12: 'PermissionDenied',
    13: 'ACL',
    14: 'QueryUsers',
    15: 'CryptSetup',
    16: 'ContextActionModify',
    17: 'ContextAction',
    18: 'UserList',
    19: 'VoiceTarget',
    20: 'PermissionQuery',
    21: 'CodecVersion',
    22: 'UserStats',
    23: 'RequestBlob',
    24: 'ServerConfig',
    25: 'SuggestConfig',
  };

  static const Map<String, int> mapFromName = {
    'Version': 0,
    'UDPTunnel': 1,
    'Authenticate': 2,
    'Ping': 3,
    'Reject': 4,
    'ServerSync': 5,
    'ChannelRemove': 6,
    'ChannelState': 7,
    'UserRemove': 8,
    'UserState': 9,
    'BanList': 10,
    'TextMessage': 11,
    'PermissionDenied': 12,
    'ACL': 13,
    'QueryUsers': 14,
    'CryptSetup': 15,
    'ContextActionModify': 16,
    'ContextAction': 17,
    'UserList': 18,
    'VoiceTarget': 19,
    'PermissionQuery': 20,
    'CodecVersion': 21,
    'UserStats': 22,
    'RequestBlob': 23,
    'ServerConfig': 24,
    'SuggestConfig': 25,
  };

  static const int Version = 0;
  static const int UDPTunnel = 1;
  static const int Authenticate = 2;
  static const int Ping = 3;
  static const int Reject = 4;
  static const int ServerSync = 5;
  static const int ChannelRemove = 6;
  static const int ChannelState = 7;
  static const int UserRemove = 8;
  static const int UserState = 9;
  static const int BanList = 10;
  static const int TextMessage = 11;
  static const int PermissionDenied = 12;
  static const int ACL = 13;
  static const int QueryUsers = 14;
  static const int CryptSetup = 15;
  static const int ContextActionModify = 16;
  static const int ContextAction = 17;
  static const int UserList = 18;
  static const int VoiceTarget = 19;
  static const int PermissionQuery = 20;
  static const int CodecVersion = 21;
  static const int UserStats = 22;
  static const int RequestBlob = 23;
  static const int ServerConfig = 24;
  static const int SuggestConfig = 25;

  GeneratedMessage get asGeneratedMessage => _generatedMessage;
  MumbleUDPPacket get asUDPPacket => _udpPacket;

  String get name => mapFromId[type];
  String get debug =>
      _udpPacket != null ? 'UDP PACKET' : asGeneratedMessage.toDebugString();

  Uint8List writeToBuffer() {
    if (_udpPacket != null)
      return _udpPacket.writeToBuffer();
    else
      return _generatedMessage.writeToBuffer();
  }

  MumbleMessage({this.type, this.data}) {
    _generatedMessage = parse(type, data);
  }

  MumbleMessage.wrap(this.type, this._generatedMessage) {
    data = _generatedMessage.writeToBuffer();
  }

  @override
  String toString() {
    return '$name (#$type):\n$debug';
  }

  dynamic parse(int type, Uint8List data) {
    switch (type) {
      case MumbleMessage.Version:
        return mpb.Version.fromBuffer(data);
      case MumbleMessage.UDPTunnel:
        // the Mumble.proto doesn't use this message
        // so we create an empty UDPTunnel message
        // and the consumer will use the data directly
        _udpPacket = MumbleUDPPacket.received(data);
        return mpb.UDPTunnel.create();
      case MumbleMessage.Authenticate:
        return mpb.Authenticate.fromBuffer(data);
      case MumbleMessage.Ping:
        return mpb.Ping.fromBuffer(data);
      case MumbleMessage.Reject:
        return mpb.Reject.fromBuffer(data);
      case MumbleMessage.ServerSync:
        return mpb.ServerSync.fromBuffer(data);
      case MumbleMessage.ChannelRemove:
        return mpb.ChannelRemove.fromBuffer(data);
      case MumbleMessage.ChannelState:
        return mpb.ChannelState.fromBuffer(data);
      case MumbleMessage.UserRemove:
        return mpb.UserRemove.fromBuffer(data);
      case MumbleMessage.UserState:
        return mpb.UserState.fromBuffer(data);
      case MumbleMessage.BanList:
        return mpb.BanList.fromBuffer(data);
      case MumbleMessage.TextMessage:
        return mpb.TextMessage.fromBuffer(data);
      case MumbleMessage.PermissionDenied:
        return mpb.PermissionDenied.fromBuffer(data);
      case MumbleMessage.ACL:
        return mpb.ACL.fromBuffer(data);
      case MumbleMessage.QueryUsers:
        return mpb.QueryUsers.fromBuffer(data);
      case MumbleMessage.CryptSetup:
        return mpb.CryptSetup.fromBuffer(data);
      case MumbleMessage.ContextActionModify:
        return mpb.ContextActionModify.fromBuffer(data);
      case MumbleMessage.ContextAction:
        return mpb.ContextAction.fromBuffer(data);
      case MumbleMessage.UserList:
        return mpb.UserList.fromBuffer(data);
      case MumbleMessage.VoiceTarget:
        return mpb.VoiceTarget.fromBuffer(data);
      case MumbleMessage.PermissionQuery:
        return mpb.PermissionQuery.fromBuffer(data);
      case MumbleMessage.CodecVersion:
        return mpb.CodecVersion.fromBuffer(data);
      case MumbleMessage.UserStats:
        return mpb.UserStats.fromBuffer(data);
      case MumbleMessage.RequestBlob:
        return mpb.RequestBlob.fromBuffer(data);
      case MumbleMessage.ServerConfig:
        return mpb.ServerConfig.fromBuffer(data);
      case MumbleMessage.SuggestConfig:
        return mpb.SuggestConfig.fromBuffer(data);
      default:
        return null;
    }
  }
}
