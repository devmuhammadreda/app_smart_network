/// Simple model that maps JSONPlaceholder `/posts` responses.
class PostModel {
  final int id;
  final int userId;
  final String title;
  final String body;

  const PostModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) => PostModel(
        id: json['id'] as int,
        userId: json['userId'] as int,
        title: json['title'] as String,
        body: json['body'] as String,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'title': title,
        'body': body,
      };

  @override
  String toString() => 'Post(id: $id, title: $title)';
}
