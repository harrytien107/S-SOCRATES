import json

history = []


def load_memory():
    global history

    try:
        with open("memory.json") as f:
            history = json.load(f)
    except:
        history = []


def save_memory(user, ai):

    history.append({
        "user": user,
        "ai": ai
    })

    with open("memory.json", "w") as f:
        json.dump(history, f)