import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import 'comments_sheet.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final bool openComments;
  const PostDetailScreen({super.key, required this.postId, this.openComments = false});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final p = await app.loadPost(widget.postId);
    if (p != null) await app.warmUsers([p.uid]);
    if (!mounted) return;
    setState(() {
      _post = p;
      _loading = false;
    });
    if (p != null && widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showCommentsSheet(context, p.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gönderi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? const EmptyState(icon: Icons.hide_image_outlined, title: 'Bu gönderi artık yok')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      PostCard(
                        key: ValueKey('${_post!.id}_${_post!.likes}_${_post!.commentCount}'),
                        post: _post!,
                        onDeleted: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
    );
  }
}
