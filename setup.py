import os
import sys
import platform
from setuptools import setup, Extension, find_packages

NAME = "lens_format"
VERSION = "4.0.1"

def get_extensions():
    base_dir = os.path.abspath(os.path.dirname(__file__))
    source_path = os.path.join(base_dir, "lens_format", "core.pyx")
    
    if not os.path.exists(source_path):
        source_path = source_path.replace(".pyx", ".c")
        if not os.path.exists(source_path):
            return []

    if platform.system() == "Windows":
        extra_args = ["/Ox", "/Oi", "/Ot", "/DNDEBUG"]
        extra_link = []
    else:
        extra_args = ["-O3", "-ffast-math", "-DNDEBUG"]
        extra_link = []

    ext = Extension(
        "lens_format.core",
        sources=[source_path],
        extra_compile_args=extra_args,
        extra_link_args=extra_link,
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )

    try:
        from Cython.Build import cythonize
        return cythonize(
            [ext],
            compiler_directives={
                'language_level': "3",
                'boundscheck': False,
                'wraparound': False,
                'initializedcheck': False,
                'cdivision': True,
                'infer_types': True,
            },
        )
    except ImportError:
        return [ext]

setup(
    name=NAME,
    version=VERSION,
    author="Vincent Noll",
    license="MIT",
    packages=find_packages(exclude=["tests*", "benchmarks*"]),
    ext_modules=get_extensions(),
    python_requires=">=3.8",
    zip_safe=False,
    install_requires=[], 
)
