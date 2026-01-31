# cython: language_level=3
# cython: boundscheck=False, wraparound=False, initializedcheck=False, cdivision=True

cimport cython
from libc.stdint cimport uint64_t, int64_t
from libc.string cimport memcpy

from cpython.dict cimport PyDict_SetItem
from cpython.set cimport PySet_Add
from cpython.unicode cimport PyUnicode_DecodeUTF8

from datetime import datetime, timezone


# ============================================================
# Errors
# ============================================================

class LensError(Exception): pass
class LensEncodeError(LensError): pass
class LensDecodeError(LensError): pass

cdef object UTC = timezone.utc


# ============================================================
# Endianness helper
# ============================================================

cdef extern from *:
    """
    #include <stdint.h>
    #if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
        #define NEED_SWAP 0
    #else
        #define NEED_SWAP 1
    #endif

    #if defined(_MSC_VER)
        #define BSWAP64(x) _byteswap_uint64(x)
    #else
        #define BSWAP64(x) __builtin_bswap64(x)
    #endif

    static inline uint64_t lens_be64(uint64_t x) {
        if (NEED_SWAP) return BSWAP64(x);
        return x;
    }
    """
    uint64_t lens_be64(uint64_t) nogil


# ============================================================
# Tags
# ============================================================

cdef enum LensTags:
    T_NULL   = 0
    T_TRUE   = 1
    T_FALSE  = 2
    T_INT    = 3
    T_FLOAT  = 4
    T_STR    = 5
    T_ARR    = 6
    T_OBJ    = 7
    T_SYMREF = 8
    T_BYTES  = 9
    T_TIME   = 10
    T_EXT    = 11
    T_SET    = 12
    T_TUPLE  = 13


# ============================================================
# Varint helpers
# ============================================================

cdef inline uint64_t zigzag_encode(int64_t n) nogil:
    return (n << 1) ^ (n >> 63)

cdef inline int64_t zigzag_decode(uint64_t n) nogil:
    return (n >> 1) ^ -(n & 1)


# ============================================================
# Decode frame
# ============================================================

cdef class DecodeFrame:
    cdef object container          # list / dict / set
    cdef Py_ssize_t remaining
    cdef Py_ssize_t index
    cdef object current_key
    cdef bint is_dict
    cdef bint is_tuple             # NEW: marks tuple frames

    def __init__(self, object container,
                 Py_ssize_t remaining,
                 bint is_dict,
                 bint is_tuple=False):
        self.container = container
        self.remaining = remaining
        self.index = 0
        self.current_key = None
        self.is_dict = is_dict
        self.is_tuple = is_tuple


# ============================================================
# Encoder (unchanged, safe)
# ============================================================

@cython.final
cdef class FastEncoder:
    cdef bytearray buffer
    cdef dict symbol_map
    cdef object ext_handler

    def __init__(self, list symbols, object ext_handler=None):
        self.buffer = bytearray()
        self.symbol_map = {s: i for i, s in enumerate(symbols)}
        self.ext_handler = ext_handler

    cdef inline void _write_varint(self, uint64_t n):
        # NOTE: This is correct and fast.
        # Micro-opt: could unroll into a local buffer if needed.
        while n >= 0x80:
            self.buffer.append(<unsigned char>((n & 0x7F) | 0x80))
            n >>= 7
        self.buffer.append(<unsigned char>n)

    cpdef bytes encode(self, object obj):
        self.buffer.clear()
        self._encode(obj)
        return bytes(self.buffer)

    cdef void _encode(self, object obj):
        cdef uint64_t bits
        cdef double f
        cdef bytes b

        if obj is None:
            self.buffer.append(T_NULL)

        elif obj is True:
            self.buffer.append(T_TRUE)

        elif obj is False:
            self.buffer.append(T_FALSE)

        elif isinstance(obj, int):
            self.buffer.append(T_INT)
            self._write_varint(zigzag_encode(obj))

        elif isinstance(obj, float):
            self.buffer.append(T_FLOAT)
            f = obj
            memcpy(&bits, &f, 8)
            bits = lens_be64(bits)
            self.buffer.extend((<unsigned char*>&bits)[:8])

        elif isinstance(obj, str):
            if obj in self.symbol_map:
                self.buffer.append(T_SYMREF)
                self._write_varint(self.symbol_map[obj])
            else:
                b = obj.encode("utf-8")
                self.buffer.append(T_STR)
                self._write_varint(len(b))
                self.buffer.extend(b)

        elif isinstance(obj, datetime):
            self.buffer.append(T_TIME)
            self._write_varint(
                zigzag_encode(int(obj.timestamp() * 1000))
            )

        elif isinstance(obj, list):
            self.buffer.append(T_ARR)
            self._write_varint(len(obj))
            for x in obj:
                self._encode(x)

        elif isinstance(obj, tuple):
            self.buffer.append(T_TUPLE)
            self._write_varint(len(obj))
            for x in obj:
                self._encode(x)

        elif isinstance(obj, set):
            self.buffer.append(T_SET)
            self._write_varint(len(obj))
            for x in obj:
                self._encode(x)

        elif isinstance(obj, dict):
            self.buffer.append(T_OBJ)
            self._write_varint(len(obj))
            for k, v in obj.items():
                self.buffer.append(T_SYMREF)
                self._write_varint(self.symbol_map[k])
                self._encode(v)

        elif isinstance(obj, (bytes, bytearray)):
            self.buffer.append(T_BYTES)
            self._write_varint(len(obj))
            self.buffer.extend(obj)

        else:
            if self.ext_handler:
                res = self.ext_handler(obj)
                if res:
                    eid, payload = res
                    self.buffer.append(T_EXT)
                    self._write_varint(eid)
                    self._write_varint(len(payload))
                    self.buffer.extend(payload)
                    return
            raise LensEncodeError(f"Unsupported type: {type(obj)}")


