from setuptools import setup, Extension
from Cython.Build import cythonize

ext_modules = [
    Extension(
        "lens_format.core",
        ["lens_format/core.pyx"],
        language="c",
        extra_compile_args=["-O3"]
    )
]

setup(
    name="lens_format",
    version="4.0.1",
    packages=["lens_format"],
    ext_modules=cythonize(
        ext_modules,
        compiler_directives={
            "language_level": "3",
            "boundscheck": False,
            "wraparound": False
        }
    ),
    zip_safe=False,
)
