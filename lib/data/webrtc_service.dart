import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  final Map<String, dynamic> configuration = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ]
  };

  Future<void> initLocalStream(RTCVideoRenderer localRenderer) async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'facingMode': 'user',
      }
    };
    
    localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = localStream;
  }

  Future<void> setupPeerConnection(RTCVideoRenderer remoteRenderer, Function(RTCIceCandidate) onIceCandidate) async {
    _peerConnection = await createPeerConnection(configuration);
    
    _peerConnection?.onIceCandidate = (candidate) {
      onIceCandidate(candidate);
    };

    _peerConnection?.onAddStream = (stream) {
      remoteStream = stream;
      remoteRenderer.srcObject = stream;
      debugPrint("Remote stream added");
    };

    if (localStream != null) {
      _peerConnection?.addStream(localStream!);
    }
  }

  Future<RTCSessionDescription> createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<void> handleOffer(RTCSessionDescription offer, Function(RTCSessionDescription) sendAnswerCallback) async {
    await _peerConnection?.setRemoteDescription(offer);
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    sendAnswerCallback(answer);
  }

  Future<void> handleAnswer(RTCSessionDescription answer) async {
    await _peerConnection?.setRemoteDescription(answer);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection?.addCandidate(candidate);
  }

  void dispose() {
    localStream?.dispose();
    remoteStream?.dispose();
    _peerConnection?.dispose();
  }
}
