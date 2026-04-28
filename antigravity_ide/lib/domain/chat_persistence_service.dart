import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_message.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime lastUpdated;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.lastUpdated,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'lastUpdated': lastUpdated.toIso8601String(),
    'messages': messages.map((m) => {'text': m.text, 'isUser': m.isUser}).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'],
      title: json['title'],
      lastUpdated: DateTime.parse(json['lastUpdated']),
      messages: (json['messages'] as List).map((m) => ChatMessage(
        text: m['text'], 
        isUser: m['isUser']
      )).toList(),
    );
  }
}

class ChatPersistenceService {
  static const String _storageKey = 'locode_ai_chats';

  static Future<void> saveSessions(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  static Future<List<ChatSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((j) => ChatSession.fromJson(j)).toList();
    } catch (e) {
      print('Error loading chat sessions: $e');
      return [];
    }
  }
}
