import 'dart:typed_data';

import './errors.dart';

/// {MumbleVarInt}s are different from protobuf varints
/// They are described online here:
/// https://mumble-protocol.readthedocs.io/en/latest/voice_data.html#variable-length-integer-encoding
class MumbleVarIntPrefix {
  static const int u7 = 0; // return n
  static const int u14 = 0x80; // 0x80 → 1000 0000
  static const int u21 = 0xC0; // 0xC0 → 1100 0000
  static const int u28 = 0xE0; // 0xE0 → 1110 0000
  static const int u32 = 0xF0; // 0xF0 → 1111 0000
  static const int s64 = 0xF4; // 0xF4 → 1111 0100

  // negative recursive varint
  static const int nrv = 0xF8; // 0xF8 → 1111 1000

  // byte-inverted negative two bit number
  static const int i2 = 0xFC; // 0xFC → 1111 1100

  // also store the bitmasks here
  static const int u7mask = 0x7F;
  static const int u14mask = 0x3F;
  static const int u21mask = 0x1F;
  static const int u28mask = 0x0F;
  static const int i2mask = 0x03;
}

// see reference implementation here:
// https://github.com/mumble-voip/mumble/blob/master/src/PacketDataStream.h
class MumbleVarInt {
  Uint8List bytes;

  static int getPrefix(int b) {
    if (b & MumbleVarIntPrefix.u14 == MumbleVarIntPrefix.u7) {
      return MumbleVarIntPrefix.u7;
    }
    if (b & MumbleVarIntPrefix.u21 == MumbleVarIntPrefix.u14) {
      return MumbleVarIntPrefix.u14;
    }
    if (b & MumbleVarIntPrefix.u28 == MumbleVarIntPrefix.u21) {
      return MumbleVarIntPrefix.u21;
    }
    if (b & MumbleVarIntPrefix.u32 == MumbleVarIntPrefix.u28) {
      return MumbleVarIntPrefix.u28;
    }
    if (b & MumbleVarIntPrefix.u32 == MumbleVarIntPrefix.u28) {
      return MumbleVarIntPrefix.u28;
    }
    return b & MumbleVarIntPrefix.i2;
  }

  String toString() {
    return '<MumbleVarInt> $value ($bytes)';
  }

  int get length => bytes.lengthInBytes;
  int get prefix => getPrefix(bytes[0]);

  int get value {
    var i;
    var b = bytes;
    var v = b[0];

    switch (prefix) {
      case MumbleVarIntPrefix.u7:
        i = b[0] & MumbleVarIntPrefix.u7mask;
        break;
      case MumbleVarIntPrefix.u14:
        i = b[0] & MumbleVarIntPrefix.u14mask << 8 | b[1];
        break;
      case MumbleVarIntPrefix.u21:
        i = b[0] & MumbleVarIntPrefix.u21mask << 16 | b[1] << 8 | b[2];
        break;
      case MumbleVarIntPrefix.u28:
        i = b[0] & MumbleVarIntPrefix.u28mask << 24 | b[1] << 16 | b[2] << 8 | b[3];
        break;
      case MumbleVarIntPrefix.u32:
        i = b[1] << 24 | b[2] << 16 | b[3] << 8 | b[4];
        break;
      case MumbleVarIntPrefix.s64:
        i = b[1] << 24 | b[2] << 16 | b[3] << 8 | b[4];
        i = i << 32;
        i |= b[5] << 24 | b[6] << 16 | b[7] << 8 | b[8];
        break;
      case MumbleVarIntPrefix.i2:
        i = ~(b[0] & MumbleVarIntPrefix.i2mask);
        break;
      case MumbleVarIntPrefix.nrv:
        i = ~MumbleVarInt.fromBuffer(b, 1).value;
        break;
      default:
        throw InvalidVarInt('invalid var int encoding');
    }
    return i;
  }

  MumbleVarInt.fromInt([int i = 0]) {
    var arr = <int>[];

    if (i < 0) {
      i = ~i;
      // can we encode this with two bits?
      if (i <= 0x3) {
        bytes = Uint8List.fromList([MumbleVarIntPrefix.i2 | i]);
        return;
      }
      // store as negative recursive varint, and add that prefix
      arr.add(MumbleVarIntPrefix.nrv);
    }

    // this compact code is preserved from node-mumble
    // it's so pretty, I didn't want to change it up with all
    // my prefix class constants
    if (i < 0x80) {
      arr.add(i);
    } else if (i < 0x4000) {
      arr.add((i >> 8) | 0x80);
      arr.add(i & 0xFF);
    } else if (i < 0x200000) {
      arr.add((i >> 16) | 0xC0);
      arr.add((i >> 8) & 0xFF);
      arr.add(i & 0xFF);
    } else if (i < 0x10000000) {
      arr.add((i >> 24) | 0xE0);
      arr.add((i >> 16) & 0xFF);
      arr.add((i >> 8) & 0xFF);
      arr.add(i & 0xFF);
    } else if (i < 0x100000000) {
      arr.add(0xF0);
      arr.add((i >> 24) & 0xFF);
      arr.add((i >> 16) & 0xFF);
      arr.add((i >> 8) & 0xFF);
      arr.add(i & 0xFF);
    }

    bytes = Uint8List.fromList(arr);
  }

