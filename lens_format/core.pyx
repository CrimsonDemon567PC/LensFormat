# cython: language_level=3, boundscheck=False, wraparound=False, initializedcheck=False, cdivision=True, infer_types=True
cimport cython
from libc.stdint cimport uint64_t, int64_t
from libc.string cimport memcpy
from cpython.bytes cimport PyBytes_FromStringAndSize
from cpython.list cimport PyList_New, PyList_SET_ITEM
from cpython.dict cimport PyDict_New, PyDict_SetItem
from cpython.tuple cimport PyTuple_New, PyTuple_SET_ITEM
from cpython.set cimport PySet_New, PySet_Add
from cpython.ref cimport Py_INCREF, Py_XDECREF
from datetime import datetime, timezone
from cpython.unicode cimport PyUnicode_DecodeUTF8

# ==============================
# 1. Errors & UTC
# ==============================
class LensError(Exception): pass
class LensEncodeError(LensError): pass
class LensDecodeError(LensError): pass

cdef object UTC = timezone.utc

# ==============================
# 2. Low-level helpers
# ==============================
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
    uint64_t lens_be64(uint64_t x) nogil

cdef enum LensTags:
    T_NULL = 0, T_TRUE = 1, T_FALSE = 2, T_INT = 3, T_FLOAT = 4
    T_STR = 5, T_ARR = 6, T_OBJ = 7, T_SYMREF = 8, T_BYTES = 9
    T_TIME = 10, T_EXT = 11, T_SET = 12, T_TUPLE = 13

cdef inline int64_t c_zigzag_decode(uint64_t n) nogil:
    return (n >> 1) ^ -(n & 1)

cdef inline uint64_t c_zigzag_encode(int64_t n) nogil:
    return (n << 1) ^ (n >> 63)

# ==============================
# 3. DecodeFrame
# ==============================
@cython.final
cdef class DecodeFrame:
    cdef public object container
    cdef public Py_ssize_t remaining, list_idx
    cdef public object current_key
    cdef public bint is_dict

    def __init__(self, object container, Py_ssize_t remaining, bint is_dict):
        self.reset(container, remaining, is_dict)

    cdef inline void reset(self, object container, Py_ssize_t remaining, bint is_dict):
        self.container = container
        self.remaining = remaining
        self.is_dict = is_dict
        self.current_key = None
        self.list_idx = 0

# ==============================
# 4. FastEncoder
# ==============================
@cython.final
cdef class FastEncoder:
    cdef object buffer
    cdef dict symbol_map
    cdef object ext_handler

    def __init__(self, list symbols, object ext_handler=None):
        self.buffer = bytearray()
        self.symbol_map = {sym: i for i, sym in enumerate(symbols)}
        self.ext_handler = ext_handler

    cdef inline void _write_varint(self, uint64_t n):
        while n >= 0x80:
            self.buffer.append(<unsigned char>((n & 0x7F) | 0x80))
            n >>= 7
        self.buffer.append(<unsigned char>n)

    cpdef bytes encode(self, object obj):
        self.buffer.clear()  # reuse buffer
        self._encode_recursive(obj)
        return bytes(self.buffer)

    cdef void _encode_recursive(self, object obj):
        cdef uint64_t ubits
        cdef double fval
        cdef bytes b_val

        if obj is None: self.buffer.append(T_NULL)
        elif obj is True: self.buffer.append(T_TRUE)
        elif obj is False: self.buffer.append(T_FALSE)
        elif isinstance(obj, int):
            self.buffer.append(T_INT)
            self._write_varint(c_zigzag_encode(obj))
        elif isinstance(obj, float):
            self.buffer.append(T_FLOAT)
            fval = obj
            memcpy(&ubits, &fval, 8)
            ubits = lens_be64(ubits)
            self.buffer.extend((<unsigned char *> &ubits)[:8])
        elif isinstance(obj, str):
            if obj in self.symbol_map:
                self.buffer.append(T_SYMREF)
                self._write_varint(self.symbol_map[obj])
            else:
                self.buffer.append(T_STR)
                b_val = obj.encode('utf-8')
                self._write_varint(len(b_val))
                self.buffer.extend(b_val)
        elif isinstance(obj, datetime):
            self.buffer.append(T_TIME)
            ts = int(obj.timestamp() * 1000)
            self._write_varint(c_zigzag_encode(ts))
        elif isinstance(obj, list):
            self.buffer.append(T_ARR)
            self._write_varint(len(obj))
            for item in obj: self._encode_recursive(item)
        elif isinstance(obj, dict):
            self.buffer.append(T_OBJ)
            self._write_varint(len(obj))
            for k, v in obj.items():
                self.buffer.append(T_SYMREF)
                self._write_varint(self.symbol_map[k])
                self._encode_recursive(v)
        elif isinstance(obj, (bytes, bytearray)):
            self.buffer.append(T_BYTES)
            self._write_varint(len(obj))
            self.buffer.extend(obj)
        elif isinstance(obj, tuple):
            self.buffer.append(T_TUPLE)
            self._write_varint(len(obj))
            for item in obj: self._encode_recursive(item)
        elif isinstance(obj, set):
            self.buffer.append(T_SET)
            self._write_varint(len(obj))
            for item in obj: self._encode_recursive(item)
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

