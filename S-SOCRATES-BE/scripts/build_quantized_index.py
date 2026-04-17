from pathlib import Path
import sys


BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))


from services.retrieval.retriever import build_quantized_store, retriever


def main() -> None:
    build_quantized_store()
    print(retriever.stats())


if __name__ == "__main__":
    main()
