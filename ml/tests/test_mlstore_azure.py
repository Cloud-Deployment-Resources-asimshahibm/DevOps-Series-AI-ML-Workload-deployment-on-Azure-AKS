"""az:// model registry backend, exercised against an in-memory fake Blob container
(no Azure account or network needed)."""

import io
import json

import pytest

import mlstore
from mlstore import ModelStore, read_json_uri, split_az, write_json_uri


class FakeDownload:
    def __init__(self, data: bytes) -> None:
        self._data = data

    def readall(self) -> bytes:
        return self._data

    def readinto(self, fh) -> int:
        fh.write(self._data)
        return len(self._data)


class FakeBlobClient:
    def __init__(self, blobs: dict, name: str) -> None:
        self._blobs, self._name = blobs, name

    def exists(self) -> bool:
        return self._name in self._blobs


class FakeContainer:
    def __init__(self) -> None:
        self.blobs: dict[str, bytes] = {}

    def upload_blob(self, name, data, overwrite=False, **_kwargs):
        if not overwrite and name in self.blobs:
            raise FileExistsError(name)
        self.blobs[name] = data.read() if hasattr(data, "read") else bytes(data)

    def download_blob(self, name):
        if name not in self.blobs:
            raise FileNotFoundError(name)
        return FakeDownload(self.blobs[name])

    def get_blob_client(self, name):
        return FakeBlobClient(self.blobs, name)


@pytest.fixture
def fake_blob(monkeypatch):
    containers: dict[tuple[str, str], FakeContainer] = {}

    def _container(account, container):
        return containers.setdefault((account, container), FakeContainer())

    monkeypatch.setattr(mlstore, "_container", _container)
    pytest.importorskip("azure.storage.blob")  # ContentSettings used by write_json_uri
    return containers


def test_split_az():
    assert split_az("az://acct/models") == ("acct", "models", "")
    assert split_az("az://acct/artifacts/tuning/x/best.json") == ("acct", "artifacts", "tuning/x/best.json")
    for bad in ("s3://bucket/key", "az://acct", "az:///models"):
        with pytest.raises(ValueError):
            split_az(bad)


def test_json_roundtrip(fake_blob):
    uri = "az://acct/artifacts/tuning/uid/best_params.json"
    write_json_uri(uri, {"best_params": {"max_depth": 4}})
    assert read_json_uri(uri) == {"best_params": {"max_depth": 4}}
    assert "tuning/uid/best_params.json" in fake_blob[("acct", "artifacts")].blobs


def test_registry_promote_and_files(fake_blob, tmp_path):
    store = ModelStore("az://acct/models/")
    assert not store.exists("m", "latest.json")

    artifact = tmp_path / "model.joblib"
    artifact.write_bytes(b"model-bytes")
    assert store.put_file(artifact, "m", "v1", "model.joblib") == "az://acct/models/m/v1/model.joblib"
    store.put_json({"metrics": {"accuracy": 0.97}}, "m", "v1", "metadata.json")

    assert store.promote("m", "v1") == {"version": "v1", "previous": None}
    assert store.promote("m", "v2") == {"version": "v2", "previous": "v1"}
    assert store.resolve("m") == "v2"
    assert store.resolve("m", "v1") == "v1"

    out = store.get_file(tmp_path / "dl" / "model.joblib", "m", "v1", "model.joblib")
    assert out.read_bytes() == b"model-bytes"
    assert store.get_json("m", "v1", "metadata.json")["metrics"]["accuracy"] == 0.97


def test_prefix_inside_container(fake_blob):
    store = ModelStore("az://acct/data/registry")
    store.put_json({"version": "v1", "previous": None}, "m", "latest.json")
    blobs = fake_blob[("acct", "data")].blobs
    assert json.loads(blobs["registry/m/latest.json"]) == {"version": "v1", "previous": None}


def test_dataset_csv_from_blob(fake_blob):
    from trainer.data import load_dataset

    csv = "sepal_length,sepal_width,petal_length,petal_width,species\n5.1,3.5,1.4,0.2,setosa\n6.7,3.0,5.2,2.3,virginica\n"
    fake_blob.setdefault(("acct", "data"), FakeContainer()).upload_blob("datasets/iris.csv", io.BytesIO(csv.encode()))
    ds = load_dataset("az://acct/data/datasets/iris.csv")
    assert ds.class_names == ["setosa", "virginica"]
    assert ds.X.shape == (2, 4)
