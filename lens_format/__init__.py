"""
Lens Protocol - High Performance Binary Serialization
Version: v4.0.1
Features: Aggressive Frame-Pooling, Zero-Copy EXT, UTC-Optimized, C-Stack-Logic
"""

import sys

__version__ = "4.0.1"

try:
    from .core import (
        FastEncoder,
        FastDecoder,
        LensError,
        LensDecodeError,
        LensEncodeError
    )
except ImportError:
    # During the build process, the C-extension is not yet available.
    # We pass silently so setup.py can finish the build.
    pass

def dumps(obj, symbols, ext_handler=None):
    encoder = FastEncoder(symbols, ext_handler=ext_handler)
    return encoder.encode(obj)

def loads(data, symbols, zero_copy=False, ext_hook=None, ts_hook=None):
    decoder = FastDecoder(
        data, 
        symbols, 
        zero_copy=zero_copy, 
        ext_hook=ext_hook, 
        ts_hook=ts_hook
    )
    return decoder.decode_all()

def set_debug(enabled: bool):
    try:
        from . import core
        core.DEBUG = enabled
    except ImportError:
        pass

__all__ = [
    "dumps", 
    "loads", 
    "FastEncoder", 
    "FastDecoder", 
    "LensError", 
    "LensDecodeError", 
    "LensEncodeError",
    "set_debug",
    "__version__"
]
