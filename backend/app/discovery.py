from __future__ import annotations

import socket
from typing import Optional, Tuple

try:
    from zeroconf import ServiceInfo, Zeroconf
except Exception:  # pragma: no cover - optional dependency
    ServiceInfo = None
    Zeroconf = None


ServiceHandle = Optional[Tuple["Zeroconf", "ServiceInfo"]]


def _local_ip() -> str:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        try:
            sock.close()
        except Exception:
            pass
    return ip


def start_discovery(port: int) -> ServiceHandle:
    if Zeroconf is None or ServiceInfo is None:
        return None
    ip = _local_ip()
    hostname = socket.gethostname().split(".")[0]
    service_type = "_guttertheory._tcp.local."
    name = f"guttertheory-backend-{hostname}.{service_type}"
    info = ServiceInfo(
        service_type,
        name,
        addresses=[socket.inet_aton(ip)],
        port=port,
        properties={"app": "guttertheory"},
    )
    zeroconf = Zeroconf()
    try:
        zeroconf.register_service(info)
    except Exception:
        try:
            zeroconf.close()
        except Exception:
            pass
        return None
    return zeroconf, info


def stop_discovery(handle: ServiceHandle) -> None:
    if not handle:
        return
    zeroconf, info = handle
    try:
        zeroconf.unregister_service(info)
    except Exception:
        pass
    try:
        zeroconf.close()
    except Exception:
        pass
