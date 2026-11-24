/// Appwrite yapılandırma dosyası
class AppwriteConfig {
  // 🌐 Appwrite endpoint
  static const String endpoint = String.fromEnvironment('APPWRITE_ENDPOINT', defaultValue: 'https://cloud.appwrite.io/v1');

  // 🆔 Project
  static const String projectId = String.fromEnvironment('APPWRITE_PROJECT_ID');

  // 🗄 Database
  static const String databaseId = String.fromEnvironment('APPWRITE_DATABASE_ID');

  // 📦 Storage
  static const String storageBucketId = String.fromEnvironment('APPWRITE_STORAGE_BUCKET_ID');

  // ================= COLLECTIONS =================

  // 👤 Users
  static const String usersCollectionId = 'users';

  // 📝 Posts
  static const String postsCollectionId = 'posts';
  static const String commentsCollectionId = 'comments';
  static const String postActionsCollectionId = 'post_actions'; 
  // like / unlike / soft delete vs.
  
  // 📸 Stories
  static const String storiesCollectionId = 'stories';

  // 💬 Messages
  static const String messagesCollectionId = 'messages';
  static const String chatsCollectionId = 'chats';

  // 🤝 Friendships
  static const String friendshipsCollectionId = 'friendships'; // Eski sistem (DatabaseService temizlenene kadar kalsın)
  static const String followsCollectionId = 'follows'; // Yeni sistem
  static const String blocksCollectionId = 'blocks'; // 🚫 Engellenenler

  // ================= EVENTS =================

  // 📅 Events
  static const String eventsCollectionId = 'events';

  // 👥 Event Participants
  static const String eventParticipantsCollectionId = 'event_participants';

  // ❤️ Event Likes
  /// Event like’ları post_actions içinde tutuluyor
  static const String eventLikesCollectionId = 'post_actions';

  // 📩 Event Join Requests  ✅ (EKSİKTİ)
  static const String eventJoinRequestsCollectionId = 'event_join_requests';

  // 🔔 Notifications ✅ (EKSİKTİ)
  static const String notificationsCollectionId = 'notifications';
}
