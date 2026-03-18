import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'activity_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _error = '';

  Future<void> _login() async {
    setState(() { _isLoading = true; _error = ''; });
    try {
      final result = await ApiService.login(
        _usernameController.text,
        _passwordController.text,
      );
      if (result['token'] != null) {
        await ApiService.saveToken(result['token']);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ActivityScreen(
              username: result['username'],
              trailColor: result['trailColor'],
            ),
          ),
        );
      } else {
        setState(() { _error = 'Invalid credentials'; });
      }
    } catch (e) {
      setState(() { _error = 'Connection error — is backend running?'; });
    }
    setState(() { _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('AURARUN',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF2D78),
                    letterSpacing: 8,
                  )),
              const Text('PAINT YOUR CITY',
                  style: TextStyle(color: Colors.white54, letterSpacing: 4)),
              const SizedBox(height: 60),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              if (_error.isNotEmpty)
                Text(_error, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2D78),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('LOGIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ",
                      style: TextStyle(color: Colors.white38)),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('Sign up',
                        style: TextStyle(
                          color: Color(0xFFFF2D78),
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

  }
}