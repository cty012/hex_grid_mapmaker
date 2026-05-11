import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:provider/provider.dart';

class PropertiesPanel extends StatefulWidget {
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeRegion = state.activeRegion;

    if (activeRegion != null && _nameController.text != activeRegion.name) {
      _nameController.text = activeRegion.name;
    }

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            width: 1,
          ),
        ),
      ),
      child: activeRegion == null
          ? const Center(
              child: Text(
                'No Region Selected',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20.0),
                    children: [
                      _buildMainProperties(state, activeRegion),
                      const SizedBox(height: 32),
                      _buildAttributesSection(context, state, activeRegion),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text(
            'Properties',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildMainProperties(AppState state, activeRegion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Name',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (val) {
            activeRegion.name = val;
            state.forceUpdate();
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'ID',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            activeRegion.id,
            style: const TextStyle(color: Colors.white54, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildAttributesSection(BuildContext context, AppState state, activeRegion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Attributes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: () {
                final newKey = 'key_${activeRegion.attributes.length}';
                activeRegion.attributes[newKey] = '';
                state.forceUpdate();
              },
              tooltip: 'Add Attribute',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(28, 28),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...activeRegion.attributes.keys.toList().map((key) {
          return _buildAttributeRow(context, state, activeRegion, key);
        }),
      ],
    );
  }

  Widget _buildAttributeRow(BuildContext context, AppState state, activeRegion, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: key,
              decoration: InputDecoration(
                hintText: 'Key',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (newKey) {
                if (newKey != key && newKey.isNotEmpty) {
                  final val = activeRegion.attributes.remove(key);
                  activeRegion.attributes[newKey] = val;
                  state.forceUpdate();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: activeRegion.attributes[key].toString(),
              decoration: InputDecoration(
                hintText: 'Value',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (val) {
                activeRegion.attributes[key] = val;
                state.forceUpdate();
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () {
              activeRegion.attributes.remove(key);
              state.forceUpdate();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}
