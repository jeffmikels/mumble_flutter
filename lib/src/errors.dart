///Thrown when receiving an audio packet from an unsupported codec
class CodecNotSupportedError implements Exception {
  String cause;
  CodecNotSupportedError(this.cause);
}

///Thrown when server reject the connection
class ConnectionRejectedError implements Exception {
  String cause;
  ConnectionRejectedError(this.cause);
}

///Thrown when receiving a packet not understood
class InvalidFormatError implements Exception {
  String cause;
  InvalidFormatError(this.cause);
}

///Thrown when asked for an unknown callback
class UnknownCallbackError implements Exception {
  String cause;
  UnknownCallbackError(this.cause);
}

///Thrown when using an unknown channel
class UnknownChannelError implements Exception {
  String cause;
  UnknownChannelError(this.cause);
}

///Thrown when trying to send an invalid audio pcm data
class InvalidSoundDataError implements Exception {
  String cause;
  InvalidSoundDataError(this.cause);
}

///Thrown when trying to decode an invalid varint
class InvalidVarInt implements Exception {
  String cause;
  InvalidVarInt(this.cause);
}

///Thrown when trying to send a message which is longer than allowed
class TextTooLongError implements Exception {
  String cause;
  TextTooLongError(this.cause);
}

///Thrown when trying to send a message or image which is longer than allowed
class ImageTooBigError implements Exception {
  String cause;
  ImageTooBigError(this.cause);
}

///Thrown when trying to send an opus audio frame
class FrameTooLongError implements Exception {
  String cause;
  FrameTooLongError(this.cause);
}
