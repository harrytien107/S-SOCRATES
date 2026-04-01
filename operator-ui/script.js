let currentData = null;
let selectedEmotion = 'neutral';
let lastLogMsg = "";

// Remote Mic Control State
let isMicActive = false;
let micTimerInterval = null;
let micStartTime = null;

function formatTimer(ms) {
    const totalSec = Math.floor(ms / 1000);
    const min = String(Math.floor(totalSec / 60)).padStart(2, '0');
    const sec = String(totalSec % 60).padStart(2, '0');
    return `${min}:${sec}`;
}

// === Gửi lệnh Mic tới Backend ===
async function _sendMicAction(action) {
    const base = window.location.origin;
    try {
        await fetch(`${base}/operator/mic-control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action })
        });
        return true;
    } catch (err) {
        addLog(`⚠️ Không gửi được lệnh mic: ${action}`);
        return false;
    }
}

// === QUICK SEND — Gửi emotion trực tiếp qua /send-to-robot ===
// Không cần bấm SEND TO BOT. Dùng kênh đã hoạt động tốt.
async function quickSendEmotion(emo, btn) {
    const base = window.location.origin;

    // Highlight nút được chọn  
    setEmotion(emo, btn, false);

    try {
        const response = await fetch(`${base}/send-to-robot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: '', emotion: emo })
        });
        const result = await response.json();
        if (result.status) {
            if (emo === 'listening') {
                addLog(`🎙️ → Robot đang LẮNG NGHE (mic bật thật)`);
            } else if (emo === 'uploading') {
                addLog(`📤 → Robot đang GỬI audio lên server...`);
            } else {
                addLog(`✓ Sent emotion: ${emo}`);
            }
        } else {
            throw new Error("Queue failed");
        }
    } catch (err) {
        addLog(`⚠️ Không gửi được lệnh ${emo}`);
    }
}

// === HỦY BỎ (nếu cần gọi từ logic khác) ===
async function cancelRobotMic() {
    if (!isMicActive) return;
    if (await _sendMicAction('cancel')) {
        isMicActive = false;
        addLog(`❌ Đã HỦY thu âm. Dữ liệu không được gửi.`);
    }
}

// === WEBSOCKET CONNECTION ===
let ws = null;
let reconnectTimer = null;
let _lastSyncedStatus = 'idle';

function connectWebSocket() {
    const baseInput = window.location.origin;
    // Chuyển HTTP/HTTPS -> WS/WSS
    let wsUrl = baseInput.replace('http:', 'ws:').replace('https:', 'wss:') + '/ws/operator';
    
    addLog('🔌 Connecting to WebSocket...');
    ws = new WebSocket(wsUrl);

    ws.onopen = () => {
        document.getElementById('online-dot').classList.add('active');
        addLog("🟢 WebSocket Connected!");
        if (reconnectTimer) clearInterval(reconnectTimer);
    };

    ws.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            
            if (msg.type === 'mic_status') {
                const status = msg.status || 'idle';
                if (status === _lastSyncedStatus) return;
                _lastSyncedStatus = status;

                if (status === 'listening' && !isMicActive) {
                    isMicActive = true;
                    addLog(`🎙️ [Sync] App bật Mic.`);
                } else if (status !== 'listening' && isMicActive) {
                    isMicActive = false;
                    if (status === 'processing') addLog(`📤 [Sync] App gửi audio lên Server.`);
                }
            }
            
            if (msg.type === 'transcript') {
                currentData = msg.data;
                displayWorkflow(msg.data);
                addLog("⚡ Received real-time voice input from Robot.");
            }

            if (msg.type === 'stt_interim') {
                // Deepgram: đang nói — cập nhật dòng nhảy chữ
                const interim = document.getElementById('transcript-interim');
                if (interim) interim.textContent = '░░ ' + msg.text + '...';
            }

            if (msg.type === 'stt_final') {
                // Deepgram: chốt 1 câu — thêm vào transcript log
                const box = document.getElementById('transcript-box');
                const speakerLabel = msg.speaker >= 0 ? `[Speaker ${msg.speaker}]` : '';
                if (box.textContent === 'Chưa có tín hiệu âm thanh...') box.innerHTML = '';
                box.innerHTML += `<p style="margin: 4px 0;"><span style="color: var(--cyan); font-weight: 600;">${speakerLabel}</span> ${msg.text}</p>`;
                box.scrollTop = box.scrollHeight;
                // Xóa dòng interim
                const interim = document.getElementById('transcript-interim');
                if (interim) interim.textContent = '';
                addLog(`🎙️ [Final] ${speakerLabel} ${msg.text.substring(0, 50)}...`);
            }

            if (msg.type === 'stt_error') {
                addLog(`❌ STT Error: ${msg.error}`);
            }

            if (msg.type === 'stream_progress') {
                // TTS streaming: AI đang nói từng câu
                addLog(`🗣️ Chunk #${msg.index}: ${msg.text.substring(0, 40)}...`);
            }

            if (msg.type === 'log') {
                addLog(`📱 ROBOT: ${msg.message}`);
            }

        } catch (e) {
            console.error('WS parse error:', e);
        }
    };

    ws.onclose = () => {
        document.getElementById('online-dot').classList.remove('active');
        addLog("🔴 WebSocket Disconnected. Reconnecting...");
        ws = null;
        if (!reconnectTimer) {
            reconnectTimer = setInterval(connectWebSocket, 3000);
        }
    };

    ws.onerror = (error) => {
        console.error("WebSocket Error: ", error);
        ws.close();
    };
}

