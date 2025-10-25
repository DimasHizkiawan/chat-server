# 💬 Chat Server – Secure Local Messaging App

A lightweight and fast **local chat & file sharing server** built with **Dart (Shelf Framework)** and **Flutter**.  
Perfect for sending messages and temporary files securely across devices connected to the same Wi-Fi network.

---

## 🚀 Features

✅ **Send & Receive Messages** — Real-time message delivery with WebSocket.  
📁 **File Transfer** — Share files easily within the same network.  
🧹 **Auto-Cleanup** — Messages and files are automatically deleted when the app closes.  
🔐 **Password Protection** — Use `/setpass` to lock your server with a custom password.  
📡 **Device Detection** — Displays connected devices and their IP addresses.  
📋 **Copy & Download Support** — Users can copy messages or download files directly.  
⚡ **Lightweight & Fast** — Built with pure Dart server backend.

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-------------|
| **Frontend** | Flutter |
| **Backend** | Dart + Shelf |
| **Protocol** | HTTP + WebSocket |
| **Storage** | Temporary in-memory (auto-cleared) |

---

## 📦 Installation

### 1. Clone this repository
```bash
git clone https://github.com/DimasHizkiawan/chat-server.git
cd chat-server
2. Get dependencies
bash
Copy code
dart pub get
3. Run the server
bash
Copy code
dart run
Server will start at:

perl
Copy code
http://<your-local-ip>:8080
📱 Connect via Flutter App
On your mobile device (connected to the same Wi-Fi):

Open the Flutter client.

Enter the IP address shown on the server (example: 192.168.0.101:8080).

Start chatting instantly.

🧩 Commands
Command	Description
/editpass <newpass>	Set or change the server password (only available to owner)
/help	Show available commands (planned feature)

⚙️ Folder Structure
graphql
Copy code
chat-server/
├── bin/
│   └── server.dart        # Main server entry point
├── lib/
│   └── handlers.dart      # Request and WebSocket handlers
├── pubspec.yaml           # Dependencies
└── README.md
🧠 Future Improvements
Persistent chat logs

User authentication

File size limit settings

Web interface dashboard

💻 Developed by
Dimas Hizkiawan
🎓 SMK N 5 Surakarta – Software Engineering (PPLG)
🛠️ Passionate about building simple, elegant, and practical solutions.

🧡 "Built for local simplicity, secured for everyone."
© 2025 DimasHizkiawan Project
