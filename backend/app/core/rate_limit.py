"""Small in-memory sliding-window rate limiter.

Per Cloud Run instance only (max 2 instances), which is enough to stop the
unauthenticated failed-login endpoint (D-27) from being used to flood audit_logs.
"""

import time
from collections import defaultdict, deque
from threading import Lock


class RateLimiter:
    def __init__(self, max_events: int, window_seconds: float = 60.0) -> None:
        self._max = max_events
        self._window = window_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def allow(self, key: str, now: float | None = None) -> bool:
        t = time.monotonic() if now is None else now
        with self._lock:
            q = self._events[key]
            while q and t - q[0] >= self._window:
                q.popleft()
            if len(q) >= self._max:
                return False
            q.append(t)
            return True
