#!/usr/bin/env python3
"""Mock Portainer API for Flutter web screenshots."""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class MockHandler(BaseHTTPRequestHandler):
    def _respond(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Methods', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self._respond({})

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/containers/summary':
            self._respond([
                {"Id": "abc123", "Names": ["/nginx"], "Image": "nginx:latest",
                 "State": "running", "Status": "Up 3 days", "Ports": [{"IP": "0.0.0.0", "PublicPort": 80, "PrivatePort": 80}],
                 "Created": 1717000000, "StackName": "web"},
                {"Id": "def456", "Names": ["/redis"], "Image": "redis:7",
                 "State": "running", "Status": "Up 5 days", "Ports": [],
                 "Created": 1716900000, "StackName": ""},
                {"Id": "ghi789", "Names": ["/postgres"], "Image": "postgres:16",
                 "State": "running", "Status": "Up 7 days", "Ports": [{"IP": "0.0.0.0", "PublicPort": 5432, "PrivatePort": 5432}],
                 "Created": 1716800000, "StackName": "db"},
            ])
        elif path == '/images':
            self._respond([
                {"Id": "sha256:abc", "RepoTags": ["nginx:latest"], "Size": 187000000, "Created": 1717000000},
                {"Id": "sha256:def", "RepoTags": ["redis:7"], "Size": 117000000, "Created": 1716900000},
                {"Id": "sha256:ghi", "RepoTags": ["postgres:16"], "Size": 412000000, "Created": 1716800000},
            ])
        elif path == '/networks':
            self._respond([
                {"Name": "bridge", "Id": "net1", "Driver": "bridge", "Scope": "local"},
                {"Name": "host", "Id": "net2", "Driver": "host", "Scope": "local"},
            ])
        elif path == '/volumes':
            self._respond([
                {"Name": "nginx_data", "Driver": "local", "Mountpoint": "/var/lib/docker/volumes/nginx_data"},
                {"Name": "postgres_data", "Driver": "local", "Mountpoint": "/var/lib/docker/volumes/postgres_data"},
            ])
        elif path == '/stacks':
            self._respond([
                {"Name": "web", "Services": 2, "Orchestrator": "swarm"},
                {"Name": "db", "Services": 1, "Orchestrator": "swarm"},
            ])
        elif path == '/usage':
            self._respond({
                "cpu": {"usage": 23.5, "cores": 4},
                "memory": {"used": 8589934592, "total": 17179869184},
                "disk": {"used": 107374182400, "total": 536870912000},
                "network": {"rx_bytes": 1234567890, "tx_bytes": 987654321},
                "gpu": [{"index": 0, "name": "NVIDIA RTX 3060", "temperature": 62,
                          "load": 45, "memory_used": 4294967296, "memory_total": 12884901888}]
            })
        elif path == '/info':
            self._respond({
                "ID": "docker-host-01",
                "Name": "prod-server",
                "Images": 3, "Containers": 3, "ContainersRunning": 3,
                "NCPU": 8, "MemTotal": 17179869184,
                "OperatingSystem": "Ubuntu 24.04 LTS",
                "DockerRootDir": "/var/lib/docker",
            })
        elif path == '/git/version':
            self._respond({"version": "v2.19.4"})
        elif path == '/ports/available':
            self._respond([])
        elif path == '/containers/abc123':
            self._respond({
                "Id": "abc123", "Names": ["/nginx"],
                "Image": "nginx:latest", "State": "running",
                "Status": "Up 3 days", "Created": "2024-05-01T10:00:00Z",
                "Ports": [{"IP": "0.0.0.0", "PublicPort": 80, "PrivatePort": 80, "Type": "tcp"}],
                "HostConfig": {"NetworkMode": "bridge"},
                "NetworkSettings": {"Networks": {"bridge": {"IPAddress": "172.17.0.2"}}},
                "Mounts": [{"Type": "volume", "Source": "nginx_data", "Destination": "/usr/share/nginx/html"}],
                "Config": {"Env": ["PATH=/usr/local/sbin:/usr/local/bin", "NGINX_VERSION=1.25"]},
                "StackName": "web",
            })
        elif path == '/containers/abc123/stats':
            self._respond({"stream": False, "cpu_stats": {}, "memory_stats": {}})
        elif path == '/containers/abc123/logs':
            self._respond(b'2024-06-01T10:00:00Z [notice] nginx started\n2024-06-01T10:00:01Z [info] listening on port 80\n')
        elif path == '/containers/abc123/files':
            self._respond([
                {"name": "nginx.conf", "path": "/etc/nginx/nginx.conf", "is_dir": False, "size": 1024},
                {"name": "html", "path": "/usr/share/nginx/html", "is_dir": True, "size": 0},
            ])
        elif path == '/containers/abc123/inspect':
            self._respond({"Id": "abc123", "Name": "/nginx"})
        elif path.startswith('/stacks/') and path.endswith('/containers'):
            self._respond([
                {"Id": "abc123", "Names": ["/nginx"], "Image": "nginx:latest", "State": "running", "Status": "Up 3 days"}
            ])
        elif path.startswith('/admin/'):
            self._respond({})
        else:
            print(f"Unhandled GET: {path}")
            self._respond({})

    def do_POST(self):
        self._respond({})

    def do_PUT(self):
        self._respond({})

    def do_DELETE(self):
        self._respond({})

    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8000), MockHandler)
    print("Mock Portainer API running on http://localhost:8000")
    server.serve_forever()
