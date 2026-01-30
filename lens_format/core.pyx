# cython: language_level=3, boundscheck=False, wraparound=False, initializedcheck=False, cdivision=True, infer_types=True
cimport cython
from libc.stdint cimport uint64_t, int64_t, uint8_t
from libc.string cimport memcpy
from cpython.bytes cimport PyBytes_FromStringAndSize
from cpython.list cimport PyList_New, PyList_SET_ITEM
from cpython.dict cimport PyDict_New, PyDict_SetItem
from posix.types cimport Py_ssize_t
from datetime import datetime, timezone

DEBUG = False

# --- Exceptions ---
class LensError(Exception): pass
class LensDecodeError(LensError): pass
class LensEncodeError(LensError): pass

cdef extern from *:
    """
    #include <stdint.h>
    #if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
        #define NEED_SWAP 0
    #else
        #define NEED_SWAP 1
    #endif
    #if defined(_MSC_VER)
        #include <stdlib.h>
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
    T_STR = 5, T_ARR = 6, T_OBJ = 7, T_SYMREF = 8, T_BYTES = 9, 
    T_TIME = 10, T_EXT = 11

cdef inline int64_t c_zigzag_decode(uint64_t n) nogil:
    return (n >> 1) ^ -(n & 1)

cdef inline uint64_t c_zigzag_encode(int64_t n) nogil:
    return (n << 1) ^ (n >> 63)

# ==========================================
# 1. FRAME POOLING (Optimierte Preallocation)
# ==========================================
@cython.final
cdef class DecodeFrame:
    cdef public object container
    cdef public Py_ssize_t remaining, list_idx
    cdef public object current_key
    cdef public bint is_dict

    def __cinit__(self, object container, Py_ssize_t remaining, bint is_dict):
        self.reset(container, remaining, is_dict)

    cdef void reset(self, object container, Py_ssize_t remaining, bint is_dict):
        self.container = container
        self.remaining = remaining
        self.is_dict = is_dict
        self.current_key = None
        self.list_idx = 0

# ==========================================
# DECODER
# ==========================================



@cython.final
cdef class FastDecoder:
    cdef const unsigned char[:] buffer
    cdef Py_ssize_t pos, size
    cdef list symbols, frame_pool
    cdef bint zero_copy
    cdef int max_depth
    cdef object ext_hook, ts_hook

    def __init__(self, const unsigned char[:] data, list symbols, 
                 bint zero_copy=False, int max_depth=1000,
                 object ext_hook=None, object ts_hook=None):
        self.buffer = data
        self.size = data.shape[0]
        self.pos = 0
        self.symbols = symbols
        self.zero_copy = zero_copy
        self.max_depth = max_depth
        self.ext_hook = ext_hook
        self.ts_hook = ts_hook
        
        
        self.frame_pool = [DecodeFrame(None, 0, False) for _ in range(16)]

    
    cdef str _make_error_msg(self, str msg, list stack):
        if not DEBUG:
            return f"{msg} at offset {self.pos}"
            
        cdef list parts = ["$"]
        cdef DecodeFrame frame
        for item in stack:
            frame = <DecodeFrame>item
            parts.append(f".{frame.current_key}" if frame.is_dict and frame.current_key else f"[{frame.list_idx}]")
        
        cdef Py_ssize_t start = max(0, self.pos - 10)
        cdef Py_ssize_t end = min(self.size, self.pos + 10)
        hex_dump = " ".join([f"{self.buffer[i]:02x}" for i in range(start, end)])
        return f"{msg}\nPath: {''.join(parts)}\nContext: {hex_dump}"

    
    cdef inline uint64_t _read_varint_nogil(self) nogil except *:
        cdef uint64_t res = 0
        cdef int shift = 0
        cdef unsigned char b
        while True:
            if self.pos >= self.size:
                with gil: raise LensDecodeError("EOF in varint")
            b = self.buffer[self.pos]
            self.pos += 1
            res |= (<uint64_t>(b & 0x7F)) << shift
            if not (b & 0x80): return res
            shift += 7
            if shift >= 64:
                with gil: raise LensDecodeError("Varint overflow")

    cdef DecodeFrame _get_frame(self, object container, Py_ssize_t remaining, bint is_dict):
        if self.frame_pool:
            frame = <DecodeFrame>self.frame_pool.pop()
            frame.reset(container, remaining, is_dict)
            return frame
        return DecodeFrame(container, remaining, is_dict)

    cpdef decode_all(self):
        cdef list stack = []
        cdef DecodeFrame frame
        cdef object val = None
        cdef unsigned char tag
        cdef uint64_t bits, var_int
        cdef double fval
        cdef Py_ssize_t ln, start
        cdef int ext_id

        while True:
            if stack:
                frame = <DecodeFrame>stack[-1]
                if frame.remaining == 0:
                    val = frame.container
                    self.frame_pool.append(stack.pop()) 
                    if not stack: return val
                    frame = <DecodeFrame>stack[-1]
                    if frame.is_dict:
                        PyDict_SetItem(frame.container, frame.current_key, val)
                        frame.current_key = None
                    else:
                        PyList_SET_ITEM(frame.container, frame.list_idx, val)
                        frame.list_idx += 1
                    frame.remaining -= 1
                    continue
                
                if frame.is_dict and frame.current_key is None:
                    if self.buffer[self.pos] != T_SYMREF:
                         raise LensDecodeError(self._make_error_msg("Key error", stack))
                    self.pos += 1
                    var_int = self._read_varint_nogil()
                    frame.current_key = self.symbols[var_int]
                    continue

            tag = self.buffer[self.pos]
            self.pos += 1

            if tag == T_NULL: val = None
            elif tag == T_TRUE: val = True
            elif tag == T_FALSE: val = False
            elif tag == T_INT: val = c_zigzag_decode(self._read_varint_nogil())
            elif tag == T_FLOAT:
                memcpy(&bits, &self.buffer[self.pos], 8)
                self.pos += 8
                bits = lens_be64(bits)
                memcpy(&fval, &bits, 8)
                val = fval
            elif tag == T_STR or tag == T_BYTES:
                ln = <Py_ssize_t>self._read_varint_nogil()
                start = self.pos
                self.pos += ln
                
                if self.zero_copy: val = self.buffer[start:self.pos]
                else:
                    val = PyBytes_FromStringAndSize(<char*>&self.buffer[start], ln)
                    if tag == T_STR: val = val.decode('utf-8')
            elif tag == T_SYMREF:
                var_int = self._read_varint_nogil()
                val = self.symbols[var_int]
            elif tag == T_TIME:
                var_int = self._read_varint_nogil()
                val = self.ts_hook(c_zigzag_decode(var_int)) if self.ts_hook else \
                      datetime.fromtimestamp(c_zigzag_decode(var_int) / 1000.0, tz=timezone.utc)
            elif tag == T_EXT: 
                ext_id = <int>self._read_varint_nogil()
                ln = <Py_ssize_t>self._read_varint_nogil()
                start = self.pos
                self.pos += ln
                payload = self.buffer[start:self.pos] if self.zero_copy else \
                          PyBytes_FromStringAndSize(<char*>&self.buffer[start], ln)
                val = self.ext_hook(ext_id, payload) if self.ext_hook else (ext_id, payload)
            elif tag == T_ARR:
                var_int = self._read_varint_nogil()
                if var_int == 0: val = []
                else:
                    stack.append(self._get_frame(PyList_New(var_int), var_int, False))
                    continue 
            elif tag == T_OBJ:
                var_int = self._read_varint_nogil()
                if var_int == 0: val = {}
                else:
                    stack.append(self._get_frame(PyDict_New(), var_int, True))
                    continue 
            else:
                raise LensDecodeError(f"Tag {tag} unknown")

            if not stack: return val
            frame = <DecodeFrame>stack[-1]
            if frame.is_dict:
                PyDict_SetItem(frame.container, frame.current_key, val)
                frame.current_key = None
            else:
                PyList_SET_ITEM(frame.container, frame.list_idx, val)
                frame.list_idx += 1
            frame.remaining -= 1
