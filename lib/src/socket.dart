import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import './messages.dart';

class MumbleSocketCompleter {
  int length;
  Completer<Uint8List> completer;
  Uint8List bytes;

  Future get future => completer.future;

  void complete() {
    if (!completer.isCompleted) {
      completer.complete(bytes);
    }
  }

  MumbleSocketCompleter(this.length) {
    bytes = Uint8List(length);
    completer = Completer<Uint8List>();
  }
}

class MumbleSocket {
  String host;
  int port;
  Future connected;

  List<int> buffer = [];
  SecureSocket socket;

  StreamSubscription<Uint8List> socketListener;

  StreamController statusController;
  StreamController<MumbleMessage> messageStreamController;

  bool closed = false;
  bool checkingBuffer = false;

  Stream<String> get status => statusController.stream;
  Stream<MumbleMessage> get messageStream => messageStreamController.stream;

  void _receiveData(Uint8List data) {
    // print('---received socket data:');
    // print(data);
    // print('----- ${DateTime.now()} ------');
    buffer.addAll(data);
    _checkBuffer();
  }

  void _checkBuffer() {
    if (checkingBuffer) return;
    checkingBuffer = true;
    // mumble messages carry a 6 byte prefix
    // two bytes contain the 'MumbleMessageType' as a Uint16BE
    // four bytes contain the Message Length as a UInt32BE
    while (buffer.length >= 6) {
      var byteView = ByteData.view(Uint8List.fromList(buffer).buffer);
      var type = byteView.getUint16(0, Endian.big);
      var length = byteView.getUint32(2, Endian.big);
      var totalLength = length + 6;
      if (byteView.lengthInBytes < totalLength) {
        // print('not enough data yet');
        break;
      }

      try {
        var data = Uint8List.fromList(buffer.sublist(6, totalLength));
        var mm = MumbleMessage(type: type, data: data);
        if (type != MumbleMessage.Ping) {
          // print(mm.toString());
        }
        messageStreamController.add(mm);
        buffer.removeRange(0, totalLength);
      } on InvalidProtocolBufferException {
        buffer.clear();
        // print('message decode failed');
      }
    }
    checkingBuffer = false;
  }

  MumbleSocket({this.host, this.port}) {
    statusController = StreamController();
    messageStreamController = StreamController();
    buffer.clear();

    connected = connect().timeout(Duration(seconds: 5), onTimeout: () {
      closed = true;
    });
  }

  Future connect() async {
    socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
    );

    // listener will accumulate data received on the socket forever
    // print('setting up socket listener');
    socketListener = socket.listen((Uint8List data) {
      _receiveData(data);
    });

    socket.done.then((_) => close());
  }

  Future close() async {
    if (closed) return;
    await socketListener?.cancel();
    await socket?.close();
    socket?.destroy();
    closed = true;
    print('socket closed');
  }

  // // notify the socket that we are waiting for data
  // // of a specific length
  // // NOTE: It might be better to use socket.take(length) to let Dart handle this
  // Future<Uint8List> read(int length) async {
  //   var c = MumbleSocketCompleter(length);
  //   completers.add(c);

  //   // it's possible that we got data from the server before we called
  //   // "read" so we use this opportunity to check the buffers
  //   // this step might be completely unnecessary
  //   _checkBuffer();
  //   return c.future;
  // }

  Future add(Uint8List buffer) async {
    // print('---sending socket data');
    // print(buffer);
    if (!closed) {
      await connected;
      socket.add(buffer);
    }
  }
}