window.onload = () => {
    
    const preview = document.getElementById('final-preview');
    preview.addEventListener('input', updateSendButton);
    preview.addEventListener('paste', (e) => e.preventDefault());
    preview.addEventListener('keydown', (e) => e.preventDefault());
    
    checkConnection();
    updateSendButton();
    addLog("Console Ready.");
    
    // Khởi tạo WebSocket thay vì setInterval polling
    connectWebSocket();
};

function addLog(msg) {
    if (msg === lastLogMsg) return; // Anti-spam
    lastLogMsg = msg;

    const logContainer = document.getElementById('log-container');
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    entry.innerHTML = `<span style="color: var(--text-dim)">[${time}]</span> ${msg}`;
    
    logContainer.insertBefore(entry, logContainer.firstChild);

    const maxLogs = logContainer.classList.contains('log-expanded') ? 100 : 20;
    while (logContainer.children.length > maxLogs) {
        logContainer.removeChild(logContainer.lastChild);
    }
}

let _logExpanded = false;
function toggleLogExpand() {
    _logExpanded = !_logExpanded;
    const container = document.getElementById('log-container');
    const btn = document.getElementById('expand-log-btn');
    if (_logExpanded) {
        container.classList.add('log-expanded');
        container.style.maxHeight = '500px';
        container.style.minHeight = '300px';
        btn.textContent = '⤡ COLLAPSE';
    } else {
        container.classList.remove('log-expanded');
        container.style.maxHeight = '';
        container.style.minHeight = '';
        btn.textContent = '⤢ EXPAND';
    }
}

function statusMessage(msg, type = 'normal') {
    const status = document.getElementById('last-sent-status');
    status.innerText = msg;
    status.style.color = type === 'error' ? 'var(--danger)' : (type === 'success' ? 'var(--cyan)' : 'var(--text-dim)');
}

function toggleModal(show) {
    document.getElementById('settings-modal').classList.toggle('open', show);
    if (show) syncConfigs();
}

function syncExpandedPreview() {
    const preview = document.getElementById('final-preview');
    const expanded = document.getElementById('final-preview-expanded');
    if (!preview || !expanded) return;
    expanded.innerText = preview.innerText || '';
}

function togglePreviewModal(show) {
    const modal = document.getElementById('preview-modal');
    if (!modal) return;
    if (show) {
        syncExpandedPreview();
    }
    modal.classList.toggle('open', show);
}

