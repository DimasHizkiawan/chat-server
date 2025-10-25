import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'local_server.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startServer();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ChatPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatPage extends StatefulWidget {
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  Timer? _timer;
  bool _isUploading = false;
  String _deviceName = 'Phone';
  String _serverAddress = 'Loading...';
  bool _showPasswordDialog = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    fetchMessages();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      fetchMessages();
    });
  }

  Future<void> _initializeApp() async {
    try {
      final deviceName = await getDeviceName();
      print('Device name detected: $deviceName');

      final ipAddress = serverIpAddress ?? 'localhost';
      print('Server IP: $ipAddress');

      setState(() {
        _deviceName = deviceName;
        _serverAddress = 'http://$ipAddress:8080';
      });
    } catch (e) {
      print('Error initializing app: $e');
      setState(() {
        _deviceName = 'Unknown Device';
        _serverAddress = 'localhost:8080';
      });
    }
  }

  Future<void> sendMessage(String message) async {
    try {
      await http.post(
        Uri.parse('http://localhost:8080/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'device': _deviceName,
        }),
      );
      _controller.clear();
      await fetchMessages();
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  Future<void> fetchMessages() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:8080/messages'));
      if (res.statusCode == 200) {
        setState(() {
          messages = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      print('Error fetching messages: $e');
    }
  }

  Future<void> pickAndUploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isUploading = true);

        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;

        print('Uploading file: $fileName from $filePath');

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://localhost:8080/upload'),
        );

        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ),
        );

        request.fields['device'] = _deviceName;

        print('Sending request...');

        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw TimeoutException('Upload timeout');
          },
        );

        final response = await http.Response.fromStream(streamedResponse);

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ File uploaded successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
          await fetchMessages();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Failed: ${response.statusCode}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        print('No file selected or path is null');
      }
    } catch (e, stackTrace) {
      print('Error uploading file: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
// tentukan lokasi penyimpanan file
  Future<Directory> getMediaDir() async {
    if(await Permission.storage.request().isGranted) {
      final dir = Directory('/storage/emulated/0/Android/media/com.example.shared_text');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } else {
      throw Exception("Permission denied");
    }
  }

  Future<void> downloadFile(String fileId, String fileName) async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost:8080/download/$fileId'),
      );

      if (response.statusCode == 200) {
        final directory = await getMediaDir();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved to: $filePath')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading: $e')),
        );
      }
    }
  }

  void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showServerAddress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Address'),
        content: SelectableText(
          _serverAddress,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _serverAddress));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Address copied!')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    final isSystemMessage = msg['device'] == 'System';

    if (msg['type'] == 'file') {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Colors.green[50],
        child: ListTile(
          leading: const Icon(Icons.attachment, color: Colors.green),
          title: Text(
            msg['device'] ?? 'Unknown',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg['fileName'] ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              Text(
                msg['fileSize'] ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download, color: Colors.blue),
            onPressed: () {
              downloadFile(msg['fileId'], msg['fileName']);
            },
            tooltip: 'Download',
          ),
        ),
      );
    } else {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: isSystemMessage ? Colors.amber[50] : null,
        child: ListTile(
          leading: isSystemMessage
              ? const Icon(Icons.info_outline, color: Colors.orange)
              : null,
          title: Text(
            msg['device'] ?? 'Unknown',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSystemMessage ? Colors.orange : Colors.grey,
            ),
          ),
          subtitle: Text(
            msg['message'] ?? '',
            style: const TextStyle(fontSize: 16),
          ),
          trailing: isSystemMessage
              ? null
              : IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () => copyToClipboard(msg['message'] ?? ''),
            tooltip: 'Copy',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Chat'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showServerAddress,
            tooltip: 'Server Address',
          ),
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.wifi, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Server: $_serverAddress',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _serverAddress));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Address copied!')),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Text(
                'No messages yet...',
                style: TextStyle(color: Colors.grey),
              ),
            )
                : ListView.builder(
              itemCount: messages.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                return _buildMessageItem(messages[index]);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Type message...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (text) {
                          if (text.trim().isNotEmpty) {
                            sendMessage(text);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send),
                      color: Colors.blue,
                      iconSize: 28,
                      onPressed: () {
                        if (_controller.text.trim().isNotEmpty) {
                          sendMessage(_controller.text);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : pickAndUploadFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_isUploading ? 'Uploading...' : 'Upload File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}