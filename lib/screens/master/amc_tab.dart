import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class AmcTab extends ConsumerStatefulWidget {
  const AmcTab({super.key});

  @override
  ConsumerState<AmcTab> createState() => _AmcTabState();
}

class _AmcTabState extends ConsumerState<AmcTab> {
  final _refService = ReferenceService();
  final _userService = UserService();
  final _courseService = CourseService();
  String? _selectedCourseTypeId;

  @override
  void initState() {
    super.initState();
    final types = _refService.getCourseTypes();
    if (types.isNotEmpty) _selectedCourseTypeId = types.first.id;
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final types = _refService.getCourseTypes();
    final typeInfo = _selectedCourseTypeId != null
        ? _refService.getCourseType(_selectedCourseTypeId!)
        : null;
    final allUsers = _userService.getAllUsers();
    final instructors = allUsers.where((u) => u.userRole == UserRole.instructor).toList();

    // Find which instructors are assigned to active courses of this type
    final activeCourses = _selectedCourseTypeId != null
        ? _courseService.getAllCourses()
            .where((c) => c.courseTypeId == _selectedCourseTypeId && c.isActive)
            .toList()
        : [];

    final courseInstructorIds = activeCourses
        .expand((c) => c.instructorIds)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('Tabella AMC', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              DropdownButton<String>(
                value: _selectedCourseTypeId,
                dropdownColor: kSurface,
                style: const TextStyle(color: kText),
                underline: const SizedBox(),
                items: types
                    .map((t) => DropdownMenuItem(value: t.id, child: Text(t.code)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCourseTypeId = v),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (typeInfo != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              typeInfo.name,
              style: const TextStyle(color: kTextDim, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        if (typeInfo == null)
          const Center(child: Text('Seleziona un tipo di corso', style: TextStyle(color: kTextDim)))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Table(
                border: TableBorder.all(color: kBorder, width: 0.5),
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: kSurface),
                    children: [
                      _cell('Sottomodulo', header: true),
                      _cell('Istruttori abilitati (nei corsi attivi)', header: true),
                    ],
                  ),
                  for (final module in typeInfo.modules)
                    for (final sub in module.submodules)
                      TableRow(
                        children: [
                          _cell('${sub.code}\n${sub.name}'),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: courseInstructorIds.isEmpty
                                ? const Text('—', style: TextStyle(color: kTextDim, fontSize: 12))
                                : Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: instructors
                                        .where((i) => courseInstructorIds.contains(i.id))
                                        .map((i) => Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: kPrimary.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: kPrimary.withOpacity(0.3)),
                                              ),
                                              child: Text(i.fullName,
                                                  style: const TextStyle(color: kPrimary, fontSize: 11)),
                                            ))
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cell(String text, {bool header = false}) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      text,
      style: TextStyle(
        color: header ? kText : kTextDim,
        fontWeight: header ? FontWeight.bold : FontWeight.normal,
        fontSize: header ? 13 : 12,
      ),
    ),
  );
}
