import os
import platform
from setuptools import setup, Extension, find_packages

# 1. Cython-Check und Build-Logik
try:
    from Cython.Build import cythonize
    USE_CYTHON = True
except ImportError:
    USE_CYTHON = False

ext_name = "lens_format.core"
# Fallback auf .c falls die Source-Distribution ohne Cython installiert wird
ext_source = os.path.join("lens_format", "core.pyx") if USE_CYTHON else os.path.join("lens_format", "core.c")

# 2. Compiler-spezifische Flags für maximale Performance
if platform.system() == "Windows":
    # MSVC Optimierungen: /Ox (Full Optimization), /favor:INTEL64/AMD64
    extra_compile_args = ["/Ox", "/Oi", "/Ot", "/Gy", "/DNDEBUG"]
    extra_link_args = []
else:
    # GCC/Clang: -O3 ist Standard, -ffast-math hilft bei Floats (T_FLOAT)
    # -fno-semantic-interposition erlaubt bessere Inlining-Optimierung
    extra_compile_args = [
        "-O3", 
        "-march=native", 
        "-ffast-math", 
        "-fno-plt", 
        "-flto", 
        "-DNDEBUG"
    ]
    extra_link_args = ["-flto"]

# 3. Extension Definition
extensions = [
    Extension(
        ext_name,
        sources=[ext_source],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
        # Unterdrückt NumPy Warnungen und setzt API Level
        define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
    )
]

# 4. Cython Directives (Hier definieren wir das Verhalten der Code-Generierung)
if USE_CYTHON:
    extensions = cythonize(
        extensions,
        compiler_directives={
            'language_level': "3",
            'boundscheck': False,       # Extrem wichtig für Performance
            'wraparound': False,        # Erhöht Speed bei Index-Zugriffen
            'initializedcheck': False,   # Spart Checks bei Memoryviews
            'cdivision': True,          # Nutzt C-Division statt Python-Division
            'nonecheck': False,         # Deaktiviert Checks auf None-Pointer
            'overflowcheck': False,     # Deaktiviert Checks für Integer-Overflow
            'infer_types': True,        # Erlaubt Cython intelligentere Typ-Inferenz
        },
    )

# 5. Setup Call
setup(
    name="lens_format",
    version="4.0.0",
    description="High-performance binary serialization with frame-pooling and zero-copy.",
    long_description="A binary protocol designed for speed, utilizing C-level frame pooling and aggressive zero-copy strategies.",
    author="Gemini & Peer",
    license="MIT",
    packages=find_packages(),
    ext_modules=extensions,
    # py_modules=[] falls du Hilfsskripte hast
    install_requires=[],
    # PEP 517 Support (pyproject.toml ist heutzutage besser, aber setup_requires bleibt kompatibel)
    setup_requires=["cython"],
    python_requires=">=3.8", # v4 nutzt moderne Type-Hints und Datetime-Features
    zip_safe=False,
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Cython",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Operating System :: OS Independent",
    ],
)
