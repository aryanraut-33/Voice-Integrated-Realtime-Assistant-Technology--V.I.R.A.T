import os
import struct
import wave
import threading
import subprocess
from datetime import datetime
from dotenv import load_dotenv

import google.generativeai as genai
import pyaudio
import pvporcupine
from flask import Flask, jsonify, request
from flask_cors import CORS

# --- Constants and Configuration ---
# Using constants makes the code cleaner and easier to modify.

# Recording settings
RECORD_SECONDS = 12
WAVE_OUTPUT_FILENAME = "temp_recording.wav"

# --- IMPORTANT: Verify and set your paths here ---
# Ensure these absolute paths are correct for your system.
WHISPER_CPP_PATH = "/Users/aryan/MACHINE-LEARNING/Project Vi/whisper.cpp"
WHISPER_CLI_PATH = f"{WHISPER_CPP_PATH}/build/bin/whisper-cli"
WHISPER_MODEL_PATH = f"{WHISPER_CPP_PATH}/models/ggml-base.en.bin"


# --- Initialization and Pre-flight Checks ---

print("Initializing V.I.R.A.T. Backend...")

# Load environment variables from the .env file
load_dotenv()

# --- Critical Pre-flight Checks ---
# Check for API keys and necessary files before starting.
# This prevents the application from starting in a broken state.
PICOVOICE_API_KEY = os.environ.get("PICOVOICE_API_KEY")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

if not PICOVOICE_API_KEY:
    raise ValueError("FATAL: PICOVOICE_API_KEY not found in .env file.")
if not GEMINI_API_KEY:
    raise ValueError("FATAL: GEMINI_API_KEY not found in .env file.")
if not os.path.exists(WHISPER_CLI_PATH):
    raise FileNotFoundError(f"FATAL: Whisper executable not found at {WHISPER_CLI_PATH}")
if not os.path.exists(WHISPER_MODEL_PATH):
    raise FileNotFoundError(f"FATAL: Whisper model not found at {WHISPER_MODEL_PATH}")

# Configure the Gemini client
try:
    genai.configure(api_key=GEMINI_API_KEY)
    # The new Gemini API uses a system_instruction parameter for setting the persona
    # which is more effective than adding a system message to the chat history.
    generation_config = {"temperature": 0.7}
    safety_settings = {
        "HARM_CATEGORY_HARASSMENT": "BLOCK_MEDIUM_AND_ABOVE",
        "HARM_CATEGORY_HATE_SPEECH": "BLOCK_MEDIUM_AND_ABOVE",
        "HARM_CATEGORY_SEXUALLY_EXPLICIT": "BLOCK_MEDIUM_AND_ABOVE",
        "HARM_CATEGORY_DANGEROUS_CONTENT": "BLOCK_MEDIUM_AND_ABOVE",
    }
    model = genai.GenerativeModel('gemini-2.5-flash', generation_config=generation_config, safety_settings=safety_settings)
    print("Gemini client configured successfully.")
except Exception as e:
    raise RuntimeError(f"FATAL: Failed to configure Gemini client: {e}")

# Initialize Flask App
app = Flask(__name__)
CORS(app)

# Global in-memory store for the conversation history
conversation = []


# --- Core Functions with Detailed Error Handling ---

def record_audio(filename, duration, sample_rate, frame_length):
    """
    Records audio from the microphone for a fixed duration.
    This function is designed to be robust, ensuring resources are always released.
    """
    pa = pyaudio.PyAudio()
    stream = None
    try:
        stream = pa.open(
            rate=sample_rate,
            channels=1,
            format=pyaudio.paInt16,
            input=True,
            frames_per_buffer=frame_length
        )
        print("Recording...")
        frames = [stream.read(frame_length) for _ in range(0, int(sample_rate / frame_length * duration))]
        print("Recording stopped.")
        
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(1)
            wf.setsampwidth(pa.get_sample_size(pyaudio.paInt16))
            wf.setframerate(sample_rate)
            wf.writeframes(b''.join(frames))
            
    except IOError as e:
        print(f"AUDIO ERROR: Could not record audio. Is microphone connected? Error: {e}")
    finally:
        if stream and stream.is_active():
            stream.stop_stream()
            stream.close()
        if pa:
            pa.terminate()

def transcribe_audio(filename):
    """
    Transcribes the audio file using whisper.cpp via a subprocess call.
    Uses subprocess.run for better error handling than os.popen.
    """
    command = [
        WHISPER_CLI_PATH,
        '-m', WHISPER_MODEL_PATH,
        '-f', filename,
        '-otxt' # Output as a text file
    ]
    try:
        # We use subprocess.run for better control and error capturing
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        
        # Whisper-cli creates a .txt file. We need to read it.
        output_txt_file = f"{filename}.txt"
        if os.path.exists(output_txt_file):
            with open(output_txt_file, 'r') as f:
                transcribed_text = f.read().strip()
            os.remove(output_txt_file) # Clean up the text file
            
            # The output may still contain timestamps. We clean it.
            clean_text = transcribed_text.split("]", 1)[1].strip() if "]" in transcribed_text else transcribed_text
            print(f"You said: {clean_text}")
            return clean_text
        else:
            print("TRANSCRIPTION ERROR: Output file was not created by Whisper.")
            return ""

    except subprocess.CalledProcessError as e:
        # This catches errors if whisper-cli returns a non-zero exit code
        print(f"WHISPER ERROR: whisper-cli failed with exit code {e.returncode}.")
        print(f"   Stderr: {e.stderr}")
        return ""
    except Exception as e:
        print(f"An unexpected error occurred during transcription: {e}")
        return ""

