import os
import platform
from setuptools import setup, Extension, find_packages

import numpy
from Cython.Build import cythonize

NAME = "lens_format"
VERSION = "4.0.1"

def make_extensions():
    base_dir = os.path.abspath(os.path.dirname(__file__))
    pyx = os.path.join(base_dir, "lens_format", "core.pyx")

    if not os.path.exists(pyx):
        raise RuntimeError("core.pyx missing")

    if platform.system() == "Windows":
        extra_compile_args = ["/Ox", "/Oi", "/Ot", "/DNDEBUG"]
    else:
        extra_compile_args = ["-O3", "-ffast-math", "-DNDEBUG"]

    ext = Extension(
        name="lens_format.core",
        sources=[pyx],
        include_dirs=[numpy.get_include()],
        extra_compile_args=extra_compile_args,
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )

    return cythonize(
        [ext],
        compiler_directives={
            "language_level": "3",
            "boundscheck": False,
            "wraparound": False,
            "initializedcheck": False,
            "cdivision": True,
            "infer_types": True,
        },
    )

setup(
    name=NAME,
    version=VERSION,
    packages=find_packages(),
    ext_modules=make_extensions(),
    zip_safe=False,
    python_requires=">=3.8",
)
