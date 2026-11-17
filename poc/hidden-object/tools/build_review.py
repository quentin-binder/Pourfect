"""Builds out/review.html: a self-contained page to judge the art and the layering.
Click an object to make it vanish (alpha hit-test on its layer). Not the game engine."""
import base64, io, json, sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
m = json.loads((root / "layers/scene.json").read_text())
spec = json.loads((root / "scene_spec.json").read_text())

def data_url(img, fmt="PNG", **kw):
    b = io.BytesIO(); img.save(b, fmt, **kw)
    return f"data:image/{fmt.lower()};base64," + base64.b64encode(b.getvalue()).decode()

bg = Image.open(root / m["background"]).convert("RGB")
layers = []
for L in m["objects"]:
    item = {"name": L["name"], "label": L["label"]}
    for k in ("shadow", "object", "occluder"):
        if k in L:
            item[k] = {"src": data_url(Image.open(root / L[k]["file"])), "x": L[k]["x"], "y": L[k]["y"]}
    o = Image.open(root / f"objects/{L['name']}.png").convert("RGBA"); o = o.crop(o.getbbox()); o.thumbnail((96, 96))
    item["thumb"] = data_url(o)
    layers.append(item)

html = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hidden Object Art PoC</title>
<style>
:root{--bg:#1d1913;--panel:#2a241b;--ink:#f3e7cf;--muted:#b9a98a;--gold:#e0b45c}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.4 -apple-system,system-ui,sans-serif}
header{padding:12px 16px;display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center}
h1{font:600 18px Georgia,serif;margin:0;color:var(--gold)}
label{color:var(--muted);user-select:none}button{background:var(--panel);color:var(--ink);border:1px solid #4a3f2e;border-radius:8px;padding:5px 10px;cursor:pointer}
#wrap{position:relative;margin:0 16px;overflow:auto;border-radius:10px;max-height:78vh}
#stage{position:relative;transform-origin:0 0}
#stage img{position:absolute;pointer-events:none}
#stage.debug .obj{outline:3px solid #ff2a78}
.fx{position:absolute;pointer-events:none;border-radius:50%;animation:pop .9s ease-out forwards}
@keyframes pop{0%{transform:scale(.2);opacity:1;box-shadow:0 0 30px 18px rgba(255,230,150,.9)}100%{transform:scale(2.4);opacity:0;box-shadow:0 0 60px 30px rgba(255,230,150,0)}}
.miss{position:absolute;pointer-events:none;border:3px solid rgba(255,255,255,.7);border-radius:50%;animation:miss .5s ease-out forwards}
@keyframes miss{to{transform:scale(1.8);opacity:0}}
.vanish{transition:opacity .7s ease, transform .7s ease;opacity:0!important;transform:scale(1.25)}
#list{display:flex;flex-wrap:wrap;gap:8px;padding:12px 16px}
.chip{display:flex;align-items:center;gap:6px;background:var(--panel);border-radius:10px;padding:4px 10px 4px 4px}
.chip img{width:40px;height:40px;object-fit:contain}.chip.done{opacity:.35;text-decoration:line-through}
p.note{color:var(--muted);margin:0 16px 16px;max-width:900px}
</style></head><body>
<header><h1>__TITLE__</h1>
<label>Zoom <input id="zoom" type="range" min="0.35" max="1.2" step="0.05" value="0.5"></label>
<label><input id="dbg" type="checkbox"> show where things are</label>
<label><input id="bare" type="checkbox"> background only</label>
<button id="reset">Reset</button><span id="count"></span></header>
<div id="wrap"><div id="stage"></div></div>
<div id="list"></div>
<p class="note">__NOTE__</p>
<script>
const BG = "__BG__", W = __W__, H = __H__, LAYERS = __LAYERS__;
const stage = document.getElementById('stage'), list = document.getElementById('list');
stage.style.width = W+'px'; stage.style.height = H+'px';
const bgImg = new Image(); bgImg.src = BG; bgImg.style.left='0'; bgImg.style.top='0'; bgImg.width=W; bgImg.height=H; stage.appendChild(bgImg);
const hit = [];
function add(src, x, y, cls){const i=new Image(); i.src=src; i.style.left=x+'px'; i.style.top=y+'px'; if(cls) i.className=cls; stage.appendChild(i); return i;}
for (const L of LAYERS) {
  const els = [];
  if (L.shadow) els.push(add(L.shadow.src, L.shadow.x, L.shadow.y, 'layer'));
  const o = add(L.object.src, L.object.x, L.object.y, 'layer obj'); els.push(o);
  if (L.occluder) els.push(add(L.occluder.src, L.occluder.x, L.occluder.y, 'layer'));
  const c = document.createElement('canvas'); const ctx = c.getContext('2d', {willReadFrequently:true});
  o.onload = () => { c.width=o.naturalWidth; c.height=o.naturalHeight; ctx.drawImage(o,0,0); };
  const chip = document.createElement('div'); chip.className='chip'; chip.innerHTML = `<img src="${L.thumb}" alt=""><span>${L.label}</span>`; list.appendChild(chip);
  hit.push({L, o, ctx, c, els, chip, found:false});
}
function scale(){return parseFloat(document.getElementById('zoom').value)}
function applyZoom(){stage.style.transform=`scale(${scale()})`; const w=document.getElementById('wrap'); w.style.height=(H*scale())+'px'; w.style.width='auto'; stage.parentElement.style.maxWidth=(W*scale()+2)+'px';}
document.getElementById('zoom').oninput = applyZoom; applyZoom();
document.getElementById('dbg').onchange = e => stage.classList.toggle('debug', e.target.checked);
document.getElementById('bare').onchange = e => document.querySelectorAll('.layer').forEach(el => el.style.visibility = e.target.checked ? 'hidden' : '');
document.getElementById('reset').onclick = () => { for (const h of hit){h.found=false; h.chip.classList.remove('done'); h.els.forEach(e=>{e.classList.remove('vanish'); e.style.display='';});} count(); };
function count(){document.getElementById('count').textContent = hit.filter(h=>h.found).length + ' / ' + hit.length + ' found';}
count();
document.getElementById('wrap').addEventListener('click', ev => {
  const r = stage.getBoundingClientRect(); const s = scale();
  const x = (ev.clientX - r.left)/s, y = (ev.clientY - r.top)/s;
  for (let k = hit.length-1; k >= 0; k--) { const h = hit[k]; if (h.found) continue;
    const ox = x - h.L.object.x, oy = y - h.L.object.y;
    if (ox < -6 || oy < -6 || ox > h.c.width+6 || oy > h.c.height+6) continue;
    // generous hit area: any opaque pixel within 6 px
    let ok = false; for (let dy=-6; dy<=6 && !ok; dy+=3) for (let dx=-6; dx<=6 && !ok; dx+=3) {
      const px = Math.round(ox+dx), py = Math.round(oy+dy); if (px<0||py<0||px>=h.c.width||py>=h.c.height) continue;
      if (h.ctx.getImageData(px,py,1,1).data[3] > 60) ok = true; }
    if (!ok) continue;
    h.found = true; h.chip.classList.add('done'); count();
    const fx = document.createElement('div'); fx.className='fx'; const d = Math.max(h.c.width,h.c.height);
    Object.assign(fx.style,{left:(h.L.object.x+h.c.width/2-d/2)+'px',top:(h.L.object.y+h.c.height/2-d/2)+'px',width:d+'px',height:d+'px'}); stage.appendChild(fx);
    h.els.forEach(e => e.classList.add('vanish')); setTimeout(()=>{h.els.forEach(e=>e.style.display='none'); fx.remove();}, 900);
    return; }
  const m = document.createElement('div'); m.className='miss'; Object.assign(m.style,{left:(x-25)+'px',top:(y-25)+'px',width:'50px',height:'50px'}); stage.appendChild(m); setTimeout(()=>m.remove(),500);
});
</script></body></html>"""
DEFAULT_NOTE = """Everything here is generated art: one painted background plus 12 separately generated objects, cut out, tinted toward the scene, given soft contact shadows, and in two cases (toadstool in the fruit bowl, egg in the basket) partly hidden behind scene pixels drawn back on top. Each object is its own layer, so it can vanish cleanly. Click an object to find it."""
html = html.replace("__TITLE__", spec.get("title", "Alchemist's Attic — hidden-object art test")).replace("__NOTE__", spec.get("note", DEFAULT_NOTE))
html = (html.replace("__BG__", data_url(bg, "JPEG", quality=86)).replace("__W__", str(m["size"][0])).replace("__H__", str(m["size"][1]))
        .replace("__LAYERS__", json.dumps(layers)))
(root / "out/review.html").write_text(html)
print("review.html", round(len(html) / 1e6, 1), "MB")