# ==============================
# 5. FastDecoder
# ==============================
@cython.final
cdef class FastDecoder:
    cdef const unsigned char[:] buffer
    cdef Py_ssize_t pos, size
    cdef list symbols
    cdef DecodeFrame frame_pool[32]
    cdef int pool_idx
    cdef bint zero_copy
    cdef object ext_hook, ts_hook

    def __init__(self, const unsigned char[:] data, list symbols,
                 bint zero_copy=False, object ext_hook=None, object ts_hook=None):
        self.buffer = data
        self.size = data.shape[0]
        self.pos = 0
        self.symbols = symbols
        self.zero_copy = zero_copy
        self.ext_hook = ext_hook
        self.ts_hook = ts_hook
        self.pool_idx = 0
        for i in range(32):
            self.frame_pool[i] = DecodeFrame(None, 0, False)

    cdef inline uint64_t _read_varint(self) except *:
        cdef uint64_t res = 0
        cdef int shift = 0
        cdef unsigned char b
        while True:
            if self.pos >= self.size:
                raise LensDecodeError("Unexpected end of buffer in varint")
            b = self.buffer[self.pos]
            self.pos += 1
            res |= (<uint64_t>(b & 0x7F)) << shift
            if not (b & 0x80): return res
            shift += 7
            if shift > 63:
                raise LensDecodeError("Varint overflow")

    cdef inline DecodeFrame _push_frame(self, object container, Py_ssize_t remaining, bint is_dict):
        if self.pool_idx >= 32:
            return DecodeFrame(container, remaining, is_dict)
        cdef DecodeFrame f = self.frame_pool[self.pool_idx]
        self.pool_idx += 1
        f.reset(container, remaining, is_dict)
        return f

    cpdef decode_all(self):
        cdef list stack = []
        cdef DecodeFrame frame
        cdef object val = None
        cdef bint owned
        cdef unsigned char tag
        cdef uint64_t bits, var_int
        cdef double fval
        cdef Py_ssize_t ln, start

        while True:
            if stack:
                frame = <DecodeFrame>stack[-1]
                if frame.remaining == 0:
                    val = frame.container
                    stack.pop()
                    if self.pool_idx > 0: self.pool_idx -= 1
                    if not stack:
                        return val
                    self._fill_container(<DecodeFrame>stack[-1], val, owned=True)
                    continue

                # Dict key handling
                if frame.is_dict and frame.current_key is None:
                    tag = self.buffer[self.pos]
                    if tag != T_SYMREF:
                        raise LensDecodeError(f"Expected T_SYMREF for dict key, got {tag}")
                    self.pos += 1
                    frame.current_key = self.symbols[self._read_varint()]
                    continue

            if self.pos >= self.size:
                raise LensDecodeError("Unexpected end of buffer")

            tag = self.buffer[self.pos]
            self.pos += 1
            owned = True

            if tag == T_NULL: val = None
            elif tag == T_TRUE: val = True
            elif tag == T_FALSE: val = False
            elif tag == T_INT: val = c_zigzag_decode(self._read_varint())
            elif tag == T_FLOAT:
                if self.pos + 8 > self.size:
                    raise LensDecodeError("Unexpected end of buffer for float")
                memcpy(&bits, &self.buffer[self.pos], 8)
                self.pos += 8
                bits = lens_be64(bits)
                memcpy(&fval, &bits, 8)
                val = fval
            elif tag == T_STR:
                ln = <Py_ssize_t>self._read_varint()
                if self.pos + ln > self.size:
                    raise LensDecodeError("Unexpected end of buffer for string")
                start = self.pos
                self.pos += ln
                val = PyUnicode_DecodeUTF8(<char *>&self.buffer[start], ln, "strict")
                owned = True
            elif tag == T_BYTES:
                ln = <Py_ssize_t>self._read_varint()
                if self.pos + ln > self.size:
                    raise LensDecodeError("Unexpected end of buffer for bytes")
                start = self.pos
                self.pos += ln
                val = self.buffer[start:self.pos] if self.zero_copy else self.buffer[start:self.pos].tobytes()
                owned = True
            elif tag == T_SYMREF:
                val = self.symbols[self._read_varint()]
                owned = False
            elif tag == T_TIME:
                var_int = c_zigzag_decode(self._read_varint())
                if self.ts_hook: val = self.ts_hook(var_int)
                else: val = datetime.fromtimestamp(var_int / 1000.0, tz=UTC)
            elif tag == T_EXT:
                var_int = self._read_varint()
                ln = <Py_ssize_t>self._read_varint()
                start = self.pos
                self.pos += ln
                val = self.ext_hook(var_int, self.buffer[start:self.pos]) if self.ext_hook else (var_int, self.buffer[start:self.pos])
            elif tag == T_ARR:
                var_int = self._read_varint()
                if var_int == 0: val = []
                else:
                    stack.append(self._push_frame(PyList_New(var_int), var_int, False))
                    continue
            elif tag == T_OBJ:
                var_int = self._read_varint()
                if var_int == 0: val = {}
                else:
                    stack.append(self._push_frame(PyDict_New(), var_int, True))
                    continue
            elif tag == T_TUPLE:
                var_int = self._read_varint()
                stack.append(self._push_frame(PyTuple_New(var_int), var_int, False))
                continue
            elif tag == T_SET:
                var_int = self._read_varint()
                stack.append(self._push_frame(PySet_New(None), var_int, False))
                continue
            else:
                raise LensDecodeError(f"Unknown tag {tag}")

            if stack:
                self._fill_container(<DecodeFrame>stack[-1], val, owned)
            else:
                return val

    cdef inline void _fill_container(self, DecodeFrame frame, object val, bint owned):
        if frame.is_dict:
            PyDict_SetItem(frame.container, frame.current_key, val)
            frame.current_key = None
            if owned: Py_XDECREF(val)
        elif isinstance(frame.container, list):
            Py_INCREF(val)
            PyList_SET_ITEM(frame.container, frame.list_idx, val)
            frame.list_idx += 1
        elif isinstance(frame.container, tuple):
            Py_INCREF(val)
            PyTuple_SET_ITEM(frame.container, frame.list_idx, val)
            frame.list_idx += 1
        else:  # set
            PySet_Add(frame.container, val)
            if owned: Py_XDECREF(val)
        frame.remaining -= 1
