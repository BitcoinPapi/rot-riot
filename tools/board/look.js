// Tries the idea board's page in a test browser with a pretend notebook (the published page uses
// the real one): both pages, changing numbers and names, pictures, a phone, a read-only visitor.
//   godot --headless -- --dump-game=/tmp/sheet
//   node tools/board/look.js tools/board/gang-wars-ideas.html /tmp/sheet [FOLDER FOR SCREENSHOTS]
// Needs Node with Playwright. Prints what it saw; the last line must say "errors: none".
const { chromium } = require('playwright');
const fs = require('fs');
const http = require('http');
const path = require('path');
const page_html = fs.readFileSync(process.argv[2], 'utf8');
const sheet_dir = process.argv[3];
const shots = process.argv[4] || require('os').tmpdir();
const game = {};
for (const f of fs.readdirSync(sheet_dir)) if (f.endsWith('.json')) { const d = JSON.parse(fs.readFileSync(path.join(sheet_dir, f), 'utf8')); game[d.id] = d; }

const mock = `<script>
(function(){
  var now = Date.now();
  var store = {
    ideas: {
      a1: {title:"Give each gang boss its own attack", text:"Today all five are the same monster with a new name.", area:"bosses", by:"Claude", at:now-86400000, status:"yes", votes:{kosta:{v:true,n:"Kosta"}, tatoni:{v:true,n:"Tatoni"}}, comments:{c1:{by:"Tatoni", text:"Papa Zo should raise skeletons", at:now-3600000}}},
      a2: {title:"Music: what style fits?", text:"The game has no music yet.", area:"sound", by:"Claude", at:now-80000000, status:"new", votes:{kosta:{v:true,n:"Kosta"}}, comments:{}},
      a3: {title:"A machete as a melee weapon", text:"", area:"weapons", by:"Kosta", at:now-1000, status:"building", votes:{}, comments:{}}
    },
    game: ${JSON.stringify(game)},
    changes: {
      "weapons.pistol.damage": {section:"weapons", row:"pistol", col:"damage", item:"PISTOL", label:"Damage", unit:"", kind:"number", from:14, to:18, raw:18, path:"WEAPONS.pistol.damage", by:"Kosta", at:now-7200000},
      "gangs.2.boss": {section:"gangs", row:"2", col:"boss", item:"MAP 3", label:"Its boss", unit:"", kind:"text", from:"PAPA ZO", to:"PAPA ZONBI", raw:"PAPA ZONBI", path:"MAPS[2].boss", by:"Tatoni", at:now-3600000}
    },
    pics: {
      p1: {section:"weapons", row:"pistol", asset:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1", by:"Kosta", at:now-5000},
      p2: {section:"weapons", row:"pistol", asset:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2", by:"Tatoni", at:now-4000},
      p3: {section:"weapons", row:"shotgun", asset:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3", by:"Kosta", at:now-3000}
    }
  };
  var listeners = {}, counter = 0;
  window.__store = store; window.__uploads = []; window.__deleted = [];
  function snap(name){ var docs = store[name] || {}; return {docs:Object.keys(docs).map(function(k){return {id:k, exists:true, data:function(){return docs[k];}};}), metadata:{fromCache:false}}; }
  function tell(name){ (listeners[name]||[]).forEach(function(fn){ fn(snap(name)); }); }
  function merge(into, from){ Object.keys(from).forEach(function(k){ if (from[k] && typeof from[k]==="object" && !Array.isArray(from[k]) && into[k] && typeof into[k]==="object") merge(into[k], from[k]); else into[k] = from[k]; }); }
  function docRef(name, id){
    return { id:id, path:name+"/"+id,
      set:function(data){ store[name] = store[name]||{}; store[name][id] = JSON.parse(JSON.stringify(data)); tell(name); return Promise.resolve(); },
      update:function(data){ if (!store[name] || !store[name][id]) return Promise.reject({code:"invalid_argument"}); merge(store[name][id], JSON.parse(JSON.stringify(data))); tell(name); return Promise.resolve(); },
      delete:function(){ if (store[name]) delete store[name][id]; tell(name); return Promise.resolve(); } };
  }
  var db = {
    collection:function(name){ return {
      onSnapshot:function(next){ (listeners[name] = listeners[name]||[]).push(next); setTimeout(function(){ next(snap(name)); }, 40); return function(){}; },
      doc:function(id){ return docRef(name, id || ("n" + (++counter) + now.toString(36))); } }; },
    doc:function(p){ var parts = p.split("/"); return docRef(parts[0], parts[1]); }
  };
  var user = { can:function(){ return Promise.resolve(window.__canWrite !== false); } };
  var assets = {
    upload:function(blob){ var id = ("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" + (++counter)).slice(-32); window.__uploads.push({id:id, size:blob.size, type:blob.type}); return Promise.resolve({id:id, url:"/_blob/"+id, sizeBytes:blob.size, contentType:blob.type}); },
    delete:function(id){ window.__deleted.push(id); return Promise.resolve({deleted:true}); },
    list:function(){ return Promise.resolve({assets:[], usage:{files:0, bytes:0, maxFiles:100, maxBytes:1e9}}); }
  };
  window.claude = { use:function(n){ return Promise.resolve(n==="db"?db:(n==="user"?user:(n==="assets" && window.__noAssets !== true ? assets : null))); } };
})();
</script>`;
const skeleton = (extra) => '<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"><style>:root{color-scheme:light}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>' + extra + mock + page_html + '</body></html>';
const picture = (n) => `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="hsl(${(n * 67) % 360} 45% 38%)"/><circle cx="200" cy="150" r="90" fill="hsl(${(n * 67 + 40) % 360} 60% 60%)"/><text x="200" y="165" font-size="60" text-anchor="middle" fill="#fff">${n}</text></svg>`;

