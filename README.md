Lens Format v4.0.1
Lens Format is a high-performance binary serialization format for Python, optimized for maximum speed and minimal memory allocation. By leveraging Cython and aggressive C-level optimizations, it achieves performance levels far beyond traditional formats like JSON or Pickle.

Key Features
Extreme Performance: Implemented in Cython with aggressive compiler directives for minimal overhead.

Frame Pooling: Uses a static C-array for decoding frames to minimize Garbage Collector pressure during nested object parsing.

Zero-Copy Support: Allows slicing of byte data without memory copying operations.

Compactness: Employs Varints and ZigZag encoding for efficient integer storage.

Extensible: Supports custom extension handlers for specialized data types.

Native Type Support: Full support for datetime (UTC-optimized), set, tuple, list, dict, and bytes.

Installation
Lens Format provides pre-compiled wheels for most major platforms.

Bash
pip install lens_format==4.0.1
Quickstart
Basic Usage

Python
import lens_format
from datetime import datetime

# Symbols (keys) to be efficiently referenced in the format
symbols = ["id", "name", "timestamp", "active"]

data = {
    "id": 12345,
    "name": "Lens User",
    "timestamp": datetime.now(),
    "active": True,
    "tags": {"python", "cython", "fast"}
}

# Encoding
encoded = lens_format.encode(data, symbols=symbols)

# Decoding
decoded = lens_format.decode(encoded, symbols=symbols)

print(decoded == data)  # True
Zero-Copy & Extension Handling

For maximum efficiency with large binary payloads, you can enable zero-copy mode:

Python
# Data is returned as memoryview slices, not copied
decoded = lens_format.decode(encoded, symbols=symbols, zero_copy=True)
Technical Design
Lens Format utilizes a tag-based system with the following optimizations:

ZigZag Varints: Efficiently encodes both small and negative integers.

Symbol Mapping: Strings used as keys are referenced via a symbol table, eliminating redundancy in the payload.

Big-Endian Floats: Ensures portability through enforced byte-order at the C-level.

C-Level Stack: The decoder uses a hybrid stack (C-array + Python fallback) to handle recursion without massive overhead.
