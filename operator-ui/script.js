let currentData = null;
let selectedEmotion = 'neutral';
let lastLogMsg = "";

window.onload = () => {
    const saved = localStorage.getItem('socrates_api_base');
    if (saved) document.getElementById('api-base').value = saved;
    
    const preview = document.getElementById('final-preview');
    preview.addEventListener('input', updateSendButton);
    preview.addEventListener('paste', (e) => e.preventDefault());
    preview.addEventListener('keydown', (e) => e.preventDefault());
    
    checkConnection();
    updateSendButton(); // Sync initial state
    addLog("Console Ready.");
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

    // Keep only last 20 logs
    if (logContainer.children.length > 20) {
        logContainer.removeChild(logContainer.lastChild);
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
    const base = document.getElementById('api-base').value;
    localStorage.setItem('socrates_api_base', base);

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
    const base = document.getElementById('api-base').value;
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
    const base = document.getElementById('api-base').value;
    fetch(`${base}/`).then(() => {
        document.getElementById('online-dot').classList.add('active');
        addLog("System Online.");
        
        // Start polling for transcripts once connected
        if (!window.transcriptPollInterval) {
            window.transcriptPollInterval = setInterval(pollTranscript, 2000);
        }
    }).catch(() => {
        document.getElementById('online-dot').classList.remove('active');
        addLog("Backend Offline.");
        if (window.transcriptPollInterval) {
            clearInterval(window.transcriptPollInterval);
            window.transcriptPollInterval = null;
        }
    });
}

async function pollTranscript() {
    const base = document.getElementById('api-base').value;
    try {
        const response = await fetch(`${base}/latest-transcript`);
        if (response.ok) {
            const data = await response.json();
            if (data && data.transcript) {
                currentData = data;
                displayWorkflow(data);
                addLog("Received new voice input from Robot.");
            }
        }
    } catch (err) {
        // Ignore silent polling errors
    }
}

async function handleFileUpload(input) {
    if (!input.files || !input.files[0]) return;
    const file = input.files[0];
    const base = document.getElementById('api-base').value;
    
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
    const base = document.getElementById('api-base').value;
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
    const base = document.getElementById('api-base').value;
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

async function sendToRobot() {
    const base = document.getElementById('api-base').value;
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
