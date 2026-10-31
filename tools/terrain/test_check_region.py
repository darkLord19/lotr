import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check_region as cr  # noqa: E402


def test_itinerary_pois_reachable() -> None:
    region = cr.load_region()
    assert cr.check(region, cr.itinerary_pois()) == []


def test_walk_time_bag_end_to_pony() -> None:
    assert cr.MIN_MINUTES <= cr.walk_minutes(cr.load_region()) <= cr.MAX_MINUTES


def test_unreachable_poi_detected() -> None:
    region = cr.load_region()
    region["road_graph"]["edges"] = [e for e in region["road_graph"]["edges"] if "bree_hill" not in e[:2]]
    errs = cr.check(region, {"bree_hill": {"x"}})
    assert any("unreachable" in e for e in errs)


def test_every_settlement_has_faction() -> None:
    region = cr.load_region()
    assert {s["faction"] for s in region["settlements"]} == {"shire", "buckland", "bree"}
