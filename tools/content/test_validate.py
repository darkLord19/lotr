"""Each bad fixture under game/tests/fixtures/content_bad/<case>/ is a tiny content root plus expected.txt."""
from __future__ import annotations

import datetime as dt
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import validate  # noqa: E402

FIXTURES = validate.REPO / "game" / "tests" / "fixtures" / "content_bad"
CASES = sorted(p for p in FIXTURES.iterdir() if p.is_dir())


def test_fixtures_exist() -> None:
    assert len(CASES) >= 15


@pytest.mark.parametrize("case", CASES, ids=lambda p: p.name)
def test_bad_fixture(case: Path) -> None:
    expected = (case / "expected.txt").read_text().strip()
    rep = validate.validate(case)
    assert rep.errors, f"{case.name}: no error reported"
    assert any(expected in e for e in rep.errors), f"{case.name}: wanted '{expected}' in {rep.errors}"


def test_cli_exit_codes(tmp_path: Path) -> None:
    py = sys.executable
    script = str(Path(validate.__file__))
    bad = subprocess.run([py, script, "--root", str(CASES[0])], capture_output=True, text=True)
    assert bad.returncode != 0 and "CONTENT_OK" not in bad.stdout
    good = subprocess.run([py, script], capture_output=True, text=True)
    assert good.returncode == 0 and "CONTENT_OK" in good.stdout, good.stdout


def test_real_content_ok() -> None:
    assert validate.validate().errors == []


def test_missing_portrait_and_verify_flag_are_fine(tmp_path: Path) -> None:
    root = tmp_path / "content"
    shutil.copytree(validate.DEFAULT_ROOT, root)
    p = root / "lore_cards" / "characters" / "barliman_butterbur.json"
    card = json.loads(p.read_text())
    card["portrait"] = "res://assets/portraits/definitely_missing.png"
    card["verify"] = True
    p.write_text(json.dumps(card))
    rep = validate.validate(root, validate.DEFAULT_SCHEMAS)
    assert rep.errors == []
    assert any("portrait file missing" in w for w in rep.warnings)


def test_calendar_lookup() -> None:
    cal = json.loads((validate.DEFAULT_ROOT / "calendar.json").read_text())
    f = lambda s: validate.shire_date(validate.parse_date(s), cal)  # noqa: E731
    assert f("3018-09-22") == "Halimath 22, S.R. 1418"
    assert f("3018-09-29T20:00") == "Halimath 29, S.R. 1418"
    assert f("3018-01-01") == "Afteryule 1, S.R. 1418"
    assert f("3018-12-30") == "2 Yule, S.R. 1418"
    assert f("3018-12-31") == "1 Yule, S.R. 1419"
    assert f("3019-01-01") == "Afteryule 1, S.R. 1419"
    assert f("3018-06-30") == "1 Lithe, S.R. 1418"
    assert f("3018-07-01") == "Midyear's Day, S.R. 1418"
    assert f("3018-07-02") == "2 Lithe, S.R. 1418"
    assert f("3018-07-03") == "Afterlithe 1, S.R. 1418"
    assert f("3020-02-29") == "Overlithe, S.R. 1420"
    assert f("3020-03-01").split(",")[0] == f("3018-03-01").split(",")[0]
    # every day of 3019 maps to a name (no gaps) and Dec 31 rolls the year
    d = dt.datetime(3019, 1, 1)
    seen = {validate.shire_date(d + dt.timedelta(days=i), cal) for i in range(365)}
    assert len(seen) == 365
