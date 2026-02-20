import livereload from 'rollup-plugin-livereload';
import { nodeResolve } from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import { terser } from 'rollup-plugin-terser';

const isRelease = process.env.NODE_ENV === 'production';

export default [{
  input: 'src/storage/client/app.js',
  output: [
    {
      name: 'UI',
      file: 'src/storage/assets/app.js',
      format: 'iife'
    }
  ],
  plugins: [
    (!isRelease) && livereload('src/storage/assets'),
    nodeResolve(),
    commonjs({
      include: 'node_modules/**',
      requireReturnsDefault: 'auto'
    }),
    ...(isRelease ? [terser()] : [])
  ]
}];