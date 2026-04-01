"""
Deepgram STT Streaming Service — Raw WebSocket
Mở kết nối wss://api.deepgram.com/v1/listen để stream audio real-time.
"""
import os
import json
import asyncio
import websockets
from utils.logger import log


DEEPGRAM_WS_URL = "wss://api.deepgram.com/v1/listen"


class StreamingSTTSession:
    """
    Quản lý 1 phiên streaming STT tới Deepgram.
    - on_interim(text): callback khi có interim result (đang nói)
    - on_final(text, speaker): callback khi có final result (ngưng nói)
    - on_error(err): callback khi có lỗi
    """

    def __init__(self, on_interim=None, on_final=None, on_error=None,
                 model="nova-2", language="vi"):
        self.on_interim = on_interim
        self.on_final = on_final
        self.on_error = on_error
        self.model = model
        self.language = language
        self._ws = None
        self._receive_task = None
        self._running = False

    async def start(self):
        """Mở kết nối WebSocket tới Deepgram."""
        api_key = os.getenv("DEEPGRAM_API_KEY")
        if not api_key:
            raise Exception("DEEPGRAM_API_KEY not set in .env")

        params = (
            f"?model={self.model}"
            f"&language={self.language}"
            f"&smart_format=true"
            f"&diarize=true"
            f"&interim_results=true"
            f"&utterance_end_ms=1500"
            f"&encoding=linear16"
            f"&sample_rate=16000"
            f"&channels=1"
        )
        url = DEEPGRAM_WS_URL + params
        headers = {"Authorization": f"Token {api_key}"}

        log.info(f"🎙️ Mở kết nối Deepgram Streaming: model={self.model}, lang={self.language}")

        try:
            self._ws = await websockets.connect(url, additional_headers=headers)
            self._running = True
            self._receive_task = asyncio.create_task(self._receive_loop())
            log.info("✅ Deepgram Streaming connected!")
        except Exception as e:
            log.error(f"❌ Deepgram connect failed: {e}")
            if self.on_error:
                await self.on_error(str(e))
            raise

    async def send_audio(self, chunk: bytes):
        """Gửi 1 chunk audio PCM tới Deepgram."""
        if self._ws and self._running:
            try:
                await self._ws.send(chunk)
            except Exception as e:
                log.error(f"❌ Send audio error: {e}")

    async def stop(self):
        """Đóng kết nối Deepgram."""
        self._running = False
        if self._ws:
            try:
                # Gửi tín hiệu kết thúc
                await self._ws.send(json.dumps({"type": "CloseStream"}))
                await self._ws.close()
                log.info("🔌 Deepgram Streaming disconnected.")
            except Exception:
                pass
        if self._receive_task:
            self._receive_task.cancel()
            try:
                await self._receive_task
            except asyncio.CancelledError:
                pass

    async def _receive_loop(self):
        """Vòng lặp nhận kết quả từ Deepgram."""
        try:
            async for msg in self._ws:
                if not self._running:
                    break
                try:
                    data = json.loads(msg)
                    await self._handle_message(data)
                except json.JSONDecodeError:
                    continue
        except websockets.exceptions.ConnectionClosed as e:
            log.warning(f"🔌 Deepgram WS closed: code={e.code}")
        except asyncio.CancelledError:
            pass
        except Exception as e:
            log.error(f"❌ Deepgram receive error: {e}")
            if self.on_error:
                await self.on_error(str(e))

    async def _handle_message(self, data: dict):
        """Parse JSON từ Deepgram và gọi callbacks."""
        msg_type = data.get("type", "")

        if msg_type == "Results":
            channel = data.get("channel", {})
            alt = channel.get("alternatives", [{}])[0]
            transcript = alt.get("transcript", "").strip()
            is_final = data.get("is_final", False)

            if not transcript:
                return

            # Tìm speaker từ diarization
            words = alt.get("words", [])
            speaker = -1
            if words:
                speaker = words[0].get("speaker", -1)

            if is_final:
                if self.on_final:
                    await self.on_final(transcript, speaker)
            else:
                if self.on_interim:
                    await self.on_interim(transcript)

        elif msg_type == "Metadata":
            request_id = data.get("request_id", "?")
            model_name = data.get("model_info", {}).get("name", "?")
            log.info(f"📋 Deepgram metadata: model={model_name}, request_id={request_id}")

        elif msg_type == "Error":
            desc = data.get("description", str(data))
            log.error(f"❌ Deepgram error: {desc}")
            if self.on_error:
                await self.on_error(desc)
