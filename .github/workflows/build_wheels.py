name: Build and Upload Wheels

on:
  push:
    tags:
      - 'v*' 

jobs:
  build_wheels:
    name: Build wheels on ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Install cibuildwheel
        run: python -m pip install cibuildwheel==2.16.2

      - name: Build wheels
        run: python -m cibuildwheel --output-dir wheelhouse
        

      - uses: actions/upload-artifact@v4
        with:
          name: cibw-wheels-${{ matrix.os }}-${{ strategy.job-index }}
          path: ./wheelhouse/*.whl

  upload_pypi:
    needs: [build_wheels]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: dist
          merge-multiple: true

      - name: Publish to PyPI
        uses: pypa/gh-action-pypi-publish@release/v1
        with:
          # Hier wird das Secret sicher verwendet:
          password: ${{ secrets.PYPI_API_TOKEN }}
