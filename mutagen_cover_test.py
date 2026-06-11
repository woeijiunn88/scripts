#!/usr/bin/env python3
"""
Standalone FLAC cover detection test
Tests if mutagen can properly detect covers
"""

import sys
from pathlib import Path

try:
    from mutagen.flac import FLAC
except ImportError:
    print("ERROR: mutagen not installed")
    print("Install: pip3 install mutagen --break-system-packages")
    sys.exit(1)

def test_file(flac_path):
    """Test a single FLAC file"""
    print(f"\nTesting: {flac_path}")
    print("=" * 70)

    try:
        audio = FLAC(flac_path)

        print(f"✓ File opened successfully")
        print(f"✓ Audio info: {audio.info.length:.1f}s, {audio.info.sample_rate}Hz")

        # Check pictures
        num_pictures = len(audio.pictures)
        print(f"\n{'✓' if num_pictures > 0 else '✗'} Number of pictures: {num_pictures}")

        if num_pictures > 0:
            for i, pic in enumerate(audio.pictures):
                print(f"\n  Picture #{i+1}:")
                print(f"    MIME type: {pic.mime}")
                print(f"    Size: {pic.width}x{pic.height} px")
                print(f"    Data size: {len(pic.data)} bytes")
                print(f"    Type: {pic.type} ({get_type_name(pic.type)})")
                print(f"    Description: {pic.desc if pic.desc else '(none)'}")
        else:
            print("  (no embedded pictures found)")

        # Check tags
        print(f"\n✓ Tags found: {len(audio.tags) if audio.tags else 0}")
        if audio.tags:
            for key in ['TITLE', 'ARTIST', 'ALBUM']:
                if key in audio:
                    print(f"  {key}: {audio[key][0]}")

        return num_pictures > 0

    except Exception as e:
        print(f"✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

def get_type_name(pic_type):
    """Get human-readable picture type name"""
    types = {
        0: 'Other',
        1: 'File icon',
        2: 'Other file icon',
        3: 'Cover (front)',
        4: 'Cover (back)',
        5: 'Leaflet page',
        6: 'Media',
        7: 'Lead artist',
        8: 'Artist',
        9: 'Conductor',
        10: 'Band',
        11: 'Composer',
        12: 'Lyricist',
        13: 'Recording location',
        14: 'During recording',
        15: 'During performance',
        16: 'Video screen capture',
        17: 'A bright colored fish',
        18: 'Illustration',
        19: 'Band logotype',
        20: 'Publisher logotype'
    }
    return types.get(pic_type, f'Unknown type {pic_type}')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: test_cover_mutagen.py <flac_file_or_directory>")
        sys.exit(1)

    path = Path(sys.argv[1])

    if path.is_file():
        # Test single file
        has_cover = test_file(str(path))
        sys.exit(0 if has_cover else 1)

    elif path.is_dir():
        # Test all FLAC files in directory
        flac_files = sorted(path.glob('*.flac'))

        if not flac_files:
            print(f"No FLAC files found in: {path}")
            sys.exit(1)

        print(f"Found {len(flac_files)} FLAC files")

        with_cover = 0
        without_cover = 0

        for flac_file in flac_files:
            if test_file(str(flac_file)):
                with_cover += 1
            else:
                without_cover += 1

        print("\n" + "=" * 70)
        print(f"SUMMARY:")
        print(f"  Files with cover:    {with_cover}")
        print(f"  Files without cover: {without_cover}")
        print(f"  Total:               {len(flac_files)}")

        sys.exit(0 if with_cover > 0 else 1)
    else:
        print(f"ERROR: Not a file or directory: {path}")
        sys.exit(1)
