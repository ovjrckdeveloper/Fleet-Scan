import 'package:flutter/material.dart';
import '../services/erp_session.dart';

class ErpLogin extends StatefulWidget {
  final ErpSession session;
  final String? errorMessage;
  const ErpLogin({super.key, required this.session, this.errorMessage});
  @override
  State<ErpLogin> createState() => _ErpLoginState();
}

class _ErpLoginState extends State<ErpLogin> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      if (widget.session.needsVerification) {
        await widget.session.verifyCode(_code.text);
      } else {
        await widget.session.login(_username.text, _password.text);
      }
    } on ErpAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in could not be completed. Please try again.');
    } finally {
      if (mounted) {
        _password.clear();
        _code.clear();
        setState(() => _busy = false);
      }
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0xFFE3E8EE)),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF80858D), fontSize: 18),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF8792A2)),
      prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 58),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFF0052FF), width: 1.5)),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFFD92D20))),
      focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFFD92D20), width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verification = widget.session.needsVerification;
    final error = _error ?? widget.errorMessage;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Inter', bodyColor: const Color(0xFF0A2540)),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0052FF), brightness: Brightness.light),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final top = constraints.maxHeight < 600 ? 32.0 : constraints.maxHeight * 0.23;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, top, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(child: Image.asset('assets/tubig_connect_logo.png',
                          width: 100, height: 100, fit: BoxFit.contain,
                          semanticLabel: 'TubigConnect, General Santos City Water District')),
                        const SizedBox(height: 24),
                        Text(verification ? 'Verify your sign-in' : 'Login to Fleet Scan',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 26,
                            fontWeight: FontWeight.w700, color: Color(0xFF0A2540),
                            letterSpacing: -0.7, height: 1.2)),
                        const SizedBox(height: 40),
                        if (!verification) ...[
                          Semantics(
                            label: 'Email or username',
                            child: TextFormField(
                              key: const ValueKey('login-username'),
                              controller: _username,
                              enabled: !_busy,
                              decoration: _fieldDecoration('jane@example.com', Icons.mail_outline_rounded).copyWith(
                                hintStyle: const TextStyle(color: Color(0xFF80858D), fontSize: 16)),
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 16, height: 1.2),
                              autofillHints: const [AutofillHints.username],
                              autocorrect: false,
                              textCapitalization: TextCapitalization.none,
                              textInputAction: TextInputAction.next,
                              validator: (value) => value == null || value.trim().isEmpty ? 'Enter your ERPNext username.' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            label: 'Password',
                            child: TextFormField(
                              key: const ValueKey('login-password'),
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.password],
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 16, height: 1.2),
                              decoration: _fieldDecoration('•••••', Icons.lock_outline_rounded).copyWith(
                                hintStyle: const TextStyle(color: Color(0xFF80858D), fontSize: 16),
                                suffixIcon: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: TextButton(
                                    onPressed: _busy ? null : () => setState(() => _obscure = !_obscure),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF8792A2),
                                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500)),
                                    child: Text(_obscure ? 'Show' : 'Hide'),
                                  ),
                                ),
                              ),
                              onFieldSubmitted: (_) => _submit(),
                              validator: (value) => value == null || value.isEmpty ? 'Enter your password.' : null,
                            ),
                          ),
                        ] else ...[
                          const Text('Enter the code from your authenticator app, email, or SMS as configured in ERPNext.',
                            style: TextStyle(color: Color(0xFF697386), height: 1.5)),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('login-code'),
                            controller: _code,
                            enabled: !_busy,
                            decoration: _fieldDecoration('Verification code', Icons.lock_outline_rounded),
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            onFieldSubmitted: (_) => _submit(),
                            validator: (value) => value == null || value.trim().isEmpty ? 'Enter the verification code.' : null,
                          ),
                        ],
                        const SizedBox(height: 32),
                        if (error != null) ...[
                          Semantics(liveRegion: true, child: Text(error,
                            style: const TextStyle(color: Color(0xFFD92D20), height: 1.5))),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          height: 60,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0052FF),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF80A8FF),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600)),
                            child: Text(_busy ? 'Signing in…' : verification ? 'Verify code' : 'Login'),
                          ),
                        ),
                        if (verification)
                          TextButton(
                            onPressed: _busy ? null : () {
                              widget.session.cancelVerification();
                              setState(() { _error = null; _code.clear(); });
                            },
                            child: const Text('Start sign-in again'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
