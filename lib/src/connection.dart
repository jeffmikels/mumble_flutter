import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:opus_flutter/opus_dart.dart';
import 'package:audiostream/audiostream.dart';

import './mumble.pb.dart' as mpb;

import './channel.dart';
import './user.dart';
import './socket.dart';
import './streams.dart';
import './errors.dart';
import './messages.dart';
import './varint.dart';

const MUMBLE_VERSION = [1, 4, 0];
const PING_DURATION = 15;

enum ConnectionMessageType {
  ping,
  channelRemove,
  userRemove,
  serverSync,
  userState,
  channelState,
  permissionQuery,
  textMessage,
}

class MumbleCodecs {
  static const int celt = 0;
  static const int opus = 4;
}

class MumbleConnection {
  static int sampleRate = 48000; // samples per second
  static int bytesPerSample = 2; // for 16 bit samples
  static int frameSize = 480; // samples per frame
  static int frameMillis = 10; // milliseconds per frame
  static int bufferMillis = 1000; // milliseconds to buffer
  static int bufferSizeInBytes = sampleRate * bytesPerSample ~/ bufferMillis;

  String host;
  int port;

  mpb.CryptSetup cryptSetup;
  mpb.CodecVersion codecVersion;
  mpb.ServerConfig serverConfig;
  mpb.Ping lastPing;

  String name;
  String password;
  List<String> tokens = [];

  Timer pingTimer;

  MumbleSocket socket;

  int codecId = MumbleCodecs.opus;
  SimpleOpusDecoder decoder;
  SimpleOpusEncoder encoder;

  MumbleUser user;
  Map<int, MumbleUser> userSessions = {};
  Map<int, MumbleChannel> channels = {};

  bool playerPlaying = false;
  List<int> playerBuffer = [];
  List<int> voiceBuffer = [];

  // FlutterSoundRecorder recorder = FlutterSoundRecorder();

  StreamController<String> connectionStatusController;
  Stream<String> get connectionStatusStream =>
      connectionStatusController.stream;

  Map<int, StreamController<MumbleMessage>> messageControllers;
  MumbleAudioStream audioStream;

  // for listening to the socket messages
  StreamSubscription<MumbleMessage> messageStreamListener;

  // for determining when a command has completed
  Map<int, Completer> completers = {};

  int voiceSequence = 0;
  bool authSent = false;
  bool initialized = false;
  bool closed = true;

  List<int> initsNeeded = [
    MumbleMessage.ServerSync,
    MumbleMessage.ServerConfig
  ];

  bool get connected => initialized && !closed;
  bool get initPending => initsNeeded.isNotEmpty;

  MumbleMessage get encodedMumbleVersion {
    // 32 bit encoded version Integer

    var v = mpb.Version.create();
    v.version = ((MUMBLE_VERSION[0] & 0xffff) << 16) |
        ((MUMBLE_VERSION[1] & 0xff) << 8) |
        (MUMBLE_VERSION[2] & 0xff);

    v.release = MUMBLE_VERSION.join('.');
    // v.os = Platform.operatingSystem;
    v.os = 'X11';
    // v.osVersion = Platform.operatingSystemVersion;
    v.osVersion = 'Arch Linux';
    return MumbleMessage.wrap(MumbleMessage.Version, v);
  }

  MumbleConnection({
    this.host,
    this.port,
    this.socket,
    this.name,
    this.password,
    this.tokens,
  }) {
    initOpus();
    decoder = SimpleOpusDecoder(sampleRate: sampleRate, channels: 1);
    encoder = SimpleOpusEncoder(
      sampleRate: sampleRate,
      channels: 1,
      application: Application.voip,
    );
    tokens ??= [];
    audioStream = MumbleAudioStream();
    connectionStatusController = StreamController<String>.broadcast();

    // create a stream for every kind of mumble message
    messageControllers = {};
    MumbleMessage.mapFromId.forEach((key, value) {
      messageControllers[key] = StreamController<MumbleMessage>.broadcast();
    });

    initAudio();
  }

  Future initAudio() async {
    await Audiostream.initialize(48000);
    // Initialization state 1 means 'isInitializing'
    // if (player.isInited.index != 1)
    //   await player.openAudioSession(
    //     focus: AudioFocus.requestFocusTransient,
    //     category: SessionCategory.playback,
    //     mode: SessionMode.modeDefault,
    //     audioFlags: outputToSpeaker,
    //     device: AudioDevice.speaker,
    //   );
  }

  Future connect() async {
    userSessions.clear();
    channels.clear();
    if (!closed) disconnect();
    socket = MumbleSocket(host: host, port: port);
    await socket.connected;
    if (socket?.closed != false) return;
    closed = false;

    messageStreamListener = socket.messageStream.listen((MumbleMessage mm) {
      closed = false;
      handleMessage(mm);
    });

    initialize();
    pingTimer = Timer(Duration(seconds: 2), ping);
    return authenticate();
  }

