import '../core/utils.dart';

class FUser {
  final String uid;
  final String username;
  final String email;
  final String? photo;
  final String bio;
  final bool verified;
  final int lastUsernameChange;
  final Set<String> saved;

  const FUser({
    required this.uid,
    required this.username,
    this.email = '',
    this.photo,
    this.bio = '',
    this.verified = false,
    this.lastUsernameChange = 0,
    this.saved = const {},
  });

  factory FUser.fromMap(String uid, Map<String, dynamic> m) => FUser(
        uid: uid,
        username: asStr(m['username'], 'kullanıcı'),
        email: asStr(m['email']),
        photo: asStrOrNull(m['profilePhotoUrl']),
        bio: asStr(m['bio']),
        verified: asBool(m['verified']),
        lastUsernameChange: asInt(m['lastUsernameChange']),
        saved: asMap(m['saved']).keys.toSet(),
      );
}

class Reply {
  final String id;
  final String uid;
  final String username;
  final String text;
  final int timestamp;
  const Reply(this.id, this.uid, this.username, this.text, this.timestamp);

  factory Reply.fromMap(String id, Map<String, dynamic> m) => Reply(
        id,
        asStr(m['uid']),
        asStr(m['username'], 'kullanıcı'),
        asStr(m['text']),
        asInt(m['timestamp']),
      );
}

class Comment {
  final String id;
  final String uid;
  final String username;
  final String text;
  final int timestamp;
  final List<Reply> replies;
  final Set<String> likedBy;

  const Comment({
    required this.id,
    required this.uid,
    required this.username,
    required this.text,
    required this.timestamp,
    this.replies = const [],
    this.likedBy = const {},
  });

  factory Comment.fromMap(String id, Map<String, dynamic> m) {
    final r = asMap(m['replies']).entries
        .map((e) => Reply.fromMap(e.key, asMap(e.value)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Comment(
      id: id,
      uid: asStr(m['uid']),
      username: asStr(m['username'], 'kullanıcı'),
      text: asStr(m['text']),
      timestamp: asInt(m['timestamp']),
      replies: r,
      likedBy: asMap(m['likedBy']).keys.toSet(),
    );
  }
}

class Post {
  final String id;
  final String uid;
  final String username;
  final String url;
  final String caption;
  final String type; // image | video | text
  final int likes;
  final Set<String> likedBy;
  final List<Comment> comments;
  final int timestamp;
  final bool edited;

  const Post({
    required this.id,
    required this.uid,
    required this.username,
    required this.url,
    required this.caption,
    required this.type,
    this.likes = 0,
    this.likedBy = const {},
    this.comments = const [],
    this.timestamp = 0,
    this.edited = false,
  });

  factory Post.fromMap(String id, Map<String, dynamic> m) {
    final c = asMap(m['comments']).entries
        .map((e) => Comment.fromMap(e.key, asMap(e.value)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final liked = asMap(m['likedBy']).entries.where((e) => asBool(e.value)).map((e) => e.key).toSet();
    var type = asStr(m['type'], 'image');
    final url = asStr(m['url']);
    if (url.isEmpty && type != 'text') type = 'text';
    return Post(
      id: id,
      uid: asStr(m['uid']),
      username: asStr(m['username'], 'kullanıcı'),
      url: url,
      caption: asStr(m['caption']),
      type: type,
      likes: liked.isNotEmpty ? liked.length : asInt(m['likes']),
      likedBy: liked,
      comments: c,
      timestamp: asInt(m['timestamp']),
      edited: asBool(m['edited']),
    );
  }

  int get commentCount => comments.fold(0, (s, c) => s + 1 + c.replies.length);
  bool get isValid => username.isNotEmpty && username != 'undefined';
}

class NotificationItem {
  final String id;
  final String type; // like | comment | reply | follow | mention | milestone
  final String message; // HTML (<strong>..</strong>)
  final String from;
  final String postId;
  final String commentId;
  final int time;
  final bool read;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.message,
    required this.from,
    this.postId = '',
    this.commentId = '',
    this.time = 0,
    this.read = false,
  });

  factory NotificationItem.fromMap(String id, Map<String, dynamic> m) => NotificationItem(
        id: id,
        type: asStr(m['type']),
        message: asStr(m['message']),
        from: asStr(m['from']),
        postId: asStr(m['postId']),
        commentId: asStr(m['commentId']),
        time: asInt(m['time']),
        read: asBool(m['read']),
      );
}

class Story {
  final String id;
  final String uid;
  final String url;
  final String caption;
  final int timestamp;
  final Set<String> viewers;

  const Story({
    required this.id,
    required this.uid,
    required this.url,
    this.caption = '',
    this.timestamp = 0,
    this.viewers = const {},
  });

  factory Story.fromMap(String id, String uid, Map<String, dynamic> m) => Story(
        id: id,
        uid: uid,
        url: asStr(m['url']),
        caption: asStr(m['caption']),
        timestamp: asInt(m['timestamp']),
        viewers: asMap(m['viewers']).keys.toSet(),
      );

  bool get expired =>
      DateTime.now().millisecondsSinceEpoch - timestamp > const Duration(hours: 24).inMilliseconds;
}
