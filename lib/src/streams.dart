import 'dart:async';
import 'dart:typed_data';
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

class MumbleAudioStream {
  static Uint8List emptyAudioFrame = Uint8List(
      MumbleConnection.samplesPerFrame * MumbleConnection.bytesPerSample);

  MumbleUser user;
  MumbleConnection connection;

  // sound data that we receive from the server
  StreamController<Uint8List> receivedController;
  Stream<Uint8List> get received => receivedController.stream;

  // sound data that we send to the server
  StreamController<Uint8List> sendingController;
  Stream<Uint8List> get sending => sendingController.stream;

  MumbleJitterBuffer receivedAudioBuffer;
  MumbleJitterBuffer sendingAudioBuffer;

  List<int> receivedAudioCache = [];
  List<int> sendingAudioCache = [];

  int frameSize;

  MumbleAudioStream() {
    receivedAudioBuffer = MumbleJitterBuffer();
    sendingAudioBuffer = MumbleJitterBuffer();

    receivedController = StreamController();
    sendingController = StreamController();

    // setup listener on the connection to listen to events that should get piped to this stream
    // if we get a 'voice' packet or a 'voice-user' packet for this user
    // add it to this user's audio stream
    frameSize =
        MumbleConnection.bytesPerSample * MumbleConnection.samplesPerFrame;
  }

  void dispose() {
    receivedController.close();
    sendingController.close();
  }

  // ensures that the stream controllers only get full sized frames
  void _streamFrames(List<int> data, StreamController controller) {
    while (data.length >= frameSize) {
      var frame = data.sublist(0, frameSize);
      data.removeRange(0, MumbleConnection.samplesPerFrame);
      controller.add(Uint8List.fromList(frame));
    }
  }

  void send(Uint8List bytes) {
    sendingAudioCache.addAll(bytes);
    _streamFrames(sendingAudioCache, sendingController);
  }

  void receive(Uint8List bytes) {
    receivedAudioCache.addAll(bytes);
    _streamFrames(receivedAudioCache, receivedController);

    // other implementations make sure to delete buffered data if there is more
    // than five seconds already in the buffer for some reason.
    // while (frames.length > 5000 / MumbleConnection.frameLength) frames.removeAt(0);
  }
}
