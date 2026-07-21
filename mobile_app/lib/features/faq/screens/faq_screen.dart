import 'package:flutter/material.dart';
import 'package:mobile_app/core/theme.dart';

import '../data/faq_items.dart';
import '../models/faq_item.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final _searchController = TextEditingController();

  String _query = '';
  String _selectedCategory = 'Alles';

  List<String> get _categories {
    final categories = faqItems.map((item) => item.category).toSet().toList()
      ..sort();

    return ['Alles', ...categories];
  }

  List<FaqItem> get _filteredItems {
    return faqItems.where((item) {
      final matchesCategory =
          _selectedCategory == 'Alles' || item.category == _selectedCategory;

      final normalizedQuery = _query.trim().toLowerCase();

      if (normalizedQuery.isEmpty) {
        return matchesCategory;
      }

      final matchesSearch =
          item.question.toLowerCase().contains(normalizedQuery) ||
          item.answer.toLowerCase().contains(normalizedQuery) ||
          item.category.toLowerCase().contains(normalizedQuery);

      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Veelgestelde vragen',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SearchField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _query = value);
                },
                onClear: _query.isEmpty ? null : _clearSearch,
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = category == _selectedCategory;

                  return ChoiceChip(
                    selected: selected,
                    label: Text(category),
                    onSelected: (_) {
                      setState(() => _selectedCategory = category);
                    },
                    selectedColor: const Color(0xFFE0BD22),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFF222222)
                          : const Color(0xFF6B7280),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFFE0BD22)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: items.isEmpty
                  ? _EmptyFaqState(query: _query, onClear: _clearSearch)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _FaqCard(item: items[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 15,
          color: Color(0xFF111827),
        ),
        decoration: InputDecoration(
          hintText: 'Zoeken in veelgestelde vragen',
          hintStyle: const TextStyle(
            fontFamily: 'DM Sans',
            color: Color(0xFF9CA3AF),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF6B7280),
          ),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF6B7280),
                  ),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  final FaqItem item;

  const _FaqCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            iconColor: const Color(0xFF111827),
            collapsedIconColor: const Color(0xFF6B7280),
            title: Text(
              item.question,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.category,
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE0BD22),
                ),
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.answer,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFaqState extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _EmptyFaqState({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.help_outline_rounded,
              size: 44,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 12),
            const Text(
              'Geen resultaten gevonden',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              query.isEmpty
                  ? 'Er zijn geen vragen in deze categorie.'
                  : 'Er zijn geen vragen gevonden voor “$query”.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 14),
            if (query.isNotEmpty)
              TextButton(
                onPressed: onClear,
                child: const Text('Zoekopdracht wissen'),
              ),
          ],
        ),
      ),
    );
  }
}
