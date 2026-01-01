#!/usr/bin/env python
"""
Minimal integration test for pyrsm in containerized environment.
Tests basic import functionality and core features.
"""
import sys
import time

def test_import_speed():
    """Test that pyrsm imports quickly (lazy loading check)."""
    start = time.perf_counter()
    import pyrsm
    duration = time.perf_counter() - start
    print(f"✓ pyrsm imported in {duration:.3f}s")
    assert duration < 2.0, f"Import too slow: {duration}s"
    return pyrsm

def test_core_modules(pyrsm):
    """Test that core modules are accessible."""
    print("✓ Testing core module access...")
    assert hasattr(pyrsm, 'basics'), "Missing basics module"
    assert hasattr(pyrsm, 'model'), "Missing model module"
    print("✓ Core modules accessible")

def test_basic_functionality():
    """Test basic pyrsm functionality with minimal data."""
    import polars as pl
    from pyrsm.basics import compare_means

    print("✓ Testing basic functionality...")
    df = pl.DataFrame({
        'group': ['A', 'A', 'B', 'B', 'B'],
        'value': [1.0, 2.0, 3.0, 4.0, 5.0]
    })

    # Simple smoke test - just ensure it doesn't crash
    result = compare_means(df, var1='group', var2='value')
    print("✓ compare_means executed successfully")

def test_architecture_info():
    """Print architecture information for verification."""
    import platform
    print(f"✓ Architecture: {platform.machine()}")
    print(f"✓ Python: {platform.python_version()}")

if __name__ == '__main__':
    print("=" * 50)
    print("Minimal pyrsm Integration Test")
    print("=" * 50)

    try:
        test_architecture_info()
        pyrsm = test_import_speed()
        test_core_modules(pyrsm)
        test_basic_functionality()

        print("=" * 50)
        print("✓ All tests passed!")
        print("=" * 50)
        sys.exit(0)
    except Exception as e:
        print(f"✗ Test failed: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
