import os
import platform
from setuptools import setup, Extension, find_packages

# 1. Cython Check
try:
    from Cython.Build import cythonize
    USE_CYTHON = True
except ImportError:
    USE_CYTHON = False

# 2. Extension Name and Path Logic
ext_name = "lens_format.core"
pyx_path = os.path.join("lens_format", "core.pyx")
c_path = os.path.join("lens_format", "core.c")

# Force .c if Cython is missing, otherwise use .pyx
if USE_CYTHON and os.path.exists(pyx_path):
    source_path = pyx_path
else:
    source_path = c_path

# 3. Compiler Flags
if platform.system() == "Windows":
    extra_compile_args = ["/Ox", "/Oi", "/Ot", "/Gy", "/DNDEBUG"]
    extra_link_args = []
else:
    # Removed -march=native for better compatibility in CI/CD wheels
    extra_compile_args = ["-O3", "-ffast-math", "-flto", "-DNDEBUG"]
    extra_link_args = ["-flto"]

# 4. Definition of the Extension
extensions = [
    Extension(
        ext_name,
        sources=[source_path],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )
]

# 5. Apply Cythonize
if USE_CYTHON and source_path.endswith(".pyx"):
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

# 6. Setup Call
setup(
    name="lens_format",
    version="4.0.1",
    description="High-performance binary serialization with frame-pooling and zero-copy.",
    author="Vincent Noll",
    license="MIT",
    packages=find_packages(),
    ext_modules=extensions,
    install_requires=[],
    python_requires=">=3.8",
    zip_safe=False,
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Cython",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
)