const server = http.createServer((req, res) => {
  if (req.url.startsWith('/_blob/')) { res.writeHead(200, { 'content-type': 'image/svg+xml' }); res.end(picture(parseInt(req.url.slice(-1), 36) || 0)); return; }
  const extra = req.url.includes('readonly') ? '<script>window.__canWrite=false;window.__noAssets=true;</script>' : '';
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); res.end(skeleton(extra));
});

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch();
  const errors = [], say = (...a) => console.log(...a);
  const open = async (name, w, h, scheme, url) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, colorScheme: scheme, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    page.on('pageerror', e => errors.push(name + ': ' + e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(name + ' console: ' + m.text().slice(0, 160)); });
    await page.goto(base + url);
    await page.waitForTimeout(500);
    return { ctx, page };
  };
  const sideways = (page) => page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
  const id = (s) => `[id="${s}"]`;
  const chip = (name) => `#sectionChips .chip:text-matches("^${name}( · [0-9]+)?$")`;
  const sections = Object.keys(game).length;

  // --- the ideas page still works ---
  {
    const { ctx, page } = await open('board', 1200, 1000, 'dark', '/#board');
    await page.fill('#who', 'Henry');
    await page.click('#talk-a1');
    await page.screenshot({ path: path.join(shots, 'board-dark.png') });
    say('board: cards', await page.locator('.idea').count(), '| sideways scroll', await sideways(page));
    await ctx.close();
  }

  // --- the game page on a desk ---
  {
    const { ctx, page } = await open('game', 1200, 1100, 'dark', '/#game');
    say('game: view shown', await page.isVisible('#view-game'), '| board hidden', !(await page.isVisible('#view-board')),
      '| sections', await page.locator('#sectionChips .chip').allTextContents());
    say('game: items', await page.locator('.item').count(), '| tiles in the first', await page.locator('.item >> nth=0').locator('.tile').count(),
      '| waiting', await page.textContent('#waitCount'), '| changed tiles', await page.locator('.tile.changed').count(),
      '| thumbs', await page.locator('.thumb').count(), '| add buttons', await page.locator('.addpic').count());
    await page.screenshot({ path: path.join(shots, 'game-dark.png') });

    // a change without a name is refused and asks for the name
    await page.click(id('t-weapons.smg.damage'));
    await page.fill('#edit-input', '9');
    await page.click('#edit-save');
    say('no name: hint shown', await page.isVisible('#whohint'), '| stored', await page.evaluate(() => !!window.__store.changes['weapons.smg.damage']));
    await page.fill('#who', 'Henry');
    say('the editor stayed open with what was typed:', await page.inputValue('#edit-input'));

    // a number: wrong input, the steppers, then save
    await page.fill('#edit-input', 'lots');
    await page.click('#edit-save');
    say('bad number:', await page.textContent('#edit-error'));
    await page.fill('#edit-input', '999999');
    await page.click('#edit-save');
    say('too big:', await page.textContent('#edit-error'));
    await page.fill('#edit-input', '7');
    await page.click('#edit-more'); await page.click('#edit-more'); await page.click('#edit-less');
    say('stepper 7 +1 +1 -1 =', await page.inputValue('#edit-input'));
    await page.screenshot({ path: path.join(shots, 'game-editing.png') });
    await page.click('#edit-save');
    say('saved:', JSON.stringify(await page.evaluate(() => window.__store.changes['weapons.smg.damage'])));
    say('tile now:', (await page.textContent(id('t-weapons.smg.damage'))).replace(/\s+/g, ' '), '| waiting', await page.textContent('#waitCount'));

    // a share shown as percent keeps the game's own number beside it
    await page.click(chip('Villains'));
    await page.click(id('t-villains.RUNNER.share'));
    await page.fill('#edit-input', '50');
    await page.keyboard.press('Enter');
    say('percent:', JSON.stringify(await page.evaluate(() => { var c = window.__store.changes['villains.RUNNER.share']; return [c.from, c.to, c.raw, c.path, c.unit]; })));
    say('empty cells are not buttons:', await page.locator('.item >> nth=0').locator('div.tile.none').count());

    // a name
    await page.click(chip('Gang zones'));
    await page.click(id('t-gangs.0.boss'));
    await page.fill('#edit-input', '  Kòk   Wouj ');
    await page.click('#edit-save');
    say('name:', JSON.stringify(await page.evaluate(() => { var c = window.__store.changes['gangs.0.boss']; return [c.from, c.to, c.raw, c.path]; })));

    // typing the game's own value again takes the change away; so does Undo; Escape cancels
    await page.click(id('t-gangs.0.boss'));
    await page.click('#edit-back');
    say('back: gone', await page.evaluate(() => !window.__store.changes['gangs.0.boss']));
    await page.click(id('undo-weapons.pistol.damage'));
    say('undo: gone', await page.evaluate(() => !window.__store.changes['weapons.pistol.damage']), '| waiting', await page.textContent('#waitCount'));
    await page.click(id('t-gangs.1.hp'));
    await page.keyboard.press('Escape');
    say('escape closes the editor:', (await page.locator('.tile.editing').count()) === 0);
    await page.click(id('go-weapons.smg.damage'));
    say('jump from the list: section', await page.textContent('.sheet-head h2'));

    // pictures: add two, look at one, remove it
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
    await page.setInputFiles(id('addpic-weapons.rifle'), [{ name: 'a.png', mimeType: 'image/png', buffer: png }, { name: 'b.png', mimeType: 'image/png', buffer: png }, { name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('x') }]);
    await page.waitForTimeout(400);
    say('pictures: uploads', await page.evaluate(() => window.__uploads.length), '| on the rifle', await page.locator(id('item-weapons.rifle') + ' .thumb').count(),
      '| note', await page.textContent('#notice'));
    await page.click('#pic-p1');
    await page.waitForTimeout(200);
    say('viewer open:', await page.evaluate(() => document.getElementById('viewer').open), '|', await page.textContent('#viewerCap'));
    await page.screenshot({ path: path.join(shots, 'game-viewer.png') });
    await page.click('#viewer-remove');
    await page.click('#viewer-yes');
    await page.waitForTimeout(200);
    say('removed: doc gone', await page.evaluate(() => !window.__store.pics.p1), '| asset erased', JSON.stringify(await page.evaluate(() => window.__deleted)),
      '| viewer closed', await page.evaluate(() => !document.getElementById('viewer').open));
    say('rules have no picture places:', await (async () => { await page.click(chip('Levels & rules')); return (await page.locator('.pics').count()) === 0 && (await page.locator('.item').count()); })());
    await page.screenshot({ path: path.join(shots, 'game-rules.png') });

    // a section made of several tables: gear = the pieces, the tiers, how it is found
    await page.click(chip('Gear'));
    say('gear: parts', await page.locator('.part-head h3').allTextContents(), '| items', await page.locator('.item').count(),
      '| picture places', await page.locator('.addpic').count(), '| plain list rows', await page.locator('.item.single').count());
    say('gear: a piece reads', (await page.textContent(id('item-gear.riot_helmet') + ' .tiles')).replace(/\s+/g, ' '));
    await page.screenshot({ path: path.join(shots, 'game-gear.png') });
    await page.click(id('t-gear.hard_hat.first'));
    await page.fill('#edit-input', '3');
    await page.click('#edit-save');
    await page.click(id('t-gear.3.chance'));
    await page.fill('#edit-input', '55');
    await page.click('#edit-save');
    await page.click(id('t-gear.gear_drop_chance_brute.value'));
    await page.fill('#edit-input', '6,5');
    await page.click('#edit-save');
    say('gear changes:', JSON.stringify(await page.evaluate(() => ['gear.hard_hat.first', 'gear.3.chance', 'gear.gear_drop_chance_brute.value'].map(k => { var c = window.__store.changes[k]; return c && [c.item, c.label, c.from, c.to, c.raw, c.path]; }))));
    await page.click('#part-go-1');
    await page.waitForTimeout(100);
    await page.screenshot({ path: path.join(shots, 'game-gear-tiers.png') });
    await page.click(chip('Weapon perks'));
    say('weapon perks: items', await page.locator('.item').count(), '| first reads', (await page.textContent(id('item-wperks.pistol_1'))).replace(/\s+/g, ' ').slice(0, 150));
    await page.click(id('t-wperks.shotgun_1.first'));
    await page.click('#edit-more');
    await page.click('#edit-save');
    await page.click(id('t-wperks.weapon_perk_levels_0.value'));
    await page.fill('#edit-input', '3');
    await page.click('#edit-save');
    say('weapon perk changes:', JSON.stringify(await page.evaluate(() => ['wperks.shotgun_1.first', 'wperks.weapon_perk_levels_0.value'].map(k => { var c = window.__store.changes[k]; return c && [c.item, c.label, c.from, c.to, c.raw, c.path, c.unit]; }))));
    await page.screenshot({ path: path.join(shots, 'game-wperks.png') });
    await page.click(chip('Weapon upgrades'));
    say('weapon upgrades: parts', await page.locator('.part-head h3').allTextContents(), '| items', await page.locator('.item').count());
    await page.click(id('go-gear.3.chance'));
    say('jump to a row of a part: section', await page.textContent('.sheet-head h2'), '| waiting', await page.textContent('#waitCount'));
    for (let i = 0; i < sections; i++) { await page.click('#sectionChips .chip >> nth=' + i); if (await sideways(page)) say('SIDEWAYS SCROLL in section', i); }
    await page.click('#tab-board');
    say('back to ideas: board shown', await page.isVisible('#view-board'), '| address', await page.evaluate(() => location.hash));
    await ctx.close();
  }

  // --- a phone, light ---
  {
    const { ctx, page } = await open('phone', 400, 1100, 'light', '/#game');
    await page.screenshot({ path: path.join(shots, 'game-phone-light.png') });
    let wide = [];
    for (let i = 0; i < sections; i++) { await page.click('#sectionChips .chip >> nth=' + i); if (await sideways(page)) wide.push(i); }
    await page.click(chip('Gear'));
    await page.screenshot({ path: path.join(shots, 'game-phone-gear.png') });
    await page.click('#sectionChips .chip >> nth=0');
    await page.fill('#who', 'Henry');
    await page.click(id('t-weapons.pistol.interval'));
    await page.screenshot({ path: path.join(shots, 'game-phone-editing.png') });
    say('phone: sideways scroll in sections', JSON.stringify(wide), '| while editing', await sideways(page));
    await ctx.close();
  }

  // --- somebody who may only read ---
  {
    const { ctx, page } = await open('reader', 1000, 900, 'dark', '/?readonly#game');
    say('reader: buttons among tiles', await page.locator('button.tile').count(), '| add buttons', await page.locator('.addpic').count(),
      '| undo buttons', await page.locator('.change > button').count(), '| thumbs', await page.locator('.thumb').count(), '| note:', (await page.textContent('#notice')).slice(0, 50));
    await page.click('#pic-p1');
    say('reader: viewer buttons', await page.locator('#viewerButtons button').allTextContents());
    await ctx.close();
  }

  say('errors:', errors.length ? errors.join(' | ') : 'none');
  await browser.close();
  server.close();
})();
