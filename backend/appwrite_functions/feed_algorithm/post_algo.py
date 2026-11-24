import os
from appwrite.query import Query
from datetime import datetime, timedelta
from .scoring import calculate_post_raw_score, calculate_time_decay_score
from .appwrite_queries import get_databases, update_document_score

DATABASE_ID = os.getenv("DATABASE_ID", "demo_databaseId")
POSTS_COLLECTION_ID = os.getenv("POSTS_COLLECTION_ID", "posts")

def process_and_update_posts(limit: int = 100):
    """
    Son 48 saatteki normal postları (Resim/Yazı) çeker, skorlarını hesaplar ve veritabanına yazar.
    """
    databases = get_databases()
    
    try:
        # Optimizasyon: Son 48 saati hesapla
        forty_eight_hours_ago = (datetime.utcnow() - timedelta(hours=48)).isoformat()
        
        # Appwrite üzerinden ham ve optimize veriyi çek (Query.limit ve Query.orderDesc)
        response = databases.list_documents(
            database_id=DATABASE_ID,
            collection_id=POSTS_COLLECTION_ID,
            queries=[
                Query.not_equal("mediaType", "video"), # Sadece normal postlar
                Query.greater_than_equal("$createdAt", forty_eight_hours_ago),
                Query.order_desc("$createdAt"),
                Query.limit(limit)
            ]
        )
        
        posts = response.get("documents", [])
        updated_count = 0
        
        for post in posts:
            post_id = post.get("$id")
            # Etkileşim verilerini al (KaBOOK Flutter Şemasına uygun olarak)
            comment_count = post.get("commentsCount", 0)
            save_count = post.get("sharesCount", 0) + post.get("repostsCount", 0)
            like_count = post.get("likesCount", 0)
            
            raw_score = calculate_post_raw_score(comment_count, save_count, like_count)
            final_score = calculate_time_decay_score(raw_score, post.get("$createdAt"))
            
            # Appwrite'daki dokümanı güncelle
            update_document_score(DATABASE_ID, POSTS_COLLECTION_ID, post_id, final_score)
            updated_count += 1
            
        return f"{updated_count} normal post güncellendi."
        
    except Exception as e:
        print(f"Post güncellenirken hata meydana geldi: {e}")
        return str(e)