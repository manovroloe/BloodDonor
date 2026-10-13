"""Normal startup: never installs, upgrades, or downloads dependencies."""
from __future__ import annotations
import logging
import sys

def main() -> int:
    try:
        import uvicorn
        from server.core.config import Settings, ConfigurationError
        settings = Settings.from_env()
    except ImportError:
        print("BloodCare dependencies are missing. Run setup.bat (Windows) or ./setup.sh (macOS/Linux) once.", file=sys.stderr)
        return 1
    except (ValueError, OSError) as exc:
        print(f"BloodCare configuration error: {exc}", file=sys.stderr)
        return 1
    logging.basicConfig(level=settings.log_level.upper(), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.info("Starting BloodCare %s at %s:%s", settings.environment, settings.host, settings.port)
    # ASGI import string enables managed worker startup. Do not use reload in production.
    uvicorn.run("server.main:app", host=settings.host, port=settings.port, workers=settings.workers, reload=False, log_level=settings.log_level, access_log=False, proxy_headers=bool(settings.forwarded_allow_ips), forwarded_allow_ips=settings.forwarded_allow_ips, server_header=False)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
