import 'dart:async';
import 'connection.dart';

/**
 * @summary Mumble connection manager
 *
 * @description
 * A connection tool to decouple connecting to the server
 * from the module itself.
 *
 * @constructor
 * @param {string} url - Mumble server address. mumble://username:password@host:port
 * @param {Object} options - TLS options.
 */
class MumbleConnectionManager {
  static String host = '';
  static int port = 64738;
  static String username = '';
  static String password = '';
  static String key = '';
  static String cert = '';

  static bool useTLS = true;
  static bool rejectUnauthorized = false;

  static MumbleConnection connection = MumbleConnection();
  static bool get connected => connection.connected;
  static Stream<String> get connectionStatus =>
      connection.connectionStatusStream;

  static Future connect({
    host,
    port,
    username,
    password,
    key,
    cert,
    useTLS,
    rejectUnauthorized,
  }) async {
    MumbleConnectionManager.host = host ?? MumbleConnectionManager.host;
    MumbleConnectionManager.port = port ?? MumbleConnectionManager.port;
    MumbleConnectionManager.username =
        username ?? MumbleConnectionManager.username;
    MumbleConnectionManager.password =
        password ?? MumbleConnectionManager.password;
    MumbleConnectionManager.key = key ?? MumbleConnectionManager.key;
    MumbleConnectionManager.cert = cert ?? MumbleConnectionManager.cert;
    MumbleConnectionManager.useTLS = useTLS ?? MumbleConnectionManager.useTLS;
    MumbleConnectionManager.rejectUnauthorized =
        rejectUnauthorized ?? MumbleConnectionManager.rejectUnauthorized;

    // initializing mumble connection
    // await connection?.disconnect();

    // open new socket and allow all self-signed certificates

    // wrap in our custom MumbleSocket
    connection.host = host;
    connection.port = port;
    connection.name = username;
    connection.password = password;
    return connection.connect();
  }
}
