import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const FeedVideoPlayer({super.key, required this.videoUrl});

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      });
      
    _controller.addListener(() {
      if (mounted) {
        final isPlaying = _controller.value.isPlaying;
        if (isPlaying != _isPlaying) {
          setState(() {
            _isPlaying = isPlaying;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        height: 300,
        color: Colors.black12,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          // Oynat/Duraklat İkonu (Video oynarken kaybolur)
          if (!_isPlaying)
            Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 40,
              ),
            ),
          // Ses ikonu (Opsiyonel: sağ altta)
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.volume_up, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
