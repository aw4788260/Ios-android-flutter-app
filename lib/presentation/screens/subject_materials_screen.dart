import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import 'chapter_contents_screen.dart';
import 'exam_view_screen.dart';
import 'exam_result_screen.dart';
import 'teacher/manage_content_screen.dart';
import 'teacher/create_exam_screen.dart';
import 'teacher/exam_stats_screen.dart';
import '../../core/constants/api_constants.dart';

class SubjectMaterialsScreen extends StatefulWidget {
  final String subjectId;
  final String subjectTitle;

  const SubjectMaterialsScreen({
    super.key,
    required this.subjectId,
    required this.subjectTitle,
  });

  @override
  State<SubjectMaterialsScreen> createState() => _SubjectMaterialsScreenState();
}

class _SubjectMaterialsScreenState extends State<SubjectMaterialsScreen> {
  String _activeTab = 'chapters'; // chapters | exams
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _content;
  bool _isTeacher = false;

  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance
        .log("Opened Subject: ${widget.subjectTitle} (${widget.subjectId})");
    _checkUserRole();
    _fetchContent();
  }

  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });
    }
  }

  Future<void> _fetchContent() async {
    try {
      var box = await StorageService.openBox('auth_box');
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      final res = await Dio().get(
        '$_baseUrl/api/secure/get-subject-content',
        queryParameters: {'subjectId': widget.subjectId},
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-device-id': deviceId,
          'x-app-secret': "My_Sup3r_S3cr3t_K3y_For_Android_App_Only",
        }),
      );

      if (mounted) {
        setState(() {
          _content = res.data;
          _loading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Fetching Subject Content Failed');
      if (mounted)
        setState(() {
          _error = "Failed to load content.";
          _loading = false;
        });
    }
  }

  // ✅ دالة لتحديث الشابتر في القائمة محلياً (Optimistic Update) أو بعد العودة
  void _updateChapterList(dynamic result) {
    // إذا كانت النتيجة true فقط (بدون بيانات)، نعيد جلب البيانات كاملة من السيرفر
    if (result == true) {
      _fetchContent();
      return;
    }

    if (result == null || _content == null) return;

    setState(() {
      List chapters = List.from(_content!['chapters'] ?? []);

      if (result is Map && result['deleted'] == true) {
        // حذف شابتر
        chapters
            .removeWhere((c) => c['id'].toString() == result['id'].toString());
      } else if (result is Map<String, dynamic>) {
        // إضافة أو تحديث
        int index = chapters
            .indexWhere((c) => c['id'].toString() == result['id'].toString());
        if (index != -1) {
          chapters[index] = result;
        } else {
          chapters.add(result);
        }
      }
      _content!['chapters'] = chapters;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_error != null)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          appBar: AppBar(
              backgroundColor: Colors.transparent,
              leading: BackButton(color: AppColors.accentYellow)),
          body: Center(
              child: Text(_error!, style: TextStyle(color: AppColors.error))));

    final chapters = _content!['chapters'] as List;
    final exams = _content!['exams'] as List;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ✅ الجزء الأيسر: زر الرجوع + العناوين (مع Expanded)
                      Expanded(
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.05)),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black12, blurRadius: 4)
                                  ],
                                ),
                                child: Icon(LucideIcons.arrowLeft,
                                    color: AppColors.accentYellow, size: 20),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // ✅ Expanded للنصوص لتأخذ المساحة المتبقية فقط
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ✅ SingleChildScrollView للعنوان الطويل جداً
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      widget.subjectTitle.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                        // تمت إزالة overflow: ellipsis للسماح بالسحب
                                        letterSpacing: -0.5,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "SUBJECT CONTENTS",
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accentYellow,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 🟢 زر إضافة محتوى (يظهر للمعلم فقط)
                      if (_isTeacher) ...[
                        const SizedBox(width: 10), // مسافة أمان
                        GestureDetector(
                          onTap: () {
                            if (_activeTab == 'chapters') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ManageContentScreen(
                                    contentType: ContentType.chapter,
                                    parentId: widget.subjectId,
                                  ),
                                ),
                              ).then((val) {
                                // ✅ تحديث البيانات عند العودة (val == true)
                                if (val == true) _fetchContent();
                              });
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CreateExamScreen(
                                      subjectId: widget.subjectId),
                                ),
                              ).then((_) => _fetchContent());
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color:
                                      AppColors.accentYellow.withOpacity(0.5)),
                            ),
                            child: Icon(
                                _activeTab == 'chapters'
                                    ? LucideIcons.folderPlus
                                    : LucideIcons.filePlus,
                                color: AppColors.accentYellow,
                                size: 22),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tab Switcher
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildTab("Chapters", 'chapters'),
                        _buildTab("Exams (${exams.length})", 'exams'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _activeTab == 'chapters'
                  ? _buildChaptersList(chapters)
                  : _buildExamsList(exams),
            ),
          ],
        ),
      ),
    );
  }

  // --- قائمة الامتحانات ---
  Widget _buildExamsList(List allExams) {
    final visibleExams = allExams.where((exam) {
      if (_isTeacher) return true;

      if (exam['start_time'] != null) {
        final DateTime startTime = DateTime.parse(exam['start_time']).toLocal();
        if (DateTime.now().isBefore(startTime)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (visibleExams.isEmpty) {
      return _buildEmptyState(LucideIcons.fileCheck, "No exams available yet");
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: visibleExams.length,
      itemBuilder: (context, index) {
        final exam = visibleExams[index];
        final bool isCompleted = exam['isCompleted'] ?? false;
        final bool isExpired = exam['isExpired'] ?? false;

        final Color statusColor = isCompleted
            ? AppColors.success
            : (isExpired ? AppColors.error : AppColors.accentOrange);

        String statusText = "UNSOLVED";
        if (isCompleted) {
          statusText = "COMPLETED";
        } else if (isExpired) {
          statusText = "EXPIRED";
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              // الأيقونة
              GestureDetector(
                onTap: () => _openExam(exam, isCompleted, isExpired),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Icon(
                      isCompleted
                          ? LucideIcons.checkCircle2
                          : (isExpired ? LucideIcons.clock : LucideIcons.fileX),
                      color: statusColor,
                      size: 20),
                ),
              ),
              const SizedBox(width: 16),

              // التفاصيل
              Expanded(
                child: GestureDetector(
                  onTap: () => _openExam(exam, isCompleted, isExpired),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (exam['title'] ?? 'Untitled Exam')
                            .toString()
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            "${exam['duration_minutes'] ?? 0} MINS",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary.withOpacity(0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 🟢 أزرار التحكم للمعلم
              if (_isTeacher)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(LucideIcons.edit,
                          color: AppColors.accentOrange, size: 20),
                      tooltip: "تعديل الامتحان",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateExamScreen(
                              subjectId: widget.subjectId,
                              examId: exam['id'].toString(),
                            ),
                          ),
                        ).then((val) {
                          if (val == true) _fetchContent();
                        });
                      },
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.barChart2,
                          color: AppColors.accentYellow, size: 20),
                      tooltip: "Statistics",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExamStatsScreen(
                              examId: exam['id'].toString(),
                              examTitle: exam['title'] ?? "Exam",
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                )
              else
                IconButton(
                  icon: Icon(LucideIcons.chevronRight,
                      size: 20, color: statusColor.withOpacity(0.5)),
                  onPressed: () => _openExam(exam, isCompleted, isExpired),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openExam(Map exam, bool isCompleted, bool isExpired) {
    if (isCompleted) {
      final attemptId = exam['last_attempt_id'] ??
          exam['first_attempt_id'] ??
          exam['attempt_id'];
      if (attemptId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
              attemptId: attemptId.toString(),
              examTitle: exam['title'] ?? 'Exam Result',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error: Cannot load result."),
            backgroundColor: AppColors.error));
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ExamViewScreen(
                  examId: exam['id'].toString(),
                  examTitle: exam['title'] ?? 'Exam',
                  isCompleted: isCompleted,
                )),
      );
    }
  }

  Widget _buildChaptersList(List chapters) {
    if (chapters.isEmpty)
      return _buildEmptyState(LucideIcons.bookOpen, "No chapters found");

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final videosCount = (chapter['videos'] as List? ?? []).length;
        final pdfsCount = (chapter['pdfs'] as List? ?? []).length;

        return GestureDetector(
          onTap: () {
            final String courseTitle =
                _content?['course_title'] ?? 'Unknown Course';

            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChapterContentsScreen(
                        chapter: Map<String, dynamic>.from(chapter),
                        courseTitle: courseTitle,
                        subjectTitle: widget.subjectTitle,
                        subjectId: widget
                            .subjectId, // ✅ ضروري لتحديث المحتوى داخل الشابتر
                      )),
            ).then((updatedChapter) {
              // ✅ التعديل هنا: استقبال الشابتر المحدث وتحديث القائمة المحلية
              if (updatedChapter != null && updatedChapter is Map) {
                _updateChapterList(Map<String, dynamic>.from(updatedChapter));
              } else {
                _fetchContent(); // كإجراء احتياطي فقط
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4)
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 2)
                    ],
                  ),
                  child: Center(
                    child: Text(
                      "${index + 1}".padLeft(2, '0'),
                      style: TextStyle(
                        color: AppColors.accentYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (chapter['title'] ?? 'Chapter')
                            .toString()
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(LucideIcons.hash,
                              size: 10, color: AppColors.accentOrange),
                          const SizedBox(width: 4),
                          Text(
                            "${videosCount + pdfsCount} CONTENTS",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 🟢 زر تعديل الشابتر للمعلم
                if (_isTeacher)
                  IconButton(
                    icon: Icon(LucideIcons.edit2,
                        size: 18, color: AppColors.accentYellow),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManageContentScreen(
                            contentType: ContentType.chapter,
                            initialData: chapter,
                            parentId: widget.subjectId,
                          ),
                        ),
                      ).then((val) {
                        // ✅ تحديث فوري عند العودة (true)
                        if (val == true) _fetchContent();
                      });
                    },
                  )
                else
                  Icon(LucideIcons.chevronRight,
                      size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab(String title, String key) {
    final isActive = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeTab = key);
          FirebaseCrashlytics.instance.log("Switched tab to: $key");
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.backgroundPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: isActive
                ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                : [],
          ),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color:
                  isActive ? AppColors.accentYellow : AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