  MumbleVarInt.fromBuffer(Uint8List data, [int offset = 0]) {
    var prefix = getPrefix(data[offset]);
    var len = 0;
    switch (prefix) {
      case MumbleVarIntPrefix.u7:
        len = 1;
        break;
      case MumbleVarIntPrefix.u14:
        len = 2;
        break;
      case MumbleVarIntPrefix.u21:
        len = 3;
        break;
      case MumbleVarIntPrefix.u28:
        len = 4;
        break;
      case MumbleVarIntPrefix.u32:
        len = 5;
        break;
      case MumbleVarIntPrefix.s64:
        len = 9;
        break;
      case MumbleVarIntPrefix.i2:
        len = 1;
        break;
      case MumbleVarIntPrefix.nrv:
        len = MumbleVarInt.fromBuffer(data, offset + 1).length + 1;
        break;
      default:
        throw InvalidVarInt('invalid var int encoding');
    }
    if (len == 0) {
      throw InvalidVarInt('invalid var int encoding');
    } else {
      bytes = data.sublist(offset, offset + len);
    }
  }

  MumbleVarInt(this.bytes);
}

/** THIS IS THE COOLEST METHOD FOR DOING PROTOBUF VARINT DECODING
 *int get value {
    // strip the major bit from each byte
    // reverse the order, concatenate, and add
    var sum = 0;
    var shifter = 0;
    for (var b in bytes) {
      // concatenate the bytes with proper shifting
      sum |= (b & 0x7f) << shifter;
      shifter += 7;
    }
    // varints use twos complement encoding
    // dart probably does also, so I'm guessing
    // all of this is fine.
    return sum;
  }
*/

/** OLD CODE FOR CONVERTING VARINT TO INT
 *  // method... check for the prefix type
    // return the value of the bits indicated by x
    if ((v & 0x80) == 0x00) {
      // 0x80 → 1000 0000
      // major bit is clear
      // structure was 0xxx xxxx
      // 7 bit integer
      // 0x7F → 0111 1111
      i = (v & 0x7F);
    } else if ((v & 0xC0) == 0x80) {
      // 0xC0 → 1100 0000
      // 0x3F → 0011 1111
      // major bit is set and the next is not
      // structure is 10xx xxxx  xxxx xxxx
      // 14 bit integer
      i = (v & 0x3F) << 8 | b[1];
    } else if ((v & 0xE0) == 0xC0) {
      // 0xE0 → 1110 0000
      // 0xC0 → 1100 0000
      // 0x1F → 0001 1111
      // first two bits are set, third is not
      i = (v & 0x1F) << 16 | b[1] << 8 | b[2];
    } else if ((v & 0xF0) == 0xE0) {
      // 0xF0 → 1111 0000
      // 0xE0 → 1110 0000
      // 0x0F → 0000 1111
      // first three bits are set, fourth is not
      i = (v & 0x0F) << 24 | b[1] << 16 | b[2] << 8 | b[3];
    } else if ((v & 0xF0) == 0xF0) {
      // first four bits are set
      // prefix is 1111 xxxx  xxxx xxxx ...
      // 0xFC → 1111 1100

      switch (v & 0xFC) {
        case 0xF0:
          // 0xF0 → 1111 0000
          // prefix is 1111 00__
          // next four bytes are a straight 32 bit unsigned int
          i = b[1] << 24 | b[2] << 16 | b[3] << 8 | b[4];
          break;
        case 0xF4:
          // 0xF4 → 1111 0100
          // prefix is 1111 01__
          // next 8 bytes are a signed 64 bit int
          i = b[1] << 24 | b[2] << 16 | b[3] << 8 | b[4];
          i = i << 32 | b[5] << 24 | b[6] << 16 | b[7] << 8 | b[8];
          break;
        case 0xF8:
          // 0xF8 → 1111 1000
          // negative recursive varint... basically, it's a varint
          // inside a varint, but all the bits need to be flipped
          i = MumbleVarInt.fromBuffer(b, 1).value;
          i = ~i;
          break;
        case 0xFC:
          // 0xFC → 1111 1100
          // 0x03 → 0000 0011
          // byte-inverted two bit negative number
          i = v & 0x03;
          i = ~i;
          break;
        default:
          throw InvalidVarInt('Unknown varint');
      }
*/
