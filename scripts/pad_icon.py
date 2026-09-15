from PIL import Image
import os

img_path = 'assets/images/app_icon.png'
img = Image.open(img_path).convert("RGB")

width, height = img.size
new_w = int(width * 0.70)
new_h = int(height * 0.70)

resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

# Create a background with the exact same color as the logo's background (25, 50, 20)
bg_color = (25, 50, 20)
canvas = Image.new('RGB', (width, height), bg_color)

offset_x = (width - new_w) // 2
offset_y = (height - new_h) // 2
canvas.paste(resized, (offset_x, offset_y))

out_path = 'assets/images/app_icon_foreground.png'
canvas.save(out_path)
print(f"Foreground image generated successfully at {out_path}!")