  void ping() {
    pingTimer?.cancel();

    print('ping!');

    // if this ping fails, disconnect
    sendMessage(
      MumbleMessage.wrap(MumbleMessage.Ping, mpb.Ping.create()),
      useCompleter: true,
    ).timeout(Duration(seconds: PING_DURATION), onTimeout: () {
      print('ping failed to receive a response');
      disconnect();
    });

    if (!closed) {
      pingTimer = Timer(Duration(seconds: PING_DURATION), ping);
    }
  }

  void dispose() async {
    disconnect();
    // player.closeAudioSession();
    Audiostream.close();
    connectionStatusController.close();
  }

  void disconnect() {
    connectionStatusController.add('disconnecting');
    pingTimer?.cancel();
    messageStreamListener?.cancel();
    completers.forEach((key, value) {
      if (!value.isCompleted) value.complete();
    });
    socket?.close();
    connectionStatusController.add('disconnected');
    closed = true;
  }

  void handleMessage(MumbleMessage mm) {
    connectionStatusController.add('mumble message received: $mm');
    if (completers[mm.type]?.isCompleted == false) {
      completers[mm.type].complete();
    }

    // check for two initialization messages
    if (initPending) {
      initsNeeded.remove(mm.type);
      if (!initPending) {
        connectionStatusController.add('mumble connection initialized');
      }
    }

    // pass on all mumble messages for now
    messageControllers[mm.type].add(mm);

    // make sure to handle some messages internally for this "connection"
    // and pass other messages out to the world
    var gm = mm.asGeneratedMessage;
    switch (mm.type) {
      case MumbleMessage.CryptSetup:
        cryptSetup = gm;
        break;
      case MumbleMessage.CodecVersion:
        codecVersion = gm;
        break;
      case MumbleMessage.Ping:
        lastPing = gm;
        break;
      case MumbleMessage.Version:
        break;
      case MumbleMessage.UDPTunnel:
        handleUDPPacket(mm);
        break;
      case MumbleMessage.Authenticate:
        break;
      case MumbleMessage.Reject:
        break;
      case MumbleMessage.ServerSync:
        var ss = mm.asGeneratedMessage as mpb.ServerSync;
        user = userSessions[ss.session];
        print(ss.welcomeText);
        break;
      case MumbleMessage.ChannelRemove:
        break;
      case MumbleMessage.ChannelState:
        var cs = mm.asGeneratedMessage as mpb.ChannelState;
        channels[cs.channelId] = MumbleChannel(cs);
        break;
      case MumbleMessage.UserRemove:
        break;
      case MumbleMessage.UserState:
        var u = mm.asGeneratedMessage as mpb.UserState;
        userSessions[u.session] = MumbleUser(u);
        break;
      case MumbleMessage.BanList:
        break;
      case MumbleMessage.TextMessage:
        break;
      case MumbleMessage.PermissionDenied:
        break;
      case MumbleMessage.ACL:
        break;
      case MumbleMessage.QueryUsers:
        break;
      case MumbleMessage.ContextActionModify:
        break;
      case MumbleMessage.ContextAction:
        break;
      case MumbleMessage.UserList:
        break;
      case MumbleMessage.VoiceTarget:
        break;
      case MumbleMessage.PermissionQuery:
        break;
      case MumbleMessage.UserStats:
        break;
      case MumbleMessage.RequestBlob:
        break;
      case MumbleMessage.ServerConfig:
        serverConfig = gm;
        break;
      case MumbleMessage.SuggestConfig:
        break;
    }
  }

  /**
   * Handle incoming voice data
   *
   * @private
   *
   * @param {Object} data Voice packet
   **/
  void handleUDPPacket(MumbleMessage mm) {
    var packet = mm.asUDPPacket;
    // the data might be a ping packet
    // or an encoded audio packet
    // ping packets need to be echoed back

    if (packet.type == MumbleUDPPacketType.ping) {
      sendMessage(mm);
    } else {
      playerBuffer.addAll(mm.asUDPPacket.payload);
      // var pcm = decoder.decode(input: mm.asUDPPacket.payload);
      // player.startPlayer(
      //   fromDataBuffer: Uint8List.fromList(pcm),
      //   codec: Codec.pcm16,
      // );
      // print(pcm);
    }
    checkPlayer();
  }

  void checkPlayer() {
    // if (player.isPlaying) return;
    // playerPlaying = true;
    var buffers = playerBuffer.length ~/ bufferSizeInBytes;
    if (buffers > 0) {
      var bufLen = buffers * bufferSizeInBytes;
      var tmpBuf = Uint8List.fromList(playerBuffer.sublist(0, bufLen));
      playerBuffer.removeRange(0, bufLen);
      print('playing $buffers frames');
      // player.startPlayer(
      //   fromDataBuffer: tmpBuf,
      //   codec: Codec.opusOGG,
      // );
      Audiostream.write(tmpBuf);
    }
  }