async function saveSettings() {
    const base = window.location.origin;

    // Push audio config to backend
    try {
        await fetch(`${base}/configs`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                tts_voice: document.getElementById('cfg-tts-voice').value,
                tts_speed: parseFloat(document.getElementById('cfg-tts-speed').value),
                stt_model: document.getElementById('cfg-stt-model').value,
                stt_language: document.getElementById('cfg-stt-language').value,
                gemini_model: document.getElementById('cfg-gemini-model').value,
            })
        });
        addLog("🔊 Audio config saved to backend.");
    } catch (err) {
        addLog("⚠️ Failed to save audio config.");
    }

    checkConnection();
    toggleModal(false);
    addLog("Settings updated.");
}

async function syncConfigs() {
    const base = window.location.origin;
    try {
        const res = await fetch(`${base}/configs`);
        if (!res.ok) return;
        const data = await res.json();
        const cfg = data.config;

        // Sync TTS Voice
        const voiceEl = document.getElementById('cfg-tts-voice');
        if (voiceEl) voiceEl.value = cfg.tts_voice;

        // Sync TTS Speed
        const speedEl = document.getElementById('cfg-tts-speed');
        const speedDisplay = document.getElementById('speed-display');
        if (speedEl) {
            speedEl.value = cfg.tts_speed;
            if (speedDisplay) speedDisplay.innerText = cfg.tts_speed + 'x';
        }

        // Sync STT Model
        const modelEl = document.getElementById('cfg-stt-model');
        if (modelEl) modelEl.value = cfg.stt_model;

        // Sync STT Language
        const langEl = document.getElementById('cfg-stt-language');
        if (langEl) langEl.value = cfg.stt_language;

        // Sync Gemini Model
        const geminiEl = document.getElementById('cfg-gemini-model');
        if (geminiEl) geminiEl.value = cfg.gemini_model;

        addLog("🔧 Synced audio config from backend.");
    } catch (err) {
        // Silent fail - backend might not be up yet
    }
}

function checkConnection() {
    const base = window.location.origin;
    fetch(`${base}/`).then(() => {
        addLog("HTTP API Online. Waiting for WS...");
    }).catch(() => {
        addLog("Backend Offline.");
    });
}

async function handleFileUpload(input) {
    if (!input.files || !input.files[0]) return;
    const file = input.files[0];
    const base = window.location.origin;
    
    toggleModal(false);
    addLog(`Audio File: ${file.name}`);
    document.getElementById('transcript-box').innerHTML = '<span class="transcript-highlight">Processing...</span>';
    
    const formData = new FormData();
    formData.append('file', file);

    try {
        const response = await fetch(`${base}/process-audio`, {
            method: 'POST',
            body: formData
        });
        const data = await response.json();
        currentData = data;
        displayWorkflow(data);
        addLog("Transcript received.");
    } catch (err) {
        document.getElementById('transcript-box').innerText = "Connection Error";
        addLog("STT Failed.");
    }
}

function displayWorkflow(data) {
    document.getElementById('transcript-box').innerHTML = data.transcript;
    const list = document.getElementById('suggestions-list');
    list.innerHTML = '';
    
    if (data.candidates && data.candidates.length > 0) {
        document.getElementById('match-count').innerText = `${data.candidates.length} matches`;
        data.candidates.forEach((c) => {
            const card = document.createElement('div');
            card.className = 'suggestion-card';
            card.innerHTML = `
                <span class="score-pill">${(c.score * 100).toFixed(0)}%</span>
                <div class="a-text">${c.answer}</div>
            `;
            card.onclick = () => selectResponse(c.answer, 'preset', card);
            list.appendChild(card);
        });
    } else {
        list.innerHTML = '<div style="text-align: center; color: var(--text-dim); margin-top: 2rem;">No presets match.</div>';
    }
}

function selectResponse(text, mode, element) {
    document.getElementById('final-preview').innerText = text;
    syncExpandedPreview();
    updateSendButton();
    
    document.querySelectorAll('.suggestion-card').forEach(el => el.classList.remove('active'));
    if (element) element.classList.add('active');
    addLog(`Preset selected.`);
}

