import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/models/hex_region.dart';
import 'package:hex_grid_mapmaker/state/editor_state.dart';
import 'package:hex_grid_mapmaker/state/map_state.dart';
import 'package:provider/provider.dart';

class PropertiesPanel extends StatefulWidget {
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _idFocusNode = FocusNode();
  String? _idError;
  String? _currentRegionId;
  List<String> _attributeKeys = [];

  @override
  void initState() {
    super.initState();
    _idFocusNode.addListener(_onIdFocusChange);
  }

  void _onIdFocusChange() {
    if (!_idFocusNode.hasFocus && mounted) {
      final mapState = context.read<MapState>();
      final editor = context.read<EditorState>();
      if (_currentRegionId == null) return;
      final region = mapState.hexMap
          .getLayer(editor.activeLayerIndex)
          ?.getRegion(_currentRegionId!);
      if (region == null) return;

      final val = _idController.text;
      if (val != region.id) {
        final error = mapState.updateRegionId(
            region.id, val, editor.activeLayerIndex);
        if (error != null) {
          setState(() => _idError = error);
        } else {
          setState(() => _idError = null);
          _currentRegionId = val;
          editor.setActiveRegion(val);
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _idFocusNode.dispose();
    super.dispose();
  }

  HexRegion? _getActiveRegion(MapState mapState, EditorState editor) {
    if (editor.activeRegionId == null) return null;
    return mapState.hexMap
        .getLayer(editor.activeLayerIndex)
        ?.getRegion(editor.activeRegionId!);
  }

  void _syncControllers(HexRegion? activeRegion) {
    if (activeRegion != null) {
      if (_currentRegionId != activeRegion.id) {
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
        if (_nameController.text != activeRegion.name) {
          _nameController.value = TextEditingValue(
            text: activeRegion.name,
            selection:
                TextSelection.collapsed(offset: activeRegion.name.length),
          );
        }
        if (!_idFocusNode.hasFocus &&
            _idController.text != activeRegion.id &&
            _idError == null) {
          _idController.value = TextEditingValue(
            text: activeRegion.id,
            selection:
                TextSelection.collapsed(offset: activeRegion.id.length),
          );
        }
      }
    } else {
      _currentRegionId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapState = context.watch<MapState>();
    final editor = context.watch<EditorState>();
    final activeRegion = _getActiveRegion(mapState, editor);
    _syncControllers(activeRegion);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      child: activeRegion == null
          ? const Center(
              child:
                  Text('No Region Selected', style: TextStyle(color: Colors.white38)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20.0),
                    children: [
                      _buildMainProperties(
                          mapState, editor, activeRegion),
                      const SizedBox(height: 32),
                      _buildAttributesSection(
                          context, mapState, activeRegion),
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
          const Text('Properties',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildMainProperties(
      MapState mapState, EditorState editor, HexRegion activeRegion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Name',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white54)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (val) {
            mapState.setRegionName(
                editor.activeLayerIndex, activeRegion.id, val);
          },
        ),
        const SizedBox(height: 16),
        const Text('ID',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white54)),
        TextField(
          controller: _idController,
          focusNode: _idFocusNode,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            errorText: _idError,
          ),
          onChanged: (val) {
            if (_idError != null) setState(() => _idError = null);
          },
          onSubmitted: (val) {
            final error = mapState.updateRegionId(
                activeRegion.id, val, editor.activeLayerIndex);
            if (error != null) {
              setState(() => _idError = error);
            } else {
              setState(() => _idError = null);
              _currentRegionId = val;
              editor.setActiveRegion(val);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAttributesSection(
      BuildContext context, MapState mapState, HexRegion activeRegion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Attributes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: () {
                int counter = activeRegion.attributes.length;
                String newKey = 'key_$counter';
                while (activeRegion.attributes.containsKey(newKey)) {
                  counter++;
                  newKey = 'key_$counter';
                }
                activeRegion.setAttribute(newKey, '');
                _attributeKeys.add(newKey);
                mapState.forceUpdate();
              },
              tooltip: 'Add Attribute',
              style: IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(28, 28),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._attributeKeys.asMap().entries.map((entry) {
          return _buildAttributeRow(
              context, mapState, activeRegion, entry.key);
        }),
      ],
    );
  }

  Widget _buildAttributeRow(
      BuildContext context, MapState mapState, HexRegion region, int index) {
    final key = _attributeKeys[index];
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
                hintStyle:
                    const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (newKey) {
                final oldKey = _attributeKeys[index];
                if (newKey != oldKey && newKey.isNotEmpty) {
                  region.renameAttribute(oldKey, newKey);
                  _attributeKeys[index] = newKey;
                  mapState.forceUpdate();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: region.attributes[key]?.toString() ?? '',
              decoration: InputDecoration(
                hintText: 'Value',
                hintStyle:
                    const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (val) {
                region.setAttribute(_attributeKeys[index], val);
                mapState.forceUpdate();
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () {
              region.removeAttribute(_attributeKeys[index]);
              _attributeKeys.removeAt(index);
              mapState.forceUpdate();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}