  // send a protocol message
  Future sendMessage(
    MumbleMessage message, {
    bool useCompleter = false,
  }) async {
    if (completers[message.type]?.isCompleted == false) {
      completers[message.type]
          .completeError('new completer overrides previous');
    }

    if (socket.closed) throw SocketException.closed();

    // prepare mumble message packet
    print('sending mumble message');
    // print('${MumbleMessage.mapFromId[message.type]} (#${message.type})');
    print('${message.name} (#${message.type})');
    print(message.debug);
    var payload = message.writeToBuffer();

    // prepare mumble message prefix
    var prefix = Uint8List(6);
    var view = ByteData.view(prefix.buffer, 0);
    view.setUint16(0, message.type, Endian.big);
    view.setUint32(2, payload.lengthInBytes, Endian.big);

    var packet = Uint8List.fromList([...prefix, ...payload]);

    // prepare completer
    Future retval;
    if (useCompleter) {
      completers[message.type] = Completer();
      retval = completers[message.type].future;
    } else {
      retval = Future.value();
    }

    socket.add(packet);

    return retval.timeout(
      Duration(seconds: 2),
      onTimeout: () =>
          print('completer timeout: ${message.name} (#${message.type})'),
    );
  }

  void initialize() {
    sendMessage(encodedMumbleVersion);
  }

  Future authenticate() async {
    var message = mpb.Authenticate.create();
    message.username = name;
    message.password = password;
    message.opus = true;
    message.tokens.addAll(tokens ?? []);
    authSent = true;
    return sendMessage(MumbleMessage.wrap(MumbleMessage.Authenticate, message));
  }

  Future joinChannel(MumbleChannel channel) async {
    return sendMessage(
      MumbleMessage.wrap(
        MumbleMessage.UserState,
        mpb.UserState()
          ..session = user.sessionId
          ..actor = user.sessionId
          ..channelId = channel.id,
      ),
    );
  }

  /// * @param {Buffer} chunk - PCM audio data in 16bit unsigned LE format.
  /// * @param {number} whisperTarget - Optional whisper target ID.
  void sendVoiceFrame(
    Int16List frame, {
    int whisperId,
    int forcedVoiceSequence,
  }) {
    if (!initialized) return;

    // If frame is empty, we got nothing to send.
    if (frame.isEmpty) return;

    // Grab the encoded buffer.
    var encoded = encoder.encode(input: frame);

    // Send the raw packets.
    sendEncodedFrames(
      [encoded],
      codecId: codecId,
      whisperTargetId: whisperId,
      forcedVoiceSequence: forcedVoiceSequence,
    );

    // return framesSent;
  }

/**
 * @summary Send encoded voice frames.
 *
 * @param {Buffer} packets - Encoded frames.
 * @param {number} codec - Audio codec number for the packets.
 * @param {number} [whisperTargetId] - Optional whisper target ID. Defaults to null.
 * @param {number} [voiceSequence] -
 *      Voice packet sequence number. Required when multiplexing several audio
 *      streams to different users.
 *
 * @returns {number} Amount of frames sent.
 **/
  int sendEncodedFrames(
    List<Uint8List> packets, {
    int codecId = MumbleCodecs.opus,
    int whisperTargetId = 0,
    int forcedVoiceSequence,
  }) {
    if (forcedVoiceSequence != null) voiceSequence = forcedVoiceSequence;
    var type = codecId == MumbleCodecs.opus ? 4 : 0;
    var target = whisperTargetId ?? 0; // Default to talking
    var typetarget = type << 5 | target;
    var sequenceVarint = MumbleVarInt.fromInt(voiceSequence);

    // Client side voice header.
    var voiceHeader = Uint8List.fromList([typetarget, ...sequenceVarint.bytes]);

    // Gather the audio frames.
    var frames = [];
    var framesLength = 0;
    for (var i = 0; i < packets.length; i++) {
      var packet = packets[i];

      // Construct the header based on the codec type.
      var header;
      if (codecId == MumbleCodecs.opus) {
        // Opus header
        if (packet.length > 0x1FFF) {
          throw FrameTooLongError(
              'Audio frame too long! Opus max length ${0x1FFF} bytes.');
        }

        // TODO: Figure out how to support terminator bit.
        var headerValue = packet.length;
        header = MumbleVarInt.fromInt(headerValue).bytes;
      } else {
        // Celt
        if (packet.length > 127) {
          throw FrameTooLongError(
            'Audio frame too long! Celt max length 127 bytes.',
          );
        }

        // If this isn't the last frame, set the terminator bit as 1.
        // This signals there are more audio frames after this one.
        var terminator = (i == packets.length - 1);
        header = Uint8List.fromList([packet.length | (terminator ? 0 : 0x10)]);
      }

      var frame = Uint8List.fromList([...header, ...packet]);

      // Push the frame to the list.
      frames.add(frame);
      voiceSequence++;
    }

    // UDP tunnel prefix.
    var prefix = Uint8List(6);
    var bytedata = ByteData.view(prefix.buffer);
    bytedata.setUint16(0, MumbleMessage.UDPTunnel, Endian.big);
    bytedata.setUint32(2, voiceHeader.length + framesLength, Endian.big);
    socket.add(prefix);

    // Write the voice header
    socket.add(voiceHeader);

    // Write the frames.
    for (var f in frames) {
      socket.add(frames[f]);
    }

    return frames.length;
  }
}
