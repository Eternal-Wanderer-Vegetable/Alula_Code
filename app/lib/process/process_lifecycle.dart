/// Host-side child process registration callbacks backed by the Rust supervisor.
typedef ProcessRegistrar = void Function(
  int pid,
  String kind,
  String label,
  String? workspace,
);

typedef ProcessUnregistrar = void Function(int pid);
