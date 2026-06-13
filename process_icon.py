from PIL import Image
import numpy as np

img = Image.open(r"C:\Users\Gianmarco\Documents\smam.PNG").convert("RGBA")
data = np.array(img, dtype=np.float32)

r, g, b, a = data[:,:,0], data[:,:,1], data[:,:,2], data[:,:,3]

# White detection: all channels bright and low colorfulness
whiteness = np.minimum(np.minimum(r, g), b)
colorfulness = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)

# Hard mask: very white pixels
mask_white = (whiteness > 230) & (colorfulness < 30)

# Transition zone: semi-white anti-aliasing pixels
mask_trans = (whiteness > 200) & (colorfulness < 40) & ~mask_white

new_a = data[:,:,3].copy()
new_a[mask_white] = 0
fade = (whiteness[mask_trans] - 200) / 30.0
new_a[mask_trans] = data[:,:,3][mask_trans] * (1.0 - fade)

result = data.copy().astype(np.uint8)
result[:,:,3] = np.clip(new_a, 0, 255).astype(np.uint8)

out = Image.fromarray(result, "RGBA")

# Save transparent master
out.save(r"C:\Users\Gianmarco\Documents\smam_transparent.PNG")

# Generate all needed sizes
for size in [16, 32, 192, 512]:
    resized = out.resize((size, size), Image.LANCZOS)
    resized.save(fr"C:\Users\Gianmarco\Documents\smam_{size}.png")

print("Done - all sizes generated")
