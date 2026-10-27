// 样式一致性探针：检查关键组件是否守住像素风规范
const puppeteer = require('C:/Users/32077/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = process.env.REPS_URL || 'http://127.0.0.1:8099/index.html';

(async () => {
  const b = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const p = await b.newPage();
  await p.setViewport({ width: 390, height: 844, deviceScaleFactor: 1 });
  await p.goto(BASE, { waitUntil: 'networkidle2' });
  await p.evaluate(() => {
    DB.profile = { h: 175, w: 70, age: 28, sex: 'm', neck: 38, waist: 82, bench: 80, squat: 110, dead: 140 };
    DB.sessions = [{ date: new Date(Date.now() - 864e5).toISOString(), exercises: [{ name: '杠铃卧推', sets: [{ w: 65, r: 10 }] }] }];
    save(); renderMe(); renderStats();
  });
  await new Promise(r => setTimeout(r, 300));

  const res = await p.evaluate(() => {
    const pick = (sel, props) => {
      const el = document.querySelector(sel);
      if (!el) return [sel, 'MISSING'];
      const cs = getComputedStyle(el);
      return [sel, props.map(k => k + '=' + cs[k]).join(' ')];
    };
    const out = [
      pick('.card', ['borderRadius', 'boxShadow', 'backgroundColor', 'borderTopWidth']),
      pick('.excard', ['borderRadius', 'boxShadow', 'backgroundColor', 'borderTopWidth']),
      pick('.pill', ['borderRadius', 'boxShadow', 'borderTopWidth', 'backgroundColor']),
      pick('.adv', ['borderLeftWidth']),
      pick('.step', ['borderRadius', 'boxShadow']),
      pick('.sval', ['fontFamily', 'fontSize']),
      pick('.setrow .v', ['borderRadius']),
      pick('.stat .v', ['fontFamily']),
      pick('.tabs-in', ['borderRadius', 'borderTopWidth']),
      pick('.pbtn', ['borderRadius', 'boxShadow']),
      pick('.head-act', ['borderRadius', 'boxShadow']),
      pick('.fld', ['borderRadius', 'boxShadow']),
      pick('.seg button', ['borderRadius', 'boxShadow'])
    ];
    // 页面里所有 SVG 描边色 / 硬编码旧配色
    const svgStroke = [...document.querySelectorAll('svg path,svg circle')].map(e => e.getAttribute('stroke') || e.getAttribute('fill')).filter(Boolean);
    // 圆角残留
    const rounded = [];
    document.querySelectorAll('.page.on *').forEach(el => {
      const r = getComputedStyle(el).borderTopLeftRadius;
      if (r && r !== '0px' && parseFloat(r) > 2) rounded.push((el.className || el.tagName).toString().split(' ')[0] + ':' + r);
    });
    return { out, svgStroke, rounded: [...new Set(rounded)] };
  });
  res.out.forEach(([s, v]) => console.log(s.padEnd(14), v));
  console.log('SVG 描边/填充:', [...new Set(res.svgStroke)].join(', ') || '无');
  console.log('非零圆角残留:', res.rounded.join(', ') || '无');
  await b.close();
})();
