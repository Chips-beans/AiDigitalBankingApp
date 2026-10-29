abstract interface class PreferencesStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryPreferencesStore implements PreferencesStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
