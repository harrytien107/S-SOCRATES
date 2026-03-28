let currentData = null;
let selectedEmotion = 'neutral';
let lastLogMsg = "";

window.onload = () => {
    const saved = localStorage.getItem('socrates_api_base');
    if (saved) document.getElementById('api-base').value = saved;
    
    const preview = document.getElementById('final-preview');
    preview.addEventListener('input', updateSendButton);
    
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
}

function saveSettings() {
    localStorage.setItem('socrates_api_base', document.getElementById('api-base').value);
    checkConnection();
    toggleModal(false);
    addLog("Settings updated.");
}

function checkConnection() {
    const base = document.getElementById('api-base').value;
    fetch(`${base}/`).then(() => {
        document.getElementById('online-dot').classList.add('active');
        addLog("System Online.");
    }).catch(() => {
        document.getElementById('online-dot').classList.remove('active');
        addLog("Backend Offline.");
    });
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
    updateSendButton();
    
    document.querySelectorAll('.suggestion-card').forEach(el => el.classList.remove('active'));
    if (element) element.classList.add('active');
    addLog(`Preset selected.`);
}

function updateSendButton() {
    const rawText = document.getElementById('final-preview').innerText.trim();
    const btn = document.getElementById('send-trigger');
    const hasText = rawText.length > 0;
    
    btn.disabled = !hasText;
    statusMessage(hasText ? "Ready to Send" : "Waiting for response...");
}

async function useAI() {
    const base = document.getElementById('api-base').value;
    if (!currentData) {
        alert("No transcript for AI.");
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

function setEmotion(emo, btn, explicit = true) {
    if (selectedEmotion === emo) return;
    selectedEmotion = emo;
    document.querySelectorAll('.emotion-btn').forEach(el => {
        const btnText = el.innerText.toLowerCase();
        el.classList.toggle('active', btnText === emo);
    });
    if (explicit) addLog(`Emotion: ${emo}`);
}

async function sendToRobot() {
    const base = document.getElementById('api-base').value;
    const text = document.getElementById('final-preview').innerText.trim();
    const btn = document.getElementById('send-trigger');

    if (!text) return;

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