# Scales the 6.9" renders down to the 6.3" and 6.1" sizes App Store Connect accepts.
# The aspect ratios differ by under 0.3%, so a straight resize doesn't visibly distort.
import os
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
SIZES = {'6.3-inch': (1206, 2622), '6.1-inch': (1179, 2556)}

for folder, size in SIZES.items():
    for lang in ('en-US', 'es'):
        source = os.path.join(ROOT, '6.9-inch', lang)
        target = os.path.join(ROOT, folder, lang)
        os.makedirs(target, exist_ok=True)
        for name in sorted(os.listdir(source)):
            if name.endswith('.png'):
                Image.open(os.path.join(source, name)).convert('RGB').resize(size, Image.LANCZOS).save(os.path.join(target, name))
                print(f'{folder}/{lang}/{name}')
