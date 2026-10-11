import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import 'app_user.dart';
import 'auth_exception.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({fb.FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<AppUser> signInWithGoogle() => _guard(() async {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw AuthCancelledException();
        }
        final googleAuth = await googleUser.authentication;
        final credential = fb.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final result = await _auth.signInWithCredential(credential);
        return _requireUser(result.user);
      });

  @override
  Future<AppUser> signInWithEmail({required String email, required String password}) =>
      _guard(() async {
        final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
        return _requireUser(result.user);
      });

  @override
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) =>
      _guard(() async {
        final result =
            await _auth.createUserWithEmailAndPassword(email: email, password: password);
        final user = result.user!;
        await user.updateDisplayName(nickname);
        await user.reload();
        return _requireUser(_auth.currentUser);
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<String?> currentIdToken() async => _auth.currentUser?.getIdToken();

  /// Firebase 오류를 화면이 아는 [AuthException]으로 바꿔 던진다. 취소(`AuthCancelledException`)는 그대로 통과한다.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseAuthCode(e.code));
    }
  }

  AppUser _requireUser(fb.User? user) {
    final appUser = _toAppUser(user);
    if (appUser == null) throw const AuthException(AuthErrorCode.unknown);
    return appUser;
  }

  AppUser? _toAppUser(fb.User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      email: user.email,
    );
  }
}

class AuthCancelledException implements Exception {
  @override
  String toString() => '로그인이 취소되었습니다';
}
