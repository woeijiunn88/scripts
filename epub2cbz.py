#!/usr/bin/env python3
"""
epub_to_cbz.py - Convert a single EPUB file to CBZ format.
Called by convert.sh for each .epub file found.
Usage: python3 epub_to_cbz.py <input.epub> <output.cbz>
"""

from pathlib import Path
import zipfile
import sys
import xml.etree.ElementTree as ET
from typing import List, Tuple, Optional, Iterator

ns = dict(
    opf='http://www.idpf.org/2007/opf',
    xhtml='http://www.w3.org/1999/xhtml',
    cont='urn:oasis:names:tc:opendocument:xmlns:container',
)


def find_opf_path(zf: zipfile.ZipFile) -> str:
    """Parse META-INF/container.xml to find the OPF rootfile path."""
    try:
        with zf.open("META-INF/container.xml") as fp:
            tree = ET.parse(fp)
            rootfile = tree.find('.//cont:rootfile', ns)
            if rootfile is not None:
                return rootfile.attrib['full-path']
    except KeyError:
        pass

    # Fallback: search for any .opf file
    for name in zf.namelist():
        if name.endswith('.opf'):
            return name

    raise FileNotFoundError("Could not locate OPF file in EPUB.")


def get_opf_dir(opf_path: str) -> str:
    """Return the directory portion of the OPF path (used to resolve relative hrefs)."""
    parts = opf_path.split('/')
    return '/'.join(parts[:-1]) + '/' if len(parts) > 1 else ''


def resolve_href(href: str, opf_dir: str) -> str:
    """Resolve an href relative to the OPF directory into a zip-relative path."""
    if href.startswith('/'):
        return href.lstrip('/')
    combined = opf_dir + href
    # Normalise ../ segments
    parts = []
    for part in combined.split('/'):
        if part == '..':
            if parts:
                parts.pop()
        elif part and part != '.':
            parts.append(part)
    return '/'.join(parts)


def get_spine_image_paths(zf: zipfile.ZipFile, opf_path: str) -> List[str]:
    """
    Parse OPF spine to get ordered list of XHTML page hrefs,
    then extract <img src> and SVG <image href> from each page.
    Returns zip-relative image paths in reading order.
    """
    opf_dir = get_opf_dir(opf_path)

    with zf.open(opf_path) as fp:
        tree = ET.parse(fp)

    # Build id -> href map for xhtml items
    item_map = {
        item.attrib['id']: resolve_href(item.attrib['href'], opf_dir)
        for item in tree.findall('.//opf:item', ns)
        if 'href' in item.attrib and 'id' in item.attrib
    }

    # Get spine order
    spine_idrefs = [
        item.attrib['idref']
        for item in tree.findall('.//opf:itemref', ns)
        if item.attrib.get('linear', 'yes') != 'no'
    ]

    image_paths = []
    seen = set()

    for idref in spine_idrefs:
        page_path = item_map.get(idref)
        if not page_path:
            continue
        page_dir = get_opf_dir(page_path)

        try:
            with zf.open(page_path) as fp:
                content = fp.read()
        except KeyError:
            print(f"  Warning: spine page not found in zip: {page_path}", file=sys.stderr)
            continue

        try:
            page_tree = ET.fromstring(content)
        except ET.ParseError as e:
            print(f"  Warning: failed to parse {page_path}: {e}", file=sys.stderr)
            continue

        # HTML <img src="...">
        for img in page_tree.iter('{http://www.w3.org/1999/xhtml}img'):
            src = img.attrib.get('src', '')
            if src:
                resolved = resolve_href(src, page_dir)
                if resolved not in seen:
                    seen.add(resolved)
                    image_paths.append(resolved)

        # SVG <image href="..."> or xlink:href
        for img in page_tree.iter('{http://www.w3.org/2000/svg}image'):
            src = (img.attrib.get('{http://www.w3.org/1999/xlink}href') or
                   img.attrib.get('href', ''))
            if src and not src.startswith('data:'):
                resolved = resolve_href(src, page_dir)
                if resolved not in seen:
                    seen.add(resolved)
                    image_paths.append(resolved)

    return image_paths


def get_cover_image(zf: zipfile.ZipFile, opf_path: str) -> Optional[Tuple[str, bytes]]:
    """Try to find cover image from OPF metadata."""
    opf_dir = get_opf_dir(opf_path)

    with zf.open(opf_path) as fp:
        tree = ET.parse(fp)

    # Method 1: <meta name="cover" content="item-id"/>
    cover_meta = tree.find('.//opf:meta[@name="cover"]', ns)
    if cover_meta is not None:
        cover_id = cover_meta.attrib.get('content')
        if cover_id:
            item = tree.find(f'.//opf:item[@id="{cover_id}"]', ns)
            if item is not None:
                href = resolve_href(item.attrib['href'], opf_dir)
                try:
                    with zf.open(href) as f:
                        return 'cover' + Path(href).suffix, f.read()
                except KeyError:
                    pass

    # Method 2: <item properties="cover-image"/>
    for item in tree.findall('.//opf:item[@properties]', ns):
        if 'cover-image' in item.attrib.get('properties', ''):
            href = resolve_href(item.attrib['href'], opf_dir)
            try:
                with zf.open(href) as f:
                    return 'cover' + Path(href).suffix, f.read()
            except KeyError:
                pass

    return None


def convert(epub_path: Path, cbz_path: Path) -> bool:
    """Convert epub_path to cbz_path. Returns True on success."""
    try:
        with zipfile.ZipFile(epub_path) as zf:
            opf_path = find_opf_path(zf)
            image_paths = get_spine_image_paths(zf, opf_path)
            cover = get_cover_image(zf, opf_path)

        if not image_paths and cover is None:
            print(f"ERROR: No images found in {epub_path.name}", file=sys.stderr)
            return False

        cbz_path.parent.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(epub_path) as zf:
            with zipfile.ZipFile(cbz_path, 'w', compression=zipfile.ZIP_STORED) as out:
                # Write cover first if it's not already the first spine image
                if cover:
                    cover_name, cover_data = cover
                    out.writestr(cover_name, cover_data)

                for counter, img_path in enumerate(image_paths, start=1):
                    suffix = Path(img_path).suffix
                    name = f'{counter:04}{suffix}'
                    try:
                        with zf.open(img_path) as f:
                            out.writestr(name, f.read())
                    except KeyError:
                        print(f"  Warning: image not found in zip: {img_path}", file=sys.stderr)

        print(f"OK: {epub_path.name} -> {cbz_path.name} ({len(image_paths)} pages)")
        return True

    except Exception as e:
        print(f"ERROR: {epub_path.name}: {e}", file=sys.stderr)
        return False


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.epub> <output.cbz>", file=sys.stderr)
        sys.exit(1)

    epub_file = Path(sys.argv[1])
    cbz_file = Path(sys.argv[2])

    if not epub_file.is_file():
        print(f"ERROR: File not found: {epub_file}", file=sys.stderr)
        sys.exit(1)

    success = convert(epub_file, cbz_file)
    sys.exit(0 if success else 1)
