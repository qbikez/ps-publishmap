const { test, expect } = require('@playwright/test');

test.describe('strings', () => {
    test('uppercases text', () => {
        expect('qbuild'.toUpperCase()).toBe('QBUILD');
    });

    test('reverses text', () => {
        expect([...'abc'].reverse().join('')).toBe('cba');
    });
});

test('top level smoke test', () => {
    expect(true).toBeTruthy();
});
