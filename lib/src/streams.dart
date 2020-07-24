import 'dart:async';
import 'dart:typed_data';
import 'package:mumble_flutter/mumble_flutter.dart';
import 'package:opus_flutter/opus_dart.dart';

import './connection.dart';
import './user.dart';

import 'package:audiostream/audiostream.dart';

class MumbleJitterPacket {
  int timestamp;
  Uint8List data;
}

class MumbleJitterBuffer {
  int maxLength = 20;
  StreamController<MumbleJitterPacket> _streamController;
  List<MumbleJitterPacket> buffer = [];

  Stream get stream => _streamController.stream;

  void add(MumbleJitterPacket packet) {
    buffer.add(packet);

    // sort by timestamp
    buffer.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // truncate buffer if too long
    var overflow = maxLength - buffer.length;
    if (overflow > 0) buffer.removeRange(0, overflow);
  }

  MumbleJitterPacket next() {
    var packet = buffer.removeAt(0);
    _streamController.add(packet);
    return packet;
  }

  MumbleJitterBuffer() : _streamController = StreamController();
}

class MumbleAudioController {
  static Uint8List emptyAudioFrame = Uint8List(MumbleConnection.samplesPerFrame * MumbleConnection.bitsPerSample);

  MumbleUser user;
  MumbleConnection connection;

  // pcm sound data that we receive from the server
  StreamController<Uint8List> receivedController;
  Stream<List<int>> get received => receivedController.stream;
  StreamSubscription audioOutputPipe;

  // sound data that we send to the server
  StreamController<Uint8List> sendingController;
  Stream<List<int>> get sending => sendingController.stream;

  StreamOpusDecoder opusDecoder;
  StreamOpusEncoder opusEncoder;

  MumbleJitterBuffer receivedAudioBuffer;
  MumbleJitterBuffer sendingAudioBuffer;

  List<int> receivedAudioCache = [];
  List<int> sendingAudioCache = [];

  int frameSize;
  int lastSentPacketNumber = 0;
  List<MumbleUDPPacket> packetStack = [];

  MumbleAudioController() {
    receivedAudioBuffer = MumbleJitterBuffer();
    sendingAudioBuffer = MumbleJitterBuffer();

    receivedController = StreamController();
    sendingController = StreamController();

    // setup listener on the connection to listen to events that should get piped to this stream
    // if we get a 'voice' packet or a 'voice-user' packet for this user
    // add it to this user's audio stream
    frameSize = MumbleConnection.bitsPerSample * MumbleConnection.samplesPerFrame * MumbleConnection.audioChannels;

    opusDecoder = StreamOpusDecoder.s16le(
      sampleRate: MumbleConnection.sampleRate,
      channels: MumbleConnection.audioChannels,
    );
    audioOutputPipe = receivedController.stream
        .transform(opusDecoder)
        .cast<Int16List>()
        .listen((pcmFrame) => Audiostream.write(pcmFrame.buffer));
  }

  void close() {
    receivedController.close();
    sendingController.close();
  }

  // ensures that the stream controllers only get full sized frames
  void _streamFrames(List<int> cache, StreamController controller) {
    while (cache.length >= frameSize) {
      var frame = cache.sublist(0, frameSize);
      cache.removeRange(0, MumbleConnection.samplesPerFrame);
      controller.add(frame);
    }
  }

  void send(Uint8List bytes) {
    sendingAudioCache.addAll(bytes);
    _streamFrames(sendingAudioCache, sendingController);
  }

  void receivePacket(MumbleUDPPacket packet) {
    var sequenceNumber = packet.sequence.value;

    // if this sequence number is in order, stream it!
    if (sequenceNumber == lastSentPacketNumber + 1) {
      receivedController.add(packet.payload);
      lastSentPacketNumber = sequenceNumber;
    } else {
      packetStack.add(packet);
      packetStack.sort((a, b) => a.sequence.value.compareTo(b.sequence.value));

      // only allow the packetstack to get three high
      if (packetStack.length > 3) {
        var localStack = packetStack.toList();
        packetStack.clear();
        for (var packet in localStack) {
          var seqNo = packet.sequence.value;
          if (seqNo > lastSentPacketNumber + 1) {
            receivedController.add(null);
          }
          receivedController.add(packet.payload);
          lastSentPacketNumber = seqNo;
        }
      }
    }
    // _streamFrames(receivedAudioCache, receivedController);

    // other implementations make sure to delete buffered data if there is more
    // than five seconds already in the buffer for some reason.
    // while (frames.length > 5000 / MumbleConnection.frameLength) frames.removeAt(0);
  }
}
