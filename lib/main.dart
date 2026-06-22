import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:clipboard/clipboard.dart';

void main() => runApp(CFOApp());

class CFOApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Personal CFO',
        theme: ThemeData(primarySwatch: Colors.teal),
        home: ChatScreen(),
      );
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final String _apiBase = 'https://personalcfo-sqtn.onrender.com';
  late stt.SpeechToText _speech;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _checkRemindersAndNudges();
  }

  bool _containsDigit(String text) => RegExp(r'\d').hasMatch(text);

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
          });
          if (result.finalResult) {
            setState(() => _isListening = false);
            if (_controller.text.isNotEmpty) {
              _sendMessage(_controller.text);
            }
          }
        },
        listenFor: Duration(seconds: 30),
        pauseFor: Duration(seconds: 3),
        localeId: 'en_US',
      );
    } else {
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speech recognition not available')),
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  void _copyAllMessages() {
    final buffer = StringBuffer();
    for (var msg in _messages) {
      buffer.writeln('CFO: ${msg['content']}');
      buffer.writeln();
    }
    if (buffer.isEmpty) return;
    FlutterClipboard.copy(buffer.toString()).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conversation copied')),
      );
    });
  }

  void _checkRemindersAndNudges() async {
    try {
      // Check scheduled cash reminder
      var remResp = await http.get(Uri.parse('$_apiBase/reminders/check'));
      if (remResp.statusCode == 200) {
        var remData = jsonDecode(remResp.body);
        if (remData['reminder'] != null) {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': remData['reminder']
              }));
        }
      }

      // Check daily nudge (only show if not already shown today)
      var nudgeResp = await http.get(Uri.parse('$_apiBase/nudge'));
      if (nudgeResp.statusCode == 200) {
        var nudgeData = jsonDecode(nudgeResp.body);
        if (nudgeData['nudges'] != null && nudgeData['nudges'].isNotEmpty) {
          for (var n in nudgeData['nudges']) {
            setState(() => _messages.add({
                  'role': 'cfo',
                  'content': n
                }));
          }
        }
      }
    } catch (e) {
      // ignore if not available
    }
  }

  void _sendMessage(String text) async {
    if (text.isEmpty) return;

    // ---- set commands (set income, set essentials, etc.) ----
    if (text.startsWith('set ')) {
      try {
        var response = await http.post(
          Uri.parse('$_apiBase/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['message'] ?? data['answer'] ?? 'Setting updated.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'I didn’t understand that setting.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Could not reach CFO. Please try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- correction / change ----
    if (text.startsWith('change ') || text.startsWith('correct ') || text.startsWith('that\'s wrong ')) {
      try {
        var response = await http.post(
          Uri.parse('$_apiBase/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['message'] ?? 'Correction applied.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'I couldn’t apply that correction.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Still waking up… please try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- invoice command ----
    if (text.startsWith('create invoice') || text.startsWith('generate invoice')) {
      try {
        var response = await http.post(
          Uri.parse('$_apiBase/invoice'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['invoice'] ?? 'Invoice could not be generated.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'Could not generate invoice. Include an amount, client, and service.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Still waking up… please try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- track money ----
    if (text.trim() == 'track money') {
      try {
        var response = await http.get(
          Uri.parse('$_apiBase/track'),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['message'] ?? 'Here is your financial overview.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'I couldn’t fetch your briefing.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Still waking up… please try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- scan my bills ----
    if (text.trim() == 'scan my bills' || text.trim() == 'optimize my bills') {
      try {
        var response = await http.get(
          Uri.parse('$_apiBase/scanbills'),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['message'] ?? 'Bill scan complete.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'Could not scan bills right now.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Still waking up… please try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- offline business analysis (tell me about ...) ----
    if (text.startsWith('tell me about ')) {
      try {
        String idea = text.replaceFirst('tell me about ', '').trim();
        var response = await http.post(
          Uri.parse('$_apiBase/business/offline'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'idea': idea}),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['report'] ?? 'No report available for that business.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'I couldn’t analyze that business. Please try another idea.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Still waking up… please try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- GENERIC: questions without digits → summary endpoint ----
    if (!_containsDigit(text)) {
      try {
        var response = await http.post(
          Uri.parse('$_apiBase/summary'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['answer'] ?? 'I didn’t understand that.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'I’m not sure what you mean.'
              }));
        }
      } catch (e) {
        setState(() => _messages.add({
              'role': 'cfo',
              'content': 'Still waking up… please wait 30 seconds and try again.'
            }));
      }
      _controller.clear();
      return;
    }

    // ---- Contains a digit → try to save as a transaction ----
    try {
      var response = await http.post(
        Uri.parse('$_apiBase/transaction'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(Duration(seconds: 60));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() => _messages.add({
              'role': 'cfo',
              'content': data['message'] ?? 'Transaction recorded.'
            }));
        // Show micro‑lesson tip if available
        if (data['tip'] != null) {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['tip']
              }));
        }
      } else {
        // Fallback to summary
        response = await http.post(
          Uri.parse('$_apiBase/summary'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        ).timeout(Duration(seconds: 60));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() => _messages.add({
                'role': 'cfo',
                'content': data['answer'] ?? 'I didn’t understand that.'
              }));
        } else {
          setState(() => _messages.add({
                'role': 'cfo',
                'content': 'I’m not sure what you mean. Try something like "i spent 500 naira on okada".'
              }));
        }
      }
    } catch (e) {
      setState(() => _messages.add({
            'role': 'cfo',
            'content': 'Still waking up… please wait 30 seconds and try again.'
          }));
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Personal CFO'),
        actions: [
          IconButton(
            icon: Icon(Icons.copy),
            onPressed: _copyAllMessages,
            tooltip: 'Copy conversation',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        _messages[i]['content']!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(hintText: 'Type a transaction...'),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                  color: _isListening ? Colors.red : Colors.teal,
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}