def process_query(user_query):
    """
    Sends the user's query to the Gemini API with a detailed system prompt
    to define the assistant's persona and behavior.
    """
    global conversation
    conversation.append({"role": "user", "parts": [user_query]})

    # --- Comprehensive Persona and Instruction Prompt ---
    # This is passed as a system instruction to the Gemini model.
    system_instruction = (
        "You are V.I.R.A.T. (Voice Integrated Realtime Assistance Technology), a sophisticated AI assistant "
        "integrated into a user's macOS computer. Your designated persona is that of a helpful, professional, "
        "and friendly Indian man in his late 20s. You are fluent and natural in English, Hindi, and Hinglish. "
        "Your primary directive is to be as helpful as possible."
        "\n**Core Rules:**"
        "\n1. **Language Matching:** You MUST respond in the primary language used in the user's query. If the query is in Hinglish, respond in natural-sounding Hinglish. If it's in Hindi, respond in Hindi."
        "\n2. **Conciseness:** Provide direct answers. Avoid unnecessary conversational filler or verbosity. Get straight to the point."
        "\n3. **Tone:** Maintain a calm, capable, and slightly formal but approachable tone."
        "\n4. **Factuality:** Do not invent facts, URLs, or information. If you do not know an answer, state that you are unable to find the information."
        "\n5. **No Follow-up Questions:** Do not end your responses with questions like 'Is there anything else I can help you with?' or 'How else can I assist?'. Simply provide the answer."
        "\n6. **Context:** You have access to the recent conversation history. Use it to understand follow-up questions."
    )
    
    # Adapt the conversation history for the Gemini API format
    messages_for_api = [msg for msg in conversation if msg['role'] != 'model' or msg.get('parts')]

    try:
        chat_session = model.start_chat(history=messages_for_api)
        response = chat_session.send_message(user_query, stream=False)

        # Robustly check for a valid response, handling safety blocks
        if response.candidates and response.candidates[0].content.parts:
            ai_response = response.candidates[0].content.parts[0].text.strip()
        elif response.candidates and response.candidates[0].finish_reason.name != "STOP":
             ai_response = f"My response was blocked due to: {response.candidates[0].finish_reason.name}. Please rephrase your query."
        else:
            ai_response = "I'm sorry, I couldn't generate a response for that."
            
        conversation.append({"role": "model", "parts": [ai_response]})
        print(f"V.I.R.A.T: {ai_response}")

    except Exception as e:
        error_message = f"Error communicating with Gemini API: {e}"
        conversation.append({"role": "model", "parts": [error_message]})
        print(f"API ERROR: {error_message}")

def wake_word_listener():
    """
    Infinitely listens for the wake word in a separate thread.
    Manages audio resources carefully to prevent system-level errors.
    """
    porcupine = None
    pa = None
    try:
        porcupine = pvporcupine.create(access_key=PICOVOICE_API_KEY, keywords=['hey barista'])
        pa = pyaudio.PyAudio()
        print(f"Wake word engine is listening for 'Hey Barista'...")
        while True:
            audio_stream = pa.open(rate=porcupine.sample_rate, channels=1, format=pyaudio.paInt16, input=True, frames_per_buffer=porcupine.frame_length)
            while True:
                pcm = audio_stream.read(porcupine.frame_length, exception_on_overflow=False)
                pcm = struct.unpack_from("h" * porcupine.frame_length, pcm)
                if porcupine.process(pcm) >= 0:
                    print("Wake word detected!")
                    break
            audio_stream.close() # Close the listening stream immediately
            
            record_audio(WAVE_OUTPUT_FILENAME, RECORD_SECONDS, porcupine.sample_rate, porcupine.frame_length)
            user_query = transcribe_audio(WAVE_OUTPUT_FILENAME)
            if user_query:
                process_query(user_query)
    except pvporcupine.PorcupineError as e:
        print(f"PICVOICE ERROR: Failed to initialize Porcupine. Is your AccessKey valid? Error: {e}")
    except Exception as e:
        print(f"An error occurred in the wake word listener: {e}")
    finally:
        if porcupine: porcupine.delete()
        if pa: pa.terminate()

# --- Flask API Endpoints for UI Communication ---
@app.route('/ask', methods=['POST'])
def ask():
    try:
        data = request.json
        user_query = data.get('query')
        if user_query:
            process_query(user_query)
            return jsonify({"status": "success"})
        return jsonify({"status": "error", "message": "Invalid query provided"}), 400
    except Exception as e:
        return jsonify({"status": "error", "message": f"Server error: {e}"}), 500

@app.route('/get_updates', methods=['GET'])
def get_updates():
    # --- CRITICAL DATA FORMATTING FIX ---
    # The Swift UI expects a field named "text". The Gemini API provides "parts".
    # We must translate the format here before sending it to the UI.
    ui_conversation = []
    for msg in conversation:
        # Ensure the message has parts and the parts list is not empty
        if 'parts' in msg and msg['parts']:
            ui_conversation.append({
                "role": msg["role"], 
                "text": msg["parts"][0] # <-- Use "text" key
            })
    
    return jsonify({"conversation": ui_conversation})

# --- Main Application Execution ---
if __name__ == '__main__':
    listener_thread = threading.Thread(target=wake_word_listener, daemon=True)
    listener_thread.start()
    
    print("Starting Flask server for UI communication on http://127.0.0.1:5001")
    app.run(port=5001)
