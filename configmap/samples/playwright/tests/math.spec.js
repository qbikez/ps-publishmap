const { test, expect } = require('@playwright/test');

test.describe('math', () => {
    test('adds numbers', () => {
        expect(1 + 2).toBe(3);
    });

    test('multiplies numbers', () => {
        expect(3 * 4).toBe(12);
    });
});
