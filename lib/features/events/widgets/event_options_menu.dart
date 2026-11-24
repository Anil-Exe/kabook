import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';

class EventOptionsMenu extends StatelessWidget {
  final String eventId;
  final String ownerId;
  final String currentUserId;
  final VoidCallback? onEdit;
  final VoidCallback? onDeleted;

  const EventOptionsMenu({
    super.key,
    required this.eventId,
    required this.ownerId,
    required this.currentUserId,
    this.onEdit,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    // SADECE etkinlik sahibi (ownerId == currentUserId) için görünür
    if (ownerId != currentUserId) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'edit') {
          onEdit?.call();
        } else if (value == 'delete') {
          _showDeleteConfirmation(context);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 20, color: Colors.black87),
              SizedBox(width: 12),
              Text('Düzenle'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text('Sil', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Etkinliği Sil'),
        content: const Text('Bu etkinliği silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await _deleteEvent(context);
    }
  }

  Future<void> _deleteEvent(BuildContext context) async {
    try {
      // Appwrite veritabanından silme işlemi
      await AppwriteService.databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: eventId,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Etkinlik başarıyla silindi')),
        );
        onDeleted?.call(); // Listeyi yenilemek için callback tetikle
      }
    } on AppwriteException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: ${e.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bir hata oluştu')),
        );
      }
    }
  }
}