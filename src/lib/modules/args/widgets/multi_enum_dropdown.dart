part of args;

class MultiEnumDropdown extends StatelessWidget {
  const MultiEnumDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  final List<String> value;
  final List<String> options;
  final ValueChanged<List<String>> onChanged;
  final String? errorText;
  final bool enabled;

  static const double _menuMaxHeight = 288;

  @override
  Widget build(BuildContext context) {
    final selected = value.toSet();
    final label = options
        .where(selected.contains)
        .map((option) => option.tr)
        .join(', ');

    return MenuAnchor(
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _menuMaxHeight),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options.map((option) {
                  final isSelected = selected.contains(option);
                  return MenuItemButton(
                    closeOnActivate: false,
                    trailingIcon: IgnorePointer(
                      child: Checkbox(value: isSelected, onChanged: (_) {}),
                    ),
                    onPressed: enabled
                        ? () {
                            final next = selected.toSet();
                            isSelected
                                ? next.remove(option)
                                : next.add(option);
                            onChanged(
                              options
                                  .where(next.contains)
                                  .toList(growable: false),
                            );
                          }
                        : null,
                    child: Text(
                      option.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return InkWell(
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          borderRadius: BorderRadius.circular(Radii.xs),
          child: InputDecorator(
            isEmpty: label.isEmpty,
            decoration: InputDecoration(
              errorText: errorText,
              enabled: enabled,
              suffixIcon: Icon(
                controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              ),
            ),
            child: Text(
              label.isEmpty ? ' ' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        );
      },
    );
  }
}
