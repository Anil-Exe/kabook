import sys
import os

# Appwrite'a bulunduğumuz klasörü zorla tanıtıyoruz (ModuleNotFoundError Çözümü)
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from feed_algorithm.post_algo import process_and_update_posts
from feed_algorithm.reels_algo import process_and_update_reels

def main(context):
    """
    Appwrite bu fonksiyonu çağırdığında çalışacak ana kod.
    """
    context.log("KaBOOK Feed ve Reels Skor Güncellemesi Başlıyor...")
    
    try:
        post_result = process_and_update_posts()
        context.log(f"Post Sonucu: {post_result}")
        
        reels_result = process_and_update_reels()
        context.log(f"Reels Sonucu: {reels_result}")
        
        return context.res.json({"success": True, "message": "Skorlar başarıyla güncellendi."})
    except Exception as e:
        context.error(f"Hata oluştu: {e}")
        return context.res.json({"success": False, "error": str(e)}, 500)