## LENS v3.1 – Hardened Reference Implementation
LENS (Lightweight Efficient Network Serialization) is a binary serialization format designed for high performance, type safety, and resilience. This implementation focuses on security hardening to protect against common binary exploitation vectors.

# Features (v3.1)
Efficient Encoding: Uses Varints and ZigZag encoding for compact integer storage.

Symbol Tables: Optimized for objects by storing keys in a centralized table to avoid redundancy.

# Hardened Security:

Zip-Bomb Protection: Decompression is capped at a strict 512 MB limit.

Trailing Garbage Detection: Rejects payloads with extra data after the valid end-of-file.

Recursion Depth Control: Prevents Stack Overflow attacks (max 500 levels).

Integrity Checks: Built-in CRC32 checksum verification for every frame.

Rich Types: Supports null, bool, int, float, string, bytes, datetime (UTC), arrays, and objects.

# Installation
```bash
pip install lens-format
```
# Usage
The library is designed to be a drop-in replacement for logic where JSON might be too bulky or insecure.

Basic API

```python
from lens_format import LensFormat, LensError, LensDecodeError
from datetime import datetime

data = {
    "server": "production-01",
    "uptime": 1234567,
    "active": True,
    "last_sync": datetime.utcnow()
}

try:
    # Encoding to binary
    # Set compress=True to enable zlib compression with safety limits
    binary_payload = LensFormat.encode(data, compress=True)

    # Decoding back to Python objects
    parsed_data = LensFormat.decode(binary_payload)
    print(f"Server: {parsed_data['server']}")
    
except LensDecodeError as e:
    print(f"Validation or decoding failed: {e}")
except LensError as e:
    print(f"A general LENS error occurred: {e}")
Exception Hierarchy
```
LENS provides specific exceptions to help you handle edge cases safely:

- `LensError`: The base class for all exceptions.

- `LensDecodeError`: Raised if the binary data is malformed, has unexpected EOF, or contains trailing garbage.

- `LensIntegrityError`: A subclass of LensDecodeError raised when the CRC32 checksum doesn't match.

`LensTypeError`: Raised during encoding if a value type is not supported.

# Technical Specifications

- Magic Header: LENS (4 bytes)

- Version: 31 (v3.1)

- Safety Limits:

- Max String/Bytes: 64 MB

- Max Array/Object Size: 1,000,000 elements

- Max Symbols: 250,000

- Max Decompressed Payload: 512 MB

# License
MIT
