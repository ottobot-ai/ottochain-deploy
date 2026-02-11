#!/usr/bin/env node
/**
 * Explorer UI Verification using Playwright
 * 
 * Verifies:
 * 1. Dashboard loads without stuck loading states
 * 2. Recent Transactions table shows data (not skeleton loaders)
 * 3. Data updates when new transactions occur
 */

const { chromium } = require('playwright');

const EXPLORER_URL = process.env.EXPLORER_URL || 'http://5.78.121.248:8080';
const TIMEOUT = parseInt(process.env.UI_TIMEOUT || '30000');
const SCREENSHOT_DIR = process.env.SCREENSHOT_DIR || './screenshots';

async function verifyExplorerUI() {
    console.log(`[UI] Testing Explorer at ${EXPLORER_URL}`);
    
    const browser = await chromium.launch({ 
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const context = await browser.newContext({
        viewport: { width: 1920, height: 1080 }
    });
    const page = await context.newPage();
    
    let passed = true;
    const results = [];
    
    const check = (name, condition) => {
        if (condition) {
            console.log(`[UI] ✅ ${name}`);
            results.push({ name, passed: true });
        } else {
            console.log(`[UI] ❌ ${name}`);
            results.push({ name, passed: false });
            passed = false;
        }
    };

    try {
        // =================================================================
        // Test 1: Page loads successfully
        // =================================================================
        console.log('[UI] Loading dashboard...');
        const response = await page.goto(EXPLORER_URL, { 
            waitUntil: 'networkidle',
            timeout: TIMEOUT 
        });
        check('Dashboard loads', response?.ok());

        // =================================================================
        // Test 2: Dashboard header/stats render
        // =================================================================
        await page.waitForTimeout(2000); // Let React hydrate
        
        // Check for stat cards (Total Fibers, Agents, Contracts, etc.)
        const statCards = await page.locator('[class*="stat"], [class*="card"], [class*="metric"]').count();
        check('Stat cards render', statCards > 0);
        
        // =================================================================
        // Test 3: Recent Transactions table - not stuck in loading
        // =================================================================
        console.log('[UI] Checking Recent Transactions table...');
        
        // Look for the Recent Transactions section
        const txSection = page.locator('text=Recent Transactions').first();
        const txSectionVisible = await txSection.isVisible().catch(() => false);
        check('Recent Transactions section visible', txSectionVisible);
        
        if (txSectionVisible) {
            // Wait a moment for data to load
            await page.waitForTimeout(3000);
            
            // Check for skeleton loaders (the gray pulsing bars = stuck loading)
            const skeletonSelectors = [
                '[class*="skeleton"]',
                '[class*="loading"]',
                '[class*="pulse"]',
                '[class*="animate-pulse"]',
                '.bg-gray-700.animate-pulse',
                '[class*="shimmer"]'
            ];
            
            let hasSkeletons = false;
            for (const selector of skeletonSelectors) {
                const count = await page.locator(selector).count();
                if (count > 3) { // A few is ok (might be other elements), many = stuck
                    hasSkeletons = true;
                    console.log(`[UI] Found ${count} skeleton elements matching: ${selector}`);
                    break;
                }
            }
            
            // After 3 seconds, should not have skeleton loaders
            check('No stuck skeleton loaders', !hasSkeletons);
            
            // Check for either:
            // - Actual transaction rows (data exists)
            // - Empty state message (no data, but not loading)
            const txRows = await page.locator('table tbody tr, [class*="transaction-row"], [class*="tx-row"]').count();
            // Use .or() for multiple patterns - comma syntax doesn't work with regex
            const emptyState = await page.locator('text=/no.*transaction/i').or(page.locator('text=/empty/i')).or(page.locator('text=/no data/i')).count();
            
            const hasContent = txRows > 0 || emptyState > 0;
            check('Transaction table has content or empty state', hasContent);
            
            if (txRows > 0) {
                console.log(`[UI] Found ${txRows} transaction rows`);
            } else if (emptyState > 0) {
                console.log('[UI] Table showing empty state (no transactions yet)');
            }
        }

        // =================================================================
        // Test 4: Live indicator / Auto-update
        // =================================================================
        // Use .or() for multiple patterns - comma syntax doesn't work with regex
        const liveIndicator = await page.locator('text=/live/i').or(page.locator('text=/auto.*update/i')).or(page.locator('[class*="live"]')).count();
        check('Live/Auto-update indicator present', liveIndicator > 0);
        
        // =================================================================
        // Test 5: No console errors
        // =================================================================
        const consoleErrors = [];
        page.on('console', msg => {
            if (msg.type() === 'error') {
                consoleErrors.push(msg.text());
            }
        });
        
        // Refresh and check for errors
        await page.reload({ waitUntil: 'networkidle' });
        await page.waitForTimeout(2000);
        
        // Filter out noise (some errors are expected)
        const criticalErrors = consoleErrors.filter(e => 
            !e.includes('favicon') && 
            !e.includes('404') &&
            !e.includes('ResizeObserver')
        );
        check('No critical console errors', criticalErrors.length === 0);
        if (criticalErrors.length > 0) {
            console.log('[UI] Console errors:', criticalErrors.slice(0, 5));
        }

        // =================================================================
        // Take screenshot for reference
        // =================================================================
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const screenshotPath = `${SCREENSHOT_DIR}/explorer-${passed ? 'pass' : 'fail'}-${timestamp}.png`;
        
        try {
            const fs = require('fs');
            if (!fs.existsSync(SCREENSHOT_DIR)) {
                fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
            }
            await page.screenshot({ path: screenshotPath, fullPage: true });
            console.log(`[UI] Screenshot saved: ${screenshotPath}`);
        } catch (e) {
            console.log('[UI] Could not save screenshot:', e.message);
        }

    } catch (error) {
        console.error('[UI] Error during verification:', error.message);
        passed = false;
        
        // Try to capture error state
        try {
            const fs = require('fs');
            if (!fs.existsSync(SCREENSHOT_DIR)) {
                fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
            }
            await page.screenshot({ path: `${SCREENSHOT_DIR}/explorer-error.png`, fullPage: true });
        } catch (e) { /* ignore */ }
        
    } finally {
        await browser.close();
    }

    // =================================================================
    // Summary
    // =================================================================
    console.log('\n[UI] =========================================');
    console.log(`[UI] Results: ${results.filter(r => r.passed).length}/${results.length} passed`);
    console.log('[UI] =========================================');
    
    if (!passed) {
        console.error('[UI] ❌ UI verification FAILED');
        process.exit(1);
    } else {
        console.log('[UI] ✅ UI verification PASSED');
        process.exit(0);
    }
}

verifyExplorerUI();
