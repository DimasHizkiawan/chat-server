import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf;
import 'package:mime/mime.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Variable global untuk simpan IP address
String? serverIpAddress;

// Variable global password
String? serverPassword;
bool isPasswordSet = false;

// Simpan koneksi WebSocket
final Set<WebSocketChannel> webSocketConnections = {};

Future<void> startServer() async {
  final router = shelf.Router();

  // Simpan pesan dengan info device
  final List<Map<String, String>> messages = [];

  // Simpan file yang diupload
  final Map<String, Map<String, dynamic>> uploadedFiles = {};

  // Simpan session yang sudah login (IP address yang authenticated)
  final Set<String> authenticatedSessions = {};

  // Dapatkan IP lokal
  String? localIp = await getLocalIpAddress();
  serverIpAddress = localIp;



  // Tambahkan pesan system otomatis dengan IP address
  messages.add({
    'message': 'Server started at http://$localIp:8080',
    'device': 'System',
    'type': 'text',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // Fungsi untuk broadcast pesan ke semua orang dengan WebSocket
  void broadcastMessage(Map<String, dynamic> message) {
    final messageJson = jsonEncode(message);
    for (final ws in webSocketConnections) {
      try {
        ws.sink.add(messageJson);
      } catch (e) {
        print('Error sending message to WebSocket: $e');
      }
    }
  }

  // WebSocket handler untuk real-time updates
  final wsHandler = webSocketHandler((WebSocketChannel ws) {
    print('New WebSocket connection established');
    webSocketConnections.add(ws);

    // Kirim semua pesan yang ada ke orang
    for (final message in messages) {
      ws.sink.add(jsonEncode(message));
    }

    // Tangani pesan dari orang
    ws.stream.listen(
          (message) {
        // Handle pesan Websocket yang masuk
        print('Received WebSocket message: $message');
      },
      onDone: () {
        print('WebSocket connection closed');
        webSocketConnections.remove(ws);
      },
      onError: (error) {
        print('WebSocket error: $error');
        webSocketConnections.remove(ws);
      },
    );
  });

  // Tambahkan route WebSocket
  router.get('/ws', wsHandler);

  // Middleware untuk cek password (kecuali untuk localhost/server owner)
  Handler authMiddleware(Handler handler) {
    return (Request request) async {
      // Casting ke HttpConnectionInfo ---
      final clientIp = request.headers['x-forwarded-for'] ??
          (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress?.address ??
          'unknown';

      // Localhost/server owner selalu bisa akses tanpa password
      if (clientIp == '127.0.0.1' || clientIp == 'localhost' || clientIp == localIp) {
        return handler(request);
      }

      // Jika password belum di-set, semua bisa akses
      if (!isPasswordSet) {
        return handler(request);
      }

      // Cek apakah sudah authenticated
      if (authenticatedSessions.contains(clientIp)) {
        return handler(request);
      }

      // Cek password dari header
      final providedPassword = request.headers['x-password'];
      if (providedPassword == serverPassword) {
        authenticatedSessions.add(clientIp);
        return handler(request);
      }

      // Password salah atau tidak ada
      return Response.forbidden(
        jsonEncode({'status': 'error', 'message': 'Password required'}),
        headers: {'Content-Type': 'application/json'},
      );
    };
  }

  // ROOT ROUTE - Halaman HTML untuk browser
  router.get('/', (Request request) {
    // Mengakses IP melalui request.context
    final clientIp = request.headers['x-forwarded-for'] ??
        (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress?.address ??
        'unknown';
    final isOwner = clientIp == '127.0.0.1' || clientIp == 'localhost' || clientIp == localIp;

    // Jika password sudah di-set dan bukan owner, tampilkan halaman login
    if (isPasswordSet && !isOwner && !authenticatedSessions.contains(clientIp)) {
      final loginHtml = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - Local Chat Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f0f0f0;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .login-container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            width: 300px;
        }
        h2 {
            text-align: center;
            color: #333;
            margin-bottom: 30px;
        }
        input {
            width: 100%;
            padding: 12px;
            margin-bottom: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
            font-size: 16px;
        }
        button {
            width: 100%;
            padding: 12px;
            background: #2196F3;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
        }
        button:hover {
            background: #1976D2;
        }
        .error {
            color: red;
            text-align: center;
            margin-top: 10px;
            display: none;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <h2>🔒 Local Chat</h2>
        <form id="loginForm">
            <input type="password" id="password" placeholder="Enter Password" autofocus>
            <button type="submit">Login</button>
        </form>
        <div class="error" id="error">Incorrect password</div>
    </div>

    <script>
        document.getElementById('loginForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const password = document.getElementById('password').value;
            
            // Test password dengan request ke /messages
            const res = await fetch('/messages', {
                headers: { 'x-password': password }
            });
            
            if (res.status === 200) {
                // Password benar, simpan dan redirect
                sessionStorage.setItem('serverPassword', password);
                window.location.reload();
            } else {
                // Password salah
                document.getElementById('error').style.display = 'block';
                document.getElementById('password').value = '';
                document.getElementById('password').focus();
            }
        });
    </script>
</body>
</html>
      ''';

      return Response.ok(
        loginHtml,
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    final html = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Local Chat Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        h1 { color: #333; }
        #messages {
            background: white;
            border: 1px solid #ddd;
            border-radius: 8px;
            padding: 20px;
            min-height: 300px;
            max-height: 400px;
            overflow-y: auto;
            margin-bottom: 20px;
        }
        .message {
            padding: 10px;
            margin: 5px 0;
            background: #e3f2fd;
            border-radius: 5px;
            word-wrap: break-word;
            position: relative;
            padding-right: 80px;
        }
        .file-message {
            background: #e8f5e9;
        }
        .device-label {
            font-size: 12px;
            color: #666;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .message-text {
            color: #333;
        }
        .file-link {
            color: #1976D2;
            text-decoration: none;
            font-weight: bold;
        }
        .file-link:hover {
            text-decoration: underline;
        }
        .copy-btn {
            position: absolute;
            right: 10px;
            top: 50%;
            transform: translateY(-50%);
            padding: 5px 10px;
            background: #4CAF50;
            color: white;
            border: none;
            border-radius: 3px;
            cursor: pointer;
            font-size: 12px;
        }
        .copy-btn:hover {
            background: #45a049;
        }
        .input-group {
            display: flex;
            gap: 10px;
            margin-bottom: 10px;
        }
        input[type="text"] {
            flex: 1;
            padding: 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 16px;
        }
        input[type="file"] {
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
            background: white;
        }
        button {
            padding: 12px 24px;
            background: #2196F3;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
        }
        button:hover {
            background: #1976D2;
        }
        .upload-btn {
            background: #FF9800;
        }
        .upload-btn:hover {
            background: #F57C00;
        }
        .info {
            background: #fff3cd;
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .connection-status {
            position: fixed;
            top: 10px;
            right: 10px;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 12px;
            font-weight: bold;
        }
        .connected {
            background: #4CAF50;
            color: white;
        }
        .disconnected {
            background: #f44336;
            color: white;
        }
    </style>
</head>
<body>
    <div id="connectionStatus" class="connection-status disconnected">Connecting...</div>
    
    <h1>📱 Local Chat Server</h1>
    <div class="info">
        <strong>Status:</strong> <span id="statusText">Connecting...</span><br>
        <strong>Endpoint:</strong> ${localIp ?? 'localhost'}:8080<br>
        <strong>Password:</strong> ${isPasswordSet ? '🔒 Protected' : '🔓 Not set'}
    </div>
    
    <div id="messages"></div>
    
    <div class="input-group">
        <input type="text" id="messageInput" placeholder="Type your message..." onkeypress="if(event.key==='Enter') sendMessage()">
        <button onclick="sendMessage()">Send</button>
        <button onclick="fetchMessages()">Refresh</button>
    </div>
    
    <div class="input-group">
        <input type="file" id="fileInput">
        <button class="upload-btn" onclick="uploadFile()">Upload File</button>
    </div>

    <script>
        let messagesCache = [];
        let deviceName = 'PC';
        let currentPassword = sessionStorage.getItem('serverPassword') || '';
        let ws = null;
        
        // Deteksi nama device dari browser dengan lebih detail
        function getDeviceName() {
            const userAgent = navigator.userAgent;
            const platform = navigator.platform;
            
            // Deteksi OS
            if (userAgent.indexOf('Win') !== -1) {
                // Coba deteksi versi Windows
                if (userAgent.indexOf('Windows NT 10.0') !== -1) deviceName = 'Windows 10/11';
                else if (userAgent.indexOf('Windows NT 6.3') !== -1) deviceName = 'Windows 8.1';
                else if (userAgent.indexOf('Windows NT 6.2') !== -1) deviceName = 'Windows 8';
                else if (userAgent.indexOf('Windows NT 6.1') !== -1) deviceName = 'Windows 7';
                else deviceName = 'Windows PC';
            } 
            else if (userAgent.indexOf('Mac') !== -1) {
                deviceName = 'MacOS';
            } 
            else if (userAgent.indexOf('Linux') !== -1) {
                if (userAgent.indexOf('Android') !== -1) {
                    deviceName = 'Android Browser';
                } else {
                    deviceName = 'Linux PC';
                }
            }
            else if (userAgent.indexOf('iPhone') !== -1) {
                deviceName = 'iPhone';
            }
            else if (userAgent.indexOf('iPad') !== -1) {
                deviceName = 'iPad';
            }
            
            // Tambahkan info browser
            let browser = '';
            if (userAgent.indexOf('Edg') !== -1) browser = ' (Edge)';
            else if (userAgent.indexOf('Chrome') !== -1) browser = ' (Chrome)';
            else if (userAgent.indexOf('Firefox') !== -1) browser = ' (Firefox)';
            else if (userAgent.indexOf('Safari') !== -1 && userAgent.indexOf('Chrome') === -1) browser = ' (Safari)';
            
            return deviceName + browser;
        }
        
        deviceName = getDeviceName();
        console.log('Device detected:', deviceName);
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // Inisialisasi WebSocket
        function initWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = \`\${protocol}//\${window.location.host}/ws\`;
            
            try {
                ws = new WebSocket(wsUrl);
                
                ws.onopen = function() {
                    console.log('WebSocket connected');
                    updateConnectionStatus(true);
                };
                
                ws.onmessage = function(event) {
                    const message = JSON.parse(event.data);
                    messagesCache.push(message);
                    displayMessages();
                };
                
                ws.onclose = function() {
                    console.log('WebSocket disconnected');
                    updateConnectionStatus(false);
                    // Coba reconnect setelah 3 detik
                    setTimeout(initWebSocket, 3000);
                };
                
                ws.onerror = function(error) {
                    console.error('WebSocket error:', error);
                    updateConnectionStatus(false);
                };
            } catch (error) {
                console.error('Failed to initialize WebSocket:', error);
                updateConnectionStatus(false);
                // Fallback ke polling jika WebSocket gagal
                setTimeout(fetchMessages, 5000);
            }
        }
        
        function updateConnectionStatus(connected) {
            const statusElement = document.getElementById('connectionStatus');
            const statusText = document.getElementById('statusText');
            
            if (connected) {
                statusElement.className = 'connection-status connected';
                statusElement.textContent = 'Connected';
                statusText.textContent = 'Connected ✅';
            } else {
                statusElement.className = 'connection-status disconnected';
                statusElement.textContent = 'Disconnected';
                statusText.textContent = 'Disconnected ❌';
            }
        }
        
        function displayMessages() {
            const container = document.getElementById('messages');
            container.innerHTML = messagesCache.length === 0 
                ? '<p style="color: #999;">No messages yet...</p>'
                : messagesCache.map((m, idx) => {
                    if (m.type === 'file') {
                        return \`
                            <div class="message file-message">
                                <div class="device-label">\${escapeHtml(m.device)}</div>
                                <div class="message-text">
                                    📎 <a href="/download/\${m.fileId}" class="file-link" download>\${escapeHtml(m.fileName)}</a>
                                    <br><small>\${m.fileSize}</small>
                                </div>
                            </div>
                        \`;
                    } else {
                        return \`
                            <div class="message">
                                <div class="device-label">\${escapeHtml(m.device)}</div>
                                <div class="message-text">\${escapeHtml(m.message)}</div>
                                <button class="copy-btn" onclick="copyMessage(\${idx})">Copy</button>
                            </div>
                        \`;
                    }
                }).join('');
            container.scrollTop = container.scrollHeight;
        }

        async function fetchMessages() {
            try {
                const res = await fetch('/messages', {
                    headers: currentPassword ? { 'x-password': currentPassword } : {}
                });
                
                if (res.status === 403) {
                    // Password salah atau berubah, redirect ke login
                    sessionStorage.removeItem('serverPassword');
                    window.location.reload();
                    return;
                }
                
                messagesCache = await res.json();
                displayMessages();
            } catch (e) {
                console.error('Error fetching messages:', e);
            }
        }

        async function sendMessage() {
            const input = document.getElementById('messageInput');
            const message = input.value.trim();
            if (!message) return;

            try {
                const res = await fetch('/send', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        ...(currentPassword ? { 'x-password': currentPassword } : {})
                    },
                    body: JSON.stringify({ 
                        message: message,
                        device: deviceName
                    })
                });
                
                if (res.status === 403) {
                    sessionStorage.removeItem('serverPassword');
                    window.location.reload();
                    return;
                }
                
                input.value = '';
                // Tidak perlu fetchMessages lagi karena WebSocket akan mengirim pesan baru
            } catch (e) {
                alert('Error sending message');
            }
        }
        
        async function uploadFile() {
            const fileInput = document.getElementById('fileInput');
            const file = fileInput.files[0];
            if (!file) {
                alert('Please select a file first');
                return;
            }
            
            // Cek ukuran file (25MB)
            const maxSize = 25 * 1024 * 1024; // 25MB in bytes
            if (file.size > maxSize) {
                alert('File size exceeds 25MB limit');
                return;
            }

            const formData = new FormData();
            formData.append('file', file);
            formData.append('device', deviceName);

            try {
                const headers = {};
                if (currentPassword) {
                    headers['x-password'] = currentPassword;
                }

                const res = await fetch('/upload', {
                    method: 'POST',
                    headers: headers,
                    body: formData
                });
                
                if (res.ok) {
                    fileInput.value = '';
                    // Tidak perlu fetchMessages lagi karena WebSocket akan mengirim pesan baru
                    alert('File uploaded successfully!');
                } else {
                    const error = await res.json();
                    alert('Failed to upload file: ' + (error.message || 'Unknown error'));
                }
            } catch (e) {
                alert('Error uploading file');
            }
        }
        
        async function copyMessage(index) {
            try {
                const text = messagesCache[index].message;
                await navigator.clipboard.writeText(text);
                alert('Message copied to clipboard!');
            } catch (e) {
                alert('Failed to copy message');
            }
        }

        // Inisialisasi WebSocket saat halaman dimuat
        initWebSocket();
        
        // Fallback: fetch pesan awal jika WebSocket tidak terhubung dalam 3 detik
        setTimeout(() => {
            if (ws && ws.readyState !== WebSocket.OPEN) {
                fetchMessages();
            }
        }, 3000);
    </script>
</body>
</html>
    ''';

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  });

  // Endpoint GET untuk ambil semua pesan
  router.get('/messages', authMiddleware((Request request) {
    return Response.ok(
      jsonEncode(messages),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }));

  // Endpoint POST untuk kirim pesan
  router.post('/send', authMiddleware((Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final message = data['message'];
      final device = data['device'] ?? 'Unknown';

      if (message != null) {
        final messageText = message.toString();
        print('Message recieved: $messageText');

        // Cek apakah ini command /editpass (hanya untuk owner)
        if (messageText.startsWith('/editpass ')) {
          // --- PERBAIKAN: Mengakses IP melalui request.context ---
          final clientIp = request.headers['x-forwarded-for'] ??
              (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress?.address ??
              'unknown';
          final isOwner = clientIp == '127.0.0.1' || clientIp == 'localhost' || clientIp == localIp;

          print('Command /editpass received from IP: $clientIp (isOwner: $isOwner)');

          if (isOwner) {
            final newPassword = messageText.substring(10).trim();
            if (newPassword.isNotEmpty) {
              serverPassword = newPassword;
              isPasswordSet = true;
              authenticatedSessions.clear();
              authenticatedSessions.add(clientIp); // Owner tetap authenticated

              print('✅ Password set to: $newPassword');


              final systemMessage = {
                'message': '🔒 Password has been set. All users must authenticate.',
                'device': 'System',
                'type': 'text',
                'timestamp': DateTime.now().toIso8601String(),
              };

              messages.add(systemMessage);
              // Broadcast ke semua klien WebSocket
              broadcastMessage(systemMessage);

              return Response.ok(
                jsonEncode({'status': 'success', 'message': 'Password set successfully'}),
                headers: {
                  'Content-Type': 'application/json',
                  'Access-Control-Allow-Origin': '*',
                },
              );
            } else {
              return Response.badRequest(
                body: jsonEncode({'status': 'error', 'message': 'Password cannot be empty'}),
              );
            }
          } else {
            print('❌ Unauthorized attempt to set password from: $clientIp');
            return Response.forbidden(
              jsonEncode({'status': 'error', 'message': 'Only server owner can set password'}),
            );
          }
        }

        // Pesan biasa
        final newMessage = {
          'message': messageText,
          'device': device.toString(),
          'type': 'text',
          'timestamp': DateTime.now().toIso8601String(),
        };

        messages.add(newMessage);
        // Broadcast ke semua klien WebSocket
        broadcastMessage(newMessage);

        return Response.ok(
          jsonEncode({'status': 'success', 'message': 'Message received'}),
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        );
      } else {
        return Response.badRequest(
          body: jsonEncode({'status': 'error', 'message': 'Message field is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': 'Invalid JSON'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }));

  // Endpoint POST untuk upload file (via browser - berfungsi dengan baik)
  router.post('/upload', authMiddleware((Request request) async {
    try {
      print('Upload request received');
      final contentType = request.headers['content-type'];
      print('Content-Type: $contentType');

      if (contentType == null || !contentType.contains('multipart/form-data')) {
        print('Not multipart request');
        return Response.badRequest(
          body: jsonEncode({'status': 'error', 'message': 'Not a multipart request'}),
        );
      }

      // Untuk upload dari browser, gunakan cara sederhana
      // Upload dari HP Flutter bisa lewat browser saja
      final boundary = contentType.split('boundary=')[1];
      final transformer = MimeMultipartTransformer(boundary);

      String? fileName;
      String? device;
      List<int>? fileBytes;

      await for (var part in transformer.bind(request.read())) {
        final contentDisposition = part.headers['content-disposition'];
        print('Content-Disposition: $contentDisposition');

        if (contentDisposition != null) {
          if (contentDisposition.contains('name="device"')) {
            final deviceBytes = <int>[];
            await for (var chunk in part) {
              deviceBytes.addAll(chunk);
            }
            device = utf8.decode(deviceBytes);
            print('Device: $device');
          } else if (contentDisposition.contains('name="file"')) {
            final match = RegExp(r'filename="([^"]+)"').firstMatch(contentDisposition);
            if (match != null) {
              fileName = match.group(1);
              print('Filename: $fileName');
            }

            final chunks = <int>[];
            await for (var chunk in part) {
              chunks.addAll(chunk);
            }
            fileBytes = chunks;
            print('File size: ${fileBytes.length} bytes');
          }
        }
      }

      if (fileName != null && fileBytes != null && fileBytes.isNotEmpty) {
        // TAMBAHKAN PEMERIKSAAN UKURAN FILE DI SINI
        const maxFileSize = 25 * 1024 * 1024; // 25MB in bytes
        if (fileBytes.length > maxFileSize) {
          print('❌ File too large: ${fileBytes.length} bytes (max: $maxFileSize bytes)');
          return Response.badRequest(
            body: jsonEncode({
              'status': 'error',
              'message': 'File size exceeds 25MB limit'
            }),
          );
        }

        final fileId = DateTime.now().millisecondsSinceEpoch.toString();
        final fileSize = _formatFileSize(fileBytes.length);

        uploadedFiles[fileId] = {
          'fileName': fileName,
          'data': fileBytes,
          'size': fileBytes.length,
        };

        final fileMessage = {
          'type': 'file',
          'device': device ?? 'Unknown',
          'fileName': fileName,
          'fileId': fileId,
          'fileSize': fileSize,
          'timestamp': DateTime.now().toIso8601String(),
        };

        messages.add(fileMessage);
        // Broadcast ke semua klien WebSocket
        broadcastMessage(fileMessage);

        print('✅ File uploaded successfully: $fileName ($fileSize)');

        return Response.ok(
          jsonEncode({'status': 'success', 'fileId': fileId}),
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }

      print('❌ No file data found');
      return Response.badRequest(
        body: jsonEncode({'status': 'error', 'message': 'No file uploaded'}),
      );
    } catch (e, stackTrace) {
      print('❌ Upload error: $e');
      print('Stack trace: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': 'Upload failed: $e'}),
      );
    }
  }));

  // Endpoint GET untuk download file
  router.get('/download/<fileId>', (Request request, String fileId) {
    if (!uploadedFiles.containsKey(fileId)) {
      return Response.notFound('File not found');
    }

    final file = uploadedFiles[fileId]!;
    final fileName = file['fileName'] as String;
    final data = file['data'] as List<int>;

    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';

    return Response.ok(
      data,
      headers: {
        'Content-Type': mimeType,
        'Content-Disposition': 'attachment; filename="$fileName"',
        'Content-Length': data.length.toString(),
      },
    );
  });



  // Handler untuk semua route
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router);

  // Jalankan server di port 8080
  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    8080,
  );

  print('✅ Local server running on http://${server.address.host}:${server.port}');
  print('📱 Access from laptop: http://$localIp:8080');
  print('');
  print('Available endpoints:');
  print('  GET  http://$localIp:8080/         - Web interface');
  print('  GET  http://$localIp:8080/ws       - WebSocket endpoint');
  print('  GET  http://$localIp:8080/messages - Get all messages');
  print('  POST http://$localIp:8080/send     - Send message');
  print('  POST http://$localIp:8080/upload   - Upload file');
  print('  GET  http://$localIp:8080/download/<fileId> - Download file');
}

// Fungsi untuk mendapatkan nama device
Future<String> getDeviceName() async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final androidInfo = await deviceInfo.androidInfo;
    // Gabungkan brand (merk) dengan model
    final brand = androidInfo.brand; // Contoh: "xiaomi", "samsung"
    final model = androidInfo.model; // Contoh: "M2010J19CG"

    // Capitalize brand dengan pengecekan untuk string kosong
    final brandCapitalized = brand.isNotEmpty
        ? brand.substring(0, 1).toUpperCase() + brand.substring(1)
        : 'Unknown';

    return '$brandCapitalized $model'; // Contoh: "Xiaomi M2010J19CG"
  } else if (Platform.isIOS) {
    final iosInfo = await deviceInfo.iosInfo;
    return iosInfo.name; // Contoh: "iPhone 13"
  } else if (Platform.isWindows) {
    final windowsInfo = await deviceInfo.windowsInfo;
    return windowsInfo.computerName; // Nama komputer
  } else if (Platform.isMacOS) {
    final macInfo = await deviceInfo.macOsInfo;
    return macInfo.computerName;
  } else if (Platform.isLinux) {
    final linuxInfo = await deviceInfo.linuxInfo;
    return linuxInfo.name;
  }

  return 'Unknown Device';
}

// Fungsi untuk format ukuran file
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

// Fungsi untuk mendapatkan IP lokal
Future<String?> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list();
    for (var interface in interfaces) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback) {
          if (
              addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.50.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
    }
  } catch (e) {
    print('Error getting IP: $e');
  }
  return '127.0.0.1';
}

Future<void> sendMsg(BuildContext context, String msg, String deviceName, String serverIpAddress) async {
  try {
    final response = await http.post(
      Uri.parse('http://$serverIpAddress:8080/send'),
      headers: {'Content-Type' : 'application/json'},
      body: jsonEncode({'message' : msg, 'device' : deviceName}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (msg.startsWith('/')) {
        _showAlert(context, 'Admin Panel', data[msg] ?? 'Command successfully executed! ',);
      } else if (response.statusCode == 403) {
        _showAlert(context, 'Admin Panel', 'You are not allowed to execute this command.',);
      }


    }
  } catch (e) {
    _showAlert(context, 'Error', 'Failed to connect to server.');
  }
}
// Fungsi utama run server
void main() async {
  await startServer();
}

void _showAlert(BuildContext context, String title, String message){
  showDialog(context: context, builder: (context) =>AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ok'),
      ),
    ],
  ),
  );
}