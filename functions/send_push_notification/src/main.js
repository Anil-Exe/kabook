import { Client, Users, Messaging, ID, Query } from "node-appwrite";

/*
  Bu fonksiyon, 'messages' koleksiyonuna yeni bir belge eklendiğinde tetiklenir.
  Environment Variables (Appwrite Console'dan eklenecek):
  - APPWRITE_ENDPOINT: https://cloud.appwrite.io/v1 (veya kendi sunucun)
  - APPWRITE_PROJECT_ID: Proje ID'niz
  - APPWRITE_API_KEY: API Key (Messaging write ve Users read yetkili)
*/

export default async function (context) {
  const client = new Client();
  const users = new Users(client);
  const messaging = new Messaging(client);

  // Ortam değişkenlerini kontrol et
  if (
    !process.env['APPWRITE_ENDPOINT'] ||
    !process.env['APPWRITE_PROJECT_ID'] ||
    !process.env['APPWRITE_API_KEY']
  ) {
    context.error("Eksik ortam değişkenleri (Environment Variables).");
    return context.res.send("Hata: Konfigürasyon eksik.", 500);
  }

  // Client ayarları
  client
    .setEndpoint(process.env['APPWRITE_ENDPOINT'])
    .setProject(process.env['APPWRITE_PROJECT_ID'])
    .setKey(process.env['APPWRITE_API_KEY']);

  // Tetikleyici verisini al (Payload)
  // Appwrite Event ile tetiklendiğinde veriler context.req.body içindedir.
  // Ancak body string gelebilir, parse etmek gerekebilir.
  let payload = context.req.body;
  
  // Eğer body string ise JSON'a çevir
  if (typeof payload === 'string') {
    try {
      payload = JSON.parse(payload);
    } catch(e) {
      context.error("Payload JSON parse hatası: " + e.message);
      // Parse edilemezse devam etme
      return context.res.send("Payload hatası", 400);
    }
  }

  // 1. Payload Analizi (Mesaj mı, Bildirim mi?)
  let senderId, receiverId, content, type, relatedId;

  // DURUM A: Mesajlar Koleksiyonundan Geliyorsa (senderId ve receiverId vardır)
  if (payload.senderId && payload.receiverId) {
      senderId = payload.senderId;
      receiverId = payload.receiverId;
      content = payload.content;
      type = 'message';
      relatedId = payload.chatId;
      
      // Mesaj tipine göre içerik metnini düzenle
      const msgType = payload.messageType || 'text';
      if (msgType === 'image') content = '📷 Fotoğraf gönderdi';
      else if (msgType === 'video') content = '🎥 Video gönderdi';
      else if (msgType === 'audio') content = '🎤 Sesli mesaj gönderdi';
  } 
  // DURUM B: Bildirimler Koleksiyonundan Geliyorsa (fromUserId ve toUserId vardır)
  else if (payload.fromUserId && payload.toUserId) {
      senderId = payload.fromUserId;
      receiverId = payload.toUserId;
      content = payload.content; // Örn: "Seni takip etti", "Gönderini beğendi"
      type = payload.type; // 'follow', 'like', 'comment', 'event_invite' vs.
      relatedId = payload.eventId; // Post ID, User ID veya Event ID
  } 
  else {
      context.log("Desteklenmeyen payload yapısı, işlem iptal.");
      return context.res.send("Payload işlenmedi: Bilinmeyen veri yapısı.");
  }

  // Kendine mesaj atıyorsa bildirim gönderme
  if (senderId === receiverId) {
    context.log("Kendine mesaj gönderildi, bildirim iptal.");
    return context.res.send("Kendine gönderilen mesaj, bildirim yok.");
  }

  try {
    // 1. Alıcının Push Target'larını (Tokenlarını) bul
    context.log(`Targetlar aranıyor: ${receiverId}`);
    const targets = await users.listTargets(receiverId);

    if (targets.total === 0) {
      context.error(`Kullanıcının (${receiverId}) kayıtlı target'ı yok.`);
      return context.res.send("Kullanıcının kayıtlı cihazı (target) yok.");
    }

    // Sadece Push (FCM/APNS) targetlarını filtrele
    const pushTargets = targets.targets
        .filter(t => t.providerType === 'push')
        .map(t => t.$id);

    if (pushTargets.length === 0) {
        context.error("Push provider target bulunamadı.");
        return context.res.send("Push bildirimi için uygun target bulunamadı.");
    }

    // 2. Gönderen İsmini Bul (Başlık olarak kullanılacak)
    let title = "KaBOOK";
    try {
        const senderUser = await users.get(senderId);
        title = senderUser.name; // Sadece isim (Örn: "Ahmet Yılmaz")
    } catch (e) {
        context.log("Gönderen ismi alınamadı, varsayılan kullanılıyor.");
    }

    // 3. Bildirimi Gönder
    context.log(`Bildirim gönderiliyor... Hedef sayısı: ${pushTargets.length}`);
    
    await messaging.createPush({
      messageId: ID.unique(),
      title: title,
      body: content,
      targets: pushTargets,
      data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          id: relatedId || "", // Chat ID veya Event ID
          type: type || "general" // 'message', 'like', 'follow' vs.
      }
    });

    context.log("Bildirim başarıyla Appwrite Messaging servisine iletildi.");
    return context.res.send("Bildirim başarıyla gönderildi.");

  } catch (error) {
    context.error("Bildirim gönderme hatası: " + error.message);
    return context.res.send("Hata: " + error.message, 500);
  }
};
