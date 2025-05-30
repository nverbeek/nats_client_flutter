# Flutter Icon Generator

This directory contains scripts to generate all necessary app launcher icons for your Flutter application across all platforms while preserving transparency.

## Prerequisites

- **Node.js** (v14 or higher)
- **npm** (comes with Node.js)

## Usage

### Method 1: Using Node.js directly

```bash
cd scripts
npm install
npm run generate
```

This will automatically:
1. Install dependencies (sharp for SVG to PNG conversion, png-to-ico for Windows icons)
2. Generate all platform icons from your SVG source
3. Preserve transparency in all icons
4. Create proper ICO files for Windows

### Method 2: Manual execution

```bash
cd scripts
npm install
node generate_icons.js
```

## What Gets Generated

The script generates icons for all Flutter platforms:

### Android
- `mipmap-mdpi/ic_launcher.png` (48x48)
- `mipmap-hdpi/ic_launcher.png` (72x72)
- `mipmap-xhdpi/ic_launcher.png` (96x96)
- `mipmap-xxhdpi/ic_launcher.png` (144x144)
- `mipmap-xxxhdpi/ic_launcher.png` (192x192)

### iOS
- All required sizes from 20x20 to 1024x1024
- `Contents.json` manifest file
- Located in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

### Web
- `Icon-192.png` (192x192)
- `Icon-512.png` (512x512)
- `Icon-maskable-192.png` (192x192 with safe area padding)
- `Icon-maskable-512.png` (512x512 with safe area padding)
- `favicon.png` (16x16)

### macOS
- All required sizes from 16x16 to 1024x1024
- `Contents.json` manifest file
- Located in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`

### Windows
- `app_icon.ico` - Automatically generated ICO file containing all necessary sizes (16, 32, 48, 64, 128, 256)
- Located in `windows/runner/resources/`

### Linux
- `icon.png` (64x64)

## Source Icon

The scripts expect the source SVG icon to be located at:
```
assets/app_launcher_icon.svg
```

## Transparency

All generated icons preserve the transparency from the source SVG. This is why we're not using the `flutter_launcher_icons` package, which can sometimes have issues with transparent backgrounds.

## Features

- **Pure JavaScript**: No external binary dependencies required
- **Transparency preservation**: Maintains alpha channel from SVG
- **Automatic ICO generation**: Windows icons are created automatically using `png-to-ico`
- **High quality**: Uses sharp for high-quality SVG to PNG conversion
- **Maskable icons**: Web icons include maskable variants for PWA support

## Troubleshooting

1. **"sharp" installation fails**: Make sure you have the latest Node.js and try:
   ```bash
   npm install --force
   ```

2. **Poor quality icons**: The script uses high DPI (300) for SVG rendering. If you need even higher quality, you can modify the `density` parameter in the script.

3. **Missing dependencies**: Run `npm install` to ensure all dependencies are installed.

## Customization

You can modify `generate_icons.js` to:
- Change icon sizes
- Add platform-specific variations
- Adjust maskable icon padding (currently 10%)
- Modify the SVG rendering density 