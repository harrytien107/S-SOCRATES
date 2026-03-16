# S-Socrates AI – Voice Debate Assistant

## S-Socrates là một AI debate assistant cho talkshow:

"Tôi tư duy, tôi tồn tại"

Ứng dụng bao gồm:

📱 Flutter App (UI + voice/chat interface)

🧠 Python Backend (FastAPI + RAG + Agent)

🤖 Local LLM (Ollama + Qwen2)

Hệ thống cho phép người dùng hỏi AI bằng tiếng Việt, và S-Socrates sẽ phản biện theo Socratic Method.

#### System Architecture
```
Flutter App
     │
     │ HTTP API
     ▼
FastAPI Backend
     │
     ├ RAG (LlamaIndex)
     │
     ├ Vector Embedding
     │
     └ LLM (Ollama + Qwen2)
```
1. Requirements
Flutter

Install Flutter SDK:

https://docs.flutter.dev/get-started/install

Check installation:

```bash
flutter doctor
```
Python

Recommended version:

Python 3.10 – 3.11

Check version:

```
python3 --version
```
2. Install Ollama (Local LLM)

We use Ollama to run LLM locally.

Install:

```bash
brew install ollama
```

or download:

https://ollama.com/download

Start Ollama server
```
ollama serve
```

You should see:

Ollama server listening on 127.0.0.1:11434
Download the model

We use Qwen2 (good multilingual model).

ollama pull qwen2:7b

Test the model:

ollama run qwen2:7b

Example prompt:

AI có thay thế kỹ sư UAV không?
3. Setup Backend (Python)

Go to backend folder:

backend/

Create virtual environment:

```bash
python3 -m venv venv
```

Activate:

Mac/Linux

```
source venv/bin/activate
```
Install dependencies
```bash
pip install fastapi uvicorn
pip install llama-index
pip install llama-index-llms-ollama
pip install llama-index-embeddings-huggingface
pip install sentence-transformers
```
Backend Folder Structure
```
backend
│
├ main.py
├ knowledge
│    └ uth.txt
```
Example Knowledge File

knowledge/uth.txt

UTH là Đại học Giao thông vận tải TP.HCM.

Các ngành nổi bật:
- Logistics
- UAV
- Embedded Systems
- Digital Economy

UTH hướng tới đào tạo High-tech Solution Engineers.
Backend Code (main.py)
```python
from fastapi import FastAPI
from pydantic import BaseModel

from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms.ollama import Ollama
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding

SYSTEM_PROMPT = """
Bạn là S-Socrates.

AI phản biện tại talkshow:
"Tôi tư duy, tôi tồn tại".

Phong cách:
- thông minh
- Gen Z nhưng lễ phép
- sử dụng phương pháp Socratic

Luôn trả lời bằng tiếng Việt.
"""

llm = Ollama(model="qwen2:7b")

embed_model = HuggingFaceEmbedding(
    model_name="sentence-transformers/all-MiniLM-L6-v2"
)

Settings.llm = llm
Settings.embed_model = embed_model

documents = SimpleDirectoryReader("knowledge").load_data()

index = VectorStoreIndex.from_documents(documents)

query_engine = index.as_query_engine()

app = FastAPI()

class ChatRequest(BaseModel):
    message: str


@app.post("/chat")
async def chat(req: ChatRequest):

    prompt = f"""
{SYSTEM_PROMPT}

Câu hỏi:
{req.message}
"""

    response = query_engine.query(prompt)

    return {"response": str(response)}
```
Run Backend
```bash
uvicorn main:app --reload
```
Server runs at:

http://127.0.0.1:8000

Open API docs:

http://127.0.0.1:8000/docs
Test Backend API

Example request:

POST /chat

Body:

{
 "message": "AI có thay thế kỹ sư UAV không?"
}

Response:

{
 "response": "S-Socrates trả lời..."
}
4. Setup Flutter App

Go to Flutter project:

flutter_app/

Install dependencies:

flutter pub get
Add HTTP package

In pubspec.yaml

dependencies:
  http: ^1.2.0
Flutter Service to Call API

lib/services/agent_api.dart

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AgentAPI {

  final String baseUrl = "http://127.0.0.1:8000/chat";

  Future<String> sendMessage(String message) async {

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "message": message
      }),
    );

    final data = jsonDecode(response.body);

    return data["response"];
  }
}
```
Run Flutter App
```bash
flutter run
```
Example Interaction
User: AI có thay thế kỹ sư không?

S-Socrates:
Thưa Giáo sư, em hơi tò mò một chút...
Nếu AI thay thế kỹ sư,
vậy ai sẽ định nghĩa vấn đề cho AI?
Future Improvements
Voice Interface

Add:

speech_to_text
flutter_tts
Knowledge RAG

Add documents:

PDF
slides
research papers
lecture notes
Multi-Agent System
Moderator Agent
Socrates Agent
Research Agent
### License

MIT License