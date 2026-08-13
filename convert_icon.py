
from PIL import Image, ImageFilter

img_path = r'C:\Users\user\.gemini\antigravity\brain\20d049e2-075f-4ecd-8d08-b52d21f5ca4f\.user_uploaded\media_1786657820766.png'
out_path = r'android\app\src\main\res\drawable\ic_notification.png'

try:
    img = Image.open(img_path).convert('RGBA')
    # Crop tighter to remove empty space if any
    gray = img.convert('L')
    pixels = gray.load()
    out = Image.new('L', img.size, 0)
    out_pixels = out.load()

    # Threshold: lower threshold to keep more thin lines
    for y in range(img.height):
        for x in range(img.width):
            if pixels[x, y] > 80:  # lower threshold
                out_pixels[x, y] = 255
            else:
                out_pixels[x, y] = 0

    # Apply MaxFilter to dilate/thicken the lines
    out = out.filter(ImageFilter.MaxFilter(3))
    
    # Bounding box to crop tight
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)

    # Make it square
    w, h = out.size
    s = max(w, h)
    square_out = Image.new('L', (s, s), 0)
    square_out.paste(out, ((s - w) // 2, (s - h) // 2))

    # Convert mask to RGBA
    rgba_out = Image.new('RGBA', square_out.size, (0, 0, 0, 0))
    rgba_pixels = rgba_out.load()
    sq_pixels = square_out.load()
    
    for y in range(s):
        for x in range(s):
            if sq_pixels[x, y] > 128:
                rgba_pixels[x, y] = (255, 255, 255, 255)

    rgba_out = rgba_out.resize((96, 96), Image.Resampling.LANCZOS)
    rgba_out.save(out_path)
    print('Thickened logo saved successfully to ' + out_path)
except Exception as e:
    print('Error:', e)

