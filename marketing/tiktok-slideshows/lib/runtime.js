'use strict';
const path = require('node:path');
const os = require('node:os');
// Prefer npm install / NODE_PATH. Also support the desktop's bundled runtime.
function playwright() {
  try { return require('playwright'); } catch (error) {
    if (error.code !== 'MODULE_NOT_FOUND') throw error;
    const bundled = path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
    try { return require(bundled); } catch {
      throw new Error('Playwright is missing. Run npm ci in marketing/tiktok-slideshows, then npx playwright install chromium.');
    }
  }
}
module.exports = { playwright };
