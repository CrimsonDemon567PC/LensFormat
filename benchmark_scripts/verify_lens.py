import lens_format
import time

def verify():
    print(f"Lens Version: {lens_format.__version__}")
    
    # Check if the core extension is loaded
    try:
        from lens_format import core
        print("C-Extension: LOADED SUCCESSFULLY")
    except ImportError:
        print("C-Extension: NOT FOUND (Running on fallback?)")
        return

    # Basic Test Data
    data = {
        "id": 1024,
        "status": True,
        "meta": {"source": "sensor_v4", "tags": ["fast", "bin", "cython"]},
        "payload": b"\x00\xff\x00\xff"
    }

    # Test Roundtrip
    blob, symbols = lens_format.dumps(data)
    decoded = lens_format.loads(blob, symbols)

    if data == decoded:
        print("Integrity Check: PASSED")
    else:
        print("Integrity Check: FAILED")

if __name__ == "__main__":
    verify()