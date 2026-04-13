let currentData = null;
let selectedEmotion = 'idle';
let lastLogMsg = "";
let hasReceivedDeepgramData = false; // Track xem đã nhận dữ liệu từ Deepgram chưa
let selectedAiInputSource = 'deepgram';
let localRuntimeStatus = null;
let localRuntimePollTimer = null;

// Remote Mic Control State
let isMicActive = false;
let micTimerInterval = null;
let micStartTime = null;
const NO_VOICE_FALLBACK_TEXT = 'Không nhận được voice. Vui lòng nói lại.';
let isPageUnloading = false;

function consumeEvent(event) {
    if (!event) return;
    event.preventDefault();
    event.stopPropagation();
    if (typeof event.stopImmediatePropagation === 'function') {
        event.stopImmediatePropagation();
    }
}

function getManualQuestionText() {
    const manualBox = document.getElementById('manual-question-box');
    return manualBox ? manualBox.innerText.trim() : '';
}

function getDeepgramText() {
    return currentData?.transcript?.trim?.() || '';
}

function getAiInputText() {
    return selectedAiInputSource === 'manual'
        ? getManualQuestionText()
        : getDeepgramText();
}

function updateAiSourceUI() {
    const deepgramBtn = document.getElementById('source-deepgram-btn');
    const manualBtn = document.getElementById('source-manual-btn');
    const deepgramBox = document.getElementById('transcript-box');
    const manualBox = document.getElementById('manual-question-box');
    const activeLabel = document.getElementById('active-input-source');
    const isManual = selectedAiInputSource === 'manual';

    if (deepgramBtn) deepgramBtn.classList.toggle('active', !isManual);
    if (manualBtn) manualBtn.classList.toggle('active', isManual);
    if (deepgramBox) deepgramBox.classList.toggle('ai-source-active', !isManual);
    if (manualBox) manualBox.classList.toggle('ai-source-active', isManual);
    if (activeLabel) {
        activeLabel.innerText = `Nguồn hiện tại cho AI: ${isManual ? 'Manual Operator Chat' : 'Deepgram Transcript'}`;
    }
}

function setAiInputSource(source, explicit = false) {
    const normalized = source === 'manual' ? 'manual' : 'deepgram';
    selectedAiInputSource = normalized;
    updateAiSourceUI();
    if (explicit) {
        addLog(`🔀 AI source: ${normalized === 'manual' ? 'Manual Operator Chat' : 'Deepgram Transcript'}`);
    }
}

function getApiBase() {
    return window.location.origin.replace(/\/+$/, '');
}

function getLocalRuntimeSummary(runtime) {
    if (!runtime) return 'TurboQuant: checking runtime status...';

    const phase = runtime.phase || 'unknown';
    const detail = runtime.detail || '';
    const prefixMap = {
        ready: '🟢 TurboQuant ready',
        cold: '🟡 TurboQuant online, context not restored yet',
        starting: '🟡 TurboQuant starting',
        warming: '🟠 TurboQuant restoring context',
        generating: '🟠 TurboQuant generating',
        offline: '🔴 TurboQuant offline',
        stopped: '⚪ TurboQuant stopped',
        error: '🔴 TurboQuant error',
    };
    const prefix = prefixMap[phase] || 'ℹ️ TurboQuant';
    return detail ? `${prefix}: ${detail}` : prefix;
}

function applyLocalRuntimeStatus(runtime) {
    localRuntimeStatus = runtime || null;
    const statusEl = document.getElementById('local-runtime-status');
    const localAiBtn = document.getElementById('btn-local-ai');
    if (!statusEl || !localAiBtn) return;

    statusEl.innerText = getLocalRuntimeSummary(runtime);

    const phase = runtime?.phase || 'offline';
    const busy = ['starting', 'warming', 'generating'].includes(phase);
    const unavailable = ['offline', 'stopped', 'error'].includes(phase) || runtime?.ready === false;

    statusEl.style.color =
        phase === 'ready' ? 'var(--cyan)'
        : phase === 'cold' ? '#facc15'
        : busy ? '#fb923c'
        : 'var(--danger)';

    localAiBtn.disabled = busy || unavailable;
    localAiBtn.title = runtime?.detail || 'TurboQuant is not ready yet';
}