# ============================================================
# Decoder
# ============================================================

@cython.final
cdef class FastDecoder:
    cdef const unsigned char[:] buf
    cdef Py_ssize_t pos
    cdef Py_ssize_t size
    cdef list symbols
    cdef bint zero_copy
    cdef object ext_hook
    cdef object ts_hook

    def __init__(self, const unsigned char[:] data, list symbols,
                 bint zero_copy=False, object ext_hook=None, object ts_hook=None):
        self.buf = data
        self.size = data.shape[0]
        self.pos = 0
        self.symbols = symbols
        self.zero_copy = zero_copy
        self.ext_hook = ext_hook
        self.ts_hook = ts_hook

    cdef inline uint64_t _read_varint(self):
        cdef uint64_t res = 0
        cdef int shift = 0
        cdef unsigned char b

        while True:
            if self.pos >= self.size:
                raise LensDecodeError("Truncated varint")

            b = self.buf[self.pos]
            self.pos += 1

            if shift > 63:
                raise LensDecodeError("Varint overflow")

            res |= (<uint64_t>(b & 0x7F)) << shift

            if not (b & 0x80):
                return res

            shift += 7

    cpdef decode_all(self):
        cdef list stack = []
        cdef DecodeFrame frame
        cdef object val
        cdef unsigned char tag
        cdef uint64_t bits
        cdef double f
        cdef Py_ssize_t ln

        while True:

            # ---------- fast dict-key path ----------
            if stack:
                frame = stack[-1]
                if frame.is_dict and frame.current_key is None:
                    if self.pos >= self.size:
                        raise LensDecodeError("Truncated dict key")
                    if self.buf[self.pos] != T_SYMREF:
                        raise LensDecodeError("Dict key must be symbol")
                    self.pos += 1
                    frame.current_key = self.symbols[self._read_varint()]
                    continue

                if frame.remaining == 0:
                    val = frame.container
                    if frame.is_tuple:
                        val = tuple(val)   # 🔒 IMMUTABLE FINALIZATION
                    stack.pop()
                    if not stack:
                        return val
                    self._fill_parent(stack[-1], val)
                    continue

            if self.pos >= self.size:
                raise LensDecodeError("Unexpected EOF")

            tag = self.buf[self.pos]
            self.pos += 1

            if tag == T_NULL:
                val = None

            elif tag == T_TRUE:
                val = True

            elif tag == T_FALSE:
                val = False

            elif tag == T_INT:
                val = zigzag_decode(self._read_varint())

            elif tag == T_FLOAT:
                if self.pos + 8 > self.size:
                    raise LensDecodeError("Truncated float")
                memcpy(&bits, &self.buf[self.pos], 8)
                self.pos += 8
                bits = lens_be64(bits)
                memcpy(&f, &bits, 8)
                val = f

            elif tag == T_STR:
                ln = self._read_varint()
                if self.pos + ln > self.size:
                    raise LensDecodeError("Truncated string")
                val = PyUnicode_DecodeUTF8(
                    <char*>&self.buf[self.pos], ln, "strict"
                )
                self.pos += ln

            elif tag == T_BYTES:
                ln = self._read_varint()
                if self.pos + ln > self.size:
                    raise LensDecodeError("Truncated bytes")
                val = self.buf[self.pos:self.pos + ln] if self.zero_copy \
                      else bytes(self.buf[self.pos:self.pos + ln])
                self.pos += ln

            elif tag == T_SYMREF:
                val = self.symbols[self._read_varint()]

            elif tag == T_TIME:
                ln = zigzag_decode(self._read_varint())
                val = self.ts_hook(ln) if self.ts_hook else \
                      datetime.fromtimestamp(ln / 1000.0, tz=UTC)

            elif tag == T_EXT:
                eid = self._read_varint()
                ln = self._read_varint()
                if self.pos + ln > self.size:
                    raise LensDecodeError("Truncated ext payload")
                payload = self.buf[self.pos:self.pos + ln]
                self.pos += ln
                val = self.ext_hook(eid, payload) if self.ext_hook else (eid, payload)

            elif tag == T_ARR:
                ln = self._read_varint()
                stack.append(DecodeFrame([None] * ln, ln, False))
                continue

            elif tag == T_TUPLE:
                ln = self._read_varint()
                stack.append(DecodeFrame([None] * ln, ln, False, is_tuple=True))
                continue

            elif tag == T_SET:
                ln = self._read_varint()
                stack.append(DecodeFrame(set(), ln, False))
                continue

            elif tag == T_OBJ:
                ln = self._read_varint()
                stack.append(DecodeFrame({}, ln, True))
                continue

            else:
                raise LensDecodeError(f"Unknown tag {tag}")

            if not stack:
                return val

            self._fill_parent(stack[-1], val)

    cdef inline void _fill_parent(self, DecodeFrame frame, object val):
        if frame.is_dict:
            PyDict_SetItem(frame.container, frame.current_key, val)
            frame.current_key = None
        else:
            if isinstance(frame.container, list):
                frame.container[frame.index] = val
                frame.index += 1
            else:
                PySet_Add(frame.container, val)
        frame.remaining -= 1
