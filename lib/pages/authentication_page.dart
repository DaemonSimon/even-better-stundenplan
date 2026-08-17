import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/session_manager.dart';

class AuthenticationPage extends StatefulWidget {
  const AuthenticationPage({super.key, required this.sessionManager});

  final SessionManager sessionManager;

  @override
  State<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  String error =
      'Deine Zugangsdaten werden verschlüsselt auf deinem Gerät gespeichert.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) trySavedCredentials();
    });
  }

  void trySavedCredentials() async {
    var success = await widget.sessionManager.tryReAuthenticate();
    if (success) {
      if (!mounted) return;
      context.pushReplacement('/');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text("Autorisierung"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: screenWidth - 32,
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'E-Mail',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Bitte geben Sie eine E-Mail-Adresse ein';
                        }
                        return null;
                      },
                      onSaved: (value) => _email = value!,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Passwort',
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Bitte geben Sie ein Passwort ein';
                        }
                        return null;
                      },
                      onSaved: (value) => _password = value!,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: screenWidth - 32,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.inversePrimary,
                          elevation: 0,
                          padding: const EdgeInsets.all(0),
                        ),

                        child: Text('Autorisieren'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();
    var success = await widget.sessionManager.login(
      email: _email,
      password: _password,
    );
    if (success) {
      if (!mounted) return;
      context.pushReplacement('/');
      return;
    }
    setState(() {
      error = 'Anmeldung fehlgeschlagen :/';
    });
  }
}
