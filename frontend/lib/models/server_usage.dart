class ServerUsage {
  final double cpuPercent;
  final int cpuCount;
  final double memoryPercent;
  final int memoryTotal;
  final int memoryUsed;
  final List<DiskUsage> disks;
  final List<GpuUsage> gpus;

  ServerUsage({
    required this.cpuPercent,
    required this.cpuCount,
    required this.memoryPercent,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.disks,
    required this.gpus,
  });

  factory ServerUsage.fromJson(Map<String, dynamic> json) {
    final cpu = json['cpu'] ?? {};
    final memory = json['memory'] ?? {};
    final diskList = json['disk'] as List? ?? [];
    final gpuList = json['gpu'] as List? ?? [];

    return ServerUsage(
      cpuPercent: (cpu['percent'] ?? 0).toDouble(),
      cpuCount: (cpu['count'] ?? 0).toInt(),
      memoryPercent: (memory['percent'] ?? 0).toDouble(),
      memoryTotal: (memory['total'] ?? 0).toInt(),
      memoryUsed: (memory['used'] ?? 0).toInt(),
      disks: diskList.map((d) => DiskUsage.fromJson(d)).toList(),
      gpus: gpuList.map((g) => GpuUsage.fromJson(g)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cpu': {
        'percent': cpuPercent,
        'count': cpuCount,
      },
      'memory': {
        'percent': memoryPercent,
        'total': memoryTotal,
        'used': memoryUsed,
      },
      'disk': disks.map((d) => d.toJson()).toList(),
      'gpu': gpus.map((g) => g.toJson()).toList(),
    };
  }
}

class DiskUsage {
  final String device;
  final String mountpoint;
  final double percent;
  final int total;
  final int used;
  final int free;

  DiskUsage({
    required this.device,
    required this.mountpoint,
    required this.percent,
    required this.total,
    required this.used,
    required this.free,
  });

  factory DiskUsage.fromJson(Map<String, dynamic> json) {
    return DiskUsage(
      device: json['device'] ?? '',
      mountpoint: json['mountpoint'] ?? '',
      percent: (json['percent'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toInt(),
      used: (json['used'] ?? 0).toInt(),
      free: (json['free'] ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device': device,
      'mountpoint': mountpoint,
      'percent': percent,
      'total': total,
      'used': used,
      'free': free,
    };
  }
}

class GpuUsage {
  final int id;
  final String name;
  final double load;
  final double memoryTotal;
  final double memoryUsed;
  final double temperature;

  GpuUsage({
    required this.id,
    required this.name,
    required this.load,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.temperature,
  });

  factory GpuUsage.fromJson(Map<String, dynamic> json) {
    return GpuUsage(
      id: (json['id'] ?? 0).toInt(),
      name: json['name'] ?? '',
      load: (json['load'] ?? 0).toDouble(),
      memoryTotal: (json['memory_total'] ?? 0).toDouble(),
      memoryUsed: (json['memory_used'] ?? 0).toDouble(),
      temperature: (json['temperature'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'load': load,
      'memory_total': memoryTotal,
      'memory_used': memoryUsed,
      'temperature': temperature,
    };
  }
}
