"""Retouche du logo proposé : on isole les flèches du fond bleu, on remplace
le cyan par le vert citron de Flux, on garde le blanc, et on recompose sur le
fond de l'app, sans coins arrondis (le téléphone les ajoute lui-même)."""
import sys
import numpy as np
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
im = np.asarray(Image.open(src).convert('RGB')).astype(np.float32)

# 1. Masque des flèches : le fond est bleu nuit (canal max < ~90).
maxc = im.max(axis=2)
alpha = np.clip((maxc - 95) / 70, 0, 1)
# Hors du carré arrondi (coins blancs) : rien.
h, w = maxc.shape
yy, xx = np.mgrid[0:h, 0:w]
inside = (xx > 120) & (xx < w - 120) & (yy > 120) & (yy < h - 120)
alpha *= inside
# Bords des ombres : on adoucit les blocs dus à la compression de l'image.
from PIL import ImageFilter as _F
alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(_F.GaussianBlur(1.2)), np.float32) / 255
alpha = np.clip((alpha - 0.1) / 0.8, 0, 1)

# 2. Recoloration : blanc reste blanc, couleurs saturées -> vert citron.
lime = np.array([198, 244, 50], np.float32)
mn = im.min(axis=2)
whiteness = np.clip((mn / np.maximum(maxc, 1) - 0.35) / 0.5, 0, 1)
# Lissage : évite l'effet « damier » de la compression sur les dégradés.
from PIL import ImageFilter
whiteness = np.asarray(Image.fromarray((whiteness * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32)[..., None] / 255
shade = np.clip(maxc / 230, 0, 1)[..., None]
colored = lime * (0.55 + 0.45 * shade)
gray = np.repeat(((im[..., 0] * 0.3 + im[..., 1] * 0.59 + im[..., 2] * 0.11) * 1.08).clip(0, 255)[..., None], 3, 2)
rgb = whiteness * gray + (1 - whiteness) * colored

# 3. Motif seul, recadré sur sa boîte, en RGBA.
ys, xs = np.where(alpha > 0.05)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
motif = np.dstack([rgb, alpha * 255])[y0:y1, x0:x1].clip(0, 255).astype(np.uint8)
Image.fromarray(motif, 'RGBA').save(out)
print('motif', motif.shape)
