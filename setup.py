import os
import platform
from setuptools import setup, Extension, find_packages

# Define metadata
NAME = "lens_format"
VERSION = "4.0.1"

# Define the Extension
# We use .pyx as the primary source. pyproject.toml ensures Cython is there.
ext_name = "lens_format.core"
source_path = os.path.join("lens_format", "core.pyx")

# Compiler Flags
if platform.system() == "Windows":
    extra_compile_args = ["/Ox", "/Oi", "/Ot", "/Gy", "/DNDEBUG"]
    extra_link_args = []
else:
    extra_compile_args = ["-O3", "-ffast-math", "-flto", "-DNDEBUG"]
    extra_link_args = ["-flto"]

# We only attempt to cythonize if we can import it. 
# This prevents the script from crashing during simple metadata checks.
extensions = [
    Extension(
        ext_name,
        sources=[source_path],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )
]

try:
    from Cython.Build import cythonize
    extensions = cythonize(
        extensions,
        compiler_directives={
            'language_level': "3",
            'boundscheck': False,
            'wraparound': False,
            'initializedcheck': False,
            'cdivision': True,
            'nonecheck': False,
            'overflowcheck': False,
            'infer_types': True,
        },
    )
except ImportError:
    # If Cython isn't available yet, we leave the extension as is.
    # setuptools will handle the .pyx or look for a .c fallback later.
    pass

setup(
    name=NAME,
    version=VERSION,
    description="High-performance binary serialization with frame-pooling and zero-copy.",
    author="Vincent Noll",
    license="MIT",
    packages=find_packages(),
    ext_modules=extensions,
    python_requires=">=3.8",
    zip_safe=False,
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Cython",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
)
