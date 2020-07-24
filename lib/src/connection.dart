import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:opus_flutter/opus_dart.dart';
import 'package:audiostream/audiostream.dart';

import './mumble.pb.dart' as mumbleProto;

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
  // STATIC CONFIGURATION
  static int sampleRate = 48000; // samples per second
  static int bitsPerSample = 16; // for 16 bit samples
  static int audioChannels = 2; // mumble sends mono audio
  static int samplesPerFrame = 480; // samples per frame
  static int frameMillis = 10; // milliseconds per frame
  static int bufferSeconds = 1; // milliseconds to buffer
  static int bufferSizeInBytes = (bufferSeconds * sampleRate * (bitsPerSample ~/ 8));

  // not sure if we need to track these bits of data
  mumbleProto.CryptSetup cryptSetup;
  mumbleProto.CodecVersion codecVersion;
  mumbleProto.ServerConfig serverConfig;
  mumbleProto.Ping lastPing;

  // connection variables
  String host;
  int port;
  String name;
  String password;

  MumbleUser user;
  Map<int, MumbleUser> userSessions = {};
  Map<int, MumbleChannel> channels = {};

  // audio handlers
  bool playerPlaying = false;
  MumbleAudioController audioController;
  StreamSubscription audioStreamListener;

  // StreamController<Uint8List> opusReceiver;
  SimpleOpusDecoder opusDecoder;
  SimpleOpusEncoder opusEncoder;
  List<int> debugAudioCache = [];
  List<MumbleUDPPacket> debugAudioPackets = [];

  // FlutterSoundRecorder recorder = FlutterSoundRecorder();

  // streams
  StreamController<String> connectionStatusController;
  Stream<String> get connectionStatusStream => connectionStatusController.stream;

  Map<int, StreamController<MumbleMessage>> messageControllers;

  // for listening to the socket messages
  StreamSubscription<MumbleMessage> messageStreamListener;

  // for determining when a command has completed
  Map<int, Completer> completers = {};

  // other variables
  List<String> tokens = [];
  Timer pingTimer;
  MumbleSocket socket;

  int voiceSequence = 0;
  bool authSent = false;
  bool initialized = false;
  bool closed = true;

  List<int> initsNeeded = [MumbleMessage.ServerSync, MumbleMessage.ServerConfig];

  bool get connected => initialized && !closed;
  bool get initPending => initsNeeded.isNotEmpty;

  MumbleMessage get encodedMumbleVersion {
    // 32 bit encoded version Integer

    var v = mumbleProto.Version.create();
    v.version = ((MUMBLE_VERSION[0] & 0xffff) << 16) | ((MUMBLE_VERSION[1] & 0xff) << 8) | (MUMBLE_VERSION[2] & 0xff);

    v.release = MUMBLE_VERSION.join('.');
    v.os = Platform.operatingSystem;
    v.osVersion = Platform.operatingSystemVersion;
    return MumbleMessage.wrap(MumbleMessage.Version, v);
  }

  /// constructor for the basic mumble connection
  MumbleConnection({
    this.host,
    this.port,
    this.socket,
    this.name,
    this.password,
    this.tokens,
  }) {
    tokens ??= [];

    connectionStatusController = StreamController<String>.broadcast();

    // create a stream for every kind of mumble message
    messageControllers = {};
    MumbleMessage.mapFromId.forEach((key, value) {
      messageControllers[key] = StreamController<MumbleMessage>.broadcast();
    });

    initAudio();
  }

  Future<void> initAudio() async {
    // setup opus
    initOpus();
    // opusDecoder = SimpleOpusDecoder(sampleRate: sampleRate, channels: audioChannels);
    // opusEncoder = SimpleOpusEncoder(
    //   sampleRate: sampleRate,
    //   channels: audioChannels,
    //   application: Application.voip,
    // );
    audioController = MumbleAudioController();

    await Audiostream.initialize(
      rate: sampleRate,
      channels: audioChannels,
      sampleBits: bitsPerSample,
      bufferSeconds: 0,
    );
  }

  Future connect() async {
    // clear previous connections
    userSessions.clear();
    channels.clear();
    if (!closed) disconnect();

    // initialize this connection
    socket = MumbleSocket(host: host, port: port);
    await socket.connected;
    if (socket?.closed != false) return;
    closed = false;

    // setup mumble message listener
    messageStreamListener = socket.messageStream.listen((MumbleMessage mm) {
      closed = false;
      handleMessage(mm);
    });

    sendMumbleVersion();
    authenticate();
    ping();
  }

  void ping() {
    pingTimer?.cancel();
    // print('ping!');

    // if this ping fails, disconnect
    sendMessage(
      MumbleMessage.wrap(MumbleMessage.Ping, mumbleProto.Ping.create()),
      useCompleter: true,
    ).timeout(Duration(seconds: PING_DURATION), onTimeout: () {
      print('ping failed to receive a response');
      disconnect();
    });

    if (!closed) {
      pingTimer = Timer(Duration(seconds: PING_DURATION), ping);
    }
  }

  /// call when you don't want to use this connection object ever again
  void close() {
    disconnect();
    Audiostream.close();
    audioController?.close();
    connectionStatusController?.close();
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

  /// processes all incoming Mumble messages
  void handleMessage(MumbleMessage mm) {
    if (mm.type != MumbleMessage.Ping) print(mm);

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
        var ss = gm as mumbleProto.ServerSync;
        user = userSessions[ss.session];
        print(ss.welcomeText);
        break;
      case MumbleMessage.ChannelRemove:
        break;
      case MumbleMessage.ChannelState:
        var cs = gm as mumbleProto.ChannelState;
        if (!channels.containsKey(cs.channelId))
          channels[cs.channelId] = MumbleChannel(cs);
        else
          channels[cs.channelId].updateFromProto(cs);
        break;
      case MumbleMessage.UserRemove:
        break;
      case MumbleMessage.UserState:
        var u = gm as mumbleProto.UserState;
        if (!userSessions.containsKey(u.session))
          userSessions[u.session] = MumbleUser(u);
        else
          userSessions[u.session].updateFromProto(u);
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
    // messageControllers[mm.type].add(mm);
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
    // print(packet.session);
    // print(packet.target);
    // print(packet.sequence);
    // the data might be a ping packet
    // or an encoded audio packet
    // ping packets need to be echoed back
    if (packet.type == MumbleUDPPacketType.ping) {
      sendMessage(mm);
    } else {
      // pipe this audio message to the audio handler
      audioController.receivePacket(packet);

      // to use the streaming opus decoder...
      // opusReceiver.add(packet.payload);

      // to use the one-off decoder
      // var pcm = opusDecoder.decode(input: packet.payload);
      // debugAudioCache.addAll(pcm);
      // Audiostream.write(pcm.buffer);
    }
  }

  // send a protocol message
  Future sendMessage(
    MumbleMessage message, {
    bool useCompleter = false,
  }) async {
    if (completers[message.type]?.isCompleted == false) {
      completers[message.type].completeError('new completer overrides previous');
    }

    if (socket.closed) throw SocketException.closed();

    // prepare mumble message packet
    // print('sending mumble message');
    // print('${MumbleMessage.mapFromId[message.type]} (#${message.type})');
    // print('${message.name} (#${message.type})');
    // print(message.debug);
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
      onTimeout: () {
        print('completer timeout: ${message.name} (#${message.type})');
        if (message.type == MumbleMessage.Ping) {
          disconnect();
        }
      },
    );
  }

  void sendMumbleVersion() {
    sendMessage(encodedMumbleVersion);
  }

  Future authenticate() async {
    var message = mumbleProto.Authenticate.create();
    message.username = name;
    message.password = password;
    message.opus = true;
    message.tokens.addAll(tokens ?? []);
    authSent = true;
    return sendMessage(MumbleMessage.wrap(MumbleMessage.Authenticate, message));
  }

  Future removeChannelListener(MumbleChannel channel) async {
    var msg = mumbleProto.UserState()
      ..session = user.sessionId
      ..actor = user.sessionId
      ..listeningChannelRemove.add(channel.id);
    print(msg);
    return sendMessage(
      MumbleMessage.wrap(
        MumbleMessage.UserState,
        msg,
      ),
    );
  }

  Future addChannelListener(MumbleChannel channel) async {
    var msg = mumbleProto.UserState()
      ..session = user.sessionId
      ..actor = user.sessionId
      ..listeningChannelAdd.add(channel.id);
    print(msg);
    return sendMessage(
      MumbleMessage.wrap(
        MumbleMessage.UserState,
        msg,
      ),
    );
  }

  Future joinChannel(MumbleChannel channel) async {
    return sendMessage(
      MumbleMessage.wrap(
        MumbleMessage.UserState,
        mumbleProto.UserState()
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
    var encoded = opusEncoder.encode(input: frame);

    // Send the raw packets.
    sendEncodedFrames(
      [encoded],
      codecId: MumbleCodecs.opus,
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
          throw FrameTooLongError('Audio frame too long! Opus max length ${0x1FFF} bytes.');
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
