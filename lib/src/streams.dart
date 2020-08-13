import 'dart:async';
import 'dart:typed_data';
import 'package:mumble_flutter/mumble_flutter.dart';
import 'package:opus_flutter/opus_dart.dart';
import 'package:audiostream/audiostream.dart';
import 'package:audio_recorder_mc/audio_recorder_mc.dart';

import './connection.dart';
import './user.dart';

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
  static Uint8List emptyAudioFrame = Uint8List(
    MumbleConnection.samplesPerFrame * MumbleConnection.bitsPerSample,
  );

  MumbleUser user;
  MumbleConnection connection;

  // pcm sound data that we receive from the server
  StreamController<Uint8List> audioPlayerController;
  Stream<List<int>> get received => audioPlayerController.stream;
  StreamSubscription audioOutputPipe;

  // sound data that we get from the microphone and send to the server
  StreamController<List<int>> sendingController;
  Stream<List<int>> get sending => sendingController.stream;
  Stream encodedAudioStream;
  AudioRecorderMc audioRecorder;

  StreamOpusDecoder opusDecoder;
  StreamOpusEncoder<double> opusEncoder;

  SimpleOpusEncoder simpleEncoder;

  MumbleJitterBuffer receivedAudioBuffer;
  MumbleJitterBuffer sendingAudioBuffer;

  List<int> receivedAudioCache = [];
  List<double> sendingAudioCache = [];

  int lastSentPacketNumber = 0;
  List<MumbleUDPPacket> packetStack = [];

  MumbleAudioController() {
    receivedAudioBuffer = MumbleJitterBuffer();
    sendingAudioBuffer = MumbleJitterBuffer();

    audioPlayerController = StreamController();
    sendingController = StreamController();

    audioRecorder = AudioRecorderMc(sampleRate: MumbleConnection.sampleRate);
    PermissionsService().requestMicrophonePermission(onPermissionDenied: () {
      print('Audio permission has been denied');
    });

    // setup listener on the connection to listen to events that should get piped to this stream
    // if we get a 'voice' packet or a 'voice-user' packet for this user
    // add it to this user's audio stream

    // PREPARE THE STREAMS FOR LOCALLY RECORDED AUDIO
    simpleEncoder = SimpleOpusEncoder(
      sampleRate: MumbleConnection.sampleRate,
      channels: MumbleConnection.audioChannels,
      application: Application.voip,
    );
    // opusEncoder = StreamOpusEncoder<double>.float(
    //   // floatInput: true,
    //   frameTime: FrameTime.ms40,
    //   sampleRate: MumbleConnection.sampleRate,
    //   channels: MumbleConnection.audioChannels,
    //   application: Application.voip,
    //   fillUpLastFrame: true,
    // );
    // the connection should listen to this stream and send data to server

    // PREPARE THE STREAMS FOR AUDIO RECEIVED FROM SERVER
    opusDecoder = StreamOpusDecoder.s16le(
      sampleRate: MumbleConnection.sampleRate,
      channels: MumbleConnection.audioChannels,
    );
    audioOutputPipe =
        received.transform(opusDecoder).cast<Int16List>().listen((pcmFrame) => Audiostream.write(pcmFrame.buffer));
  }

  Future<Stream<Uint8List>> startRecorder() async {
    StreamController<Uint8List> tmpController;
    tmpController = StreamController<Uint8List>(onCancel: () {
      tmpController.close();
    });
    sendingAudioCache.clear();

    // will create a stream of Stream<List<double>> but typed as Stream<dynamic>
    var stream = await audioRecorder.startRecord;
    stream.listen((val) {
      for (var v in val) sendingAudioCache.add(v.toDouble());
      streamSendingFrames(tmpController);
    });
    return tmpController.stream;
  }

  void stopRecorder() {
    audioRecorder.stopRecord.then(print);
  }

  void streamSendingFrames(StreamController sink) {
    if (sink.isClosed) return;
    var offset = 0;
    // var opusFrameSize = 1920; // in samples
    var opusFrameSize = MumbleConnection.samplesPerFrame;
    var data = Float32List.fromList(sendingAudioCache);
    while ((data.length - offset) >= opusFrameSize) {
      var toEncode = data.sublist(offset, offset + opusFrameSize);
      try {
        var packet = simpleEncoder.encodeFloat(input: toEncode);
        if (!sink.isClosed) sink.add(packet);
        offset += opusFrameSize;
      } on OpusException catch (e) {
        print(e);
        break;
      }
    }
    sendingAudioCache = sendingAudioCache.sublist(offset);
  }

  void close() {
    audioOutputPipe?.cancel();
    audioPlayerController.close();
    sendingController.close();
  }

  /// takes a mumble udp packet decodes it and streams it to the player
  void receivePacket(MumbleUDPPacket packet) {
    var sequenceNumber = packet.sequence.value;

    // if this sequence number is in order, stream it!
    if (sequenceNumber == lastSentPacketNumber + 1) {
      audioPlayerController.add(packet.payload);
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
            audioPlayerController.add(null);
          }
          audioPlayerController.add(packet.payload);
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
