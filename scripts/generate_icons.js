const fs = require('fs').promises;
const path = require('path');
const sharp = require('sharp');
const pngToIco = require('png-to-ico');

// Icon configurations for each platform
const iconConfigs = {
  android: [
    { folder: 'mipmap-mdpi', size: 48 },
    { folder: 'mipmap-hdpi', size: 72 },
    { folder: 'mipmap-xhdpi', size: 96 },
    { folder: 'mipmap-xxhdpi', size: 144 },
    { folder: 'mipmap-xxxhdpi', size: 192 }
  ],
  ios: [
    { size: 20, scales: [1, 2, 3] },
    { size: 29, scales: [1, 2, 3] },
    { size: 40, scales: [1, 2, 3] },
    { size: 60, scales: [2, 3] },
    { size: 76, scales: [1, 2] },
    { size: 83.5, scales: [2] },
    { size: 1024, scales: [1] }
  ],
  web: [
    { name: 'Icon-192.png', size: 192 },
    { name: 'Icon-512.png', size: 512 },
    { name: 'Icon-maskable-192.png', size: 192, maskable: true },
    { name: 'Icon-maskable-512.png', size: 512, maskable: true },
    { name: 'favicon.png', size: 16 }
  ],
  macos: [16, 32, 64, 128, 256, 512, 1024],
  windows: [16, 32, 48, 64, 128, 256],
  linux: [{ name: 'icon.png', size: 64 }]
};

async function ensureDir(dirPath) {
  try {
    await fs.mkdir(dirPath, { recursive: true });
  } catch (error) {
    console.error(`Error creating directory ${dirPath}:`, error);
  }
}

async function convertSvgToPng(svgPath, outputPath, size, options = {}) {
  try {
    const svgBuffer = await fs.readFile(svgPath);
    
    let sharpInstance = sharp(svgBuffer, { density: 300 })
      .resize(size, size, {
        fit: 'contain',
        background: { r: 0, g: 0, b: 0, alpha: 0 }
      })
      .png();

    // For maskable icons, add padding (safe area)
    if (options.maskable) {
      const padding = Math.round(size * 0.1); // 10% padding
      const iconSize = size - (padding * 2);
      
      sharpInstance = sharp(svgBuffer, { density: 300 })
        .resize(iconSize, iconSize, {
          fit: 'contain',
          background: { r: 0, g: 0, b: 0, alpha: 0 }
        })
        .extend({
          top: padding,
          bottom: padding,
          left: padding,
          right: padding,
          background: { r: 0, g: 0, b: 0, alpha: 0 }
        })
        .png();
    }

    await sharpInstance.toFile(outputPath);
    console.log(`✓ Generated: ${outputPath} (${size}x${size})`);
  } catch (error) {
    console.error(`✗ Error generating ${outputPath}:`, error.message);
  }
}

async function generateAndroidIcons(svgPath, projectRoot) {
  console.log('\n🤖 Generating Android icons...');
  
  for (const config of iconConfigs.android) {
    const outputDir = path.join(projectRoot, 'android', 'app', 'src', 'main', 'res', config.folder);
    await ensureDir(outputDir);
    
    const outputPath = path.join(outputDir, 'ic_launcher.png');
    await convertSvgToPng(svgPath, outputPath, config.size);
  }
}

