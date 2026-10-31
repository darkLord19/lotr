from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable


@dataclass
class Spec:
    name: str
    category: str          # output folder under game/assets/models
    kind: str              # budget class (tree, bush, rock, house, structure, prop, plant)
    seed: int
    fn: Callable           # fn(builder, roles) fills the builder
    lods: bool = True
    params: dict = field(default_factory=dict)
