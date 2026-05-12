import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:provider/provider.dart';

/// A side panel that displays and edits the metadata (name, ID, attributes)
/// of the currently selected [HexRegion].
class PropertiesPanel extends StatefulWidget {
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

/// The state for the properties panel.
/// 
/// **Critical State Syncing Mechanics:**
/// Because region switching can happen instantly while a user is typing,
/// this state maintains localized tracking variables (`_currentRegionId`, `_attributeKeys`).
/// This decoupling ensures that:
/// 1. `FocusNode`s don't accidentally write stale, buffered text into a newly selected region.
/// 2. Editing a map key doesn't scramble the UI by changing Dart's `LinkedHashMap` insertion order.
class _PropertiesPanelState extends State<PropertiesPanel> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final FocusNode _idFocusNode = FocusNode();
  String? _idError;
  String? _currentRegionId;
  List<String> _attributeKeys = [];

  @override
  void initState() {
    super.initState();
    // Validates and commits the region ID when the user clicks away from the text field.
    _idFocusNode.addListener(() {
      if (!_idFocusNode.hasFocus && mounted) {
        final state = context.read<AppState>();
        final activeRegion = state.activeRegion;
        if (activeRegion != null && activeRegion.id == _currentRegionId) {
          final val = _idController.text;
          if (val != activeRegion.id) {
            final error = state.updateRegionId(activeRegion, val);
            if (error != null) {
              setState(() { _idError = error; });
            } else {
              setState(() { _idError = null; });
              _currentRegionId = val;
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _idFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeRegion = state.activeRegion;

    if (activeRegion != null) {
      if (_currentRegionId != activeRegion.id) {
        // [Region Swap Detected]
        // The user clicked a new region in the hierarchy. We must instantly sync our
        // local controllers to the new region's data to prevent the focus listeners
        // from applying stale text input to the newly selected region.
        _currentRegionId = activeRegion.id;
        _attributeKeys = activeRegion.attributes.keys.toList();
        _nameController.value = TextEditingValue(
          text: activeRegion.name,
          selection: TextSelection.collapsed(offset: activeRegion.name.length),
        );
        _idController.value = TextEditingValue(
          text: activeRegion.id,
          selection: TextSelection.collapsed(offset: activeRegion.id.length),
        );
        _idError = null;
      } else {
        // [External Edit Detected]
        // The region wasn't swapped, but its data changed (e.g. undo/redo, or another tool).
        // Update the controllers but preserve the user's text cursor position.
        if (_nameController.text != activeRegion.name) {
          _nameController.value = TextEditingValue(
            text: activeRegion.name,
            selection: TextSelection.collapsed(offset: activeRegion.name.length),
          );
        }
        if (!_idFocusNode.hasFocus && _idController.text != activeRegion.id && _idError == null) {
          _idController.value = TextEditingValue(
            text: activeRegion.id,
            selection: TextSelection.collapsed(offset: activeRegion.id.length),
          );
        }
      }
    } else {
      _currentRegionId = null;
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
        TextField(
          controller: _idController,
          focusNode: _idFocusNode,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            errorText: _idError,
          ),
          onChanged: (val) {
            if (_idError != null) {
              setState(() { _idError = null; });
            }
          },
          onSubmitted: (val) {
            final error = state.updateRegionId(activeRegion, val);
            if (error != null) {
              setState(() { _idError = error; });
            } else {
              setState(() { _idError = null; });
              _currentRegionId = val;
            }
          },
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
                int counter = activeRegion.attributes.length;
                String newKey = 'key_$counter';
                while (activeRegion.attributes.containsKey(newKey)) {
                  counter++;
                  newKey = 'key_$counter';
                }
                activeRegion.attributes[newKey] = '';
                _attributeKeys.add(newKey);
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
        ..._attributeKeys.asMap().entries.map((entry) {
          final index = entry.key;
          final key = entry.value;
          return _buildAttributeRow(context, state, activeRegion, key, index);
        }),
      ],
    );
  }

  /// Builds a single key-value row for the attributes map.
  /// 
  /// Utilizes the stable `_attributeKeys[index]` tracker rather than the raw
  /// `activeRegion.attributes.keys` map to guarantee that the `TextFormField` 
  /// widget states don't get scrambled or pushed to the bottom when a key is renamed.
  Widget _buildAttributeRow(BuildContext context, AppState state, activeRegion, String key, int index) {
    return Padding(
      key: ValueKey('${_currentRegionId}_attr_$index'),
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
                hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
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
                final oldKey = _attributeKeys[index];
                if (newKey != oldKey && newKey.isNotEmpty) {
                  final val = activeRegion.attributes.remove(oldKey);
                  activeRegion.attributes[newKey] = val;
                  _attributeKeys[index] = newKey;
                  state.forceUpdate();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: activeRegion.attributes[key]?.toString() ?? '',
              decoration: InputDecoration(
                hintText: 'Value',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
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
                activeRegion.attributes[_attributeKeys[index]] = val;
                state.forceUpdate();
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () {
              activeRegion.attributes.remove(_attributeKeys[index]);
              _attributeKeys.removeAt(index);
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
