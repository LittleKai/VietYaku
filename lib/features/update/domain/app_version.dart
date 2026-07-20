/// Semver rút gọn (major.minor.patch), bỏ qua prefix 'v' và build metadata sau '+'.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  factory AppVersion.parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plusIndex = value.indexOf('+');
    if (plusIndex != -1) {
      value = value.substring(0, plusIndex);
    }
    final parts = value.split('.');
    int partAt(int index) {
      if (index >= parts.length) return 0;
      return int.tryParse(parts[index]) ?? 0;
    }

    return AppVersion(partAt(0), partAt(1), partAt(2));
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}
