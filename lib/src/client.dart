import './user.dart';
import './channel.dart';
import './connection.dart';

/**
 * @summary Mumble client API
 *
 * @description
 * Instances should be created with Mumble.connect().
 *
 * @param {MumbleConnection} connection - The underlying connection.
 */
class MumbleClient {
  List<MumbleUser> users = [];
  List<MumbleChannel> channels = [];

  bool ready = false;
  bool _gotServerSync = false;
  bool _gotInitialPing = false;

  MumbleConnection connection;
  MumbleChannel rootChannel;
  MumbleUser me;

  MumbleChannel channelById(int id) =>
      channels.firstWhere((c) => c.id == id, orElse: () => null);
  MumbleChannel channelByName(String n) =>
      channels.firstWhere((c) => c.name == n, orElse: () => null);
  MumbleChannel channelByPath(String s) =>
      channels.firstWhere((c) => c.path == s, orElse: () => null);
  MumbleUser userById(int id) =>
      users.firstWhere((u) => u.id == id, orElse: () => null);
  MumbleUser userBySession(int sessionId) =>
      users.firstWhere((u) => u.sessionId == sessionId, orElse: () => null);
  MumbleUser userByName(String s) =>
      users.firstWhere((u) => u.name == s, orElse: () => null);

  // TODO: come back here after building the channel, connection, and user objects.
  void checkReady() {
    if (!ready) ready = _gotServerSync && _gotInitialPing;
  }

  void getUsers() {}

  MumbleClient(this.connection);

  // NODE EVENT EMITTER METHODS
  // connection.once( 'ping', this._initialPing.bind( this ) );
  // connection.on( 'channelRemove', this._channelRemove.bind( this ) );
  // connection.on( 'userRemove', this._userRemove.bind( this ) );
  // connection.on( 'serverSync', this._serverSync.bind( this ) );
  // connection.on( 'userState', this._userState.bind( this ) );
  // connection.on( 'channelState', this._channelState.bind( this ) );
  // connection.on( 'permissionQuery', this._permissionQuery.bind( this ) );
  // connection.on( 'textMessage', this._textMessage.bind( this ) );

  /**
   * @summary Emitted when a text message is received.
   *
   * @event MumbleClient#message
   * @param {string} message - The text that was sent.
   * @param {User} user - The user who sent the message.
   * @param {string} scope
   *      The scope in which the message was received. 'user' if the message was
   *      sent directly to the current user or 'channel 'if it was received
   *      through the channel.
   */
}
