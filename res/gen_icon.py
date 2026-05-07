#!/usr/bin/env python3
"""Generate app icons from icon.png using Pillow (PIL)"""

from PIL import Image
import os
import sys

def main():
    # Sizes to generate
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    
    # Input file
    input_file = "icon.png"
    
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found in current directory")
        sys.exit(1)
    
    try:
        # Open original image
        img = Image.open(input_file)
        print(f"Opened {input_file} ({img.size})")
        
        # Generate resized versions
        for size in sizes:
            output = f"app_icon_{size}.png"
            resized = img.resize((size, size), Image.Resampling.LANCZOS)
            resized.save(output)
            print(f"Created {output} ({size}x{size})")
        
        # Generate .ico file (Windows icon)
        # Use subset of sizes for ICO (typically 16, 32, 48, 128, 256)
        ico_sizes = [16, 32, 48, 128, 256]
        ico_images = []
        for size in ico_sizes:
            resized = img.resize((size, size), Image.Resampling.LANCZOS)
            # Convert RGBA to RGB if needed (ICO format)
            if resized.mode == "RGBA":
                background = Image.new("RGB", resized.size, (255, 255, 255))
                background.paste(resized, mask=resized.split()[3])
                resized = background
            ico_images.append(resized)
        
        # Save as ICO
        if ico_images:
            ico_images[0].save("icon.ico", format="ICO", sizes=[(img.size) for img in ico_images])
            print(f"Created icon.ico")
        
        print("\nDone! Generated files:")
        for size in sizes:
            print(f"  - app_icon_{size}.png")
        print("  - icon.ico")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
