import './user.dart';

enum ClientEventScope { user, channel }
enum ClientEventType {
  userConnect,
  channelCreate,
}

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
class MumbleClientEvent {
  ClientEventType type;
  ClientEventScope scope;
  MumbleUser user;
  dynamic data;
}
