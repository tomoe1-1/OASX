"""Update a reused Windows runner's version resource for the manual build.

Usage: python tools/set_windows_version.py path/to/oasx.exe 2.0.0+20
The new string must have the same length as the existing version string.
Full Flutter builds generate this resource directly from pubspec.yaml.
"""

import argparse
import ctypes
import re
import struct
from pathlib import Path


def update_version(executable: Path, version: str) -> None:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\+(\d+)", version)
    if not match:
        raise ValueError("Expected major.minor.patch+build")
    major, minor, patch, build = map(int, match.groups())
    if any(value > 65535 for value in (major, minor, patch, build)):
        raise ValueError("Version components must fit 16 bits")

    api = ctypes.WinDLL("kernel32", use_last_error=True)
    handle = ctypes.c_void_p
    api.LoadLibraryExW.argtypes = [ctypes.c_wchar_p, handle, ctypes.c_uint]
    api.LoadLibraryExW.restype = handle
    api.FindResourceW.argtypes = [handle, handle, handle]
    api.FindResourceW.restype = handle
    api.LoadResource.argtypes = [handle, handle]
    api.LoadResource.restype = handle
    api.LockResource.argtypes = [handle]
    api.LockResource.restype = handle
    api.SizeofResource.argtypes = [handle, handle]
    api.SizeofResource.restype = ctypes.c_uint
    api.FreeLibrary.argtypes = [handle]
    api.BeginUpdateResourceW.argtypes = [ctypes.c_wchar_p, ctypes.c_bool]
    api.BeginUpdateResourceW.restype = handle
    api.UpdateResourceW.argtypes = [handle, handle, handle, ctypes.c_ushort, handle, ctypes.c_uint]
    api.UpdateResourceW.restype = ctypes.c_bool
    api.EndUpdateResourceW.argtypes = [handle, ctypes.c_bool]
    api.EndUpdateResourceW.restype = ctypes.c_bool

    module = api.LoadLibraryExW(str(executable.resolve()), None, 2)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        resource = api.FindResourceW(module, handle(1), handle(16))
        if not resource:
            raise ctypes.WinError(ctypes.get_last_error())
        pointer = api.LockResource(api.LoadResource(module, resource))
        blob = bytearray(ctypes.string_at(pointer, api.SizeofResource(module, resource)))
    finally:
        api.FreeLibrary(module)

    key = "FileVersion\0".encode("utf-16le")
    start = blob.index(key) + len(key)
    start = (start + 3) & ~3
    end = start
    while blob[end:end + 2] != b"\0\0":
        end += 2
    previous = blob[start:end].decode("utf-16le")
    if len(previous) != len(version):
        raise ValueError(f"Version string length differs: {previous!r} -> {version!r}")
    blob = bytearray(bytes(blob).replace(previous.encode("utf-16le"), version.encode("utf-16le")))
    fixed = blob.index(struct.pack("<I", 0xFEEF04BD))
    ms = (major << 16) | minor
    ls = (patch << 16) | build
    struct.pack_into("<IIII", blob, fixed + 8, ms, ls, ms, ls)

    update = api.BeginUpdateResourceW(str(executable.resolve()), False)
    if not update:
        raise ctypes.WinError(ctypes.get_last_error())
    data = ctypes.create_string_buffer(bytes(blob))
    if not api.UpdateResourceW(update, handle(16), handle(1), 1033, data, len(blob)):
        error = ctypes.get_last_error()
        api.EndUpdateResourceW(update, True)
        raise ctypes.WinError(error)
    if not api.EndUpdateResourceW(update, False):
        raise ctypes.WinError(ctypes.get_last_error())
    print(f"Updated {executable.name}: {previous} -> {version}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    update_version(args.executable, args.version)
