from datetime import datetime, timezone

# --- YAPILANDIRILABİLİR SABİTLER (CONFIG) ---
POST_WEIGHTS = {
    'comment': 4.0,
    'save': 3.0,     # Repost ve Paylaşımlar için de kullanılabilir
    'like': 1.0
}

REELS_WEIGHTS = {
    'completion': 10.0,
    'loop': 5.0,
    'skip_penalty': 5.0
}

TIME_DECAY_GRAVITY = 1.8


def calculate_post_raw_score(comment_count: int, save_count: int, like_count: int) -> float:
    """
    A) POST RAW SCORE (Ham Skor)
    Kullanıcı etkileşimlerinin ağırlıklandırılmış toplamını alır.
    """
    return (POST_WEIGHTS['comment'] * comment_count) + \
           (POST_WEIGHTS['save'] * save_count) + \
           (POST_WEIGHTS['like'] * like_count)


def calculate_time_decay_score(raw_score: float, created_at_iso: str) -> float:
    """
    B) TIME DECAY (Zaman Aşımı / Gravity - Hacker News Model)
    Gönderinin ne kadar eski olduğuna göre "Ham Skor" değerini törpüler.
    """
    try:
        # Appwrite "$createdAt" değeri genelde ISO-8601'dir (Örn: 2024-03-15T19:35:00.000+00:00)
        created_at = datetime.fromisoformat(created_at_iso.replace('Z', '+00:00'))
    except Exception:
        created_at = datetime.now(timezone.utc)
    
    now = datetime.now(timezone.utc)
    age_timedelta = now - created_at
    age_in_hours = age_timedelta.total_seconds() / 3600.0
    
    # Negatif saatleri engelle (Sunucu saati sapması vb. durumlar için)
    age_in_hours = max(0, age_in_hours)
    
    # Formül: final_score = (raw_score + 1) / ((age_in_hours + 2) ** gravity)
    final_score = (raw_score + 1) / ((age_in_hours + 2) ** TIME_DECAY_GRAVITY)
    return final_score


def calculate_reels_dynamic_score(watch_time_seconds: float, total_duration_seconds: float, loop_count: int, raw_interaction_score: float) -> float:
    """
    C) REELS DYNAMIC SCORE (Reels Puanlaması)
    Kısa videolar için izlenme oranına bağlı dinamik skor hesabı yapar.
    """
    if total_duration_seconds <= 0:
        completion_rate = 0.0
    else:
        completion_rate = watch_time_seconds / total_duration_seconds
        
    reels_score = (completion_rate * REELS_WEIGHTS['completion']) + \
                  (loop_count * REELS_WEIGHTS['loop']) + \
                  raw_interaction_score
                  
    # CEZA DURUMU: Hızlı geçilme (Skip) cezası
    if watch_time_seconds < 2.0:
        reels_score -= REELS_WEIGHTS['skip_penalty']
        
    return reels_score