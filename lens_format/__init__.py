"""
Lens Protocol - High Performance Binary Serialization
Version: v4.0.0
Features: Frame-Pooling, Zero-Copy, T_EXT Adapter, Lazy Diagnostics
"""

from .core import (
    FastEncoder, 
    FastDecoder, 
    LensError, 
    LensDecodeError, 
    LensEncodeError
)
import sys

__version__ = "4.0.0"

def dumps(obj, sym_map=None, sym_limit=10000, adapter=None, max_depth=1000):
    """
    Serialisiert ein Python-Objekt in das Lens-Binärformat.
    
    :param obj: Das zu serialisierende Objekt.
    :param sym_map: Dictionary für die Symbol-Wiederverwendung (wird aktualisiert).
    :param sym_limit: Abbruchkriterium für unkontrolliertes Key-Wachstum.
    :param adapter: Hook für Custom-Types. Erwartet (tag_id, bytes) oder serialisierbares Objekt.
    :param max_depth: Maximale Verschachtelungstiefe (Sicherheitsfeature).
    :return: (bytes, dict) - Die Daten und die finale Symbol-Map.
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
    Deserialisiert Lens-Daten hochperformant zurück in Python-Objekte.
    
    :param data: bytes oder memoryview der Quelldaten.
    :param symbols: Liste der Symbole (Strings) zur Auflösung von Keys.
    :param zero_copy: Wenn True, werden Slices der Quelldaten (memoryview) zurückgegeben.
    :param ext_hook: Hook zur Auflösung von T_EXT Tags (tag_id, payload).
    :param ts_hook: Hook für benutzerdefinierte Zeitstempel-Objekte.
    :param max_depth: Schutz gegen Deep-Nesting Angriffe.
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
    Aktiviert den erweiterten Debug-Modus in der C-Extension.
    Erzeugt bei Fehlern einen Pfad-Trace und einen Hex-Dump der Daten.
    """
    try:
        from . import core
        core.DEBUG = enabled
    except ImportError:
        # Fallback für Entwicklungsumgebungen
        if 'core' in sys.modules:
            sys.modules['core'].DEBUG = enabled

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
