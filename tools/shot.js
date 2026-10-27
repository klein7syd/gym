// REPS 网页版验证脚本 —— 无头浏览器截四页 + 收集报错 + 检测横向溢出
// 用法：node tools/shot.js [outDir]
const puppeteer = require('C:/Users/32077/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core');
const path = require('path');
const fs = require('fs');

const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = process.env.REPS_URL || 'http://127.0.0.1:8099/index.html';
const OUT = path.resolve(process.argv[2] || '.preview');

const SEED = () => {
  const now = Date.now(), d = n => new Date(now - n * 864e5).toISOString();
  DB.sessions = [
    { date: d(14), exercises: [
      { name: '杠铃卧推', sets: [{ w: 60, r: 8 }, { w: 60, r: 9 }, { w: 60, r: 8 }] },
      { name: '杠铃深蹲', sets: [{ w: 80, r: 8 }, { w: 80, r: 8 }, { w: 80, r: 7 }] }] },
    { date: d(7), exercises: [
      { name: '杠铃卧推', sets: [{ w: 62.5, r: 8 }, { w: 62.5, r: 9 }, { w: 62.5, r: 9 }] },
      { name: '杠铃深蹲', sets: [{ w: 85, r: 8 }, { w: 85, r: 8 }, { w: 85, r: 8 }] }] },
    { date: d(1), exercises: [
      { name: '杠铃卧推', sets: [{ w: 65, r: 10 }, { w: 65, r: 10 }, { w: 65, r: 9 }] },
      { name: '杠铃深蹲', sets: [{ w: 90, r: 8 }, { w: 90, r: 8 }, { w: 90, r: 8 }] }] }
  ];
  DB.cur = { date: d(0), exercises: [{ name: '杠铃卧推', sets: [{ w: 65, r: 10 }, { w: 65, r: 9 }] }] };
  DB.profile = { h: 175, w: 70, age: 28, sex: 'm', neck: 38, waist: 82, bench: 80, squat: 110, dead: 140 };
  save();
  renderTrain(); renderStats(); renderMe();
};

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars']
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });

  const errs = [];
  page.on('console', m => { if (m.type() === 'error') errs.push('[console] ' + m.text()); });
  page.on('pageerror', e => errs.push('[pageerror] ' + e.message));
  page.on('requestfailed', r => errs.push('[requestfailed] ' + r.url().replace(BASE, '') + ' ' + (r.failure() || {}).errorText));

  await page.goto(BASE, { waitUntil: 'networkidle2' });
  await page.evaluate(SEED);
  await new Promise(r => setTimeout(r, 400));

  const report = [];
  for (const tab of ['train', 'stats', 'lib', 'me']) {
    await page.evaluate(t => switchTab(t), tab);
    await new Promise(r => setTimeout(r, 350));
    const m = await page.evaluate(() => {
      const W = innerWidth, over = [];
      document.querySelectorAll('*').forEach(el => {
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.right > W + 0.5 && getComputedStyle(el).position !== 'fixed')
          over.push(el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/).join('.') : '') + '@' + r.right.toFixed(0));
      });
      return { W, sw: document.scrollingElement.scrollWidth, sh: document.scrollingElement.scrollHeight, over: over.slice(0, 8) };
    });
    report.push(`${tab.padEnd(6)} viewport=${m.W} scrollW=${m.sw} scrollH=${m.sh}` + (m.over.length ? `  溢出: ${m.over.join(', ')}` : ''));
    await page.screenshot({ path: path.join(OUT, tab + '.png'), fullPage: true });
  }

  // 交互冒烟：完成一组 → 计时是否启动
  await page.evaluate(() => switchTab('train'));
  await page.click('#addSet');
  await new Promise(r => setTimeout(r, 600));
  const timer = await page.evaluate(() => ({ running: T.running, text: document.querySelector('#restTime').textContent, lit: document.querySelectorAll('#pxCells i.on').length }));
  report.push(`计时     running=${timer.running} 剩余=${timer.text} 亮格=${timer.lit}/28`);
  await page.screenshot({ path: path.join(OUT, 'timer.png'), fullPage: false });

  await browser.close();
  console.log(report.join('\n'));
  console.log(errs.length ? '报错:\n' + [...new Set(errs)].join('\n') : '报错: 无');
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