function updateSendButton() {
    const rawText = document.getElementById('final-preview').innerText.trim();
    const btn = document.getElementById('send-trigger');
    const hasText = rawText.length > 0;
    if (hasText && selectedEmotion === 'neutral') {
        setEmotion('speaking', null, false);
        return;
    }
    const textRequired = selectedEmotion === 'speaking' || selectedEmotion === 'challenge';

    btn.disabled = textRequired && !hasText;
    if (btn.disabled) {
        statusMessage("Speaking/Challenge cần nội dung để gửi");
        return;
    }
    statusMessage(textRequired ? "Ready to Send" : "Ready to Send (emotion only)");
}

async function useAI() {
    const base = window.location.origin;
    if (!currentData || !currentData.transcript) {
        // Disabled logic via updateSendButton or similar, no alert
        return;
    }
    
    const btn = document.querySelector('.ai-reflex-btn');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<span>⏳ GEN...</span>';
    btn.disabled = true;
    statusMessage("Generating AI reflex...");

    try {
        const response = await fetch(`${base}/operator-decision`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mode: 'ai',
                transcript: currentData.transcript
            })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);
        
        document.getElementById('final-preview').innerText = result.text;
        syncExpandedPreview();
        setEmotion(result.emotion, null, false); // Don't log auto-set emotion
        updateSendButton();
        addLog("AI response generated.");
    } catch (err) {
        addLog("AI Failed.");
        statusMessage("AI Generation Failed", "error");
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}

async function useGemini() {
    const base = window.location.origin;
    if (!currentData || !currentData.transcript) {
        return;
    }
    
    const btn = document.querySelector('.gemini-btn');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<span>⏳ GEMINI...</span>';
    btn.disabled = true;
    statusMessage("Generating Gemini response...");

    try {
        const response = await fetch(`${base}/operator-decision`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mode: 'gemini',
                transcript: currentData.transcript
            })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);
        
        document.getElementById('final-preview').innerText = result.text;
        syncExpandedPreview();
        setEmotion(result.emotion, null, false);
        updateSendButton();
        addLog("💎 Gemini response generated.");
    } catch (err) {
        addLog("💎 Gemini Failed.");
        statusMessage("Gemini Generation Failed", "error");
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}

function setEmotion(emo, btn, explicit = true) {
    if (selectedEmotion === emo) {
        document.querySelectorAll('.emotion-btn').forEach(el => {
            el.classList.toggle('active', el.dataset.emotion === emo);
        });
        return;
    }
    selectedEmotion = emo;
    document.querySelectorAll('.emotion-btn').forEach(el => {
        el.classList.toggle('active', el.dataset.emotion === emo);
    });
    if (explicit) addLog(`Emotion: ${emo}`);
    updateSendButton();
}

async function setEmotionAndRecord(btn) {
    // Bước 1: Đặt emotion listening cho Orb 3D
    setEmotion('listening', btn, true);

    // Bước 2: Nếu đang trong trạng thái listening rồi thì TẮT (toggle)
    if (isMicActive) {
        await toggleRobotMic(); // Đây là nút tắt
        return;
    }

    // Bước 3: Bật mic thật qua cùng đường với nút BẬT MIC ROBOT
    await toggleRobotMic();
    addLog("🎙️ Listening thật — Mic đã bật kèm Emotion listening.");
}

