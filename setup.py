import os.path
import sys
from distutils.core import setup
from distutils.extension import Extension

# adapted from cytoolz: https://github.com/pytoolz/cytoolz/blob/master/setup.py

info = {}
filename = os.path.join('cyordereddict', '_version.py')
exec(compile(open(filename, "rb").read(), filename, 'exec'), info)
VERSION = info['__version__']

try:
    from Cython.Build import cythonize
    has_cython = True
except ImportError:
    has_cython = False

is_dev = 'dev' in VERSION
use_cython = is_dev or '--cython' in sys.argv or '--with-cython' in sys.argv
if '--no-cython' in sys.argv:
    use_cython = False
    sys.argv.remove('--no-cython')
if '--without-cython' in sys.argv:
    use_cython = False
    sys.argv.remove('--without-cython')
if '--cython' in sys.argv:
    sys.argv.remove('--cython')
if '--with-cython' in sys.argv:
    sys.argv.remove('--with-cython')

if use_cython and not has_cython:
    if is_dev:
        raise RuntimeError('Cython required to build dev version of cyordereddict.')
    print('WARNING: Cython not installed.  Building without Cython.')
    use_cython = False

ext = '.pyx' if use_cython else '.c'
source = os.path.join("cyordereddict", "_cyordereddict")
ext_modules = [Extension("cyordereddict._cyordereddict", [source + ext])]
if use_cython:
    ext_modules = cythonize(ext_modules)

if __name__ == '__main__':
    setup(name='cyordereddict',
          description="Cython implementation of Python's collections.OrderedDict",
          version=VERSION,
          license='MIT',
          author='Stephan Hoyer',
          author_email='shoyer@gmail.com',
          install_requires=['cython'],
          tests_require=['nose'],
          url='https://github.com/shoyer/cyordereddict',
          test_suite='nose.collector',
          packages=['cyordereddict'],
          ext_modules=ext_modules)