import os
from appwrite.query import Query
from datetime import datetime, timedelta
from .scoring import calculate_post_raw_score, calculate_reels_dynamic_score, calculate_time_decay_score
from .appwrite_queries import get_databases, update_document_score

DATABASE_ID = os.getenv("DATABASE_ID", "demo_databaseId")
POSTS_COLLECTION_ID = os.getenv("POSTS_COLLECTION_ID", "posts")
ANALYTICS_COLLECTION_ID = os.getenv("ANALYTICS_COLLECTION_ID", "analytics")

def process_and_update_reels(limit: int = 100):
    """
    Son 48 saatteki Reels (Video) postlarını çeker, dinamik skorlarını hesaplar ve günceller.
    """
    databases = get_databases()
    
    try:
        forty_eight_hours_ago = (datetime.utcnow() - timedelta(hours=48)).isoformat()
        
        response = databases.list_documents(
            database_id=DATABASE_ID,
            collection_id=POSTS_COLLECTION_ID,
            queries=[
                Query.equal("mediaType", "video"), # Sadece Reels
                Query.greater_than_equal("$createdAt", forty_eight_hours_ago),
                Query.order_desc("$createdAt"),
                Query.limit(limit)
            ]
        )
        
        reels_list = response.get("documents", [])
        updated_count = 0
        
        for reel in reels_list:
            reel_id = reel.get("$id")
            
            # Etkileşim Skoru
            raw_interaction = calculate_post_raw_score(
                reel.get("commentsCount", 0), 
                reel.get("sharesCount", 0) + reel.get("repostsCount", 0), 
                reel.get("likesCount", 0)
            )
            
            # 📊 Analytics Tablosundan Video İstatistiklerini Çek
            analytics_response = databases.list_documents(
                database_id=DATABASE_ID,
                collection_id=ANALYTICS_COLLECTION_ID,
                queries=[
                    Query.equal("postId", reel_id),
                    Query.limit(500) # Son 500 logu baz al (performans için)
                ]
            )
            
            analytics_events = analytics_response.get("documents", [])
            
            total_duration_ms = 0
            view_count = 0
            skip_count = 0
            completion_count = 0
            
            for event in analytics_events:
                e_type = event.get("eventType")
                if e_type == "view":
                    total_duration_ms += event.get("durationMs", 0)
                    view_count += 1
                elif e_type == "skip":
                    skip_count += 1
                elif e_type == "completion":
                    completion_count += 1
                    
            total_interactions = view_count + skip_count
            
            if total_interactions > 0:
                # Skip edilenleri hızlı geçilmiş (1 sn) olarak hesapla
                avg_watch_time = ((total_duration_ms / 1000.0) + (skip_count * 1.0)) / total_interactions
                avg_loop_count = completion_count / total_interactions
                
                # Tahmini video süresi (Maksimum izlenen süreye veya en az 10 saniyeye göre)
                max_watched_ms = max([e.get("durationMs", 0) for e in analytics_events if e.get("eventType") == "view"], default=10000)
                estimated_total_duration = max(10.0, max_watched_ms / 1000.0)
            else:
                # Hiç veri yoksa varsayılan puanlama (nötr)
                avg_watch_time = 0.0
                estimated_total_duration = 10.0
                avg_loop_count = 0.0
            
            # Reels skoru ve zaman aşımı hesaplama
            dynamic_score = calculate_reels_dynamic_score(
                watch_time_seconds=avg_watch_time, 
                total_duration_seconds=estimated_total_duration, 
                loop_count=avg_loop_count, 
                raw_interaction_score=raw_interaction
            )
            
            final_score = calculate_time_decay_score(dynamic_score, reel.get("$createdAt"))
            
            update_document_score(DATABASE_ID, POSTS_COLLECTION_ID, reel_id, final_score)
            updated_count += 1
            
        return f"{updated_count} Reels videosu güncellendi."
        
    except Exception as e:
        return str(e)