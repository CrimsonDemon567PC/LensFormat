import os
import platform
import sys
from setuptools import setup, Extension, find_packages

# 1. Safe-Import für Cython
# Das verhindert den Fehler "Metadata generation failed" während der Vor-Installation
try:
    from Cython.Build import cythonize
    USE_CYTHON = True
except ImportError:
    USE_CYTHON = False

# 2. Pfade und Modulname
ext_name = "lens_format.core"
# Wir nutzen .pyx wenn Cython da ist, sonst versuchen wir die .c Datei zu finden
ext_source = os.path.join("lens_format", "core.pyx") if USE_CYTHON else os.path.join("lens_format", "core.c")

# 3. OS-spezifische Compiler-Optimierungen
if platform.system() == "Windows":
    # Microsoft Visual C++ Flags
    extra_compile_args = ["/O2", "/Oi", "/Ot", "/Gy"]
    extra_link_args = []
else:
    # GCC/Clang Flags (O3, Native Architecture, Link-Time-Optimization)
    extra_compile_args = ["-O3", "-march=native", "-ffast-math", "-fno-plt", "-flto"]
    extra_link_args = ["-flto"]

# 4. Extension Definition
extensions = [
    Extension(
        ext_name,
        sources=[ext_source],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
        # Unterdrückt Warnungen für veraltete NumPy-APIs
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )
]

# 5. Cythonize nur anwenden, wenn Cython verfügbar ist
if USE_CYTHON:
    extensions = cythonize(
        extensions,
        compiler_directives={
            'language_level': "3",
            'boundscheck': False,       # Kein Overhead durch Index-Prüfung
            'wraparound': False,        # Deaktiviert negative Indizes für Speed
            'initializedcheck': False,   # Deaktiviert Memoryview-Checks
            'cdivision': True,          # Schnelle C-Division
            'always_allow_keywords': False,
        },
    )

# 6. Setup-Konfiguration
setup(
    name="lens_format",
    version="4.0.0",
    description="High-performance binary serialization with frame-pooling and zero-copy.",
    author="Gemini",
    license="MIT",
    packages=find_packages(),
    ext_modules=extensions,
    install_requires=[],
    # Teilt pip mit, dass Cython zum Bauen zwingend erforderlich ist
    setup_requires=["cython"],
    python_requires=">=3.7",
    zip_safe=False,
)