async function syncLocalRuntimeStatus() {
    const base = getApiBase();
    try {
        const response = await fetch(`${base}/local-runtime/status`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const payload = await response.json();
        applyLocalRuntimeStatus(payload.local_runtime || null);
    } catch (_) {
        applyLocalRuntimeStatus({
            phase: 'offline',
            ready: false,
            detail: 'Unable to fetch TurboQuant status from the backend.',
        });
    }
}

function normalizeEmotion(emo) {
    return emo === 'neutral' ? 'idle' : emo;
}

function formatTimer(ms) {
    const totalSec = Math.floor(ms / 1000);
    const min = String(Math.floor(totalSec / 60)).padStart(2, '0');
    const sec = String(totalSec % 60).padStart(2, '0');
    return `${min}:${sec}`;
}

// === Gửi lệnh Mic tới Backend ===
async function _sendMicAction(action) {
    const base = getApiBase();
    try {
        const response = await fetch(`${base}/robot/mic-control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action })
        });
        const rawText = await response.text();
        let result = {};
        try {
            result = rawText ? JSON.parse(rawText) : {};
        } catch (_) {
            result = { error: rawText || `HTTP ${response.status}` };
        }
        if (!response.ok || result.error) {
            throw new Error(result.error || `HTTP ${response.status}`);
        }
        return true;
    } catch (err) {
        const reason = err?.message || 'Unknown error';
        addLog(`⚠️ Không gửi được lệnh mic: ${action} | ${reason}`);
        statusMessage(`Mic command failed: ${action} | ${reason}`, 'error');
        return false;
    }
}

// === QUICK SEND — Gửi emotion trực tiếp qua /send-to-robot ===
async function quickSendEmotion(emo, btn) {
    const base = getApiBase();
    emo = normalizeEmotion(emo);

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

async function cancelRobotMic(event) {
    consumeEvent(event);
    if (!isMicActive) return;
    if (await _sendMicAction('cancel')) {
        isMicActive = false;
        updateMicButtons();
        addLog(`❌ Đã HỦY thu âm. Dữ liệu không được gửi.`);
    }
}

function updateMicButtons() {
    const startBtn = document.getElementById('mic-start-btn');
    const stopBtn = document.getElementById('mic-stop-btn');
    const cancelBtn = document.getElementById('mic-cancel-btn');
    if (!startBtn || !stopBtn || !cancelBtn) return;

    startBtn.disabled = false;
    stopBtn.disabled = !isMicActive;
    cancelBtn.disabled = !isMicActive;
}

async function startRobotMic(event) {
    consumeEvent(event);
    const ok = await _sendMicAction('start');
    if (!ok) return;

    isMicActive = true;
    updateMicButtons();
    setEmotion('idle', null, false);
    addLog(`🎙️ Đã gửi lệnh BẬT mic robot.`);
    statusMessage('Robot microphone started', 'success');
}

async function stopRobotMic(event) {
    consumeEvent(event);
    if (!isMicActive) return;
    const ok = await _sendMicAction('stop');
    if (!ok) return;

    isMicActive = false;
    updateMicButtons();
    addLog(`📤 Đã gửi lệnh TẮT mic và upload audio.`);
    statusMessage('Robot is uploading audio', 'normal');
}

// === WEBSOCKET CONNECTION ===
let ws = null;
let reconnectTimer = null;
let heartbeatTimer = null;
let _lastSyncedStatus = 'idle';

function connectWebSocket() {
    if (isPageUnloading) return;
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
        return;
    }

    const baseInput = getApiBase();
    let wsUrl = baseInput.replace('http:', 'ws:').replace('https:', 'wss:') + '/ws/operator';
    
    addLog('🔌 Connecting to WebSocket...');
    ws = new WebSocket(wsUrl);

    ws.onopen = () => {
        document.getElementById('online-dot').classList.add('active');
        addLog("🟢 WebSocket Connected!");
        if (reconnectTimer) {
            clearTimeout(reconnectTimer);
            reconnectTimer = null;
        }
        if (heartbeatTimer) {
            clearInterval(heartbeatTimer);
        }
        heartbeatTimer = setInterval(() => {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send('ping');
            }
        }, 15000);
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
                    updateMicButtons();
                    addLog(`🎙️ [Sync] App bật Mic.`);
                } else if (status !== 'listening' && isMicActive) {
                    isMicActive = false;
                    updateMicButtons();
                    if (status === 'processing') addLog(`📤 [Sync] App gửi audio lên Server.`);
                }

                if (status === 'idle') {
                    isMicActive = false;
                    updateMicButtons();
                }
            }
            
            if (msg.type === 'transcript') {
                currentData = msg.data;
                displayWorkflow(msg.data);
                addLog("⚡ Received real-time voice input from Robot.");
            }

            if (msg.type === 'log') {
                addLog(`📱 ROBOT: ${msg.message}`);
            }

            if (msg.type === 'local_runtime_status') {
                applyLocalRuntimeStatus(msg.data || null);
            }

        } catch (e) {
            console.error('WS parse error:', e);
        }
    };

    ws.onclose = () => {
        if (isPageUnloading) return;
        document.getElementById('online-dot').classList.remove('active');
        addLog("🔴 WebSocket Disconnected. Reconnecting...");
        if (heartbeatTimer) {
            clearInterval(heartbeatTimer);
            heartbeatTimer = null;
        }
        ws = null;
        scheduleReconnect();
    };

    ws.onerror = (error) => {
        console.error("WebSocket Error: ", error);
    };
}

function scheduleReconnect() {
    if (isPageUnloading) return;
    if (reconnectTimer) return;
    reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connectWebSocket();
    }, 3000);
}

window.onload = () => {
    const preview = document.getElementById('final-preview');
    const transcriptBox = document.getElementById('transcript-box');
    const manualQuestionBox = document.getElementById('manual-question-box');
    preview.addEventListener('input', updateSendButton);
    preview.addEventListener('paste', (e) => e.preventDefault());
    preview.addEventListener('keydown', (e) => e.preventDefault());
    if (manualQuestionBox) {
        manualQuestionBox.addEventListener('input', handleManualQuestionInput);
    }
    
    checkConnection();
    loadPresetQuestions();
    updateSendButton();
    updateMicButtons();
    addLog("Console Ready.");
    connectWebSocket();
};

window.addEventListener('beforeunload', () => {
    isPageUnloading = true;
    if (localRuntimePollTimer) {
        clearInterval(localRuntimePollTimer);
        localRuntimePollTimer = null;
    }
    if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
    }
    if (heartbeatTimer) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = null;
    }
    if (ws) {
        try {
            ws.onclose = null;
            ws.close();
        } catch (_) {}
        ws = null;
    }
});

function handleManualQuestionInput() {
    const manualBox = document.getElementById('manual-question-box');
    const transcript = manualBox.innerText.trim();
    setTranscriptWarning('');

    if (!currentData) {
        currentData = { transcript: '', candidates: [] };
    }

    if (!transcript) {
        addLog("📝 Ô chat tay đã được xóa.");
        return;
    }

    setAiInputSource('manual');
    addLog("📝 Operator đang nhập câu hỏi tay.");
}

function clearInputBoxes() {
    const transcriptBox = document.getElementById('transcript-box');
    const manualBox = document.getElementById('manual-question-box');
    const finalPreview = document.getElementById('final-preview');
    transcriptBox.innerText = '';
    if (manualBox) manualBox.innerText = '';
    if (finalPreview) finalPreview.innerText = '';
    setTranscriptWarning('');

    if (!currentData) {
        currentData = { transcript: '', candidates: [] };
    }
    currentData.transcript = '';
    hasReceivedDeepgramData = false;
    setAiInputSource('deepgram');
    updateSendButton();

    addLog("🧹 Đã xóa transcript, ô chat tay và preview.");
}

function isNoVoiceTranscript(text) {
    const normalized = (text || '').trim().toLowerCase();
    return normalized === '' || normalized === NO_VOICE_FALLBACK_TEXT.toLowerCase();
}

function setTranscriptWarning(message) {
    const warning = document.getElementById('transcript-warning');
    if (!warning) return;

    if (!message) {
        warning.style.display = 'none';
        warning.innerText = '';
        return;
    }

    warning.innerText = message;
    warning.style.display = 'block';
}

async function loadPresetQuestions() {
    const base = getApiBase();
    const list = document.getElementById('suggestions-list');
    const count = document.getElementById('match-count');

    list.innerHTML = '<div style="text-align: center; color: var(--text-dim); margin-top: 2rem;">Đang tải danh sách câu hỏi mẫu từ API...</div>';
    count.innerText = '...';

    try {
        const response = await fetch(`${base}/qa-presets`);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        const data = await response.json();
        if (data.error) throw new Error(data.error);

        renderPresetList(data.presets || []);
        addLog("📚 Đã tải toàn bộ câu hỏi mẫu từ API /qa-presets.");
    } catch (err) {
        list.innerHTML = '<div style="text-align: center; color: var(--danger); margin-top: 2rem;">Không tải được danh sách câu hỏi mẫu từ API /qa-presets.</div>';
        count.innerText = '0 presets';
        addLog(`⚠️ Không tải được câu hỏi mẫu từ /qa-presets: ${err.message || err}`);
    }
}

function addLog(msg) {
    if (msg === lastLogMsg) return;
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

function toggleTranscriptModal(show) {
    const modal = document.getElementById('transcript-expand-modal');
    const content = document.getElementById('transcript-expand-content');
    if (!modal || !content) return;

    if (show) {
        const transcript = document.getElementById('transcript-box');
        content.innerText = transcript ? transcript.innerText : '';
    }
    modal.classList.toggle('open', show);
}

function toggleManualModal(show) {
    const modal = document.getElementById('manual-expand-modal');
    const content = document.getElementById('manual-expand-content');
    const manual = document.getElementById('manual-question-box');

    if (!modal || !content || !manual) return;

    if (show) {
        // Mở modal: copy từ ô chính sang ô expand
        content.innerText = manual.innerText || '';
    } else {
        // Đóng modal: copy ngược từ ô expand về ô chính
        manual.innerText = content.innerText || '';

        // nếu muốn giữ logic hiện có của bạn
        handleManualQuestionInput();
    }

    modal.classList.toggle('open', show);
}

window.onload = () => {
    const preview = document.getElementById('final-preview');
    const manualQuestionBox = document.getElementById('manual-question-box');
    const manualExpandBox = document.getElementById('manual-expand-content');

    preview.addEventListener('input', updateSendButton);
    preview.addEventListener('paste', (e) => e.preventDefault());
    preview.addEventListener('keydown', (e) => e.preventDefault());

    if (manualQuestionBox) {
        manualQuestionBox.addEventListener('input', handleManualQuestionInput);
    }

    if (manualExpandBox && manualQuestionBox) {
        manualExpandBox.addEventListener('input', () => {
            manualQuestionBox.innerText = manualExpandBox.innerText;
            handleManualQuestionInput();
        });
    }

    checkConnection();
    syncLocalRuntimeStatus();
    if (localRuntimePollTimer) {
        clearInterval(localRuntimePollTimer);
    }
    localRuntimePollTimer = setInterval(syncLocalRuntimeStatus, 4000);
    loadPresetQuestions();
    updateAiSourceUI();
    updateSendButton();
    updateMicButtons();
    addLog("Console Ready.");
    connectWebSocket();
};

async function saveSettings() {
    const base = getApiBase();

    try {
        await fetch(`${base}/configs`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                robot_control_url: document.getElementById('robot-control-url').value.trim(),
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
    const base = getApiBase();
    try {
        const res = await fetch(`${base}/configs`);
        if (!res.ok) return;
        const data = await res.json();
        const cfg = data.config;
        const robotUrlEl = document.getElementById('robot-control-url');

        if (robotUrlEl) robotUrlEl.value = data.robot_control_url || '';

        const voiceEl = document.getElementById('cfg-tts-voice');
        if (voiceEl) voiceEl.value = cfg.tts_voice;

        const speedEl = document.getElementById('cfg-tts-speed');
        const speedDisplay = document.getElementById('speed-display');
        if (speedEl) {
            speedEl.value = cfg.tts_speed;
            if (speedDisplay) speedDisplay.innerText = cfg.tts_speed + 'x';
        }

        const modelEl = document.getElementById('cfg-stt-model');
        if (modelEl) modelEl.value = cfg.stt_model;

        const langEl = document.getElementById('cfg-stt-language');
        if (langEl) langEl.value = cfg.stt_language;

        const geminiEl = document.getElementById('cfg-gemini-model');
        if (geminiEl) geminiEl.value = cfg.gemini_model;

        addLog("🔧 Synced audio config from backend.");
    } catch (err) {
    }
}

function checkConnection() {
    const base = getApiBase();
    fetch(`${base}/`).then(() => {
        addLog("HTTP API Online. Waiting for WS...");
        document.getElementById('online-dot').classList.add('active');
    }).catch(() => {
        addLog("Backend Offline.");
        document.getElementById('online-dot').classList.remove('active');
    });
}

async function handleFileUpload(input) {
    if (!input.files || !input.files[0]) return;
    const file = input.files[0];
    const base = getApiBase();
    
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
    if (!currentData) currentData = {};
    const transcript = (data.transcript || '').trim();

    // Đánh dấu đã nhận dữ liệu từ Deepgram khi có transcript property
    if (typeof data.transcript !== 'undefined') {
        hasReceivedDeepgramData = true;
    }
    
    // Chỉ hiển thị warning khi đã nhận dữ liệu từ Deepgram và transcript rỗng
    if (isNoVoiceTranscript(transcript) && hasReceivedDeepgramData) {
        document.getElementById('transcript-box').innerText = '';
        currentData.transcript = '';
        setTranscriptWarning('Nhận chuỗi rỗng từ Deepgram');
        addLog('⚠️ Deepgram không trả về câu hỏi. Operator cần nhập thủ công.');
    } else {
        document.getElementById('transcript-box').innerText = transcript;
        currentData.transcript = transcript;
        setTranscriptWarning('');
    }

    if (transcript) {
        setAiInputSource('deepgram');
    }

    if (data.candidates && data.candidates.length > 0) {
        renderPresetList(data.candidates);
        return;
    }

    loadPresetQuestions();
}

function renderPresetList(presets) {
    const list = document.getElementById('suggestions-list');
    const count = document.getElementById('match-count');
    list.innerHTML = '';

    if (presets && presets.length > 0) {
        count.innerText = `${presets.length} presets`;
        presets.forEach((preset, index) => {
            const card = document.createElement('div');
            card.className = 'suggestion-card';
            card.innerHTML = `
                <span class="score-pill">#${index + 1}</span>
                <div class="q-text" style="font-weight: 700; margin-bottom: 8px;">${preset.question || 'Câu hỏi mẫu'}</div>
                <div class="a-text">${preset.answer || ''}</div>
            `;
            card.onclick = () => selectResponse(preset.answer || '', 'preset', card);
            list.appendChild(card);
        });
        return;
    }

    count.innerText = '0 presets';
    list.innerHTML = '<div style="text-align: center; color: var(--text-dim); margin-top: 2rem;">Chưa có câu hỏi mẫu.</div>';
}

function selectResponse(text, mode, element) {
    document.getElementById('final-preview').innerText = text;
    syncExpandedPreview();
    updateSendButton();
    
    document.querySelectorAll('.suggestion-card').forEach(el => el.classList.remove('active'));
    if (element) element.classList.add('active');
    addLog(`Preset selected from full preset list.`);
}

function updateSendButton() {
    const rawText = document.getElementById('final-preview').innerText.trim();
    const btn = document.getElementById('send-trigger');
    const hasText = rawText.length > 0;
    if (hasText && selectedEmotion === 'idle') {
        setEmotion('speaking', null, false);
        return;
    }
    const textRequired = selectedEmotion === 'speaking';

    btn.disabled = textRequired && !hasText;
    if (btn.disabled) {
        statusMessage("Speaking cần nội dung để gửi");
        return;
    }
    statusMessage(textRequired ? "Ready to Send" : "Ready to Send (emotion only)");
}

async function useAI() {
    const base = getApiBase();
    const aiInput = getAiInputText();
    const phase = localRuntimeStatus?.phase || 'offline';
    const unavailable =
        ['starting', 'warming', 'generating', 'offline', 'stopped', 'error'].includes(phase) ||
        localRuntimeStatus?.ready === false;

    if (unavailable) {
        statusMessage(localRuntimeStatus?.detail || 'TurboQuant is not ready yet.', "error");
        addLog(`⚠️ TurboQuant is not ready: ${localRuntimeStatus?.detail || phase}`);
        return;
    }
    if (!aiInput) {
        statusMessage(
            selectedAiInputSource === 'manual'
                ? "Manual Operator Chat đang trống"
                : "Deepgram Transcript đang trống",
            "error"
        );
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
                transcript: aiInput
            })
        });
        const result = await response.json();
        if (result.error) throw new Error(result.error);
        
        document.getElementById('final-preview').innerText = result.text;
        syncExpandedPreview();
        setEmotion(result.emotion, null, false);
        updateSendButton();
        addLog("AI response generated.");
        await syncLocalRuntimeStatus();
    } catch (err) {
        addLog("AI Failed.");
        statusMessage("AI Generation Failed", "error");
        await syncLocalRuntimeStatus();
    } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
    }
}

async function useGemini() {
    const base = getApiBase();
    const aiInput = getAiInputText();
    if (!aiInput) {
        statusMessage(
            selectedAiInputSource === 'manual'
                ? "Manual Operator Chat đang trống"
                : "Deepgram Transcript đang trống",
            "error"
        );
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
                transcript: aiInput
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
    emo = normalizeEmotion(emo);
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

async function sendToRobot(event) {
    consumeEvent(event);
    const base = getApiBase();
    const rawText = document.getElementById('final-preview').innerText.trim();
    if (rawText.length > 0 && selectedEmotion === 'idle') {
        setEmotion('speaking', null, false);
    }
    const text = rawText;
    const btn = document.getElementById('send-trigger');
    const textRequired = selectedEmotion === 'speaking';
    if (textRequired && !text) return;

    btn.disabled = true;
    statusMessage("Sending to Robot...", "normal");

    try {
        const response = await fetch(`${base}/send-to-robot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                text: text,
                emotion: selectedEmotion
            })
        });
        const result = await response.json();
        
        if (result.status) {
            addLog(`✓ Sent to Robot [${selectedEmotion.toUpperCase()}]`);
            statusMessage("Sent Successfully!", "success");
            setTimeout(() => updateSendButton(), 3000);
        } else {
            throw new Error("Queue failed");
        }
    } catch (err) {
        addLog(`✕ Send Failed.`);
        statusMessage("Send Failed", "error");
        btn.disabled = false;
    }
}
