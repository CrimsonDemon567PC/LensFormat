# cython: language_level=3, boundscheck=False, wraparound=False, initializedcheck=False, cdivision=True, nonecheck=False

cimport cython
from libc.stdint cimport uint64_t, int64_t
from libc.string cimport memcpy
from cpython.dict cimport PyDict_New, PyDict_SetItem
from cpython.set cimport PySet_New, PySet_Add
from cpython.list cimport PyList_New, PyList_SET_ITEM
from cpython.unicode cimport PyUnicode_DecodeUTF8
from cpython.ref cimport PyObject, Py_INCREF, Py_DECREF, Py_XDECREF
from cpython.object cimport PyFloat_FromDouble, PyLong_FromLongLong

# ============================================================
# Endianness helper
# ============================================================
cdef extern from *:
    """
    #include <stdint.h>
    #if defined(_MSC_VER)
        #define BSWAP64(x) _byteswap_uint64(x)
    #else
        #define BSWAP64(x) __builtin_bswap64(x)
    #endif

    static inline uint64_t lens_be64(uint64_t x) {
        #if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
            return x;
        #else
            return BSWAP64(x);
        #endif
    }
    """
    uint64_t lens_be64(uint64_t) nogil

# ============================================================
# Constants
# ============================================================
cdef int MAX_STACK_DEPTH = 128
cdef int CT_LIST  = 0
cdef int CT_DICT  = 1
cdef int CT_SET   = 2
cdef int CT_TUPLE = 3

cdef struct Frame:
    PyObject* container
    Py_ssize_t remaining
    Py_ssize_t index
    PyObject* current_key
    int c_type