async function sendToRobot() {
    const base = window.location.origin;
    const rawText = document.getElementById('final-preview').innerText.trim();
    if (rawText.length > 0 && selectedEmotion === 'neutral') {
        setEmotion('speaking', null, false);
    }
    const text = selectedEmotion === 'no_voice'
        ? "Không nhận được voice. Vui lòng nói lại."
        : rawText;
    const btn = document.getElementById('send-trigger');
    const textRequired = selectedEmotion === 'speaking' || selectedEmotion === 'challenge';
    if (textRequired && !text) return;

    btn.disabled = true;
    statusMessage("Sending to Robot...", "normal");

    try {
        // Chỉ dùng streaming TTS cho speaking/challenge (cần phát giọng)
        // Các emotion khác (error, no_voice, neutral...) chỉ gửi command, KHÔNG đọc
        const needsTTS = selectedEmotion === 'speaking' || selectedEmotion === 'challenge';
        
        let result;
        if (needsTTS && text) {
            const response = await fetch(`${base}/operator-decision/stream-tts`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text, emotion: selectedEmotion })
            });
            result = await response.json();
            if (result.error) throw new Error(result.error);
            addLog(`✓ Sent to Robot [${selectedEmotion.toUpperCase()}] — ${result.chunks} chunks`);
            statusMessage(`Sent Successfully! (${result.chunks} chunks)`, "success");
        } else {
            // Emotion-only command (no TTS)
            const response = await fetch(`${base}/send-to-robot`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text: text || '', emotion: selectedEmotion })
            });
            result = await response.json();
            if (result.error) throw new Error(result.error);
            addLog(`✓ Sent to Robot [${selectedEmotion.toUpperCase()}]`);
            statusMessage("Sent Successfully!", "success");
        }
        setTimeout(() => updateSendButton(), 3000);
    } catch (err) {
        addLog(`✕ Send Failed: ${err.message}`);
        statusMessage("Send Failed", "error");
        btn.disabled = false;
    }
}

// =========================
// LIVE AUDIO STREAMING
// =========================
let audioWs = null;
let audioContext = null;
let audioStream = null;
let isLiveStreaming = false;

// Audio source toggle
document.getElementById('audio-source')?.addEventListener('change', function() {
    const deviceSelector = document.getElementById('device-selector');
    if (this.value === 'laptop') {
        deviceSelector.style.display = 'block';
        enumerateAudioDevices();
    } else {
        deviceSelector.style.display = 'none';
    }
});

