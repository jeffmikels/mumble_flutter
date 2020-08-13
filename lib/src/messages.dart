import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessage;

import './mumble.pb.dart' as mpb;
import './varint.dart';

// typedef S MumbleMessageCreator<S>();

enum MumbleUDPPacketType { celta, ping, speex, celtb, opus }

/// Documented here:
/// https://mumble-protocol.readthedocs.io/en/latest/voice_data.html
class MumbleUDPPacket {
  MumbleUDPPacketType type;
  int target;

  int get header => type.index << 5 | target;

  MumbleVarInt timestamp; // only used for ping UDP packets
  MumbleVarInt session; // session id of the user who spoke, is null on outgoing packets
  MumbleVarInt sequence; // sequence number of this audio packet

  Uint8List payload;
  Float32List position; // null if position is not being used
  bool isLastFrame = false;

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
    List<int> bytes = <int>[];
    bytes.add(header);
    if (session != null) bytes.addAll(session.bytes);
    bytes.addAll(sequence.bytes);
    bytes.addAll(payload);
    if (position != null && position.length == 3) bytes.addAll(position.buffer.asUint8List());
    return Uint8List.fromList(bytes);
  }

  MumbleUDPPacket({
    this.type,
    this.target,
    this.timestamp,
    this.sequence,
    this.payload,
    this.position,
  });

  MumbleUDPPacket.outgoing({
    this.type,
    this.target,
    this.sequence,
    this.position,
    this.payload,
  });

  MumbleUDPPacket.received(Uint8List data) {
    List<int> payloadList = [];

    var headerByte = data[0];
    type = MumbleUDPPacketType.values[headerByte >> 5];

    // normal talking = 0
    // whisper targets 1-30 when sending audio
    // will be 1 if receiving a whisper to a channel
    // will be 2 if receiving a direct whisper
    // Server Loopback 31
    target = (headerByte & 0x1F); // 00011111 (preserve the lower 5 bits)

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
    var offset = 1 + session.length + sequence.length;
    var moreFrames = true;

    // Opus audio only has one frame
    while (moreFrames && offset < data.lengthInBytes) {
      // Audio frame header.
      int headerLength, frameLength, frameHeaderValue;

      // we only support opus audio
      if (type == MumbleUDPPacketType.opus) {
        moreFrames = false;

        // Opus header is varint
        var headerVarInt = MumbleVarInt.fromBuffer(data, offset);
        frameHeaderValue = headerVarInt.value;
        headerLength = headerVarInt.length;
        frameLength = frameHeaderValue & 0x1FFF;
        isLastFrame = (frameHeaderValue & 0x2000) != 0;
      }

      var newOffset = offset + headerLength + frameLength;
      payloadList.addAll(data.sublist(
        offset + headerLength,
        newOffset,
      ));

      offset = newOffset;
    }

    // there might be positional audio left over
    // positional audio is three floats (I'm guessing they are 32 bit floats)
    var bytes = ByteData.view(data.buffer, offset);
    if (bytes.lengthInBytes >= 24) {
      position[0] = bytes.getFloat64(0);
      position[1] = bytes.getFloat64(8);
      position[2] = bytes.getFloat64(16);
    } else if (bytes.lengthInBytes >= 12) {
      position[0] = bytes.getFloat32(0);
      position[1] = bytes.getFloat32(4);
      position[2] = bytes.getFloat32(8);
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
  String get debug => _udpPacket != null ? 'UDP PACKET' : asGeneratedMessage.toDebugString();

  Uint8List writeToBuffer() {
    if (type == MumbleMessage.UDPTunnel && _udpPacket != null) {
      var messagePayload = _udpPacket.writeToBuffer();
      var byteView = ByteData(6);
      // set the type
      byteView.setUint16(0, type);
      // set the length
      byteView.setUint32(2, messagePayload.lengthInBytes);
      return Uint8List.fromList([...messagePayload, ...byteView.buffer.asUint8List()]);
    } else
      return _generatedMessage.writeToBuffer();
  }

  MumbleMessage({this.type, this.data}) {
    _generatedMessage = parse(type, data);
  }

  MumbleMessage.wrap(this.type, this._generatedMessage) {
    data = _generatedMessage.writeToBuffer();
  }

  MumbleMessage.wrapUDP(MumbleUDPPacket packet) {
    type = MumbleMessage.UDPTunnel;
    _udpPacket = packet;
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
