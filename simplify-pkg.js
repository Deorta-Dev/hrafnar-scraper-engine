const fs = require('fs');
const path = require('path');

// 1. Leemos el package.json original
const pkg = require('./package.json');

// 2. Construimos un objeto solo con lo estrictamente necesario para producción
const simplifiedPkg = {
  name: pkg.name,
  version: pkg.version,
  description: pkg.description,
  author: pkg.author,
  main: 'main.js', // Apuntamos al entry point de NestJS compilado
  scripts: {
    'start:prod': 'node main.js',
  },
  dependencies: pkg.dependencies, // Ignoramos devDependencies por completo
};

// 3. Nos aseguramos de que el directorio dist exista (por si acaso)
const distPath = path.join(__dirname, 'dist');
if (!fs.existsSync(distPath)) {
  fs.mkdirSync(distPath, { recursive: true });
}

// 4. Escribimos el nuevo package.json en la carpeta dist
fs.writeFileSync(
  path.join(distPath, 'package.json'),
  JSON.stringify(simplifiedPkg, null, 2),
);

console.log('✅ package.json simplify generated in /dist');
