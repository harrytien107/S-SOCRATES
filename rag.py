from langchain.vectorstores import Chroma
from langchain.embeddings import HuggingFaceEmbeddings
from langchain.document_loaders import TextLoader

def load_rag():

    loader = TextLoader("knowledge/uth.txt")
    docs = loader.load()

    embeddings = HuggingFaceEmbeddings(
        model_name="intfloat/multilingual-e5-base"
    )

    vectordb = Chroma.from_documents(
        docs,
        embeddings
    )

    return vectordb