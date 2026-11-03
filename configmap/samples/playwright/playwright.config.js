// No browser projects: the sample tests use only `expect`, so `npx playwright install` is not needed.
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
    testDir: './tests',
    reporter: 'list',
});
