// Do-nothing web sign-in for the demo build (T-18 PX-2, Q-144). The demo never
// signs in with Google; registering this keeps google_sign_in's web half from
// loading Google's sign-in script at start.
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Registered in place of the real web plugin; loads nothing.
class GoogleSignInPlugin extends GoogleSignInPlatform {
  /// Called by Flutter's web plugin registrant.
  static void registerWith(Registrar registrar) {
    GoogleSignInPlatform.instance = GoogleSignInPlugin();
  }

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<void> initWithParams(SignInInitParameters params) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => null;

  @override
  Future<GoogleSignInUserData?> signIn() async => null;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async => GoogleSignInTokenData();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<void> clearAuthCache({required String token}) async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async => false;

  @override
  Future<bool> canAccessScopes(
    List<String> scopes, {
    String? accessToken,
  }) async => false;
}
