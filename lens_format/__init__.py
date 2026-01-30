"""
Lens Protocol - High Performance Binary Serialization
Version: v4.0.0
Features: Aggressive Frame-Pooling, Zero-Copy EXT, UTC-Optimized, C-Stack-Logic
"""

import sys

# Import C-extension classes
try:
    from .core import (
        FastEncoder,
        FastDecoder,
        LensError,
        LensDecodeError,
        LensEncodeError
    )
except ImportError as e:
    raise ImportError(
        f"Failed to import the Lens C-extension. Ensure it is compiled correctly. "
        f"Original error: {e}"
    )

__version__ = "4.0.0"

def dumps(obj, symbols, ext_handler=None):
    """
    Serializes a Python object into the Lens binary format.
    
    :param obj: Object to serialize.
    :param symbols: List of strings used for T_SYMREF keys.
    :param ext_handler: Optional hook function(obj) -> (ext_id, bytes).
    :return: bytes - The binary data.
    """
    encoder = FastEncoder(symbols, ext_handler=ext_handler)
    return encoder.encode(obj)

def loads(data, symbols, zero_copy=False, ext_hook=None, ts_hook=None):
    """
    Deserializes Lens binary data back into Python objects.
    
    :param data: bytes or memoryview of the source.
    :param symbols: List of strings for key resolution.
    :param zero_copy: If True, returns memoryview slices for T_BYTES and T_EXT.
    :param ext_hook: Hook for T_EXT tags: func(ext_id, payload_view).
    :param ts_hook: Optional hook for custom timestamp objects: func(milliseconds).
    :return: Python object (dict, list, etc.)
    """
    decoder = FastDecoder(
        data, 
        symbols, 
        zero_copy=zero_copy, 
        ext_hook=ext_hook, 
        ts_hook=ts_hook
    )
    return decoder.decode_all()

def set_debug(enabled: bool):
    """
    Enables extended debug mode in the C-extension.
    Note: Requires DEBUG flag support in core.pyx.
    """
    from . import core
    core.DEBUG = enabled

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
