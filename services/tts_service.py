import os
from google.cloud import texttospeech
from utils.logger import log

# =========================
# Text-To-Speech Service (Google Cloud TTS - Chirp 3 HD)
# =========================

CHIRP3_HD_VOICES = ['Aoede', 'Kore', 'Leda', 'Zephyr', 'Puck', 'Charon', 'Fenrir', 'Orus']

DEFAULT_VOICE = "Aoede"
DEFAULT_LANGUAGE = "vi-VN"
DEFAULT_MODEL = "Chirp3-HD"

_tts_client = None


def get_tts_client():
    global _tts_client
    if _tts_client is None:
        log.info("Khởi tạo Google Cloud TTS client...")
        _tts_client = texttospeech.TextToSpeechClient()
    return _tts_client


def generate_speech_file(
    text: str,
    output_path: str,
    voice: str = DEFAULT_VOICE,
    speaking_rate: float = 1.0,
    language: str = DEFAULT_LANGUAGE,
    model: str = DEFAULT_MODEL,
) -> str:
    """
    Gửi text lên Google Cloud TTS Chirp 3 HD, lưu file MP3 ra disk.
    Trả về đường dẫn file đã lưu.
    Dùng synchronous API (chạy trong QThread).
    """
    client = get_tts_client()

    if voice not in CHIRP3_HD_VOICES:
        voice = DEFAULT_VOICE
    voice_name = f"{language}-{model}-{voice}"

    synthesis_input = texttospeech.SynthesisInput(text=text)

    voice_params = texttospeech.VoiceSelectionParams(
        language_code=language,
        name=voice_name,
    )

    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3,
        speaking_rate=max(0.25, min(4.0, speaking_rate)),
    )

    log.info(f"Google TTS: voice={voice_name}, rate={speaking_rate}")

    response = client.synthesize_speech(
        input=synthesis_input,
        voice=voice_params,
        audio_config=audio_config,
    )

    # Đảm bảo thư mục tồn tại
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

    with open(output_path, "wb") as f:
        f.write(response.audio_content)

    log.info(f"TTS file saved: {output_path} ({len(response.audio_content)} bytes)")
    return output_path
