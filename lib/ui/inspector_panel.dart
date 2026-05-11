import 'package:flutter/material.dart';
import 'package:hex_grid_mapmaker/state/app_state.dart';
import 'package:provider/provider.dart';

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({super.key});

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeRegion = state.activeRegion;

    if (activeRegion != null && _nameController.text != activeRegion.name) {
      _nameController.text = activeRegion.name;
    }

    return Container(
      width: 300,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              children: [
                _buildLayerControls(context, state),
                _buildRegionList(context, state),
              ],
            ),
          ),
          const Divider(height: 1),
          if (activeRegion != null)
            _buildProperties(context, state, activeRegion),
        ],
      ),
    );
  }

  Widget _buildLayerControls(BuildContext context, AppState state) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Layer: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              DropdownButton<int>(
                value: state.activeLayerIndex,
                items: state.hexMap.layers.map((l) {
                  return DropdownMenuItem<int>(
                    value: l.index,
                    child: Text('Layer ${l.index}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) state.setActiveLayer(val);
                },
                isDense: true,
                underline: const SizedBox(),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.library_add, size: 20),
                onPressed: () => state.addLayer(),
                tooltip: 'Add Layer',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.redAccent,
                ),
                onPressed: () => _confirmDeleteLayer(context, state, state.activeLayerIndex),
                tooltip: 'Delete Layer',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegionList(BuildContext context, AppState state) {
    final activeLayer = state.activeLayer;

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Regions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => state.addRegion('New Region'),
                  tooltip: 'Add Region',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: activeLayer.regions.length,
              itemBuilder: (context, index) {
                final region = activeLayer.regions[index];
                final isSelected = region.id == state.activeRegionId;
                return ListTile(
                  title: Text(region.name),
                  subtitle: Text(
                    'ID: ${region.id}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  selected: isSelected,
                  selectedTileColor: Colors.blueAccent.withValues(alpha: 0.2),
                  onTap: () => state.setActiveRegion(region.id),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 16),
                    onPressed: () => _confirmDeleteRegion(context, state, region.id, region.name),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProperties(BuildContext context, AppState state, activeRegion) {
    return Expanded(
      flex: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Properties',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                ),
                onChanged: (val) {
                  activeRegion.name = val;
                  state.forceUpdate();
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Attributes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () {
                      final newKey = 'key_${activeRegion.attributes.length}';
                      activeRegion.attributes[newKey] = '';
                      state.forceUpdate();
                    },
                    tooltip: 'Add Attribute',
                  ),
                ],
              ),
              ...activeRegion.attributes.keys.toList().map((key) {
                return _buildAttributeRow(state, activeRegion, key);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttributeRow(AppState state, activeRegion, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: key,
              decoration: const InputDecoration(hintText: 'Key', isDense: true),
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
            child: TextFormField(
              initialValue: activeRegion.attributes[key].toString(),
              decoration: const InputDecoration(
                hintText: 'Value',
                isDense: true,
              ),
              onChanged: (val) {
                activeRegion.attributes[key] = val;
                state.forceUpdate();
              },
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              size: 16,
              color: Colors.red,
            ),
            onPressed: () {
              activeRegion.attributes.remove(key);
              state.forceUpdate();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteLayer(BuildContext context, AppState state, int layerIndex) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Layer'),
          content: Text('Are you sure you want to delete Layer $layerIndex?\nThis action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (result == true) {
      state.deleteLayer();
    }
  }

  Future<void> _confirmDeleteRegion(BuildContext context, AppState state, String regionId, String regionName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Region'),
          content: Text('Are you sure you want to delete region "$regionName"?\nThis action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (result == true) {
      state.deleteRegion(regionId);
    }
  }
}