async function enumerateAudioDevices() {
    const select = document.getElementById('audio-device-select');
    try {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            select.innerHTML = '<option disabled>Trình duyệt chặn Mic vì không dùng mã hoá HTTPS hoặc Localhost</option>';
            throw new Error("Trình duyệt chặn quyền truy cập Mic (yêu cầu HTTPS hoặc truy cập qua localhost)");
        }
        await navigator.mediaDevices.getUserMedia({ audio: true });
        const devices = await navigator.mediaDevices.enumerateDevices();
        const audioInputs = devices.filter(d => d.kind === 'audioinput');
        
        select.innerHTML = '';
        if (audioInputs.length === 0) {
            select.innerHTML = '<option disabled>Không tìm thấy Microphone</option>';
        } else {
            audioInputs.forEach(device => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Microphone ${select.children.length + 1}`;
                select.appendChild(opt);
            });
        }
        addLog(`🎛️ Found ${audioInputs.length} audio devices.`);
    } catch (err) {
        addLog(`❌ Lỗi truy cập Mic: ${err.message}`);
        // Giữ nguyên dòng hiển thị lỗi trên dropdown
        if (select.innerHTML.includes('Loading')) {
            select.innerHTML = '<option disabled>Lỗi: Không thể truy cập Microphone</option>';
        }
    }
}

function float32ToInt16(float32Array) {
    const int16 = new Int16Array(float32Array.length);
    for (let i = 0; i < float32Array.length; i++) {
        const s = Math.max(-1, Math.min(1, float32Array[i]));
        int16[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
    }
    return int16;
}

async function toggleLiveTranscribe() {
    if (isLiveStreaming) {
        stopLiveTranscribe();
    } else {
        await startLiveTranscribe();
    }
}

async function startLiveTranscribe() {
    const btn = document.getElementById('btn-live-transcribe');
    const source = document.getElementById('audio-source').value;

    try {
        // Lấy audio stream
        const constraints = { audio: { sampleRate: 16000, channelCount: 1 } };
        if (source === 'laptop') {
            const deviceId = document.getElementById('audio-device-select').value;
            if (deviceId) constraints.audio.deviceId = { exact: deviceId };
        }

        audioStream = await navigator.mediaDevices.getUserMedia(constraints);

        // Mở WebSocket tới backend
        const baseWs = window.location.origin.replace('http:', 'ws:').replace('https:', 'wss:');
        audioWs = new WebSocket(`${baseWs}/ws/audio-stream`);

        audioWs.onopen = () => {
            addLog('🎧 Live streaming connected!');

            // AudioContext → cắt thành chunks 100ms → gửi qua WS
            audioContext = new AudioContext({ sampleRate: 16000 });
            const sourceNode = audioContext.createMediaStreamSource(audioStream);
            // 1600 samples = 100ms @ 16kHz
            const processor = audioContext.createScriptProcessor(1600, 1, 1);

            processor.onaudioprocess = (e) => {
                if (audioWs && audioWs.readyState === WebSocket.OPEN) {
                    const pcm = e.inputBuffer.getChannelData(0);
                    const int16 = float32ToInt16(pcm);
                    audioWs.send(int16.buffer);
                }
            };

            sourceNode.connect(processor);
            processor.connect(audioContext.destination);
        };

        audioWs.onerror = (err) => {
            addLog('❌ Audio WS error');
            stopLiveTranscribe();
        };

        audioWs.onclose = () => {
            addLog('🔌 Audio WS closed');
            isLiveStreaming = false;
            btn.textContent = '🎧 LIVE';
            btn.style.background = '';
        };

        isLiveStreaming = true;
        btn.textContent = '⏹ STOP';
        btn.style.background = 'rgba(239, 68, 68, 0.3)';
        document.getElementById('transcript-box').innerHTML = '';
        addLog(`🎧 Live transcribe started (source: ${source})`);

    } catch (err) {
        addLog(`❌ Cannot start live streaming: ${err.message}`);
    }
}

function stopLiveTranscribe() {
    const btn = document.getElementById('btn-live-transcribe');

    if (audioWs && audioWs.readyState === WebSocket.OPEN) {
        audioWs.send(JSON.stringify({ action: 'stop' }));
        audioWs.close();
    }
    audioWs = null;

    if (audioContext) {
        audioContext.close();
        audioContext = null;
    }

    if (audioStream) {
        audioStream.getTracks().forEach(t => t.stop());
        audioStream = null;
    }

    isLiveStreaming = false;
    btn.textContent = '🎧 LIVE';
    btn.style.background = '';
    document.getElementById('transcript-interim').textContent = '';
    addLog('⏹ Live transcribe stopped.');
}

// =========================
// GEMINI STREAMING (AI TRỰC TIẾP)
// =========================
async function useGeminiStream() {
    const base = window.location.origin;

    // Lấy transcript: ưu tiên full_transcript từ streaming, fallback về currentData
    let transcript = '';
    try {
        const streamRes = await fetch(`${base}/streaming/transcript`);
        const streamData = await streamRes.json();
        if (streamData.full_text && streamData.full_text.trim()) {
            transcript = streamData.full_text;
        }
    } catch (e) {}

    if (!transcript && currentData && currentData.transcript) {
        transcript = currentData.transcript;
    }

    if (!transcript) {
        addLog('⚠️ Chưa có transcript để AI phản biện.');
        return;
    }

    const btn = document.querySelector('[onclick="useGeminiStream()"]');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<span>⏳ STREAMING...</span>';
    btn.disabled = true;
    statusMessage('⚡ AI đang trả lời trực tiếp...');

    try {
        const response = await fetch(`${base}/operator-decision/stream`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ transcript: transcript, mode: 'gemini' })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);

        document.getElementById('final-preview').innerText = result.text;
        syncExpandedPreview();
        setEmotion('challenge', null, false);
        updateSendButton();
        addLog(`⚡ AI Trực Tiếp hoàn tất: ${result.chunks} chunks`);
        statusMessage(`AI Stream done! (${result.chunks} chunks)`, 'success');
    } catch (err) {
        addLog(`⚡ AI Stream Failed: ${err.message}`);
        statusMessage('AI Stream Failed', 'error');
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}
