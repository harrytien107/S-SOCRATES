let currentData = null;
let selectedEmotion = 'neutral';
let lastLogMsg = "";
let _previewExpanded = false;
let _previewCollapsedByUser = false;
let _manualChatExpanded = false;
const PREVIEW_COLLAPSED_HEIGHT = 190;
const PREVIEW_MIN_EXPANDED_HEIGHT = 260;
const PREVIEW_AUTO_EXPAND_LINES = 5;
const PREVIEW_AUTO_EXPAND_CHARS = 220;
const MANUAL_TRANSCRIPT_LOCK_MS = 25000;
let _manualTranscriptLockUntil = 0;
let _lastBlockedTranscriptLogAt = 0;

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
    const modeSelect = document.getElementById('stt-mode-select');
    const mode = modeSelect ? modeSelect.value : 'file';

    if (action === 'start') {
        releaseManualTranscriptLock('voice-start');
    }
    
    try {
        await fetch(`${base}/operator/mic-control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action, mode })
        });
        addLog(`🎛️ Mic action: ${action.toUpperCase()} | mode=${mode}`);
        return true;
    } catch (err) {
        addLog(`⚠️ Không gửi được lệnh mic: ${action}`);
        return false;
    }
}

// === TRIGGER EMOTION ACTION ===
// Thay thế cả gửi emotion lẫn gửi nội dung nói!
async function triggerEmotionAction(emo, btn) {
    const base = window.location.origin;
    setEmotion(emo, btn, false);

    const rawText = getFinalPreviewText();
    const hasText = rawText.length > 0;

    // Các trạng thái ưu tiên phát âm thanh nếu có text
    const vocalEmotions = ['speaking', 'challenge']; 

    if (hasText && vocalEmotions.includes(emo)) {
        statusMessage(`Sending Script with ${emo}...`, "normal");
        try {
            const response = await fetch(`${base}/operator-decision/stream-tts`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text: rawText, emotion: emo })
            });
            const result = await response.json();
            if (result.error) throw new Error(result.error);
            addLog(`✓ Sent Script [${emo.toUpperCase()}] — ${result.chunks} chunks`);
            statusMessage(`Sent Successfully! (${result.chunks} chunks)`, "success");

            // Giữ nguyên FINAL SCRIPT PREVIEW sau khi gửi để operator có thể tái sử dụng.
            currentData = null;
            document.getElementById('transcript-box').innerHTML = '<div style="color: var(--text-dim); text-align: center; margin-top: 2rem;">Đang đợi ghép nối...</div>';
            document.getElementById('transcript-interim').innerText = '';
            setEmotion('neutral', document.querySelector('.emotion-btn[data-emotion="neutral"]'), false);
            loadAllPresets();
        } catch (err) {
            addLog(`✕ Send Failed: ${err.message}`);
            statusMessage("Send Failed", "error");
        }
    } else {
        // Chỉ thay đổi emotion state của Robot (text rỗng)
        try {
            const response = await fetch(`${base}/send-to-robot`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text: '', emotion: emo })
            });
            const result = await response.json();
            if (result.status) {
                addLog(`✓ Robot state set to: ${emo}`);
            }
        } catch (err) {
            addLog(`⚠️ Không cập nhật được state ${emo}`);
        }
    }
}

async function stopRobotTTS() {
    const base = window.location.origin;
    statusMessage("Đang dừng đọc...", "normal");
    try {
        const response = await fetch(`${base}/operator/stop-tts`, { method: 'POST' });
        if (response.ok) {
            addLog(`🛑 Đã gửi lệnh DỪNG TTS tới Robot`);
            statusMessage("Đã dừng đọc", "success");
        } else {
            throw new Error("API failed");
        }
    } catch (err) {
        addLog(`⚠️ Không gửi được lệnh DỪNG TTS: ${err.message}`);
        statusMessage("Lỗi dừng đọc", "error");
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
let _lastSyncedStatus = 'idle|file';

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
                const mode = msg.mode || 'file';
                const syncKey = `${status}|${mode}`;
                if (syncKey === _lastSyncedStatus) return;
                _lastSyncedStatus = syncKey;

                if (status === 'listening' && !isMicActive) {
                    isMicActive = true;
                    addLog(`🎙️ [Sync] App bật Mic | mode=${mode}`);
                } else if (status !== 'listening' && isMicActive) {
                    isMicActive = false;
                    if (status === 'processing') addLog(`📤 [Sync] App gửi audio lên Server | mode=${mode}`);
                }
            }
            
            if (msg.type === 'transcript') {
                const incoming = msg.data || {};
                const source = incoming.source || 'voice';

                if (isManualTranscriptLocked() && source !== 'manual') {
                    const now = Date.now();
                    if (now - _lastBlockedTranscriptLogAt > 4000) {
                        addLog(`🛡️ Ignore transcript source=${source} while manual input is locked.`);
                        _lastBlockedTranscriptLogAt = now;
                    }
                    return;
                }

                if (source === 'manual') {
                    lockManualTranscript(incoming.transcript || '');
                }

                currentData = incoming;
                displayWorkflow(incoming);
                if (source === 'manual') {
                    addLog('⌨️ Manual transcript synced.');
                } else {
                    addLog(`⚡ Received transcript source=${source}.`);
                }
            }

            if (msg.type === 'stt_interim') {
                if (isManualTranscriptLocked()) {
                    return;
                }
                // Deepgram: đang nói — cập nhật dòng nhảy chữ
                const interim = document.getElementById('transcript-interim');
                if (interim) interim.textContent = '░░ ' + msg.text + '...';
            }

            if (msg.type === 'stt_final') {
                if (isManualTranscriptLocked()) {
                    return;
                }
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

            if (msg.type === 'transcript_cleared') {
                currentData = null;
                document.getElementById('transcript-box').innerHTML = 'Chưa có tín hiệu âm thanh...';
                document.getElementById('transcript-interim').innerText = '';
                loadAllPresets();
                addLog('🧹 Transcript state cleared from server.');
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
    preview.addEventListener('transitionend', () => {
        if (_previewExpanded) {
            adjustPreviewHeight();
        }
    });
    
    checkConnection();
    updateSendButton();
    addLog("Console Ready.");
    setLogExpanded(true);
    setPreviewExpanded(false, false);
    window.addEventListener('resize', () => {
        if (_previewExpanded) {
            adjustPreviewHeight();
        }
    });

    if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(() => {
            syncExpandedPreview();
        }).catch(() => {
            // ignore font readiness issues
        });
    }
    
    // Khởi tạo WebSocket thay vì setInterval polling
    connectWebSocket();

    // Load tất cả presets để hiển sẵn (không cần đợi transcript)
    loadAllPresets();
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

let _logExpanded = true;

function setLogExpanded(expanded) {
    _logExpanded = !!expanded;
    const container = document.getElementById('log-container');
    const btn = document.getElementById('expand-log-btn');
    if (!container || !btn) return;

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

function toggleLogExpand() {
    setLogExpanded(!_logExpanded);
}

function statusMessage(msg, type = 'normal') {
    const status = document.getElementById('last-sent-status');
    status.innerText = msg;
    status.style.color = type === 'error' ? 'var(--danger)' : (type === 'success' ? 'var(--cyan)' : 'var(--text-dim)');
}

function isManualTranscriptLocked() {
    return Date.now() < _manualTranscriptLockUntil;
}

function lockManualTranscript(text = '') {
    _manualTranscriptLockUntil = Date.now() + MANUAL_TRANSCRIPT_LOCK_MS;
    if (text) {
        currentData = {
            ...(currentData || {}),
            transcript: text,
            source: 'manual',
        };
    }
}

function releaseManualTranscriptLock(reason = '') {
    if (_manualTranscriptLockUntil <= 0) return;
    _manualTranscriptLockUntil = 0;
    if (reason) {
        addLog(`🔓 Manual transcript unlocked (${reason}).`);
    }
}

function toggleModal(show) {
    document.getElementById('settings-modal').classList.toggle('open', show);
    if (show) syncConfigs();
}

function getFinalPreviewText() {
    const preview = document.getElementById('final-preview');
    return (preview?.innerText || '').trim();
}

function toggleManualChatExpand() {
    const input = document.getElementById('chat-input');
    const btn = document.getElementById('chat-expand-btn');
    if (!input || !btn) return;

    _manualChatExpanded = !_manualChatExpanded;
    input.classList.toggle('expanded', _manualChatExpanded);
    btn.textContent = _manualChatExpanded ? '⤡ COLLAPSE' : '⤢ EXPAND';
}

function shouldAutoExpandPreview() {
    const preview = document.getElementById('final-preview');
    if (!preview) return false;

    const text = preview.innerText || '';
    if (!text.trim()) return false;

    const explicitLineCount = text.split(/\r?\n/).length;
    const wrappedLineEstimate = Math.ceil(text.length / 90);
    const visualLineCount = Math.max(explicitLineCount, wrappedLineEstimate);
    return (
        visualLineCount >= PREVIEW_AUTO_EXPAND_LINES ||
        text.length >= PREVIEW_AUTO_EXPAND_CHARS ||
        preview.scrollHeight > PREVIEW_COLLAPSED_HEIGHT + 30
    );
}

function setFinalPreviewText(text) {
    const preview = document.getElementById('final-preview');
    if (!preview) return;

    preview.innerText = text || '';
    _previewCollapsedByUser = false;
    syncExpandedPreview();
    requestAnimationFrame(() => requestAnimationFrame(adjustPreviewHeight));
    updateSendButton();
}

function clearFinalPreview() {
    setFinalPreviewText('');
    addLog('🧹 Final script preview cleared by operator.');
    statusMessage('Final script preview cleared.');
}

function adjustPreviewHeight() {
    const preview = document.getElementById('final-preview');
    if (!preview) return;

    if (!_previewExpanded) {
        preview.style.height = `${PREVIEW_COLLAPSED_HEIGHT}px`;
        preview.style.maxHeight = '';
        preview.style.overflowY = 'auto';
        return;
    }

    preview.style.height = 'auto';
    const text = preview.innerText || '';
    const lineCount = Math.max(1, text.split(/\r?\n/).length);
    const lineHeight = parseFloat(window.getComputedStyle(preview).lineHeight) || 28;
    const lineBasedHeight = Math.ceil(lineCount * lineHeight + 56);
    const rawTargetHeight = Math.max(preview.scrollHeight + 8, lineBasedHeight);
    const minHeight = PREVIEW_MIN_EXPANDED_HEIGHT;
    const targetHeight = Math.max(rawTargetHeight, minHeight);
    preview.style.height = `${targetHeight}px`;
    preview.style.maxHeight = 'none';
    preview.style.overflowY = 'auto';
}

function setPreviewExpanded(expanded, byUser = false) {
    _previewExpanded = !!expanded;
    const preview = document.getElementById('final-preview');
    const btn = document.getElementById('expand-preview-btn');
    if (!preview || !btn) return;

    if (byUser && !_previewExpanded) {
        _previewCollapsedByUser = true;
    }
    if (_previewExpanded) {
        _previewCollapsedByUser = false;
    }

    preview.classList.toggle('preview-expanded-inline', _previewExpanded);
    btn.textContent = _previewExpanded ? '⤡ COLLAPSE' : '⤢ EXPAND';
    requestAnimationFrame(adjustPreviewHeight);
}

function togglePreviewExpand() {
    setPreviewExpanded(!_previewExpanded, true);
}

function syncExpandedPreview() {
    const preview = document.getElementById('final-preview');
    if (!preview) return;

    const text = preview.innerText.trim();
    if (!text) {
        if (_previewExpanded) {
            setPreviewExpanded(false, false);
        } else {
            requestAnimationFrame(adjustPreviewHeight);
        }
        return;
    }

    if (!_previewExpanded && !_previewCollapsedByUser && shouldAutoExpandPreview()) {
        setPreviewExpanded(true, false);
        return;
    }

    requestAnimationFrame(() => requestAnimationFrame(adjustPreviewHeight));
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
                openrouter_model: document.getElementById('cfg-openrouter-model').value,
                auto_gain: document.getElementById('cfg-auto-gain').checked,
                noise_suppression: document.getElementById('cfg-noise-supp').checked,
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

        // Sync OpenRouter Model
        const openrouterEl = document.getElementById('cfg-openrouter-model');
        if (openrouterEl) {
            openrouterEl.value = cfg.openrouter_model;
        }

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
    releaseManualTranscriptLock('file-upload');
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
        document.getElementById('match-count').innerText = `${data.candidates.length} kết quả phù hợp`;
        data.candidates.forEach((c) => {
            const card = document.createElement('div');
            card.className = 'suggestion-card';
            card.innerHTML = `
                <span class="score-pill">${(c.score * 100).toFixed(0)}%</span>
                <div class="q-text" style="font-size: 0.65rem; color: #888; margin-bottom: 4px; border-bottom: 1px dotted rgba(255,255,255,0.1); padding-bottom: 4px;">Q: ${c.question || ''}</div>
                <div class="a-text">A: ${c.answer}</div>
            `;
            card.onclick = () => selectResponse(c.answer, 'preset', card);
            list.appendChild(card);
        });
    } else {
        // Không có matching → hiển full presets thay vì để trống
        loadAllPresets();
    }
}

// Lấy transcript text từ currentData hoặc transcript-box (hỗ trợ cả voice + chat)
function getTranscriptText() {
    if (currentData && currentData.transcript) return currentData.transcript;
    const box = document.getElementById('transcript-box');
    const text = (box?.innerText || '').trim();
    if (text && text !== 'Chưa có tín hiệu âm thanh...' && text !== 'Đang đợi ghép nối...' && text !== 'Đang xử lý...') {
        return text;
    }

    const manualInput = document.getElementById('chat-input');
    const manualText = (manualInput?.value || '').trim();
    if (manualText) return manualText;

    return null;
}

async function clearTranscript() {
    releaseManualTranscriptLock('clear');
    currentData = null;
    document.getElementById('transcript-box').innerHTML = 'Chưa có tín hiệu âm thanh...';
    document.getElementById('transcript-interim').innerText = '';
    loadAllPresets();
    const base = window.location.origin;
    try {
        await fetch(`${base}/operator/clear-transcript`, { method: 'POST' });
        addLog("🗑️ Transcript cleared (local + server).");
    } catch (err) {
        addLog("⚠️ Cleared local transcript but failed to clear server state.");
    }
}

// Load và hiển thị TOÀN BỘ presets (không cần transcript)
async function loadAllPresets() {
    const base = window.location.origin;
    try {
        const res = await fetch(`${base}/presets`);
        const data = await res.json();
        const list = document.getElementById('suggestions-list');
        list.innerHTML = '';
        if (data.presets && data.presets.length > 0) {
            document.getElementById('match-count').innerText = `${data.presets.length} presets`;
            data.presets.forEach((p) => {
                const card = document.createElement('div');
                card.className = 'suggestion-card';
                card.innerHTML = `
                    <div class="q-text" style="font-size: 0.65rem; color: #888; margin-bottom: 4px; border-bottom: 1px dotted rgba(255,255,255,0.1); padding-bottom: 4px;">Q: ${p.question || p.q || ''}</div>
                    <div class="a-text">A: ${p.answer || p.a || ''}</div>
                `;
                card.onclick = () => selectResponse(p.answer, 'preset', card);
                list.appendChild(card);
            });
        } else {
            list.innerHTML = '<div style="text-align: center; color: var(--text-dim); margin-top: 2rem;">No presets available.</div>';
        }
    } catch (e) {
        console.error('Failed to load presets:', e);
    }
}

// Chat Input: Operator gõ câu hỏi thủ công khi voice không nhận được
async function submitChatInput() {
    const base = window.location.origin;
    const input = document.getElementById('chat-input');
    const text = input.value.trim();
    if (!text) return;

    input.value = '';
    lockManualTranscript(text);
    document.getElementById('transcript-box').innerHTML = `<span class="transcript-highlight">Đang xử lý...</span>`;
    addLog(`⌨️ Chat gõ: "${text.substring(0, 40)}..."`);

    try {
        const res = await fetch(`${base}/chat-input`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text })
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);
        const normalized = {
            ...data,
            source: data.source || 'manual',
        };
        lockManualTranscript(normalized.transcript || text);
        currentData = normalized;
        displayWorkflow(normalized);
        addLog('✅ Chat processed.');
    } catch (err) {
        releaseManualTranscriptLock('manual-chat-failed');
        addLog(`❌ Chat failed: ${err.message}`);
        document.getElementById('transcript-box').innerText = 'Lỗi xử lý chat.';
    }
}

function selectResponse(text, mode, element) {
    setFinalPreviewText(text);
    
    document.querySelectorAll('.suggestion-card').forEach(el => el.classList.remove('active'));
    if (element) element.classList.add('active');
    addLog(`Preset selected. Ready to send via Emotion buttons.`);
}

function updateSendButton() {
    const rawText = getFinalPreviewText();
    const hasText = rawText.length > 0;

    if (!hasText) {
        statusMessage("Chọn preset hoặc dùng AI để tạo nội dung");
    } else {
        statusMessage("Ready: Nhấn [🔊 Tự Động Nói] hoặc [Neutral] để phát text!");
    }
}

async function useAI() {
    const base = window.location.origin;
    const transcript = getTranscriptText();
    if (!transcript) {
        addLog('⚠️ Không có transcript. Hãy dùng mic hoặc gõ chat.');
        return;
    }
    
    const btn = document.querySelector('.ai-local-btn') || document.querySelector('.ai-reflex-btn');
    if (!btn) return;
    const originalText = btn.innerHTML;
    btn.innerHTML = '<span>⏳ GEN...</span>';
    btn.disabled = true;
    statusMessage("Generating AI reflex...");

    // Đưa robot vào trạng thái uploading khi đang chờ
    triggerEmotionAction('uploading', document.querySelector('.emotion-btn[data-emotion="uploading"]'));

    try {
        const response = await fetch(`${base}/operator-decision`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mode: 'ai',
                transcript: transcript
            })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);
        
        setFinalPreviewText(result.text);
        addLog("AI response generated. Ready to send.");
    } catch (err) {
        addLog("AI Failed.");
        statusMessage("AI Generation Failed", "error");
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}

async function useOpenRouter() {
    const base = window.location.origin;
    const transcript = getTranscriptText();
    if (!transcript) {
        addLog('⚠️ Không có transcript. Hãy dùng mic hoặc gõ chat.');
        return;
    }
    
    const btn = document.querySelector('.openrouter-btn');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<span>⏳ OPENROUTER...</span>';
    btn.disabled = true;
    statusMessage("Generating OpenRouter response...");

    // Đưa robot vào trạng thái uploading khi đang chờ
    triggerEmotionAction('uploading', document.querySelector('.emotion-btn[data-emotion="uploading"]'));

    try {
        const response = await fetch(`${base}/operator-decision`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mode: 'openrouter',
                transcript: transcript
            })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);
        
        setFinalPreviewText(result.text);
        addLog("🌐 OpenRouter response generated. Ready to send.");
    } catch (err) {
        const detail = err?.message || 'OpenRouter request failed.';
        addLog(`🌐 OpenRouter Failed: ${detail}`);
        statusMessage(`OpenRouter failed: ${detail}`, "error");
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

// Hàm sendToRobot cũ đã được xóa và gộp chung vào triggerEmotionAction
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
// OPENROUTER STREAMING (AI TRỰC TIẾP)
// =========================
async function useOpenRouterStream() {
    const base = window.location.origin;

    // Lấy transcript từ mọi nguồn có thể
    let transcript = '';
    try {
        const streamRes = await fetch(`${base}/streaming/transcript`);
        const streamData = await streamRes.json();
        if (streamData.full_text && streamData.full_text.trim()) {
            transcript = streamData.full_text;
        }
    } catch (e) {}

    if (!transcript) {
        transcript = getTranscriptText() || '';
    }

    if (!transcript) {
        addLog('⚠️ Chưa có transcript. Hãy dùng mic hoặc gõ chat.');
        return;
    }

    const btn = document.querySelector('[onclick="useOpenRouterStream()"]');
    const originalText = btn.innerHTML;
    btn.innerHTML = '<span>⏳ STREAMING...</span>';
    btn.disabled = true;
    statusMessage('⚡ OpenRouter đang trả lời trực tiếp...');

    try {
        const response = await fetch(`${base}/operator-decision/stream`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ transcript: transcript, mode: 'openrouter' })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);

        setFinalPreviewText(result.text);
        setEmotion('speaking', document.querySelector('.emotion-btn[data-emotion="speaking"]'), false);
        addLog(`⚡ OpenRouter stream hoàn tất: ${result.chunks} chunks`);
        statusMessage(`OpenRouter stream done! (${result.chunks} chunks)`, 'success');
    } catch (err) {
        addLog(`⚡ OpenRouter Stream Failed: ${err.message}`);
        statusMessage('OpenRouter Stream Failed', 'error');
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}
