import uuid
import pytest
from app.db.models import APIKeyModel, ClusterNode


class TestAPIKeyModel:
    def test_create_api_key(self, db_session):
        key_str = uuid.uuid4().hex
        api_key = APIKeyModel(key=key_str, note="测试密钥")
        db_session.add(api_key)
        db_session.commit()

        saved = db_session.query(APIKeyModel).filter_by(key=key_str).first()
        assert saved is not None
        assert saved.key == key_str
        assert saved.note == "测试密钥"
        assert saved.id is not None

    def test_unique_key_constraint(self, db_session):
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str))
        db_session.commit()

        dup = APIKeyModel(key=key_str)
        db_session.add(dup)
        with pytest.raises(Exception):
            db_session.commit()

    def test_delete_api_key(self, db_session):
        key_str = uuid.uuid4().hex
        api_key = APIKeyModel(key=key_str, note="待删除")
        db_session.add(api_key)
        db_session.commit()

        db_session.delete(api_key)
        db_session.commit()

        found = db_session.query(APIKeyModel).filter_by(key=key_str).first()
        assert found is None

    def test_note_can_be_null(self, db_session):
        key_str = uuid.uuid4().hex
        api_key = APIKeyModel(key=key_str)
        db_session.add(api_key)
        db_session.commit()

        saved = db_session.query(APIKeyModel).filter_by(key=key_str).first()
        assert saved.note is None


class TestClusterNode:
    def test_create_node(self, db_session):
        node = ClusterNode(
            name="node-1",
            base_url="http://example.com:8000",
            admin_user="admin",
            admin_pass="pass123",
        )
        db_session.add(node)
        db_session.commit()

        saved = db_session.query(ClusterNode).filter_by(name="node-1").first()
        assert saved is not None
        assert saved.base_url == "http://example.com:8000"
        assert saved.id is not None

    def test_unique_name_constraint(self, db_session):
        db_session.add(
            ClusterNode(
                name="dup-node",
                base_url="http://a.com",
                admin_user="u",
                admin_pass="p",
            )
        )
        db_session.commit()

        dup = ClusterNode(
            name="dup-node", base_url="http://b.com", admin_user="u", admin_pass="p"
        )
        db_session.add(dup)
        with pytest.raises(Exception):
            db_session.commit()

    def test_delete_node(self, db_session):
        node = ClusterNode(
            name="to-delete", base_url="http://x.com", admin_user="u", admin_pass="p"
        )
        db_session.add(node)
        db_session.commit()

        db_session.delete(node)
        db_session.commit()

        found = db_session.query(ClusterNode).filter_by(name="to-delete").first()
        assert found is None
