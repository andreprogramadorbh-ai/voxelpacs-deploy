from pathlib import Path
from PIL import Image

source = Path('/home/ubuntu/voxelpacs-deploy-git/ohif/assets/voxel-pacs-favicon-source.png')
out_dir = source.parent

with Image.open(source) as image:
    image = image.convert('RGBA')
    # Recorte central do símbolo geométrico, preservando margem para legibilidade em 16 px.
    cropped = image.crop((220, 100, 1400, 1280))
    for size in (16, 32, 48, 180):
        rendered = cropped.resize((size, size), Image.Resampling.LANCZOS)
        rendered.save(out_dir / f'voxel-pacs-favicon-{size}.png', optimize=True)

    rendered_32 = cropped.resize((32, 32), Image.Resampling.LANCZOS)
    rendered_32.save(out_dir / 'voxel-pacs-favicon.ico', format='ICO', sizes=[(16, 16), (32, 32)])
