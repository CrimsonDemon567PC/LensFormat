from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as f:
    readme_content = f.read()

setup(
    name="lens_format",
    version="3.2.0",
    packages=find_packages(),
    python_requires=">=3.8",
    license="MIT",
    description="LENS v3.2 – Hardened reference implementation for a custom binary data format",
    long_description=readme_content,
    long_description_content_type="text/markdown",
    author="Dein Name",
    url="https://github.com/CrimaomDemon567PC/LensFormat",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
)
