// ============================================================
// NotesSummaryPanel — Feature 4: Notes Summary Panel
// Aggregates all comments, supports filter + sort.
// ============================================================

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/comment_model.dart';

enum NotesSortMode { byPage, byNewest }

class NotesSummaryPanel extends StatefulWidget {
  /// All in-memory comments keyed by page number.
  final Map<int, List<CommentModel>> pageComments;

  /// Called when user wants to jump to a specific page.
  final void Function(int pageNumber) onJumpToPage;

  const NotesSummaryPanel({
    super.key,
    required this.pageComments,
    required this.onJumpToPage,
  });

  @override
  State<NotesSummaryPanel> createState() => _NotesSummaryPanelState();
}

class _NotesSummaryPanelState extends State<NotesSummaryPanel> {
  CommentTag? _filterTag;
  NotesSortMode _sortMode = NotesSortMode.byPage;

  /// Flatten all comments from all pages, apply filter + sort.
  List<CommentModel> get _filteredComments {
    final all = widget.pageComments.entries
        .expand((entry) => entry.value.map((c) {
              // Ensure pageNumber is stamped (migration safety).
              if (c.pageNumber == 0) c.pageNumber = entry.key;
              return c;
            }))
        .where((c) => _filterTag == null || c.tag == _filterTag)
        .toList();

    if (_sortMode == NotesSortMode.byPage) {
      all.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    } else {
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final comments = _filteredComments;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // --- Drag Handle ---
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // --- Header Row ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(LucideIcons.bookOpen,
                        color: AppColors.accentYellow, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'ملخص الملاحظات (${comments.length})',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    const Spacer(),
                    // --- Sort toggle ---
                    GestureDetector(
                      onTap: () => setState(() {
                        _sortMode = _sortMode == NotesSortMode.byPage
                            ? NotesSortMode.byNewest
                            : NotesSortMode.byPage;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundPrimary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _sortMode == NotesSortMode.byPage
                                  ? LucideIcons.arrowDown01
                                  : LucideIcons.clock,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sortMode == NotesSortMode.byPage
                                  ? 'حسب الصفحة'
                                  : 'الأحدث أولاً',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // --- Tag filter chips ---
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _FilterChip(
                      label: 'الكل',
                      color: AppColors.accentYellow,
                      selected: _filterTag == null,
                      onTap: () => setState(() => _filterTag = null),
                    ),
                    ...CommentTag.values.map((tag) => _FilterChip(
                          label: tag.label,
                          color: Color(tag.colorValue),
                          selected: _filterTag == tag,
                          onTap: () => setState(() => _filterTag == tag
                              ? _filterTag = null
                              : _filterTag = tag),
                        )),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Divider(color: Colors.white10, height: 1),

              // --- Comments List ---
              Expanded(
                child: comments.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: comments.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, i) =>
                            _CommentTile(
                          comment: comments[i],
                          onJump: () {
                            Navigator.pop(context);
                            widget.onJumpToPage(comments[i].pageNumber);
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.fileX2,
              color: AppColors.textSecondary, size: 40),
          const SizedBox(height: 12),
          Text('لا توجد ملاحظات',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

// ---- Sub-widgets ---------------------------------------------------

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : Colors.white24, width: 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? color : Colors.white54,
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentModel comment;
  final VoidCallback onJump;

  const _CommentTile({required this.comment, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final tag = comment.tag;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Color(comment.color).withOpacity(0.15),
        child: Icon(Icons.comment_rounded,
            color: Color(comment.color).withOpacity(1.0), size: 18),
      ),
      title: Text(
        comment.text.isEmpty ? '(بدون نص)' : comment.text,
        style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontStyle: comment.text.isEmpty
                ? FontStyle.italic
                : FontStyle.normal),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(
            'صفحة ${comment.pageNumber}',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
          ),
          if (tag != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Color(tag.colorValue).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tag.label,
                  style: TextStyle(
                      color: Color(tag.colorValue),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: Icon(LucideIcons.arrowRight,
            color: AppColors.accentYellow, size: 18),
        onPressed: onJump,
        tooltip: 'الانتقال للصفحة',
      ),
    );
  }
}
