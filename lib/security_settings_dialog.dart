import 'package:flutter/material.dart';

import 'auth_manager.dart';

class SecuritySettingsDialog extends StatefulWidget {
  final TextEditingController trustedCertificateController;
  final TextEditingController certificateChainController;
  final TextEditingController privateKeyController;
  final VoidCallback onTrustedCertificatePick;
  final VoidCallback onCertificateChainPick;
  final VoidCallback onPrivateKeyPick;
  final VoidCallback onClearTrustedCertificate;
  final VoidCallback onClearCertificateChain;
  final VoidCallback onClearPrivateKey;

  final AuthMethod initialAuthMethod;
  final ValueChanged<AuthMethod> onAuthMethodChanged;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController tokenController;
  final TextEditingController nkeySeedController;
  final TextEditingController credsFileController;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onTokenChanged;
  final ValueChanged<String> onNkeySeedChanged;
  final VoidCallback onCredsFilePick;
  final VoidCallback onClearCredsFile;
  final bool initialRememberCredentials;
  final ValueChanged<bool> onRememberCredentialsChanged;

  const SecuritySettingsDialog({
    super.key,
    required this.trustedCertificateController,
    required this.certificateChainController,
    required this.privateKeyController,
    required this.onTrustedCertificatePick,
    required this.onCertificateChainPick,
    required this.onPrivateKeyPick,
    required this.onClearTrustedCertificate,
    required this.onClearCertificateChain,
    required this.onClearPrivateKey,
    required this.initialAuthMethod,
    required this.onAuthMethodChanged,
    required this.usernameController,
    required this.passwordController,
    required this.tokenController,
    required this.nkeySeedController,
    required this.credsFileController,
    required this.onUsernameChanged,
    required this.onPasswordChanged,
    required this.onTokenChanged,
    required this.onNkeySeedChanged,
    required this.onCredsFilePick,
    required this.onClearCredsFile,
    required this.initialRememberCredentials,
    required this.onRememberCredentialsChanged,
  });

  @override
  State<SecuritySettingsDialog> createState() => _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends State<SecuritySettingsDialog> {
  late AuthMethod _authMethod;
  late bool _rememberCredentials;
  bool _obscureNkeySeed = true;

  @override
  void initState() {
    super.initState();
    _authMethod = widget.initialAuthMethod;
    _rememberCredentials = widget.initialRememberCredentials;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Security Settings'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: TextFormField(
                        maxLines: null,
                        readOnly: true,
                        controller: widget.trustedCertificateController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Trusted Certificate',
                          labelText: 'Trusted Certificate',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: widget.onClearTrustedCertificate,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                    child: IconButton.filledTonal(
                      tooltip: 'Browse for trusted certificate',
                      onPressed: widget.onTrustedCertificatePick,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: TextFormField(
                        maxLines: null,
                        readOnly: true,
                        controller: widget.certificateChainController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Certificate Chain',
                          labelText: 'Certificate Chain',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: widget.onClearCertificateChain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                    child: IconButton.filledTonal(
                      tooltip: 'Browse for certificate chain',
                      onPressed: widget.onCertificateChainPick,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: TextFormField(
                        maxLines: null,
                        readOnly: true,
                        controller: widget.privateKeyController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Private Key',
                          labelText: 'Private Key',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: widget.onClearPrivateKey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                    child: IconButton.filledTonal(
                      tooltip: 'Browse for private key',
                      onPressed: widget.onPrivateKeyPick,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(),
              ),
              Text('Authentication',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<AuthMethod>(
                initialValue: _authMethod,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: AuthMethod.none, child: Text('None')),
                  DropdownMenuItem(
                      value: AuthMethod.usernamePassword,
                      child: Text('Username & Password')),
                  DropdownMenuItem(
                      value: AuthMethod.token, child: Text('Token')),
                  DropdownMenuItem(
                      value: AuthMethod.nkeySeed, child: Text('NKey Seed')),
                  DropdownMenuItem(
                      value: AuthMethod.credentialsFile,
                      child: Text('Credentials File (.creds)')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _authMethod = value;
                  });
                  widget.onAuthMethodChanged(value);
                },
              ),
              if (_authMethod == AuthMethod.usernamePassword) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: widget.onUsernameChanged,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: widget.onPasswordChanged,
                ),
              ],
              if (_authMethod == AuthMethod.token) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Token',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: widget.onTokenChanged,
                ),
              ],
              if (_authMethod == AuthMethod.nkeySeed) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.nkeySeedController,
                  obscureText: _obscureNkeySeed,
                  decoration: InputDecoration(
                    labelText: 'NKey Seed',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNkeySeed
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          _obscureNkeySeed = !_obscureNkeySeed;
                        });
                      },
                    ),
                  ),
                  onChanged: widget.onNkeySeedChanged,
                ),
              ],
              if (_authMethod == AuthMethod.credentialsFile) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Flexible(
                      child: TextFormField(
                        maxLines: null,
                        readOnly: true,
                        controller: widget.credsFileController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Credentials File',
                          labelText: 'Credentials File',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: widget.onClearCredsFile,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: IconButton.filledTonal(
                        tooltip: 'Browse for credentials file',
                        onPressed: widget.onCredsFilePick,
                        icon: const Icon(Icons.folder_open),
                      ),
                    ),
                  ],
                ),
              ],
              if (_authMethod != AuthMethod.none) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _rememberCredentials,
                  title: const Text('Remember credentials on this device'),
                  subtitle: const Text('Stored locally, not encrypted'),
                  onChanged: (value) {
                    final remember = value ?? false;
                    setState(() {
                      _rememberCredentials = remember;
                    });
                    widget.onRememberCredentialsChanged(remember);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
