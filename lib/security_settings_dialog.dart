import 'package:flutter/material.dart';

class SecuritySettingsDialog extends StatelessWidget {
  final TextEditingController trustedCertificateController;
  final TextEditingController certificateChainController;
  final TextEditingController privateKeyController;
  final VoidCallback onTrustedCertificatePick;
  final VoidCallback onCertificateChainPick;
  final VoidCallback onPrivateKeyPick;
  final VoidCallback onClearTrustedCertificate;
  final VoidCallback onClearCertificateChain;
  final VoidCallback onClearPrivateKey;

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
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Security Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                  child: TextFormField(
                    maxLines: null,
                    readOnly: true,
                    controller: trustedCertificateController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Trusted Certificate',
                      labelText: 'Trusted Certificate',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: onClearTrustedCertificate,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onTrustedCertificatePick,
                    child: const Icon(Icons.folder_open),
                  ),
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
                    controller: certificateChainController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Certificate Chain',
                      labelText: 'Certificate Chain',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: onClearCertificateChain,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onCertificateChainPick,
                    child: const Icon(Icons.folder_open),
                  ),
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
                    controller: privateKeyController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Private Key',
                      labelText: 'Private Key',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: onClearPrivateKey,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onPrivateKeyPick,
                    child: const Icon(Icons.folder_open),
                  ),
                ),
              ),
            ],
          ),
        ],
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
