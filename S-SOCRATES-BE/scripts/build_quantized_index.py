from services.retrieval.retriever import build_quantized_store, retriever


def main() -> None:
    build_quantized_store()
    print(retriever.stats())


if __name__ == "__main__":
    main()
