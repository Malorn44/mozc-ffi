// ESLint for the Node bindings and their tests: ESLint's recommended rules and Node's globals.
// No style rules. The types in index.d.ts are checked by tsc (scripts/check.sh lint node).
import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import globals from 'globals';

export default defineConfig({
  files: ['**/*.js'],
  extends: [js.configs.recommended],
  languageOptions: { sourceType: 'commonjs', globals: globals.node },
});
