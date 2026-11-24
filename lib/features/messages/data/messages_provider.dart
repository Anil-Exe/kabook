final chatMessagesProvider =
    StreamProvider.family.autoDispose<List<Document>, ChatParams>(
        (ref, params) {
  final databases = AppwriteService.databases;
  final realtime = AppwriteService.realtime;

  final controller = StreamController<List<Document>>();
  List<Document> currentMessages = [];

  Future<void> loadInitialMessages() async {
    try {
      final result = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.or([
            Query.and([
              Query.equal('senderId', params.currentUserId),
              Query.equal('receiverId', params.otherUserId),
            ]),
            Query.and([
              Query.equal('senderId', params.otherUserId),
              Query.equal('receiverId', params.currentUserId),
            ]),
          ]),
          Query.orderAsc('\$createdAt'),
        ],
      );

      currentMessages = result.documents;
      if (!controller.isClosed) controller.add(currentMessages);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  loadInitialMessages();

  final subscription = realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.messagesCollectionId}.documents'
  ]);

  subscription.stream.listen((event) {
    final payload = event.payload;

    if (payload == null) return;

    final senderId = payload['senderId'];
    final receiverId = payload['receiverId'];

    final isThisChat =
        (senderId == params.currentUserId &&
                receiverId == params.otherUserId) ||
            (senderId == params.otherUserId &&
                receiverId == params.currentUserId);

    if (!isThisChat) return;

    loadInitialMessages();
  });

  ref.onDispose(() {
    subscription.close();
    controller.close();
  });

  return controller.stream;
});