async function generateIosIcons(svgPath, projectRoot) {
  console.log('\n🍎 Generating iOS icons...');
  
  const iosIconDir = path.join(projectRoot, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');
  await ensureDir(iosIconDir);
  
  const contentsJson = {
    images: [],
    info: {
      author: 'xcode',
      version: 1
    }
  };
  
  for (const config of iconConfigs.ios) {
    for (const scale of config.scales) {
      const actualSize = Math.round(config.size * scale);
      const filename = config.size === 1024 
        ? 'Icon-App-1024x1024@1x.png'
        : `Icon-App-${config.size}x${config.size}@${scale}x.png`;
      
      const outputPath = path.join(iosIconDir, filename);
      await convertSvgToPng(svgPath, outputPath, actualSize);
      
      contentsJson.images.push({
        filename,
        idiom: config.size === 1024 ? 'ios-marketing' : 'iphone',
        scale: `${scale}x`,
        size: `${config.size}x${config.size}`
      });
    }
  }
  
  // Write Contents.json
  await fs.writeFile(
    path.join(iosIconDir, 'Contents.json'),
    JSON.stringify(contentsJson, null, 2)
  );
}

async function generateWebIcons(svgPath, projectRoot) {
  console.log('\n🌐 Generating Web icons...');
  
  const webIconDir = path.join(projectRoot, 'web', 'icons');
  await ensureDir(webIconDir);
  
  for (const config of iconConfigs.web) {
    const outputPath = config.name.includes('favicon') 
      ? path.join(projectRoot, 'web', config.name)
      : path.join(webIconDir, config.name);
    
    await convertSvgToPng(svgPath, outputPath, config.size, { maskable: config.maskable });
  }
}

async function generateMacOsIcons(svgPath, projectRoot) {
  console.log('\n🖥️  Generating macOS icons...');
  
  const macIconDir = path.join(projectRoot, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');
  await ensureDir(macIconDir);
  
  const contentsJson = {
    images: [],
    info: {
      author: 'xcode',
      version: 1
    }
  };
  
  const sizePairs = [
    { size: 16, scales: [1, 2] },
    { size: 32, scales: [1, 2] },
    { size: 128, scales: [1, 2] },
    { size: 256, scales: [1, 2] },
    { size: 512, scales: [1, 2] }
  ];
  
  for (const pair of sizePairs) {
    for (const scale of pair.scales) {
      const actualSize = pair.size * scale;
      const filename = `app_icon_${actualSize}.png`;
      
      const outputPath = path.join(macIconDir, filename);
      await convertSvgToPng(svgPath, outputPath, actualSize);
      
      contentsJson.images.push({
        filename,
        idiom: 'mac',
        scale: `${scale}x`,
        size: `${pair.size}x${pair.size}`
      });
    }
  }
  
  // Write Contents.json
  await fs.writeFile(
    path.join(macIconDir, 'Contents.json'),
    JSON.stringify(contentsJson, null, 2)
  );
}

async function generateWindowsIcon(svgPath, projectRoot) {
  console.log('\n🪟 Generating Windows icons...');
  
  const windowsIconDir = path.join(projectRoot, 'windows', 'runner', 'resources');
  await ensureDir(windowsIconDir);
  
  // Generate individual PNGs in memory
  const pngBuffers = [];
  
  for (const size of iconConfigs.windows) {
    try {
      const svgBuffer = await fs.readFile(svgPath);
      const pngBuffer = await sharp(svgBuffer, { density: 300 })
        .resize(size, size, {
          fit: 'contain',
          background: { r: 0, g: 0, b: 0, alpha: 0 }
        })
        .png()
        .toBuffer();
      
      pngBuffers.push(pngBuffer);
      console.log(`✓ Generated PNG buffer for ICO (${size}x${size})`);
    } catch (error) {
      console.error(`✗ Error generating PNG for ICO (${size}x${size}):`, error.message);
    }
  }
  
  // Convert PNG buffers to ICO
  try {
    const icoBuffer = await pngToIco(pngBuffers);
    const icoPath = path.join(windowsIconDir, 'app_icon.ico');
    await fs.writeFile(icoPath, icoBuffer);
    console.log(`✓ Generated: ${icoPath}`);
  } catch (error) {
    console.error('✗ Error generating ICO file:', error.message);
  }
}

async function generateLinuxIcon(svgPath, projectRoot) {
  console.log('\n🐧 Generating Linux icon...');
  
  const linuxDir = path.join(projectRoot, 'linux');
  await ensureDir(linuxDir);
  
  for (const config of iconConfigs.linux) {
    const outputPath = path.join(linuxDir, config.name);
    await convertSvgToPng(svgPath, outputPath, config.size);
  }
}

async function main() {
  const projectRoot = path.resolve(process.cwd() + '/..');
  const svgPath = path.join(projectRoot, 'assets', 'app_launcher_icon.svg');
  
  // Check if SVG exists
  try {
    await fs.access(svgPath);
  } catch (error) {
    console.error(`❌ SVG file not found at: ${svgPath}`);
    process.exit(1);
  }
  
  console.log('🎨 Flutter App Icon Generator');
  console.log(`📁 Project root: ${projectRoot}`);
  console.log(`🖼️  Source SVG: ${svgPath}`);
  
  // Generate icons for all platforms
  await generateAndroidIcons(svgPath, projectRoot);
  await generateIosIcons(svgPath, projectRoot);
  await generateWebIcons(svgPath, projectRoot);
  await generateMacOsIcons(svgPath, projectRoot);
  await generateWindowsIcon(svgPath, projectRoot);
  await generateLinuxIcon(svgPath, projectRoot);
  
  console.log('\n✅ Icon generation complete!');
  console.log('🎉 All platform icons have been generated with transparency preserved!');
}

// Run the script
main().catch(console.error); 