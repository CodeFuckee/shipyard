import os
import pytest


class TestConfig:
    def test_default_admin_user(self):
        assert os.getenv("ADMIN_USER", "admin") == "admin"

    def test_default_admin_password(self):
        assert os.getenv("ADMIN_PASSWORD", "password") == "password"

    def test_api_key_name(self):
        from app.core.config import API_KEY_NAME

        assert API_KEY_NAME == "X-API-Key"

    def test_ignored_events_default(self):
        from app.core.config import IGNORED_EVENTS

        assert "exec_create" in IGNORED_EVENTS
        assert "exec_start" in IGNORED_EVENTS
        assert "exec_die" in IGNORED_EVENTS

    def test_host_filesystem_root_default(self):
        from app.core.config import HOST_FILESYSTEM_ROOT

        assert HOST_FILESYSTEM_ROOT == "/hostfs"

    def test_docker_socket_path_default(self):
        from app.core.config import DOCKER_SOCKET_PATH

        assert DOCKER_SOCKET_PATH == "/var/run/docker.sock"

    def test_docker_engine_api_enabled_default(self):
        from app.core.config import DOCKER_ENGINE_API_ENABLED

        assert DOCKER_ENGINE_API_ENABLED is True
