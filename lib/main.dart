import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
// Entry point of the application
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wi-Fi Audio Streamer',
      theme: ThemeData.dark(),
      home: const AudioStreamerScreen(),
    );
  }
}

class AudioStreamerScreen extends StatefulWidget {
  const AudioStreamerScreen({Key? key}) : super(key: key);

  @override
  State<AudioStreamerScreen> createState() => _AudioStreamerScreenState();
}

class _AudioStreamerScreenState extends State<AudioStreamerScreen> {
  final _ipController = TextEditingController();

  // MODIFIED: We now store the file path instead of all its bytes in memory.
  String? _songPath;
  String _songTitle = 'No song selected';

  String _statusText = 'Please select a song';
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _ipController.text = '192.168.70.153';
  }

  // MODIFIED: This function now gets the file's PATH, not its data.
  Future<void> _pickAudioFile() async {
    // We set withData to false to only get the file path, saving memory.
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _songPath = result.files.single.path; // Store the path
        _songTitle = result.files.single.name;
        _statusText = 'Song selected. Ready to stream.';
      });
    }
  }

  Future<void> _streamAudioToESP() async {
    if (_songPath == null) {
      setState(() {
        _statusText = 'Error: No song selected!';
      });
      return;
    }
    if (_ipController.text.isEmpty) {
      setState(() {
        _statusText = 'Error: Please enter ESP32 IP address!';
      });
      return;
    }

    setState(() {
      _isStreaming = true;
      _statusText = 'Connecting to ESP32...';
    });

    Socket? socket;
    RandomAccessFile? file;

    try {
      socket = await Socket.connect(_ipController.text, 8080,
          timeout: const Duration(seconds: 5));

      setState(() {
        _statusText = 'Connected! Analyzing WAV file...';
      });

      file = await File(_songPath!).open(mode: FileMode.read);

      // --- ROUBUST WAV HEADER PARSING ---
      // This new code intelligently searches for the 'data' chunk.

      // Move pointer past the 'RIFF' and chunk size descriptor
      await file.setPosition(8);
      // Check if format is 'WAVE'
      if (String.fromCharCodes(await file.read(4)) != 'WAVE') {
        throw Exception('File is not a valid WAVE format');
      }

      bool dataChunkFound = false;
      // Loop through all chunks until we find the 'data' chunk
      while (await file.position() < await file.length()) {
        // Read chunk ID (4 bytes)
        String chunkId = String.fromCharCodes(await file.read(4));
        // Read chunk size (4 bytes)
        var sizeBytes = await file.read(4);
        int chunkSize = ByteData.sublistView(sizeBytes).getUint32(0, Endian.little);

        developer.log("Found chunk: '$chunkId' with size: $chunkSize");

        if (chunkId == 'data') {
          dataChunkFound = true;
          developer.log("PCM data found! Starting stream...");
          // The file pointer is now exactly where the raw sound data begins.
          break;
        } else {
          // This is not the data chunk, so skip its contents
          await file.setPosition(await file.position() + chunkSize);
        }
      }

      if (!dataChunkFound) {
        throw Exception('Could not find the "data" chunk in this WAV file.');
      }

      // --- Stream the file from the found position ---
      setState(() {
        _statusText = 'Streaming audio...';
      });

      const bufferSize = 4096;
      final buffer = Uint8List(bufferSize);
      int bytesRead;

      while ((bytesRead = await file.readInto(buffer)) > 0) {
        if (!_isStreaming) break;
        socket.add(buffer.sublist(0, bytesRead));
      }

      await socket.flush();
      if (mounted) {
        setState(() {
          _statusText = 'Stream finished successfully! 🎉';
        });
      }
    } catch (e) {
      developer.log("Streaming Error: $e");
      if (mounted) {
        setState(() {
          _statusText = 'Error: $e';
        });
      }
    } finally {
      socket?.destroy();
      await file?.close();
      if (mounted) {
        setState(() {
          _isStreaming = false;
        });
      }
    }
  }
  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The build method remains the same as before.
    // ... (paste your existing build method here) ...
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Audio Bridge'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple.shade900,
        elevation: 0,
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.shade800,
              Colors.deepPurple.shade400,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_tethering_rounded,
                  size: 100, color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _songTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _ipController,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'ESP32 IP Address',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isStreaming ? null : _pickAudioFile,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Choose Song'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isStreaming || _songPath == null
                    ? null
                    : _streamAudioToESP,
                icon: _isStreaming
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.send_to_mobile_rounded),
                label: Text(
                    _isStreaming ? 'Streaming...' : 'Stream to Headphone'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.green.shade600,
                  disabledBackgroundColor: Colors.grey.shade600,
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}