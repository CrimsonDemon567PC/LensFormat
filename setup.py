import os
import platform
from setuptools import setup, Extension, find_packages
from Cython.Build import cythonize

# Define the extension module
ext_name = "lens_format.core"
ext_source = os.path.join("lens_format", "core.pyx")

# Optimization flags based on the operating system
if platform.system() == "Windows":
    # MSVC specific flags
    extra_compile_args = ["/O2", "/Oi", "/Ot", "/Gy"]
    extra_link_args = []
else:
    # GCC/Clang specific flags for maximum performance
    extra_compile_args = [
        "-O3", 
        "-march=native", 
        "-ffast-math", 
        "-fno-plt",
        "-flto"
    ]
    extra_link_args = ["-flto"]

extensions = [
    Extension(
        ext_name,
        sources=[ext_source],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
        # Informs Cython that this module does not need the GIL for certain parts
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )
]

setup(
    name="lens_format",
    version="4.0.0",
    description="High-performance binary serialization with frame-pooling and zero-copy.",
    author="Your Name",
    license="MIT",
    packages=find_packages(),
    # Use cythonize to compile the .pyx file into a .c file and then into a shared library
    ext_modules=cythonize(
        extensions,
        compiler_directives={
            'language_level': "3",
            'boundscheck': False,       # Maximizes speed by removing array bounds checking
            'wraparound': False,        # Disables Python-style negative indexing for speed
            'initializedcheck': False,   # Removes checks for memoryview initialization
            'cdivision': True,          # Uses C-style division (faster)
            'always_allow_keywords': False,
        },
    ),
    install_requires=[
        # No heavy runtime dependencies, just Cython for building
    ],
    python_requires=">=3.7",
    zip_safe=False,
)
