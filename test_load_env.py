"""Self-check for server.load_env(): run with  python3 test_load_env.py

Covers the behaviour that caused the original "401 invalid_api_key" failure:
the file is re-read when it changes, real environment variables win over the
file, and keys deleted from the file disappear from the process.
"""
import os
import pathlib
import tempfile
import time

import server


def main():
    tmp = pathlib.Path(tempfile.mkdtemp()) / ".env"
    server._ENV_FILE = tmp
    server._ENV.update(mtime=None, keys=set())
    for k in ("T_FILE", "T_REAL"):
        os.environ.pop(k, None)
    os.environ["T_REAL"] = "from-real-env"

    tmp.write_text('T_FILE="one"\nT_REAL=from-file\n# comment\n\n')
    assert server.load_env() is True
    assert os.environ["T_FILE"] == "one", "quoted file value should load"
    assert os.environ["T_REAL"] == "from-real-env", "real environment must win over the file"
    assert server.load_env() is False, "unchanged file must not reload"

    time.sleep(0.01)
    tmp.write_text("T_FILE=two\n")
    os.utime(tmp, None)                      # make sure mtime moves even on coarse filesystems
    assert server.load_env() is True
    assert os.environ["T_FILE"] == "two", "changed value should be picked up without restart"
    assert os.environ["T_REAL"] == "from-real-env", "real env still untouched"

    time.sleep(0.01)
    tmp.write_text("\n")
    os.utime(tmp, None)
    assert server.load_env() is True
    assert "T_FILE" not in os.environ, "key removed from file should be unset"
    print("ok: load_env reloads on change, real env wins, removed keys are unset")


if __name__ == "__main__":
    main()
