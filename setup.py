import os
import platform
from setuptools import setup, Extension, find_packages

# VERHINDERE IMPORT-FEHLER: 
# Importiere NIEMALS etwas aus lens_format hier drin.

ext_name = "lens_format.core"
# Wir nutzen direkt .pyx - pyproject.toml stellt sicher, dass Cython da ist.
source_path = os.path.join("lens_format", "core.pyx")

if platform.system() == "Windows":
    extra_compile_args = ["/Ox", "/Oi", "/Ot", "/Gy", "/DNDEBUG"]
    extra_link_args = []
else:
    # Kein -march=native für maximale Wheel-Kompatibilität
    extra_compile_args = ["-O3", "-ffast-math", "-flto", "-DNDEBUG"]
    extra_link_args = ["-flto"]

# Cython erst hier importieren, damit der Metadata-Check nicht crashed
try:
    from Cython.Build import cythonize
    USE_CYTHON = True
except ImportError:
    USE_CYTHON = False

extensions = [
    Extension(
        ext_name,
        sources=[source_path],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )
]

if USE_CYTHON:
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

setup(
    name="lens_format",
    version="4.0.1",
    author="Vincent Noll",
    license="MIT",
    # WICHTIG: Explizite Angabe, falls find_packages() im Container versagt
    packages=["lens_format"],
    ext_modules=extensions,
    python_requires=">=3.8",
    zip_safe=False,
    include_package_data=True,
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Cython",
        "Operating System :: OS Independent",
    ],
)
