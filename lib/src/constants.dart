import 'dart:io' show Platform;

var DART_MUMBLE_VERSION = '1.1';

// ============================================================================
// Tunable parameters
// ============================================================================
var DART_MUMBLE_CONNECTION_RETRY_INTERVAL = 10; // in sec
var DART_MUMBLE_AUDIO_PER_PACKET = 20 / 1000; // size of one audio packet in sec
var DART_MUMBLE_BANDWIDTH = 50 * 1000; // total outgoing bitrate in bit/seconds
var DART_MUMBLE_LOOP_RATE =
    0.01; // pause done between two iteration of the main loop of the mumble thread, in sec
// should be small enough to manage the audio output, so smaller than var DART_MUMBLE_AUDIO_PER_PACKET

// ============================================================================
// Constants
// ============================================================================
var DART_MUMBLE_PROTOCOL_VERSION = {1, 2, 4};
var DART_MUMBLE_VERSION_STRING = 'DartMumble $DART_MUMBLE_VERSION';
var DART_MUMBLE_OS_STRING = 'DartMumble $DART_MUMBLE_VERSION';
var DART_MUMBLE_OS_VERSION_STRING =
    'Dart ${Platform.version} - ${Platform.operatingSystem} ${Platform.operatingSystemVersion}'; // "Python %s - %s %s" % (sys.version, platform.system(), platform.release());

var DART_MUMBLE_PING_DELAY = 10; // interval between 2 pings in sec

var DART_MUMBLE_SAMPLERATE = 48000; // in hz

var DART_MUMBLE_SEQUENCE_DURATION = 10 / 1000; // in sec
var DART_MUMBLE_SEQUENCE_RESET_INTERVAL = 5; // in sec
var DART_MUMBLE_READ_BUFFER_SIZE =
    4096; // how many bytes to read at a time from the control socket, in bytes

// client connection state
// enum DartMumbleConnectionState {notConnected, authenticating, connected, failed}
var DART_MUMBLE_CONN_STATE_NOT_CONNECTED = 0;
var DART_MUMBLE_CONN_STATE_AUTHENTICATING = 1;
var DART_MUMBLE_CONN_STATE_CONNECTED = 2;
var DART_MUMBLE_CONN_STATE_FAILED = 3;

// Mumble control messages types
var DART_MUMBLE_MSG_TYPES_VERSION = 0;
var DART_MUMBLE_MSG_TYPES_UDPTUNNEL = 1;
var DART_MUMBLE_MSG_TYPES_AUTHENTICATE = 2;
var DART_MUMBLE_MSG_TYPES_PING = 3;
var DART_MUMBLE_MSG_TYPES_REJECT = 4;
var DART_MUMBLE_MSG_TYPES_SERVERSYNC = 5;
var DART_MUMBLE_MSG_TYPES_CHANNELREMOVE = 6;
var DART_MUMBLE_MSG_TYPES_CHANNELSTATE = 7;
var DART_MUMBLE_MSG_TYPES_USERREMOVE = 8;
var DART_MUMBLE_MSG_TYPES_USERSTATE = 9;
var DART_MUMBLE_MSG_TYPES_BANLIST = 10;
var DART_MUMBLE_MSG_TYPES_TEXTMESSAGE = 11;
var DART_MUMBLE_MSG_TYPES_PERMISSIONDENIED = 12;
var DART_MUMBLE_MSG_TYPES_ACL = 13;
var DART_MUMBLE_MSG_TYPES_QUERYUSERS = 14;
var DART_MUMBLE_MSG_TYPES_CRYPTSETUP = 15;
var DART_MUMBLE_MSG_TYPES_CONTEXTACTIONMODIFY = 16;
var DART_MUMBLE_MSG_TYPES_CONTEXTACTION = 17;
var DART_MUMBLE_MSG_TYPES_USERLIST = 18;
var DART_MUMBLE_MSG_TYPES_VOICETARGET = 19;
var DART_MUMBLE_MSG_TYPES_PERMISSIONQUERY = 20;
var DART_MUMBLE_MSG_TYPES_CODECVERSION = 21;
var DART_MUMBLE_MSG_TYPES_USERSTATS = 22;
var DART_MUMBLE_MSG_TYPES_REQUESTBLOB = 23;
var DART_MUMBLE_MSG_TYPES_SERVERCONFIG = 24;

// callbacks names
var DART_MUMBLE_CLBK_CONNECTED = 'connected';
var DART_MUMBLE_CLBK_DISCONNECTED = 'disconnected';
var DART_MUMBLE_CLBK_CHANNELCREATED = 'channel_created';
var DART_MUMBLE_CLBK_CHANNELUPDATED = 'channel_updated';
var DART_MUMBLE_CLBK_CHANNELREMOVED = 'channel_remove';
var DART_MUMBLE_CLBK_USERCREATED = 'user_created';
var DART_MUMBLE_CLBK_USERUPDATED = 'user_updated';
var DART_MUMBLE_CLBK_USERREMOVED = 'user_remove';
var DART_MUMBLE_CLBK_SOUNDRECEIVED = 'sound_received';
var DART_MUMBLE_CLBK_TEXTMESSAGERECEIVED = 'text_received';
var DART_MUMBLE_CLBK_CONTEXTACTIONRECEIVED = 'contextAction_received';

// audio types
var DART_MUMBLE_AUDIO_TYPE_CELT_ALPHA = 0;
var DART_MUMBLE_AUDIO_TYPE_PING = 1;
var DART_MUMBLE_AUDIO_TYPE_SPEEX = 2;
var DART_MUMBLE_AUDIO_TYPE_CELT_BETA = 3;
var DART_MUMBLE_AUDIO_TYPE_OPUS = 4;
var DART_MUMBLE_AUDIO_TYPE_OPUS_PROFILE = 'voip';

// command names
var DART_MUMBLE_CMD_MOVE = 'move';
var DART_MUMBLE_CMD_MODUSERSTATE = 'update_user';
var DART_MUMBLE_CMD_TEXTMESSAGE = 'text_message';
var DART_MUMBLE_CMD_TEXTPRIVATEMESSAGE = 'text_private_message';
