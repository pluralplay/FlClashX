import 'dart:convert';
import 'dart:io';

import 'git.dart';
import 'models.dart';
import 'parser.dart';
import 'render.dart';

/// The upstream release the fork sits on; versions up to it are not ours.
const frozenBoundaryTag = 'v0.9.2';

const changelogDataPath = 'changelog.json';

const changelogMarkdownPath = 'CHANGELOG.md';

class PendingVersion {
  const PendingVersion({
    required this.version,
    required this.date,
    this.prerelease = false,
  });

  final String version;
  final String date;
  final bool prerelease;

  String get tag => 'v$version';
}

class ChangelogBuildResult {
  const ChangelogBuildResult({
    required this.changelog,
    required this.warnings,
    this.commitIdsByTag = const <String, Set<String>>{},
  });

  final Changelog changelog;
  final List<String> warnings;

  /// Short hashes of every commit that fed each version, including the ones
  /// that produced no entry. `verify` uses it to allow hand written entries as
  /// long as they point at a commit that really is in the version's range.
  final Map<String, Set<String>> commitIdsByTag;
}

class ChangelogBuilder {
  ChangelogBuilder(this.git, {this.boundary = frozenBoundaryTag});

  final Git git;
  final String boundary;

  ChangelogBuildResult build({PendingVersion? pending}) {
    final boundaryTag = VersionTag.tryParse(boundary);
    // Fork releases are numbered below upstream's, so compare by history.
    final stable = boundaryTag != null && git.tagExists(boundaryTag.name)
        ? git.stableTags(notMergedInto: boundaryTag.name)
        : git
              .stableTags()
              .where(
                (tag) => boundaryTag == null || tag.compareTo(boundaryTag) > 0,
              )
              .toList();
    final parser = ChangelogParser();
    final versions = <ChangelogVersion>[];
    final commitIdsByTag = <String, Set<String>>{};

    final boundaryRef = _boundaryRef(boundaryTag);
    if (pending != null && !git.tagExists(pending.tag)) {
      final commits = git.commits(
        from: stable.isEmpty ? boundaryRef : stable.first.name,
        to: 'HEAD',
      );
      commitIdsByTag[pending.tag] = _idsOf(commits);
      versions.add(
        ChangelogVersion(
          version: pending.version,
          tag: pending.tag,
          date: pending.date,
          prerelease: pending.prerelease,
          groups: groupItems(parser.parseAll(commits)),
        ),
      );
    }

    for (var index = 0; index < stable.length; index++) {
      final tag = stable[index];
      final previous = index + 1 < stable.length
          ? stable[index + 1].name
          : boundaryRef;
      final commits = git.commits(from: previous, to: tag.name);
      commitIdsByTag[tag.name] = _idsOf(commits);
      versions.add(
        ChangelogVersion(
          version: tag.version,
          tag: tag.name,
          date: git.tagDate(tag.name),
          groups: groupItems(parser.parseAll(commits)),
        ),
      );
    }

    return ChangelogBuildResult(
      changelog: Changelog(versions: versions),
      warnings: parser.warnings,
      commitIdsByTag: commitIdsByTag,
    );
  }

  String? _boundaryRef(VersionTag? tag) {
    if (tag == null) return null;
    if (git.tagExists(tag.name)) return tag.name;
    return git.latestReleaseCommit();
  }

  Set<String> _idsOf(List<RawCommit> commits) =>
      commits.map((commit) => commit.shortHash).toSet();
}

/// [built], keeping the entries [written] holds so a rebuild keeps wording.
Changelog keepWrittenEntries(Changelog built, Changelog written) {
  final writtenByTag = {
    for (final version in written.versions) version.tag: version,
  };
  return Changelog(
    versions: [
      for (final version in built.versions)
        switch (writtenByTag[version.tag]) {
          final kept? => _withWrittenEntries(version, kept),
          null => version,
        },
    ],
  );
}

ChangelogVersion _withWrittenEntries(
  ChangelogVersion built,
  ChangelogVersion written,
) {
  final known = {
    for (final group in written.groups)
      for (final entry in group.entries) '${group.type.id}:${entry.id}',
  };
  List<ChangelogEntry> entriesOf(
    ChangelogVersion version,
    ChangelogType type,
  ) => [
    for (final group in version.groups)
      if (group.type == type) ...group.entries,
  ];
  return ChangelogVersion(
    version: built.version,
    tag: built.tag,
    date: built.date,
    prerelease: built.prerelease,
    groups: [
      for (final type in ChangelogType.values)
        if ([
              ...entriesOf(written, type),
              for (final entry in entriesOf(built, type))
                if (!known.contains('${type.id}:${entry.id}')) entry,
            ]
            case final entries when entries.isNotEmpty)
          ChangelogGroup(type: type, entries: entries),
    ],
  );
}

final _frozenComment = RegExp(r'\s*<!--.*?-->', dotAll: true);

/// End of the generated head: the frozen marker plus whatever comment lines
/// follow it. Matching comments by shape rather than by text means the note can
/// be reworded without stranding the previous wording in the frozen tail.
int _frozenBoundary(String content) {
  final markerIndex = content.indexOf(changelogFrozenMarker);
  if (markerIndex < 0) {
    return -1;
  }
  var cursor = markerIndex + changelogFrozenMarker.length;
  while (true) {
    final match = _frozenComment.matchAsPrefix(content, cursor);
    if (match == null) {
      return cursor;
    }
    cursor = match.end;
  }
}

String mergeMarkdown(String rendered, String existing) {
  final boundary = _frozenBoundary(existing);
  if (boundary < 0) {
    var tail = existing.trimLeft();
    if (tail.startsWith(changelogTitle)) {
      tail = tail.substring(changelogTitle.length).trimLeft();
    }
    return '$rendered$tail';
  }
  return '$rendered${existing.substring(boundary).trimLeft()}';
}

String markdownHead(String content) {
  final boundary = _frozenBoundary(content);
  return boundary < 0 ? content : content.substring(0, boundary);
}

/// Tags [derived] has a version for that [recorded] never wrote down.
///
/// This is what catches a release tagged without running `release` first. The
/// entry-by-entry checks in `verify` only look at versions both sides have, so
/// a version missing from `changelog.json` outright would otherwise pass and
/// only surface at the end of the release, when `render` finds no notes for the
/// tag being published.
List<String> missingReleaseTags(Changelog recorded, Changelog derived) {
  final known = <String>{for (final version in recorded.versions) version.tag};
  return <String>[
    for (final version in derived.versions)
      if (!known.contains(version.tag)) version.tag,
  ];
}

String encodeChangelog(Changelog changelog) =>
    '${const JsonEncoder.withIndent('  ').convert(changelog.toJson())}\n';

Changelog decodeChangelog(String source) =>
    Changelog.fromJson(jsonDecode(source) as Map<String, dynamic>);

String readPubspecVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('No version found in pubspec.yaml');
  }
  return match.group(1)!;
}

String today() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

File resolve(String root, String path) {
  final separator = Platform.pathSeparator;
  if (path.startsWith(separator) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return File(path);
  }
  return File('$root$separator$path');
}