# ============================================================
# Decoder + Encoder
# ============================================================
@cython.final
cdef class FastDecoder:
    cdef const unsigned char* curr
    cdef const unsigned char* end
    cdef list symbols
    cdef Py_ssize_t num_symbols

    def __init__(self, const unsigned char[:] data, list symbols):
        if data.shape[0] > 0:
            self.curr = &data[0]
            self.end = self.curr + data.shape[0]
        else:
            self.curr = NULL
            self.end = NULL
        self.symbols = symbols
        self.num_symbols = len(symbols)

    cdef inline uint64_t _read_varint(self) except? 0:
        cdef uint64_t res = 0
        cdef int shift = 0
        cdef unsigned char b
        while True:
            if self.curr >= self.end:
                raise ValueError("Truncated varint")
            b = self.curr[0]
            self.curr += 1
            if shift >= 63 and (b & 0x7F) > 1:
                raise ValueError("Varint overflow")
            res |= (<uint64_t>(b & 0x7F)) << shift
            if not (b & 0x80):
                return res
            shift += 7

    cpdef decode_all(self):
        cdef Frame stack[MAX_STACK_DEPTH]
        cdef int depth = -1
        cdef PyObject* val = NULL
        cdef unsigned char tag
        cdef uint64_t u_val
        cdef double f_val
        cdef Py_ssize_t ln
        cdef PyObject* c_obj
        cdef PyObject* tmp_key
        cdef int ct
        cdef object val_obj

        try:
            while True:
                # -------------------------------
                # Process top-of-stack container
                # -------------------------------
                if depth >= 0:
                    frame = &stack[depth]

                    # DICT KEY PATH
                    if frame.c_type == CT_DICT and frame.current_key == NULL:
                        if self.curr >= self.end or self.curr[0] != 8:
                            raise ValueError("Expected dict key symbol")
                        self.curr += 1
                        u_val = self._read_varint()
                        if u_val >= <uint64_t>self.num_symbols:
                            raise ValueError("Symbol index out of range")
                        tmp_key = <PyObject*>self.symbols[u_val]
                        Py_INCREF(tmp_key)
                        frame.current_key = tmp_key
                        continue

                    # CONTAINER CLOSURE
                    if frame.remaining == 0:
                        if frame.c_type == CT_TUPLE:
                            val_obj = tuple(<object>frame.container)
                            val = <PyObject*>val_obj
                            Py_INCREF(val)
                            Py_DECREF(frame.container)
                        else:
                            val = frame.container
                        frame.container = NULL
                        depth -= 1
                        if depth < 0:
                            res_obj = <object>val
                            Py_DECREF(val)
                            return res_obj
                        self._fill_parent(&stack[depth], val)
                        val = NULL
                        continue

                # -------------------------------
                # Decode next value
                # -------------------------------
                if self.curr >= self.end:
                    raise ValueError("Unexpected EOF")
                tag = self.curr[0]
                self.curr += 1

                if tag == 0: # NULL
                    val = <PyObject*>None; Py_INCREF(val)
                elif tag == 1: # TRUE
                    val = <PyObject*>True; Py_INCREF(val)
                elif tag == 2: # FALSE
                    val = <PyObject*>False; Py_INCREF(val)
                elif tag == 3: # INT
                    u_val = self._read_varint()
                    val = <PyObject*>PyLong_FromLongLong((u_val >> 1) ^ -(u_val & 1))
                elif tag == 4: # FLOAT
                    if self.curr + 8 > self.end:
                        raise ValueError("Truncated float")
                    memcpy(&u_val, self.curr, 8)
                    self.curr += 8
                    u_val = lens_be64(u_val)
                    memcpy(&f_val, &u_val, 8)
                    val = <PyObject*>PyFloat_FromDouble(f_val)
                elif tag == 5: # STR
                    ln = <Py_ssize_t>self._read_varint()
                    if self.curr + ln > self.end:
                        raise ValueError("Truncated string")
                    val = <PyObject*>PyUnicode_DecodeUTF8(<char*>self.curr, ln, "strict")
                    self.curr += ln
                elif tag == 8: # SYMREF
                    u_val = self._read_varint()
                    if u_val >= <uint64_t>self.num_symbols:
                        raise ValueError("Symbol index out of range")
                    val = <PyObject*>self.symbols[u_val]; Py_INCREF(val)
                elif tag in (6, 13):  # LIST / TUPLE
                    if depth + 1 >= MAX_STACK_DEPTH:
                        raise RuntimeError("Stack overflow")
                    ln = <Py_ssize_t>self._read_varint()
                    c_obj = <PyObject*>PyList_New(ln)
                    if c_obj == NULL:
                        raise MemoryError()
                    # Fill with None to prevent segfault
                    for i in range(ln):
                        Py_INCREF(None)
                        PyList_SET_ITEM(<object>c_obj, i, None)
                    ct = CT_LIST if tag == 6 else CT_TUPLE
                    depth += 1
                    stack[depth].container = c_obj
                    stack[depth].remaining = ln
                    stack[depth].index = 0
                    stack[depth].current_key = NULL
                    stack[depth].c_type = ct
                    continue
                elif tag == 7:  # DICT
                    if depth + 1 >= MAX_STACK_DEPTH:
                        raise RuntimeError("Stack overflow")
                    ln = <Py_ssize_t>self._read_varint()
                    c_obj = PyDict_New()
                    if c_obj == NULL: raise MemoryError()
                    ct = CT_DICT
                    depth += 1
                    stack[depth].container = c_obj
                    stack[depth].remaining = ln
                    stack[depth].index = 0
                    stack[depth].current_key = NULL
                    stack[depth].c_type = ct
                    continue
                elif tag == 12:  # SET
                    if depth + 1 >= MAX_STACK_DEPTH:
                        raise RuntimeError("Stack overflow")
                    ln = <Py_ssize_t>self._read_varint()
                    c_obj = PySet_New(NULL)
                    if c_obj == NULL: raise MemoryError()
                    ct = CT_SET
                    depth += 1
                    stack[depth].container = c_obj
                    stack[depth].remaining = ln
                    stack[depth].index = 0
                    stack[depth].current_key = NULL
                    stack[depth].c_type = ct
                    continue
                else:
                    raise NotImplementedError(f"Unknown tag {tag}")

                # -------------------------------
                # Fill parent container
                # -------------------------------
                if depth < 0:
                    res_obj = <object>val
                    Py_DECREF(val)
                    return res_obj
                self._fill_parent(&stack[depth], val)
                val = NULL

        finally:
            Py_XDECREF(val)
            while depth >= 0:
                Py_XDECREF(stack[depth].container)
                Py_XDECREF(stack[depth].current_key)
                depth -= 1

    cdef inline void _fill_parent(self, Frame* frame, PyObject* val) except *:
        cdef int res
        try:
            if frame.c_type == CT_DICT:
                res = PyDict_SetItem(<object>frame.container, <object>frame.current_key, <object>val)
                Py_DECREF(frame.current_key)
                frame.current_key = NULL
                Py_DECREF(val)
                if res < 0: raise ValueError("Dict insert failed")
            elif frame.c_type == CT_LIST or frame.c_type == CT_TUPLE:
                PyList_SET_ITEM(<object>frame.container, frame.index, <object>val)
                frame.index += 1
            else:  # CT_SET
                res = PySet_Add(<object>frame.container, <object>val)
                Py_DECREF(val)
                if res < 0: raise ValueError("Set add failed")
        except:
            Py_XDECREF(val)
            raise
        frame.remaining -= 1
