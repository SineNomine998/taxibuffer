import 'package:mobile_app/features/account/account_state.dart';
import 'package:mobile_app/features/account/profile_gate_state.dart';
import 'package:mobile_app/features/auth/auth_gate_state.dart';
import 'package:mobile_app/features/compliance/terms_of_use/terms_gate_state.dart';

import '../features/compliance/privacy/privacy_gate_state.dart';

final authGateState = AuthGateState();
final privacyGateState = PrivacyGateState();
final termsGateState = TermsGateState();
final profileGateState = ProfileGateState();
final accountState = AccountState();
