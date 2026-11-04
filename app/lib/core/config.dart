/// Build-time default API address. Override with
/// `--dart-define=API_URL=https://api.example.com`. The user can also change it
/// in Settings. 10.0.2.2 is the host machine as seen from the Android emulator.
const String kDefaultServerUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:4000');
