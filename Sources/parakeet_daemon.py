#!/usr/bin/env python3
"""
Parakeet transcription daemon - long-running process for optimal performance.
Eliminates Python startup and model loading overhead on each transcription.
"""

import sys
import json
import os
import signal
import traceback
from pathlib import Path

# Set environment to force offline operation for consistent performance
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN'] = '1'

try:
    import numpy as np
    import mlx.core as mx
    from parakeet_mlx import from_pretrained
    from parakeet_mlx.audio import get_logmel
except ImportError as e:
    print(json.dumps({"status": "error", "message": f"Import failed: {e}"}), flush=True)
    sys.exit(1)


class ParakeetDaemon:
    def __init__(self):
        self.model = None
        self.model_repo = "mlx-community/parakeet-tdt-0.6b-v3"
        self.running = True
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        self.running = False
        print(json.dumps({"status": "shutdown", "message": "Daemon shutting down"}), flush=True)
    
    def initialize_model(self):
        """Load Parakeet model once at startup"""
        try:
            print(json.dumps({"status": "loading", "message": "Loading Parakeet v3 model..."}), flush=True)
            
            # Try offline loading first for performance
            try:
                self.model = from_pretrained(self.model_repo, local_files_only=True)
                print(json.dumps({"status": "ready", "message": "Model loaded offline successfully"}), flush=True)
            except Exception as offline_error:
                print(json.dumps({"status": "warning", "message": f"Offline loading failed: {offline_error}"}), flush=True)
                print(json.dumps({"status": "loading", "message": "Falling back to online loading..."}), flush=True)
                self.model = from_pretrained(self.model_repo)
                print(json.dumps({"status": "ready", "message": "Model loaded online successfully"}), flush=True)
                
            return True
            
        except Exception as e:
            error_msg = f"Failed to load model: {e}"
            print(json.dumps({"status": "error", "message": error_msg}), flush=True)
            return False
    
    def load_raw_pcm(self, pcm_file_path, sample_rate=16000):
        """Load pre-processed raw float32 PCM data"""
        try:
            # Verify file exists and is readable
            pcm_path = Path(pcm_file_path)
            if not pcm_path.exists():
                raise FileNotFoundError(f"PCM file not found: {pcm_file_path}")
            if not os.access(pcm_file_path, os.R_OK):
                raise PermissionError(f"Cannot read PCM file: {pcm_file_path}")
            
            # Read raw float32 data from file
            audio_data = np.fromfile(pcm_file_path, dtype=np.float32)
            
            if len(audio_data) == 0:
                raise ValueError("PCM file is empty")
                
            return audio_data
            
        except Exception as e:
            raise Exception(f"Error loading PCM data: {e}")
    
    def transcribe_audio(self, pcm_file_path):
        """Transcribe audio from PCM file path"""
        try:
            if self.model is None:
                raise RuntimeError("Model not initialized")
            
            # Load the pre-processed PCM data
            audio_data = self.load_raw_pcm(pcm_file_path, sample_rate=16000)
            
            # Convert numpy array to MLX array (parakeet-mlx's format)
            audio_mlx = mx.array(audio_data.astype(np.float32))
            
            # Convert directly to log-mel spectrogram
            mel = get_logmel(audio_mlx, self.model.preprocessor_config)
            
            # Generate transcription from mel spectrogram
            result = self.model.generate(mel)
            
            # Extract text and language information from result
            text = ""
            detected_language = None
            confidence = None
            
            if isinstance(result, list) and len(result) > 0:
                # model.generate() returns a list of AlignedResult objects
                result_obj = result[0]
                text = result_obj.text if hasattr(result_obj, 'text') else str(result_obj)
                # Try to extract language information if available
                if hasattr(result_obj, 'language'):
                    detected_language = result_obj.language
                if hasattr(result_obj, 'confidence'):
                    confidence = result_obj.confidence
            elif hasattr(result, "text"):
                text = result.text
                if hasattr(result, 'language'):
                    detected_language = result.language  
                if hasattr(result, 'confidence'):
                    confidence = result.confidence
            elif hasattr(result, "texts") and len(result.texts) > 0:
                text = result.texts[0]
            elif isinstance(result, dict) and "text" in result:
                text = result["text"]
                detected_language = result.get("language")
                confidence = result.get("confidence")
            elif isinstance(result, dict) and "texts" in result and len(result["texts"]) > 0:
                text = result["texts"][0]
            else:
                raise AttributeError(f"Cannot extract text from result: {result}")
            
            text = text.strip() if text else ""
            
            # Return successful transcription
            return {
                "status": "success",
                "text": text,
                "language": detected_language,
                "confidence": confidence
            }
            
        except Exception as e:
            return {
                "status": "error", 
                "message": str(e),
                "traceback": traceback.format_exc()
            }
    
    def process_request(self, request_data):
        """Process a single transcription request"""
        try:
            if "pcm_path" not in request_data:
                return {"status": "error", "message": "Missing 'pcm_path' in request"}
            
            pcm_path = request_data["pcm_path"]
            result = self.transcribe_audio(pcm_path)
            
            return result
            
        except Exception as e:
            return {
                "status": "error", 
                "message": f"Request processing failed: {e}",
                "traceback": traceback.format_exc()
            }
    
    def run_daemon(self):
        """Main daemon loop - listen for requests on stdin"""
        print(json.dumps({"status": "starting", "message": "Parakeet daemon starting..."}), flush=True)
        
        # Initialize model at startup
        if not self.initialize_model():
            sys.exit(1)
        
        print(json.dumps({"status": "listening", "message": "Daemon ready for requests"}), flush=True)
        
        # Main request processing loop
        while self.running:
            try:
                # Read request from stdin (blocking)
                line = sys.stdin.readline()
                
                if not line:  # EOF - Swift process closed stdin
                    break
                
                line = line.strip()
                if not line:  # Empty line
                    continue
                
                # Parse JSON request
                try:
                    request = json.loads(line)
                except json.JSONDecodeError as e:
                    response = {"status": "error", "message": f"Invalid JSON: {e}"}
                    print(json.dumps(response), flush=True)
                    continue
                
                # Handle special commands
                if request.get("command") == "ping":
                    response = {"status": "pong", "message": "Daemon is alive"}
                    print(json.dumps(response), flush=True)
                    continue
                
                if request.get("command") == "shutdown":
                    self.running = False
                    response = {"status": "shutdown", "message": "Shutting down gracefully"}
                    print(json.dumps(response), flush=True)
                    break
                
                # Process transcription request
                response = self.process_request(request)
                print(json.dumps(response), flush=True)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                error_response = {
                    "status": "error", 
                    "message": f"Daemon error: {e}",
                    "traceback": traceback.format_exc()
                }
                print(json.dumps(error_response), flush=True)
        
        print(json.dumps({"status": "stopped", "message": "Daemon stopped"}), flush=True)


def main():
    """Main entry point"""
    daemon = ParakeetDaemon()
    daemon.run_daemon()


if __name__ == "__main__":
    main()