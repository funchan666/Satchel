import { mkdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const assets = name => pathToFileURL(resolve(root, '素材', name)).href;
const slides = [
  ['01-journal', 'Keep the moments<br>that matter.', 'YOUR TRAVEL JOURNAL', 'screen-journal.png'],
  ['02-guide', 'A thoughtful start<br>to every trip.', 'A HANDY TRAVEL GUIDE', 'screen-guide.png'],
  ['03-collection', 'A little more<br>room to roam.', 'YOUR TRAVEL COLLECTION', 'screen-collection.png'],
];

function html(body, style) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
    *{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden}
    body{color:#17344a;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    ${style}</style></head><body>${body}</body></html>`;
}

function capture(name, markup, width, height, dest) {
  const input = resolve(root, '素材', `${name}.html`);
  const png = resolve(root, '素材', `${name}.png`);
  writeFileSync(input, markup);
  const run = spawnSync(chrome, ['--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars', '--allow-file-access-from-files', '--force-device-scale-factor=1', '--run-all-compositor-stages-before-draw', `--user-data-dir=/tmp/satchel-art-${process.pid}`, `--window-size=${width},${height}`, `--screenshot=${png}`, pathToFileURL(input).href], {encoding:'utf8'});
  if (run.status !== 0) throw new Error(run.stderr);
  const convert = spawnSync('/usr/bin/sips', ['-s','format','jpeg','-s','formatOptions','95',png,'--out',dest], {encoding:'utf8'});
  if (convert.status !== 0) throw new Error(convert.stderr);
}

for (const [width,height,folder] of [[1320,2868,'商店图 6.9英寸'],[1206,2622,'商店图 6.3英寸']]) {
  const target = resolve(root,folder); mkdirSync(target,{recursive:true});
  for (const [name,title,kicker,screen] of slides) {
    const markup = html(`<main><div class="veil"></div><div class="heading"><div class="eyebrow">${kicker}</div><h1>${title}</h1><p>Satchel · Your travel companion</p></div><div class="capture ${name === '03-collection' ? 'collection' : ''}"><img src="${assets(screen)}" alt="Actual Satchel app screen"></div></main>`, `
      main{position:relative;width:100vw;height:100vh;overflow:hidden;background:#f4eee1 url('${assets('coastal-background.png')}') center/cover no-repeat}
      .veil{position:absolute;inset:0;background:rgba(250,248,242,.43)}
      .heading{position:absolute;top:3.8%;left:7%;width:86%;text-align:center}
      .eyebrow{font-size:2.05vw;letter-spacing:.22em;font-weight:700;color:#233e4b;text-shadow:0 1px 12px rgba(255,255,255,.8)}
      h1{font-family:Georgia,'Times New Roman',serif;font-size:7.2vw;line-height:1.07;font-weight:400;letter-spacing:-.035em;margin:2.2vw 0 1.5vw}
      p{font-size:2.35vw;color:#536f77;letter-spacing:.025em;margin:0}
      .capture{position:absolute;left:14.5%;top:20%;width:71%;border-radius:4.2vw;overflow:hidden;box-shadow:0 2.2vw 5vw rgba(27,45,48,.22),0 .2vw .9vw rgba(27,45,48,.16);background:#f7f5ed}
      .capture img{display:block;width:100%;height:auto}
      .capture.collection{left:8%;width:84%;top:23%}
      .capture.collection img{margin-top:-62.2%}
    `);
    capture(`${folder}-${name}`,markup,width,height,resolve(target,`${name}.jpg`));
  }
}

const promoDir = resolve(root,'内购推广图'); mkdirSync(promoDir,{recursive:true});
for (const [key,title] of [['monthly','Monthly Membership'],['yearly','Yearly Membership']]) {
  const markup = html(`<main><div class="label">SATCHEL</div><h1>${title}</h1><p>More room for every journey.</p></main>`, `
    main{position:relative;width:100vw;height:100vh;background:#eee3d0 url('${assets('membership-still-life.png')}') center/cover no-repeat;padding:7% 8%}
    .label{color:#526a6d;font-size:20px;font-weight:700;letter-spacing:.28em}
    h1{font-family:Georgia,'Times New Roman',serif;font-size:58px;line-height:1.08;letter-spacing:-.035em;font-weight:400;margin:22px 0 13px;color:#18344a}
    p{font-size:25px;color:#526a6d;margin:0}
  `);
  capture(`iap-${key}`,markup,1024,1024,resolve(promoDir,`${key}.jpg`));
}
