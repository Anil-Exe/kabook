import os
from appwrite.client import Client
from appwrite.services.databases import Databases

# Bağlantıyı sadece BİR KERE açmak için global değişkenler oluşturuyoruz (Hız ve Limit çözümü)
_client = None
_databases = None

def get_databases() -> Databases:
    global _client, _databases
    
    # Eğer bağlantı zaten varsa yenisini kurma
    if _databases is None:
        _client = Client()
        
        # HATA ÇÖZÜMÜ: Yönlendirme (Redirect) olmaması için adresi SIKI SABİTLİYORUZ.
        # "fra." ekini tamamen sildik.
        endpoint = os.getenv("APPWRITE_FUNCTION_ENDPOINT", "https://cloud.appwrite.io/v1")
        project_id = os.getenv("APPWRITE_FUNCTION_PROJECT_ID", "demo_projectId")
        api_key = os.getenv("APPWRITE_API_KEY") 
        
        _client.set_endpoint(endpoint)
        _client.set_project(project_id)
        if api_key:
            _client.set_key(api_key)
            
        _databases = Databases(_client)
        
    return _databases

def update_document_score(database_id: str, collection_id: str, document_id: str, new_score: float):
    """
    Hesaplanan yeni skoru Appwrite veritabanındaki ilgili dokümana (Post/Reels) yazar.
    """
    db = get_databases() # Artık var olan hazır bağlantıyı kullanacak
    try:
        db.update_document(
            database_id=database_id,
            collection_id=collection_id,
            document_id=document_id,
            data={
                "score": int(round(new_score))
            }
        )
    except Exception as e:
        print(f"Skor güncellenemedi ({document_id}): {e}")