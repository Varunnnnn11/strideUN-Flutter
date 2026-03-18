import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'activity_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String _error = '';

  Future<void> _register() async {
    if (_passwordController.text != _confirmController.text) {
      setState(() { _error = 'Passwords do not match'; });
      return;
    }
    if (_usernameController.text.length < 3) {
      setState(() { _error = 'Username must be at least 3 characters'; });
      return;
    }
    setState(() { _isLoading = true; _error = ''; });
    try {
      final result = await ApiService.register(
        _usernameController.text.trim(),
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
              trailColor: result['trailColor'] ?? 'PINK',
            ),
          ),
        );
      } else {
        setState(() { _error = result['message'] ?? 'Registration failed'; });
      }
    } catch (e) {
      setState(() { _error = 'Connection error — is backend running?'; });
    }
    setState(() { _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const SizedBox(height: 20),

              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0d1320),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white54, size: 18),
                ),
              ),

              const SizedBox(height: 40),

              // Title
              const Text('CREATE\nACCOUNT',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: 2,
                  )),

              const SizedBox(height: 8),

              const Text('Join the city conquest',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 15,
                  )),

              const SizedBox(height: 48),

              // Username field
              _buildLabel('USERNAME'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _usernameController,
                hint: 'choose a unique username',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 20),

              // Password field
              _buildLabel('PASSWORD'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _passwordController,
                hint: 'min 6 characters',
                icon: Icons.lock_outline,
                obscure: true,
              ),

              const SizedBox(height: 20),

              // Confirm password
              _buildLabel('CONFIRM PASSWORD'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _confirmController,
                hint: 'repeat your password',
                icon: Icons.lock_outline,
                obscure: true,
              ),

              const SizedBox(height: 12),

              // Trail color preview
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0d1320),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(children: [
                  const Icon(Icons.palette_outlined,
                      color: Colors.white38, size: 18),
                  const SizedBox(width: 10),
                  const Text('Trail color assigned randomly',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                  const Spacer(),
                  Row(children: [
                    _colorDot(const Color(0xFFFF2D78)),
                    _colorDot(const Color(0xFF2D8BFF)),
                    _colorDot(const Color(0xFF2DFF78)),
                    _colorDot(const Color(0xFFFF8C2D)),
                    _colorDot(const Color(0xFF8C2DFF)),
                  ]),
                ]),
              ),

              const SizedBox(height: 28),

              // Error
              if (_error.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Text(_error,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ]),
                ),

              // Register button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2D78),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('CREATE ACCOUNT',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.white,
                      )),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white24, size: 20),
        filled: true,
        fillColor: const Color(0xFF0d1320),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
              color: Color(0xFFFF2D78), width: 1.5),
        ),
      ),
    );
  }

  Widget _colorDot(Color color) {
    return Container(
      width: 16, height: 16,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}