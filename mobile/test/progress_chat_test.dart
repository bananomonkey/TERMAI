import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';

void main() {
  test('MentorChat survives Progress JSON round-trip', () {
    final chat = MentorChat(
      id: 'chat-1',
      courseId: 'linux',
      taskId: 'task-1',
      taskTitle: 'Проброс портов',
      title: 'Мой чат',
      createdAt: '2026-01-01T10:00:00.000',
      updatedAt: '2026-01-01T10:05:00.000',
      messages: [
        ChatMsg('user', 'привет'),
        ChatMsg('mentor', 'ответ'),
      ],
    );
    final p = Progress()
      ..mentorChats = [chat]
      ..activeChatId = chat.id;

    final back = Progress.fromJson(p.toJson());

    expect(back.mentorChats, hasLength(1));
    expect(back.mentorChats.first.title, 'Мой чат');
    expect(back.mentorChats.first.taskTitle, 'Проброс портов');
    expect(back.mentorChats.first.messages, hasLength(2));
    expect(back.mentorChats.first.messages[1].role, 'mentor');
    expect(back.mentorChats.first.messages[1].text, 'ответ');
    expect(back.activeChatId, chat.id);
  });
}
