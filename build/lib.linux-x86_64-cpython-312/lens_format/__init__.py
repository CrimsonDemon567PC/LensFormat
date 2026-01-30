"""
Lens Protocol - High Performance Binary Serialization
Version: v4.0.0
Features: Frame-Pooling, Zero-Copy, T_EXT Adapter, Lazy Diagnostics
"""

import sys

# Wir importieren die C-Klassen aus der kompilierten Extension
try:
    from .core import (
        FastEncoder,
        FastDecoder,
        LensError,
        LensDecodeError,
        LensEncodeError
    )
except ImportError as e:
    # Hilfreiche Fehlermeldung, falls die Extension nicht kompiliert wurde
    raise ImportError(
        f"Failed to import the Lens C-extension. Ensure it is compiled correctly. "
        f"Original error: {e}"
    )

__version__ = "4.0.0"

def dumps(obj, sym_map=None, sym_limit=10000, adapter=None, max_depth=1000):
    """
    Serializes a Python object into the Lens binary format.
    
    :param obj: Object to serialize.
    :param sym_map: Dictionary for symbol reuse.
    :param sym_limit: Maximum number of unique keys.
    :param adapter: Hook for custom types (ext_id, bytes).
    :param max_depth: Safety limit for nesting.
    :return: (bytes, dict) - The binary data and final symbol map.
    """
    encoder = FastEncoder(
        sym_map=sym_map, 
        sym_limit=sym_limit, 
        adapter=adapter, 
        max_depth=max_depth
    )
    return encoder.encode_all(obj)

def loads(data, symbols, zero_copy=False, ext_hook=None, ts_hook=None, max_depth=1000):
    """
    Deserializes Lens binary data back into Python objects.
    
    :param data: bytes or memoryview of the source.
    :param symbols: List of strings for key resolution.
    :param zero_copy: If True, returns memoryview slices for strings/bytes.
    :param ext_hook: Hook for T_EXT tags (tag_id, payload).
    :param ts_hook: Hook for custom timestamp objects.
    :param max_depth: Safety limit for nesting.
    """
    decoder = FastDecoder(
        data, 
        symbols, 
        zero_copy=zero_copy, 
        ext_hook=ext_hook, 
        ts_hook=ts_hook, 
        max_depth=max_depth
    )
    return decoder.decode_all()

def set_debug(enabled: bool):
    """
    Enables extended debug mode in the C-extension.
    Provides path-traces and hex-dumps on errors.
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