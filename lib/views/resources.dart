import 'dart:io';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' hide context;

@immutable
class GeoItem {

  const GeoItem({
    required this.label,
    required this.key,
    required this.fileName,
    required this.geoType,
  });
  final String label;
  final String key;
  final String fileName;
  final String geoType;
}

class ResourcesView extends ConsumerStatefulWidget {
  const ResourcesView({super.key});

  @override
  ConsumerState<ResourcesView> createState() => _ResourcesViewState();
}

class _ResourcesViewState extends ConsumerState<ResourcesView> {
  bool _isUpdatingAll = false;
  String? _currentlyUpdating;
  final Set<String> _individuallyUpdating = {};

  void _setFileUpdating(String fileName, bool isUpdating) {
    setState(() {
      if (isUpdating) {
        _individuallyUpdating.add(fileName);
      } else {
        _individuallyUpdating.remove(fileName);
      }
    });
  }

  Future<void> _updateAllGeoFiles() async {
    if (_isUpdatingAll || _individuallyUpdating.isNotEmpty) return;

    setState(() {
      _isUpdatingAll = true;
    });

    try {
      setState(() => _currentlyUpdating = "GeoIP.dat");
      try {
        final result1 = await clashCore.updateGeoData(const UpdateGeoDataParams(geoType: "GeoIp", geoName: "GeoIP.dat"));
        if (result1.isNotEmpty) {
          throw Exception("GeoIP.dat: $result1");
        }
      } catch (e) {
        commonPrint.log("Failed to update GeoIP.dat: $e");
      }
      
      setState(() => _currentlyUpdating = "geoip.metadb");
      try {
        final result2 = await clashCore.updateGeoData(const UpdateGeoDataParams(geoType: "MMDB", geoName: "geoip.metadb"));
        if (result2.isNotEmpty) {
          throw Exception("geoip.metadb: $result2");
        }
      } catch (e) {
        commonPrint.log("Failed to update geoip.metadb: $e");
      }
      
      setState(() => _currentlyUpdating = "GeoSite.dat");
      try {
        final result3 = await clashCore.updateGeoData(const UpdateGeoDataParams(geoType: "GeoSite", geoName: "GeoSite.dat"));
        if (result3.isNotEmpty) {
          throw Exception("GeoSite.dat: $result3");
        }
      } catch (e) {
        commonPrint.log("Failed to update GeoSite.dat: $e");
      }
      
      setState(() => _currentlyUpdating = "ASN.mmdb");
      try {
        final result4 = await clashCore.updateGeoData(const UpdateGeoDataParams(geoType: "ASN", geoName: "ASN.mmdb"));
        if (result4.isNotEmpty) {
          throw Exception("ASN.mmdb: $result4");
        }
      } catch (e) {
        commonPrint.log("Failed to update ASN.mmdb: $e");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingAll = false;
          _currentlyUpdating = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const geoItems = <GeoItem>[
      GeoItem(
        label: "GeoIp",
        fileName: geoIpFileName,
        key: "geoip",
        geoType: "GeoIp",
      ),
      GeoItem(
        label: "GeoSite",
        fileName: geoSiteFileName,
        key: "geosite",
        geoType: "GeoSite",
      ),
      GeoItem(
        label: "MMDB",
        fileName: mmdbFileName,
        key: "mmdb",
        geoType: "MMDB",
      ),
      GeoItem(
        label: "ASN",
        fileName: asnFileName,
        key: "asn",
        geoType: "ASN",
      ),
    ];

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemBuilder: (_, index) {
              final geoItem = geoItems[index];
              return GeoDataListItem(
                geoItem: geoItem,
                isGlobalUpdating: _isUpdatingAll,
                currentlyUpdatingFile: _currentlyUpdating,
                onUpdateStatusChanged: _setFileUpdating,
              );
            },
            separatorBuilder: (context, index) => const Divider(
                height: 0,
              ),
            itemCount: geoItems.length,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Builder(
                builder: (context) => FilledButton.icon(
                    icon: _isUpdatingAll
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.sync),
                    label: Text(AppLocalizations.of(context).updateAllGeoData),
                    onPressed: (_isUpdatingAll || _individuallyUpdating.isNotEmpty)
                        ? null
                        : () async {
                            await globalState.safeRun(_updateAllGeoFiles);
                          },
                  ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GeoDataListItem extends StatefulWidget {

  const GeoDataListItem({
    super.key,
    required this.geoItem,
    required this.isGlobalUpdating,
    this.currentlyUpdatingFile,
    required this.onUpdateStatusChanged,
  });
  final GeoItem geoItem;
  final bool isGlobalUpdating;
  final String? currentlyUpdatingFile;
  final void Function(String fileName, bool isUpdating) onUpdateStatusChanged;

  @override
  State<GeoDataListItem> createState() => _GeoDataListItemState();
}

class _GeoDataListItemState extends State<GeoDataListItem> {
  GeoItem get geoItem => widget.geoItem;
  bool _isUpdating = false;

  Future<FileInfo> _getGeoFileLastModified(String fileName) async {
    final homePath = await appPath.homeDirPath;
    final file = File(join(homePath, fileName));
    final lastModified = await file.lastModified();
    final size = await file.length();
    return FileInfo(
      size: size,
      lastModified: lastModified,
    );
  }

  Future<void> _updateGeoFile() async {
    if (_isUpdating) return;
    
    setState(() {
      _isUpdating = true;
    });
    widget.onUpdateStatusChanged(geoItem.fileName, true);

    try {
      final result = await clashCore.updateGeoData(
        UpdateGeoDataParams(
          geoType: geoItem.geoType,
          geoName: geoItem.fileName,
        ),
      );
      
      if (result.isNotEmpty) {
        if (mounted) {
          globalState.showMessage(
            title: appLocalizations.errorTitle,
            message: TextSpan(text: result),
          );
        }
      } else {
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        globalState.showMessage(
          title: appLocalizations.errorTitle,
          message: TextSpan(text: e.toString()),
        );
      }
    } finally {
      widget.onUpdateStatusChanged(geoItem.fileName, false);
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<String?> _getActiveGeoUrl(WidgetRef ref) async {
    try {
      final currentProfileId = ref.watch(currentProfileIdProvider);
      if (currentProfileId != null) {
        final profileConfig = await globalState.getProfileConfig(currentProfileId);
        final geoXUrl = profileConfig["geox-url"];
        if (geoXUrl != null && geoXUrl is Map) {
          if (geoItem.key == 'geoip') {
            return geoXUrl['geoip'] ?? geoXUrl['geo-ip'];
          } else if (geoItem.key == 'geosite') {
            return geoXUrl['geosite'] ?? geoXUrl['geo-site'];
          } else {
            return geoXUrl[geoItem.key];
          }
        }
      }
    } catch (e) {
    }
    
    return ref.read(patchClashConfigProvider.select((state) => state.geoXUrl.toJson()[geoItem.key]));
  }

  Widget _buildSubtitle() => Consumer(
      builder: (_, ref, __) => FutureBuilder<String?>(
          future: _getActiveGeoUrl(ref),
          builder: (context, urlSnapshot) {
            final url = urlSnapshot.data;
            
            if (url == null) {
              return const SizedBox();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  height: 4,
                ),
                FutureBuilder<FileInfo>(
                  future: _getGeoFileLastModified(geoItem.fileName),
                  builder: (_, snapshot) {
                final height = globalState.measure.bodyMediumHeight;
                return SizedBox(
                  height: height,
                  child: snapshot.data == null
                      ? SizedBox(
                          width: height,
                          height: height,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          snapshot.data!.desc,
                          style: context.textTheme.bodyMedium,
                        ),
                    );
                  },
                ),
                Text(
                  url,
                  style: context.textTheme.bodyMedium?.toLight,
                ),
              ],
            );
          },
        ),
    );



  @override
  Widget build(BuildContext context) {
    final isThisFileUpdating = widget.isGlobalUpdating && 
                                widget.currentlyUpdatingFile == geoItem.fileName;
    final isDisabled = widget.isGlobalUpdating || _isUpdating;
    
    return ListItem(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      title: Text(geoItem.label),
      subtitle: _buildSubtitle(),
      trailing: (_isUpdating || isThisFileUpdating)
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          : IconButton(
              icon: const Icon(Icons.sync),
              tooltip: appLocalizations.update,
              onPressed: isDisabled ? null : _updateGeoFile,
            ),
    );
  }
}

class UpdateGeoUrlFormDialog extends StatefulWidget {

  const UpdateGeoUrlFormDialog(
      {super.key, required this.title, required this.url, this.defaultValue});
  final String title;
  final String url;
  final String? defaultValue;

  @override
  State<UpdateGeoUrlFormDialog> createState() => _UpdateGeoUrlFormDialogState();
}

class _UpdateGeoUrlFormDialogState extends State<UpdateGeoUrlFormDialog> {
  late TextEditingController urlController;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(text: widget.url);
  }

  Future<void> _handleReset() async {
    if (widget.defaultValue == null) {
      return;
    }
    Navigator.of(context).pop<String>(widget.defaultValue);
  }

  Future<void> _handleUpdate() async {
    final url = urlController.value.text;
    if (url.isEmpty) return;
    Navigator.of(context).pop<String>(url);
  }

  @override
  Widget build(BuildContext context) => CommonDialog(
      title: widget.title,
      actions: [
        if (widget.defaultValue != null &&
            urlController.value.text != widget.defaultValue) ...[
          TextButton(
            onPressed: _handleReset,
            child: Text(appLocalizations.reset),
          ),
          const SizedBox(
            width: 4,
          ),
        ],
        TextButton(
          onPressed: _handleUpdate,
          child: Text(appLocalizations.submit),
        )
      ],
      child: Wrap(
        runSpacing: 16,
        children: [
          TextField(
            maxLines: 5,
            minLines: 1,
            controller: urlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
}
